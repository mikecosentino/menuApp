# CLAUDE.md

Guidance for working in this repo. See `README.md` for the user-facing feature tour.

## What this is

A macOS **menubar** app (Swift + AppKit + WebKit, SwiftPM) that pins websites as
`NSStatusItem`s; clicking one drops down a borderless `WKWebView` panel. No Dock icon
(`LSUIElement` / `.accessory`). macOS 13+; currently built against the macOS 26 SDK.

## Commands

```bash
swift build                          # debug build (fast iteration)
./build_app.sh                       # universal release .app, ad-hoc signed (local dev)
open menuApp.app                     # run it

# Notarized GitHub release (needs an Apple Developer account):
export MENUAPP_SIGN_IDENTITY="Developer ID Application: Mike Cosentino (Z35MHKNPB7)"
export MENUAPP_NOTARY_PROFILE="menuApp-notary"
./release.sh <version> --publish     # build -> notarize -> staple -> zip -> gh release
```

Releases are tagged `v<version>` and published as **pre-release** (0.x line). Tag points
at the pushed `main` HEAD, so commit + push before `--publish`.

## Architecture

- `AppDelegate` — owns the `MenuAppStore`, reconciles status items on change, builds the
  main menu (incl. the hidden "Window" menu that carries the keyboard shortcuts).
- `MenuAppStore` — `apps.json` persistence + Combine `@Published` list.
- `MenuApp` (`MenuAppModel.swift`) — the per-site model. **Custom `Codable` with
  `decodeIfPresent` fallbacks** — add every new field to the initializer *and* the
  decoder the same way, so old/new `apps.json` files keep loading.
- `StatusItemController` — one menubar item + its `WebWindowController`.
- `WebWindowController` — the panel, `WKWebView`, toolbar, and all in-window features
  (mute, hide/picker, theater, auto-hide toolbar, theater fit). Injected JS lives in the
  `static let ...Source` strings at the bottom.
- Window positions persist in `UserDefaults`; sizes live in the model.

## Feature notes / gotchas

- **Keyboard shortcuts**: the app has no *visible* menu bar (accessory app), but main-menu
  key equivalents still fire. `AppDelegate` routes ⌘T/⇧⌘M/⌘R/⌘W to the key
  `WebWindowController` via `frontWebController()`, gated by `validateMenuItem`.
- **Theater mode** (`theaterSource` JS): reparents the site's player element to `<body>`
  to escape wrapper/overlay stacking contexts. Per-site selectors in the `SITES` array
  (YouTube: `#movie_player`); generic `<video>`/iframe fallback otherwise. All DOM
  mutations are pushed to an `undo` stack and reversed on exit.
- **Theater fit-to-video**: JS reports the video aspect via the `menuAppHide` message
  handler; Swift resizes to it and locks the ratio during resize (`windowWillResize` +
  `ResizeGripView.constrainSize`). Exiting theater does **not** restore size — the
  current size persists (intentional).
- **Message protocol** (`userContentController(_:didReceive:)`): body is either a dict
  (`{active}` picker, `{theater, aspect}` / `{theaterAspect}` theater) or a bare selector
  string (hide). The proxy `WeakScriptMessageProxy` breaks the retain cycle.
- **Mute**: page-level via the private `_setPageMuted:` (guarded with `responds(to:)`).
  Reasserted on `didCommit`. Private API => no Mac App Store, fine for notarized direct.
- **Auto-hide toolbar**: `HoverRevealView` is a top-edge strip that returns `nil` from
  `hitTest` (clicks pass through to the page) but still gets tracking-area enter/exit.
- **Reconcile echo**: editing state round-trips store -> `update(with:)`. Mutate the
  controller's `app` locally *before* `onAppChanged?` and diff fields (e.g. `sizeChanged`,
  `isApplyingLocalEdit`) so you don't reload the page / kill playback on every edit.

## Verifying web features

There's no UI test rig; verify injected JS with a throwaway headless `WKWebView` harness
(`swiftc` a small program, load a page, `evaluateJavaScript`, print). Caveats learned:
headless WKWebView does **not** run the media decode pipeline, so `video.videoWidth`
stays `0`; and when you extract JS from the Swift `"""` strings, watch backslash escaping
(`\\.` in source becomes `\.` at runtime).

## Conventions

- **No emoji** in commit messages or release notes (README icon glyphs are fine).
- Match surrounding style; keep comments at the same density as neighboring code.
