import AppKit
import Carbon.HIToolbox

/// Global shortcut that opens the menu: Command-Space.
private let shortcutKey = kVK_Space
private let shortcutModifiers: NSEvent.ModifierFlags = [.command]

/// An open menu consumes key presses before event monitors or key equivalents see
/// them. It fetches them through this method, so this is where to step in.
final class DockMenuApp: NSApplication {
    /// Set only while the menu is open. Returns the key press the menu should get
    /// instead, which can be the same one, or nil for none.
    static var menuKeyHandler: ((NSEvent) -> NSEvent?)?

    override func nextEvent(matching mask: NSEvent.EventTypeMask, until expiration: Date?,
                            inMode mode: RunLoop.Mode, dequeue: Bool) -> NSEvent? {
        while true {
            let event = super.nextEvent(matching: mask, until: expiration, inMode: mode, dequeue: dequeue)
            guard dequeue, let event, event.type == .keyDown,
                  let handler = Self.menuKeyHandler else { return event }
            if let event = handler(event) { return event }
        }
    }
}

@main
final class DockMenu: NSObject, NSApplicationDelegate, NSMenuDelegate {
    private var statusItem: NSStatusItem!
    private var hotKey: EventHotKeyRef?

    // Only set while the menu is open.
    private var search: SearchView?
    private var index: AppIndex?

    // Since the list last changed. A pointer that merely rests over the menu must
    // not pick what Q quits or Return launches.
    private var usedArrows = false
    private var restingPointer = NSPoint.zero

    private var highlightTimer: Timer?

    /// Quitting the active app makes macOS activate another one, which closes the
    /// menu. Set from then until the user does something else.
    private var reopensAfterQuit = false
    private var highlightIsDeliberate: Bool { usedArrows || NSEvent.mouseLocation != restingPointer }

    static func main() {
        let app = DockMenuApp.shared
        let delegate = DockMenu()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        // NSApplication holds its delegate weakly; keep it alive for the whole run.
        withExtendedLifetime(delegate) { app.run() }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        let image = NSImage(systemSymbolName: "square.grid.2x2", accessibilityDescription: "DockMenu")
        image?.isTemplate = true
        statusItem.button?.image = image

        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        statusItem.menu = menu

        setUpShortcut()
    }

    // MARK: - Shortcut

