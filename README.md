# DockMenu

A tiny macOS menu bar app. Click the grid icon to list running apps and choose one to bring it forward, or type to find and launch any installed app.

| Key | Action |
|---|---|
| ⌘Space | Open or close the menu, from any app |
| Type | Search installed apps |
| ↑ ↓ | Highlight an app |
| Return | Switch to the highlighted app, or launch it. While searching, the first result is highlighted for you |
| Q | Quit the highlighted app (Finder is skipped). The menu stays open and the app disappears from the list. Types a q while searching or when no app is highlighted |
| Esc | Clear the search, then close the menu |

To quit DockMenu, right-click (or Control-click) its icon.

Search covers `/Applications`, `~/Applications` and the system's own apps, including one level of subfolders.

⌘Space is also Spotlight's default shortcut. If Spotlight opens instead, turn its shortcut off in System Settings > Keyboard > Keyboard Shortcuts > Spotlight.

To change the shortcut, edit the two constants at the top of `Sources/main.swift` and rebuild.

Requires macOS 14 or later. No special permissions needed.

## Build and install

Needs the Xcode Command Line Tools (`xcode-select --install`).

```sh
./build.sh
cp -R build/DockMenu.app /Applications/
open /Applications/DockMenu.app
```

When updating, quit DockMenu and delete the old copy from `/Applications` first.

The app is signed ad hoc, so it is meant for the Mac it was built on.

## How it works

- The list is built when the menu opens and dropped when it closes. Nothing runs while it is closed: no timers, observers or polling.
- Choosing an app opens it through LaunchServices, like a Dock click, so hidden and minimized windows come back.
- Duplicate copies of an app, and programs without an app bundle, are activated directly by process.
- Apps are scanned on the first letter typed and forgotten when the menu closes. There is no background index and Spotlight is not used.
- The shortcut is a Carbon hot key, so it needs no Accessibility permission.
- If an app has not quit three seconds after Q, the menu closes and the app is brought forward so any save dialog is visible.
- Quitting the active app makes macOS close every open menu, so DockMenu reopens its own.

To start it at login, add it in System Settings > General > Login Items.
