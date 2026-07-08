# menuApp

Pin websites to your macOS menubar. Click an icon and a window drops down showing
that site — mobile by default, but the user agent is configurable per app. Drag it
anywhere and resize it to taste; it remembers both the size and where you put it.
Strip away page clutter with Safari-style click-to-hide, mute a window's audio, or
pop into a site-aware theater mode that isolates the video and fits the window to it.
Optionally auto-hide the toolbar for a chromeless window, and drive it all from the
keyboard.

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
- The header splits its controls: **close** (✕), **back** (‹), **home** (⌂),
  **reload** (↻), and **copy URL** (🔗) sit on the left; **mute** (🔈), **theater**
  (▶▭), **hide elements** (eye-slash), **always-on-top** (⬆) and **pin** (📌) sit on
  the right.
- **Copy URL** (link icon, ⇧⌘C) — copies the page's current address to the clipboard;
  the icon flashes a checkmark to confirm.
- **Keyboard shortcuts** act on the focused window: **⌘T** theater, **⇧⌘M** mute,
  **⌘R** reload, **⌘W** close, **⇧⌘C** copy URL.
- **Mute** (speaker icon, ⇧⌘M) — silences that window's audio at the page level
  (covers HTML media and Web Audio). Remembered per site and reasserted across
  page navigations.
- **Hide distracting items** (eye-slash icon) — Safari-style click-to-hide. Toggle it
  on, then click any element (sidebars, comments, ads, banners) to remove it; press
  **Esc** to finish. Hidden elements are saved **per site** and stay hidden every time
  you reopen it. Recover from the menubar icon's right-click menu: *Undo Last Hide*
  steps back one element at a time, *Show All Hidden Items* clears them all.
- **Theater mode** (play-rectangle icon, ⌘T) — isolates the video to fill the window
  and hides everything else. It's **site-aware**: it lifts the site's real player
  element out of the page (so it escapes wrapper/overlay stacking — e.g. YouTube keeps
  its native controls), with a generic `<video>`/embed fallback for other sites. With
  **Fit window to video** on (default), entering theater resizes the window to the
  video's aspect ratio so there are no bars above or below it, and keeps that ratio
  while you resize; the size you land on becomes the window's new size. Toggle off to
  restore the page; playback isn't interrupted.
- **Right-click** a site icon for Open / Reload / Undo Last Hide / Show All Hidden Items
  / Edit / Remove / Settings / Quit.
- The **⊞ home icon** menu has *Add Menu App…*, *Settings…*, and *Quit*.

## Settings

Open **Settings…** from any menu to add, edit, and remove menuApps. Per-site you can set:

- **Name** and **URL** (scheme optional — `example.com` becomes `https://example.com`)
- **Window size** — Width/Height steppers plus iPhone / Compact / Tall presets.
  Manually resizing the window updates these fields live.
- **User Agent** — Mobile Safari (default), Desktop Safari, Desktop Chrome,
  Desktop Edge, or a Custom string. Lets you load sites that gate by browser
  (e.g. Slack) or force the desktop layout.
- **Always on top** and **Keep open when it loses focus** (pin behavior)
- **Auto-hide toolbar** — hides the window's toolbar to maximize the page; move the
  pointer to the top edge to reveal it.
- **Fit window to video in theater mode** (default on) — see *Theater mode* above.
- **Fallback icon** — pick from a searchable catalog of ~130 SF Symbols, or type any
  exact SF Symbol name. Used as the menubar icon when a site's favicon can't be fetched.

Favicons are fetched automatically and used as the menubar icon when available.

## How it works