    /// A Carbon hot key needs no permissions and costs nothing until it is pressed.
    private func setUpShortcut() {
        var pressed = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, _, context in
            let delegate = Unmanaged<DockMenu>.fromOpaque(context!).takeUnretainedValue()
            // Opening the menu blocks until it closes, so leave the event handler first.
            RunLoop.main.perform { delegate.statusItem.button?.performClick(nil) }
            return noErr
        }, 1, &pressed, Unmanaged.passUnretained(self).toOpaque(), nil)
        registerShortcut()
    }

    private func registerShortcut() {
        guard hotKey == nil else { return }
        var modifiers = 0
        if shortcutModifiers.contains(.command) { modifiers |= cmdKey }
        if shortcutModifiers.contains(.control) { modifiers |= controlKey }
        if shortcutModifiers.contains(.option) { modifiers |= optionKey }
        if shortcutModifiers.contains(.shift) { modifiers |= shiftKey }
        let id = EventHotKeyID(signature: 0x444B_4D4E /* DKMN */, id: 1)
        let status = RegisterEventHotKey(UInt32(shortcutKey), UInt32(modifiers), id, GetApplicationEventTarget(), 0, &hotKey)
        if status != noErr { NSLog("DockMenu: could not register the shortcut (error %d)", status) }
    }

    /// While the menu is open a hot key press would be held back and reopen the
    /// menu after it closes. Unregistered, it arrives as a normal key press.
    private func unregisterShortcut() {
        guard let key = hotKey else { return }
        UnregisterEventHotKey(key)
        hotKey = nil
    }

    // MARK: - Keys while the menu is open

    /// Highlights the first search result once the menu has laid out the new ones.
    /// There is no public call for that, but a menu with nothing highlighted does it
    /// on a down arrow. Until it shows the new results it would pick an old one, so
    /// the outcome is checked and tried again a few times.
    private func highlightFirstResult(of menu: NSMenu, attempts: Int = 5) {
        highlightTimer?.invalidate()
        guard attempts > 0 else { return }
        let timer = Timer(timeInterval: 0.01, repeats: false) { [unowned self, unowned menu] _ in
            guard menu.highlightedItem == nil, !usedArrows, menu.items.last?.representedObject != nil else { return }
            NSApp.postEvent(Self.ownDownArrow, atStart: true)
            highlightFirstResult(of: menu, attempts: attempts - 1)
        }
        highlightTimer = timer
        RunLoop.main.add(timer, forMode: .common)
    }

    private static let ownDownArrow: NSEvent = {
        let character = String(UnicodeScalar(NSDownArrowFunctionKey)!)
        return NSEvent.keyEvent(
            with: .keyDown, location: .zero, modifierFlags: ownEventFlags, timestamp: 0, windowNumber: 0, context: nil,
            characters: character, charactersIgnoringModifiers: character, isARepeat: false, keyCode: UInt16(kVK_DownArrow))!
    }()

    /// Tells the arrow above from a real one: no keyboard sends this with an arrow.
    private static let ownEventFlags: NSEvent.ModifierFlags = [.numericPad, .function, .help]

    /// Returns whether the key press was handled and should not reach the menu.
    private func handleKey(_ event: NSEvent, in menu: NSMenu) -> Bool {
        if !event.isARepeat { reopensAfterQuit = false }
        let modifiers = event.modifierFlags.intersection([.command, .control, .option, .shift])
        let key = Int(event.keyCode)

        if key == shortcutKey, modifiers == shortcutModifiers {
            // Ignore repeats, or holding the shortcut would close the menu again.
            if !event.isARepeat { menu.cancelTracking() }
            return true
        }

        guard let search else { return false } // the right-click menu
        let isSearching = !search.text.isEmpty

        if modifiers.contains(.command), let character = event.charactersIgnoringModifiers {
            if [kVK_Delete, kVK_LeftArrow, kVK_RightArrow].contains(key), isSearching {
                search.type(event)
                return true
            }
            return modifiers == .command && search.perform(command: character.lowercased())
        }
        if modifiers.contains(.control) { return false }

        switch key {
        case kVK_UpArrow, kVK_DownArrow:
            usedArrows = true
            return false
        case kVK_Return, kVK_ANSI_KeypadEnter:
            // The first result is the default until the user highlights another.
            guard isSearching, menu.highlightedItem == nil || !highlightIsDeliberate else { return false }
            if let first = menu.items.first(where: { $0.representedObject != nil }) {
                menu.cancelTracking()
                choose(first)
            }
            return true
        case kVK_Escape:
            guard isSearching else { return false }
            search.clear()
            return true
        case kVK_Delete, kVK_ForwardDelete, kVK_LeftArrow, kVK_RightArrow, kVK_Home, kVK_End:
            guard isSearching else { return false }
            search.type(event)
            return true
        case kVK_Tab:
            return false
        case kVK_Space where !isSearching:
            return true // a search never starts with a space
        default:
            break
        }

        // Q quits the highlighted app, unless it is part of a search.
        if modifiers.isEmpty, !isSearching, event.charactersIgnoringModifiers?.lowercased() == "q",
           let app = menu.highlightedItem?.representedObject as? NSRunningApplication,
           highlightIsDeliberate {
            // The menu stays open; appDidQuit removes the app from it.
            if !event.isARepeat { quit(app) }
            return true
        }

        // Function keys report characters in this private range. Dead keys report none.
        if let scalar = event.characters?.unicodeScalars.first,
           scalar.value < 0x20 || (0xF700...0xF8FF).contains(scalar.value) { return false }
        search.type(event)
        return true
    }

    // MARK: - Menu

    /// The menu is built only when it opens, so nothing runs in between.
    func menuNeedsUpdate(_ menu: NSMenu) {
        guard DockMenuApp.menuKeyHandler == nil else { return } // already open
        menu.removeAllItems()

        if Self.isRightClick {
            search = nil
            let quit = NSMenuItem(title: "Quit DockMenu", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
            quit.target = NSApp
            menu.addItem(quit)
            return
        }

        let search = SearchView()
        search.onChange = { [unowned self, unowned menu] in updateList(of: menu) }
        self.search = search
        let searchItem = NSMenuItem()
        searchItem.view = search
        searchItem.isEnabled = false // the arrow keys skip it
        menu.addItem(searchItem)
        menu.addItem(.separator())

        updateList(of: menu)
    }

    /// Where the list starts: after the search box and a separator.
    private static let firstIndex = 2

    /// Whether the menu is being opened with a right-click or Control-click. The age
    /// check keeps an earlier click from counting when the shortcut opens the menu.
    private static var isRightClick: Bool {
        guard let event = NSApp.currentEvent, ProcessInfo.processInfo.systemUptime - event.timestamp < 1 else { return false }
        switch event.type {
        case .rightMouseDown, .rightMouseUp: return true
        case .leftMouseDown, .leftMouseUp: return event.modifierFlags.contains(.control)
        default: return false
        }
    }

    /// Replaces everything below the search box: running apps, or search results.
    private func updateList(of menu: NSMenu) {
        let first = Self.firstIndex
        while menu.items.count > first { menu.removeItem(at: first) }
        forgetHighlight()

        let items = search?.text.isEmpty == false ? resultItems() : runningItems()
        for (offset, item) in items.enumerated() { menu.insertItem(item, at: first + offset) }
        if search?.text.isEmpty == false { highlightFirstResult(of: menu) } else { highlightTimer?.invalidate() }
    }

    private func forgetHighlight() {
        usedArrows = false
        restingPointer = NSEvent.mouseLocation
    }

    /// Only called while the menu is open. Search results list installed apps, so
    /// they stay as they are.
    @objc private func appDidQuit(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              let menu = statusItem.menu,
              let item = menu.items.first(where: { $0.representedObject as? NSRunningApplication == app }) else { return }
        menu.removeItem(item)
        // The next app slides under the pointer: a second Q must not quit it.
        forgetHighlight()
        for item in menu.items {
            if let app = item.representedObject as? NSRunningApplication { item.state = app.isActive ? .on : .off }
        }
    }

    private func runningItems() -> [NSMenuItem] {
        NSWorkspace.shared.runningApplications
            .filter { $0.activationPolicy == .regular && !$0.isTerminated }
            .map { (name: Self.name(of: $0), app: $0) }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
            .map { name, app in
                let item = makeItem(name, icon: app.icon, object: app)
                item.state = app.isActive ? .on : .off
                return item
            }
    }

    private func resultItems() -> [NSMenuItem] {
        // Scanned on the first key press and dropped when the menu closes.
        let index = self.index ?? AppIndex()
        self.index = index
        let results = index.search(search?.text ?? "", limit: 10)
        guard !results.isEmpty else {
            let item = NSMenuItem(title: "No apps found", action: nil, keyEquivalent: "")
            item.isEnabled = false
            return [item]
        }
        return results.map { makeItem($0.name, icon: NSWorkspace.shared.icon(forFile: $0.url.path), object: $0.url) }
    }

    private func makeItem(_ title: String, icon: NSImage?, object: Any) -> NSMenuItem {
        let item = NSMenuItem(title: title, action: #selector(choose(_:)), keyEquivalent: "")
        item.target = self
        item.representedObject = object
        // Copy before resizing: the icon may be shared with other users of NSWorkspace.
        if let icon = icon?.copy() as? NSImage {
            icon.size = NSSize(width: 16, height: 16)
            item.image = icon
        }
        return item
    }

    func menuWillOpen(_ menu: NSMenu) {
        unregisterShortcut()
        NSWorkspace.shared.notificationCenter.addObserver(
            self, selector: #selector(appDidQuit(_:)), name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        DockMenuApp.menuKeyHandler = { [unowned self, unowned menu] event in
            if event.modifierFlags.contains(Self.ownEventFlags) {
                // Out of date if something got highlighted or the search was cleared.
                return menu.highlightedItem == nil && search?.text.isEmpty == false ? event : nil
            }
            return handleKey(event, in: menu) ? nil : event
        }
    }

    /// Drop items and icons once the menu is gone. Deferred because the chosen
    /// item's action is sent after this callback.
    func menuDidClose(_ menu: NSMenu) {
        DockMenuApp.menuKeyHandler = nil
        highlightTimer?.invalidate()
        highlightTimer = nil
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        registerShortcut()
        let clicked = [.leftMouseDown, .leftMouseUp, .rightMouseDown, .rightMouseUp].contains(NSApp.currentEvent?.type)
        let reopens = reopensAfterQuit && !clicked
        reopensAfterQuit = false
        DispatchQueue.main.async { [self] in
            menu.removeAllItems()
            search = nil
            index = nil
            // Not from inside this block: the main queue would wait for the menu to close.
            if reopens { RunLoop.main.perform { self.statusItem.button?.performClick(nil) } }
        }
    }

    private static func name(of app: NSRunningApplication) -> String {
        app.localizedName ?? app.bundleURL?.deletingPathExtension().lastPathComponent ?? "Process \(app.processIdentifier)"
    }

    // MARK: - Quitting

    private func quit(_ app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        // macOS expects Finder to keep running.
        guard app.bundleIdentifier != "com.apple.finder" else { return NSSound.beep() }
        reopensAfterQuit = app.isActive
        app.terminate()
        // Still running means it is probably asking to save: close the menu and show
        // that dialog, which otherwise opens behind other windows. Activating directly,
        // because opening by URL could relaunch an app that is just finishing.
        DispatchQueue.main.asyncAfter(deadline: .now() + 3) { [self] in
            guard !app.isTerminated else { return }
            reopensAfterQuit = false
            statusItem.menu?.cancelTracking()
            app.activate()
        }
    }

    // MARK: - Switching and launching

    @objc private func choose(_ item: NSMenuItem) {
        if let app = item.representedObject as? NSRunningApplication {
            switchTo(app)
        } else if let url = item.representedObject as? URL {
            launch(url)
        }
    }

    private func launch(_ url: URL) {
        let path = url.resolvingSymlinksInPath().path
        let running = NSWorkspace.shared.runningApplications.first {
            $0.activationPolicy == .regular && $0.bundleURL?.resolvingSymlinksInPath().path == path
        }
        if let running { return switchTo(running) }

        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        // macOS itself tells the user when an app cannot be opened.
        NSWorkspace.shared.openApplication(at: url, configuration: configuration)
    }

    private func switchTo(_ app: NSRunningApplication) {
        guard !app.isTerminated else { return }
        if app.isHidden { app.unhide() }

        // Opening by URL cannot tell copies of the same app apart, so those are
        // activated directly. So are programs without an app bundle: bundleURL is
        // then the bare executable, and opening it would run it again in a terminal.
        guard let url = app.bundleURL, Self.isApplication(url), !Self.hasOtherInstance(of: app) else {
            app.activate(options: .activateAllWindows)
            return
        }

        // Same route as a Dock click: LaunchServices brings the app forward and
        // sends a reopen event, which restores minimized or closed windows.
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        configuration.addsToRecentItems = false
        NSWorkspace.shared.openApplication(at: url, configuration: configuration) { _, error in
            if error != nil {
                DispatchQueue.main.async { _ = app.activate(options: .activateAllWindows) }
            }
        }
    }

    private static func isApplication(_ url: URL) -> Bool {
        (try? url.resourceValues(forKeys: [.isApplicationKey]))?.isApplication == true
    }

    private static func hasOtherInstance(of app: NSRunningApplication) -> Bool {
        guard let id = app.bundleIdentifier else { return false }
        return NSRunningApplication.runningApplications(withBundleIdentifier: id)
            .contains { $0.processIdentifier != app.processIdentifier && $0.activationPolicy == .regular }
    }
}
