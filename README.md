# menuApp

Pin websites to your macOS menubar. Click an icon and an iPhone-sized window drops
down showing the **mobile** version of that site. Drag it anywhere; it remembers
where you put it.

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
- **Pin** (📌 in the window header) keeps the window open when it loses focus.
  Unpinned windows close when you click away, like a popover.
- **Reload** (↻) and **close** (✕) live in the header too.
- **Right-click** a site icon for Open / Reload / Edit / Remove / Settings / Quit.
- The **⊞ home icon** menu has *Add Menu App…*, *Settings…*, and *Quit*.

## Settings

Open **Settings…** from any menu to add, edit, and remove menuApps. Per-site you can set:

- **Name** and **URL** (scheme optional — `example.com` becomes `https://example.com`)
- **Window size** — Width/Height steppers plus iPhone / Compact / Tall presets
- **Keep open when it loses focus** (pin behavior)
- **Fallback icon** — an SF Symbol used when a site's favicon can't be fetched

Favicons are fetched automatically and used as the menubar icon when available.

## How it works

| Concern | Implementation |
|---|---|
| Menubar icons | One `NSStatusItem` per site + a "home" item (`StatusItemController`) |
| Web window | Borderless, floating `NSPanel` with a draggable header + `WKWebView` (`WebWindowController`) |
| Mobile rendering | `WKWebView.customUserAgent` set to an iPhone Safari UA |
| Settings UI | SwiftUI (`SettingsView`) hosted in an `NSWindow` |
| Persistence | Sites → `~/Library/Application Support/menuApp/apps.json`; window positions → `UserDefaults` |
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
  WebWindowController.swift   the draggable iPhone-sized web panel
  DragHandleView.swift        header that drags the window
  IconLoader.swift            favicon fetch + letter/symbol fallback
  SettingsView.swift          SwiftUI settings
  SettingsWindowController.swift  hosts settings in a window
build_app.sh                  packages everything into menuApp.app
```
