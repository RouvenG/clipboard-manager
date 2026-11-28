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

### Download a release

[Releases](https://github.com/RouvenG/clipboard-manager/releases) have a DMG and a zip for Apple Silicon Macs. Open the DMG and drag ClipShelf into Applications.

Release builds are ad hoc signed unless the repository has Developer ID secrets (see [Releases and CI](#releases-and-ci)), so Gatekeeper blocks the first launch. Either right-click ClipShelf.app, choose Open and confirm, or clear the quarantine flag:

```bash
xattr -dr com.apple.quarantine /Applications/ClipShelf.app
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

## Releases and CI

- **CI** (`.github/workflows/ci.yml`) builds and tests every pull request and every push to `main` on a macOS 26 runner with Xcode 26.6, then uploads the Debug build as a zipped artifact. Its check is called `Build and test`, which is the required status check for `main`, so keep the job name stable.
- **Release** (`.github/workflows/release.yml`) runs when a `v*` tag is pushed. It builds the Release configuration for Apple Silicon (`ARCHS=arm64`), takes `MARKETING_VERSION` from the tag and the build number from the workflow run number, and publishes `ClipShelf-<version>.dmg` and `ClipShelf-<version>.zip` to a GitHub Release with generated notes. A tag with a suffix such as `v0.3.0-beta.1` becomes a prerelease with version 0.3.0.

To cut a release, merge everything into `main`, wait for CI to pass, then tag the commit and push the tag:

```bash
git switch main && git pull
```

```bash
git tag -a v0.2.0 -m "ClipShelf 0.2.0"
```

```bash
git push origin v0.2.0
```

To check the packaging locally before tagging:

```bash
xcodebuild -project ClipShelf.xcodeproj -scheme ClipShelf -configuration Release -derivedDataPath build ARCHS=arm64 ONLY_ACTIVE_ARCH=NO MARKETING_VERSION=0.2.0 CURRENT_PROJECT_VERSION=1 build
```

```bash
Scripts/package-release.sh build/Build/Products/Release/ClipShelf.app 0.2.0 dist
```

### Signing and notarization

Builds are ad hoc signed by default. The release workflow switches to Developer ID signing with the hardened runtime, and notarizes and staples the app and the DMG, only when these repository secrets exist. None of them are required.

| Secret | Used for |
| --- | --- |
| `MACOS_CERTIFICATE_P12` | Base64 of the exported Developer ID Application certificate and key (`base64 -i cert.p12`) |
| `MACOS_CERTIFICATE_PASSWORD` | Password of that `.p12` |
| `APPLE_TEAM_ID` | Team ID, used to pick the signing identity and for Apple ID notarization |
| `APPLE_API_KEY`, `APPLE_API_KEY_ID`, `APPLE_API_ISSUER_ID` | Notarization with an App Store Connect API key (the `.p8` contents, raw or base64). Preferred. |
| `APPLE_ID`, `APPLE_APP_SPECIFIC_PASSWORD` | Notarization with an Apple ID and an app-specific password, if there's no API key |

The first three enable signing. Signing plus one of the two credential sets enables notarization. Notarized releases open without the Gatekeeper workaround.

## License

MIT
