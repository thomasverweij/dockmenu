import AppKit

/// The search box at the top of the menu.
final class SearchView: NSView, NSSearchFieldDelegate {
    var onChange: (() -> Void)?
    private let field = NSSearchField()

    var text: String { field.stringValue }

    init() {
        super.init(frame: NSRect(x: 0, y: 0, width: 260, height: 34))
        autoresizingMask = .width
        field.frame = NSRect(x: 12, y: 5, width: 236, height: 24)
        field.autoresizingMask = .width
        field.placeholderString = "Search apps"
        field.focusRingType = .none
        field.delegate = self
        addSubview(field)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError("not used") }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        window?.makeFirstResponder(field)
    }

    func controlTextDidChange(_ notification: Notification) { onChange?() }

    /// The clear button.
    func searchFieldDidEndSearching(_ sender: NSSearchField) { onChange?() }

    /// The menu also passes on arrow keys it used to move the highlight. Up and down
    /// must not move the text cursor as well.
    func control(_ control: NSControl, textView: NSTextView, doCommandBy command: Selector) -> Bool {
        command == #selector(NSResponder.moveUp(_:)) || command == #selector(NSResponder.moveDown(_:))
    }

    /// A menu does not reliably send key presses to its views, so they are passed in here.
    /// Going through the text editor keeps accents, selection and paste working.
    func type(_ event: NSEvent) {
        if field.currentEditor() == nil { window?.makeFirstResponder(field) }
        field.currentEditor()?.keyDown(with: event)
    }

    /// Returns whether the press was an editing command (⌘A, ⌘C, ⌘V or ⌘X).
    func perform(command key: String) -> Bool {
        guard let editor = field.currentEditor() else { return false }
        switch key {
        case "a": editor.selectAll(nil)
        case "c": editor.copy(nil)
        case "v": editor.paste(nil)
        case "x": editor.cut(nil)
        default: return false
        }
        return true
    }

    func clear() {
        field.currentEditor()?.string = ""
        field.stringValue = ""
        onChange?()
    }
}
