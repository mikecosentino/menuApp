# menuApp

Pin websites to your macOS menubar. Click an icon and a window drops down showing
that site — mobile by default, but the user agent is configurable per app. Drag it
anywhere and resize it to taste; it remembers both the size and where you put it.

## Build & run

```bash
./build_app.sh          # compiles + packages menuApp.app
open menuApp.app        # launch (lives in the menubar, no Dock icon)
cp -r menuApp.app /Applications/   # optional: install
```

For quick iteration without packaging:

```bash
swift build && .build/debug/menuApp
```

Requires macOS 13+ and the Swift toolchain (ships with Xcode / Command Line Tools).

## Using it

- **Click** a site's menubar icon → toggles its window open/closed under the icon.
- **Drag** the window's top bar to reposition it anywhere; the spot is remembered.
- **Resize** by dragging the grip in the bottom-right corner. The new size persists
  and is reflected live in the Settings width/height fields.
- **Pin** (📌 in the window header) keeps the window open when it loses focus.
  Unpinned windows close when you click away, like a popover.
- The header splits its controls: **close** (✕), **back** (‹), **home** (⌂), and
  **reload** (↻) sit on the left; **always-on-top** (⬆) and **pin** (📌) sit on the right.
- **Right-click** a site icon for Open / Reload / Edit / Remove / Settings / Quit.
- The **⊞ home icon** menu has *Add Menu App…*, *Settings…*, and *Quit*.

## Settings

Open **Settings…** from any menu to add, edit, and remove menuApps. Per-site you can set:

- **Name** and **URL** (scheme optional — `example.com` becomes `https://example.com`)
- **Window size** — Width/Height steppers plus iPhone / Compact / Tall presets.
  Manually resizing the window updates these fields live.
- **User Agent** — Mobile Safari (default), Desktop Safari, Desktop Chrome,
  Desktop Edge, or a Custom string. Lets you load sites that gate by browser
  (e.g. Slack) or force the desktop layout.
- **Keep open when it loses focus** (pin behavior)
- **Fallback icon** — pick from a searchable catalog of ~130 SF Symbols, or type any
  exact SF Symbol name. Used as the menubar icon when a site's favicon can't be fetched.

Favicons are fetched automatically and used as the menubar icon when available.

## How it works

| Concern | Implementation |
|---|---|
| Menubar icons | One `NSStatusItem` per site + a "home" item (`StatusItemController`) |
| Web window | Borderless, resizable, floating `NSPanel` with a draggable header + `WKWebView` (`WebWindowController`) |
| Resizing | Bottom-right `ResizeGripView`; the resulting size is written back to the model |
| User agent | `WKWebView.customUserAgent` driven by the per-app `UserAgentMode` (Mobile/Desktop Safari, Chrome, Edge, Custom) |
| Settings UI | SwiftUI (`SettingsView`) hosted in an `NSWindow`; icon picker over `SymbolCatalog` |
| Persistence | Sites (incl. size + UA) → `~/Library/Application Support/menuApp/apps.json`; window positions → `UserDefaults` |
| No Dock icon | `LSUIElement` + `NSApp.setActivationPolicy(.accessory)` |

Login sessions persist via the default `WKWebsiteDataStore`, so signed-in sites stay
signed in between launches.

## Notes & limitations

- **Build from source** (`./build_app.sh`). The bundle is ad-hoc signed, not
  notarized — a prebuilt `.app` would trip Gatekeeper's "unidentified developer"
  warning, but building locally avoids that entirely.
- **App Transport Security is disabled** (`NSAllowsArbitraryLoads`) so non-HTTPS
  sites load. Reasonable for a personal web wrapper; remove it in `build_app.sh`
  if you only ever load HTTPS.
- **Sessions are shared.** All menuApps use the default `WKWebsiteDataStore`, so a
  login on one wrapper is shared with others on the same domain.
- Some sites with enterprise SSO / device-trust (e.g. O365 Conditional Access)
  won't sign in inside an embedded `WKWebView` — that's a platform restriction,
  not a bug.

## License

MIT — see [LICENSE](LICENSE).

## Project layout

```
Sources/menuApp/
  main.swift                  entry point
  AppDelegate.swift           wires store ↔ status items, reconciles on change
  MenuAppModel.swift          the MenuApp model
  MenuAppStore.swift          JSON persistence + Combine publishing
  StatusItemController.swift  one menubar item + its window
  WebWindowController.swift   the draggable, resizable web panel
  DragHandleView.swift        header that drags the window
  ResizeGripView.swift        bottom-right corner resize handle
  IconLoader.swift            favicon fetch + letter/symbol fallback
  SymbolCatalog.swift         the searchable SF Symbol catalog
  SettingsView.swift          SwiftUI settings
  SettingsWindowController.swift  hosts settings in a window
build_app.sh                  packages everything into menuApp.app
```