| Concern | Implementation |
|---|---|
| Menubar icons | One `NSStatusItem` per site + a "home" item (`StatusItemController`) |
| Web window | Borderless, resizable, floating `NSPanel` with a draggable header + `WKWebView` (`WebWindowController`) |
| Resizing | Bottom-right `ResizeGripView`; the resulting size is written back to the model. In theater "fit", the grip and `windowWillResize` lock the video's aspect ratio |
| User agent | `WKWebView.customUserAgent` driven by the per-app `UserAgentMode` (Mobile/Desktop Safari, Chrome, Edge, Custom) |
| Mute | Page-level mute via WebKit's `_setPageMuted:` (covers HTML media + Web Audio), persisted per app and reasserted on navigation |
| Auto-hide toolbar | Web view fills the window; a click-through `HoverRevealView` strip at the top edge fades the toolbar in/out on hover |
| Hide / theater | `WKUserScript`s injected at document start: an engine applies saved selectors as `display:none` (with a `MutationObserver` to survive SPA re-renders), a picker generates a stable selector per click and posts it back via `WKScriptMessageHandler`, and theater mode reparents the site's player element to `<body>` (per-site registry + generic fallback) and can fit the window to the reported video aspect ratio. Selectors persist in `hiddenSelectors` on the model |
| Keyboard shortcuts | A hidden "Window" menu in the app's main menu carries the key equivalents (⌘T/⇧⌘M/⌘R/⌘W); `AppDelegate` routes them to the key `WebWindowController`, gated by `validateMenuItem` |
| Settings UI | SwiftUI (`SettingsView`) hosted in an `NSWindow`; icon picker over `SymbolCatalog` |
| Persistence | Sites (incl. size + UA) → `~/Library/Application Support/menuApp/apps.json`; window positions → `UserDefaults` |
| No Dock icon | `LSUIElement` + `NSApp.setActivationPolicy(.accessory)` |

Login sessions persist via the default `WKWebsiteDataStore`, so signed-in sites stay
signed in between launches.

## Notes & limitations

- **Local builds are ad-hoc signed** (`./build_app.sh`) and fine to run on your own
  machine. Published releases are Developer ID-signed and notarized (see *Releasing*),
  so downloads open without Gatekeeper warnings.
- **App Transport Security is disabled** (`NSAllowsArbitraryLoads`) so non-HTTPS
  sites load. Reasonable for a personal web wrapper; remove it in `build_app.sh`
  if you only ever load HTTPS.
- **Sessions are shared.** All menuApps use the default `WKWebsiteDataStore`, so a
  login on one wrapper is shared with others on the same domain.
- Some sites with enterprise SSO / device-trust (e.g. O365 Conditional Access)
  won't sign in inside an embedded `WKWebView` — that's a platform restriction,
  not a bug.
- **Hide / theater can't reach inside cross-origin iframes.** You can hide or
  enlarge the iframe element itself, but not the elements within a third-party
  embed — same-origin policy, same as Safari. Saved selectors that no longer match
  after a site redesign simply do nothing (use *Show All Hidden Items* to reset).
- **Theater "fit to video" needs a readable video.** It reads the aspect ratio from
  the page's `<video>`; cross-origin iframe embeds don't expose their dimensions, so
  those are isolated but not auto-fit.
- **Mute uses a private WebKit method** (`_setPageMuted:`, guarded so it no-ops if it
  ever disappears). It's fine for notarized/direct distribution but rules out the Mac
  App Store.

## Releasing

Published releases are universal (Apple Silicon + Intel), Developer ID-signed,
notarized, and stapled, so a downloaded build opens with no Gatekeeper prompt.

**One-time setup** (requires an Apple Developer account):

1. Create a **Developer ID Application** certificate — Xcode → Settings → Accounts →
   Manage Certificates → **+** → *Developer ID Application* (or on
   developer.apple.com → Certificates). Note: only the account holder can create it.
   Confirm it's installed: `security find-identity -v -p codesigning`.
2. Store notarization credentials in a keychain profile (an
   [app-specific password](https://support.apple.com/102654) for your Apple ID):

   ```bash
   xcrun notarytool store-credentials menuApp-notary \
     --apple-id "you@example.com" --team-id "YOURTEAMID" --password "app-specific-pw"
   ```

**Cut a release:**

```bash
export MENUAPP_SIGN_IDENTITY="Developer ID Application: Your Name (YOURTEAMID)"
export MENUAPP_NOTARY_PROFILE="menuApp-notary"
./release.sh 1.1.0 --publish      # build → notarize → staple → zip → GitHub release
```

`release.sh` writes the version into the bundle, notarizes (waits for Apple),
staples the ticket, and — with `--publish` — creates the `v1.1.0` tag and uploads
`menuApp-1.1.0.zip` via `gh`. Omit `--publish` to produce the notarized zip without
releasing.

## Download

Grab the latest `menuApp-*.zip` from [Releases](../../releases), unzip, and move
`menuApp.app` to `/Applications`. Notarized builds just open — no right-click dance.

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
build_app.sh                  packages everything into menuApp.app (universal)
release.sh                    signs + notarizes + staples + publishes a release
```
