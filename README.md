# ClipShelf

A local, keyboard-first clipboard manager for macOS, modeled on [Paste](https://pasteapp.io). It keeps your clipboard history on your Mac only, shows it as a card shelf at the bottom of the screen, and lets you transform text (built-ins or your own TypeScript scripts) before pasting.

- **Local only:** no network code, no sync. History lives in `~/Library/Application Support/ClipShelf`.
- **Private by default:** skips anything apps mark as concealed or transient (passwords, one-time codes) and ignores copies from password managers. Add your own excluded apps in Settings.
- **Keyboard-first:** open with ⌥⌘V (change it in Settings > General), type to search, arrows to move, Return to paste.
- **Dev tooling:** detects code (monospace cards with a language badge) and transforms text with JSON, whitespace, case and encoding helpers or your own scripts.

## Requirements

- macOS 26 or later
- Xcode 26 (builds from the command line, no Xcode UI needed)
- Optional, for custom scripts: [bun](https://bun.sh), [deno](https://deno.com) or Node.js 22.6+

## Build and run

```bash
xcodebuild -project ClipShelf.xcodeproj -scheme ClipShelf -configuration Release -derivedDataPath build build
```

```bash
cp -R build/Build/Products/Release/ClipShelf.app ~/Applications/
```

```bash
open ~/Applications/ClipShelf.app
```

ClipShelf runs as a menu bar app (clipboard icon, no Dock icon). Run the tests with:

```bash
xcodebuild -project ClipShelf.xcodeproj -scheme ClipShelf -derivedDataPath build test
```

## Permissions

| Permission | Why | Where |
| --- | --- | --- |
| Accessibility | Paste back: ClipShelf puts the clip on the pasteboard and sends ⌘V to the app you were in. Without it, ClipShelf still copies the clip and you press ⌘V yourself. | System Settings > Privacy & Security > Accessibility |
| Pasteboard access | macOS 26 can ask before an app reads the clipboard programmatically. If it asks, choose to always allow ClipShelf, otherwise history stays empty. Settings > General shows the current state. | System Settings > Privacy & Security |

The build is ad hoc signed, so macOS treats every rebuild as a new app. After rebuilding, remove ClipShelf from the Accessibility list and add it again (or toggle it off and on).

Launch at login is a toggle in Settings > General (uses `SMAppService`; works best when the app lives in `~/Applications` or `/Applications`).

## Using the shelf

| Key | Action |
| --- | --- |
| ⌥⌘V | Open or close the shelf. To change it, click the shortcut in Settings > General and press a new one (it needs ⌘, ⌥ or ⌃, or use a function key). macOS doesn't report clashes with other apps' shortcuts, so pick one nothing else uses. |
| Typing | Search (text, source app, language) |
| ← → | Move between cards |
| Return | Paste the selected card |
| ⇧Return | Paste as plain text |
| ⌘1 to ⌘9 | Paste card 1 to 9 directly (add ⇧ for plain text) |
| ⌘K | Transform the selected card, then paste the result |
| ⌘O | Edit the selected text or link card (also Edit… in the card's right-click menu). ⌘↩ or ⌘S saves, Esc cancels. Changing rich text saves it as plain text. |
| ⌘R | Name the selected card (also Rename… in the right-click menu). Any card can have a name, including images and files. |
| ⌘P | Add to or remove from a pinboard (type a new name and Return to create one) |
| Drag a card onto a tab | Move it to that pinboard (hold ⌥ to keep it in the current one too). Dropping on History takes it off its pinboard. Cards also drag out into other apps. |
| Tab / ⇧Tab | Switch between History and pinboards |
| ⌘0 ⌘T ⌘I ⌘L ⌘F ⌘E | Filter: all, text, images, links, files, code |
| ⌘C | Copy the card without pasting |
| ⌘⌫ | Delete the card |
| Esc | Clear search, then filter, then close |

History older than the retention window (default 30 days, configurable, or forever) is pruned hourly. Items in pinboards never expire.

## Custom scripts

Put `.ts`, `.js` or `.mjs` files in `~/Library/Application Support/ClipShelf/Scripts` (Settings > Scripts > Open in Finder). Each one shows up in the ⌘K menu. A script default-exports a function that takes the clip text and returns the text to paste:

```ts
// @name Slugify
// @description Turn text into a URL slug
export default (input: string, context: { sourceApp?: string }): string =>
  input.toLowerCase().trim().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "");
```

`@name` and `@description` are optional. Async functions work too. Scripts run with the first runtime found (bun, then deno, then node), or the path you set in Settings. Deno runs them sandboxed (no network, reads limited to the scripts folder); bun and node run them with your user's permissions. Each run times out after 5 seconds. ClipShelf seeds `slugify.ts` as an example the first time it starts.

Writing these with an AI assistant works well: describe the transform and paste the contract above.

## Development

- `ClipShelf/` app sources (SwiftUI with AppKit for the panel, hotkey and paste), `ClipShelfTests/` Swift Testing tests.
- Debug builds listen for commands from `Scripts/debug-command.swift` so the shelf can be driven and snapshotted without screen recording, for example:

```bash
swift Scripts/debug-command.swift show "type:json" snapshot:/tmp/shelf.png state:/tmp/shelf.json
```

- Debug commands act on your real history. For test runs, quit your normal instance and start one with its own data folder:

```bash
open -n build/Build/Products/Debug/ClipShelf.app --args -ClipShelfSupportDirectory /tmp/clipshelf-test
```

## License

MIT
