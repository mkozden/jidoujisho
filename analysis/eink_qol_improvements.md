# QoL improvements for black-and-white e-ink devices

This report targets Android e-ink readers such as Onyx Boox, Bigme, Hisense,
PocketBook Era/InkPad Android models and Meebook. It covers what in jidoujisho
(`yuuna/`) works against e-ink today, what to change, and how. Line references are
to this branch.

E-ink panels:

- refresh slowly (120–450 ms for a full refresh)
- leave **ghosting** after partial updates
- show only around 16 grey levels, so tinted colours collapse into similar greys
- benefit from the screen being static: battery use is near zero while nothing
  changes

Anything that animates, fades, shimmers, or relies on colour or low contrast
therefore works against the device.

## Summary

| # | Change | Effort | Impact |
|---|---|---|---|
| 1 | "E-ink mode" master toggle (drives the items below) | S | — |
| 2 | Kill route transitions, ripples and scroll animations app-wide | S | High |
| 3 | Pure black/white high-contrast theme | M | High |
| 4 | Dictionary popup without translucency, colours or blur | S | High |
| 5 | Static loading indicators | S | Medium |
| 6 | Reader page turns without animation (ttu and Mokuro) | S–M | High |
| 7 | Tap-zone page turning in readers | M | High |
| 8 | Hardware page-turn keys beyond volume keys | S | High |
| 9 | Optional full refresh every N page turns | M | Medium |
| 10 | Don't hold a wakelock while reading on e-ink | S | Medium |
| 11 | Larger touch targets / font scale for dictionary results | S | Medium |
| 12 | Auto-detect common e-ink devices to suggest the mode | S | Low |

S = under a day, M = 1–3 days.

---

## 1. One "E-ink mode" toggle

Store it in the `appModel` Hive box as `e_ink_mode`, next to `is_dark_mode`
(`app_model.dart:1248`). Expose `bool get isEinkMode` on `AppModel`, and put the
toggle in the existing home-page overflow menu, next to dark mode
(`home_page.dart:~321`). Like `toggleDarkMode()` (`app_model.dart:1256`), it can
simply call `Restart.restartApp()`. That avoids threading the flag through
rebuilds. Every item below reads this flag, so users without e-ink are unaffected.

## 2. Remove animations app-wide

Most of the motion comes from a few places, so this is cheap.

- **Route transitions.** Pages are pushed with `MaterialPageRoute`
  (`app_model.dart:2484, 2491, 2624`; `home_page.dart:294`), which animates on
  Android. Add a no-op `PageTransitionsTheme` to both `ThemeData`s
  (`app_model.dart:432` and `:515`). That changes every route at once:

  ```dart
  class _NoTransitionsBuilder extends PageTransitionsBuilder {
    const _NoTransitionsBuilder();
    @override
    Widget buildTransitions<T>(PageRoute<T> route, BuildContext context,
        Animation<double> a, Animation<double> b, Widget child) => child;
  }
  // in ThemeData(...)
  pageTransitionsTheme: isEinkMode
      ? const PageTransitionsTheme(builders: {
          TargetPlatform.android: _NoTransitionsBuilder(),
        })
      : null,
  splashFactory: isEinkMode ? NoSplash.splashFactory : null,
  ```

  Several overlay routes already use zero-duration `PageRouteBuilder`s
  (creator, `app_model.dart:~2427`), so this is consistent with existing code.
- **Ripples and highlights.** `splashFactory: NoSplash.splashFactory` (above),
  plus `highlightColor: Colors.transparent`.
- **Scroll-to-top.** `home_page.dart:146-149` uses `animateTo(...200 ms)`. Use
  `jumpTo` in e-ink mode.
- **Fades.**
  - `FadeInImage` in the history grids (`history_reader_page.dart`,
    `history_player_page.dart`, `media_item_dialog_page.dart`,
    `immersion_kit_sentences_dialog_page.dart`): set `fadeInDuration` and
    `fadeOutDuration` to `Duration.zero`.
  - `AnimatedOpacity` in `browser_source_page.dart` and `player_source_page.dart`:
    set `duration: Duration.zero`.
- **Marquee.** `JidoujishoMarquee` (`utils/components/jidoujisho_marquee.dart`)
  scrolls long titles forever, which means constant partial refresh on e-ink. In
  e-ink mode, render a `Text` with `overflow: TextOverflow.ellipsis` instead.
  That is one branch inside the component.
- **Overscroll.** Replace `BouncingScrollPhysics` with `ClampingScrollPhysics`.
  Set `ScrollConfiguration(behavior: ...copyWith(overscroll: false))` once
  around `MaterialApp` (`main.dart:~353`).
- **System-level.** Respect Android's "Remove animations" setting.
  `MediaQuery.of(context).disableAnimations` is already exposed; the e-ink flag
  can simply OR with it.

## 3. A real black/white theme

The current light theme is already white-based, but it uses:

- red accents (`ColorScheme.fromSwatch()` with red primary)
- grey inactive tracks
- 30-grey dark cards (`Color(255,30,30,30)` in `darkTheme`)

Red renders as mid-grey on e-ink and becomes nearly invisible against white.

Add a third `ThemeData get einkTheme`:

- `scaffoldBackgroundColor`, `cardColor`, `dialogBackgroundColor`,
  `canvasColor`: `Colors.white`
- `colorScheme`: `ColorScheme.light(primary: Colors.black, secondary: Colors.black, surface: Colors.white, onSurface: Colors.black, …)`
- `dividerColor`: black at 1 px
- `unselectedWidgetColor` and inactive slider tracks: black at full opacity, with
  state shown by outline or fill rather than by tint
- `textTheme` with weight ≥ 500 for body text; thin strokes ghost badly
- `elevation: 0` everywhere, with borders instead of shadows. Shadows render as
  muddy grey bands.
- `BottomNavigationBar` / `NavigationBar`: selected item underlined or inverted
  (white on black), not coloured

Then, in `main.dart`, pass `theme: isEinkMode ? einkTheme : theme`. Dark mode
stays available, because some users prefer white-on-black on e-ink. A dark
variant of the same theme just swaps black and white.

**Hard-coded colours to audit.** Search for `Colors.red`, `Colors.grey` and
`Theme.of(context).unselectedWidgetColor`. The quick-action colours in
`creator_model`/`quickActionColorProvider` and the tag colours in
`JidoujishoTag` should fall back to black with a white label in e-ink mode.

## 4. Dictionary popup

This is the most-used surface while reading.

- **ttu.** `setDictionaryColors()` in `reader_ttu_source_page.dart:191-238` maps
  each ttu theme to a background with `dictionaryEntryOpacity`. Translucency
  over book text is unreadable on e-ink. In e-ink mode, force opacity to 1.0 with
  a pure white or black background and a 1–2 px black border.
- **Mokuro.** The same applies to its popup.
- **Everywhere.**
  - Avoid `BlurryContainer` (the `blurrycontainer` dependency) in e-ink mode.
    Blur is expensive and turns into grey noise.
  - Pitch-accent graphs and frequency tags should use solid black strokes and
    outlined chips.
  - Highlighted selection in readers: `::selection` is injected as
    `background: rgba(255,0,0,0.6)` (`reader_ttu_source_page.dart`, in
    `javascriptToExecute`). Make it `background:#000;color:#fff` in e-ink mode.
    That one string can be parameterised from Dart.

## 5. Loading indicators

`CircularProgressIndicator` spins forever. It appears in `base_page.dart:98`
and about 20 other call sites, mostly via `buildLoading()`. In e-ink mode,
`buildLoading()` should return a static "Loading…" label or an
`Icon(Icons.hourglass_empty)`. Doing it in `BasePageState.buildLoading` covers
most screens in one place.

## 6. Reader page turns

- **ttu (paginated).** Page flips are instant (no CSS transition), which is
  already good. Continuous mode uses `behavior: 'smooth'` scrolling
  (`page-manager-continuous.ts:47`) and a JS smooth-scroll for wheel events.
  Either recommend paginated mode in e-ink mode, or inject
  `html { scroll-behavior: auto !important; }` and set
  `localStorage.autoScrollMultiplier` low.
  - Volume-key paging dispatches a synthetic `wheel` on `document.body`
    (`leftArrowSimulateJs` / `rightArrowSimulateJs`). That only works in
    paginated mode, because continuous mode listens on the content element. A
    one-line fix is to dispatch on `document.querySelector('.book-content')`
    when it exists.
- **ttu themes.** The new bundle's `light-theme` has a white background, but its
  text is black at 87 % alpha, which renders as dark grey. Its selection colour
  is mid-grey, and ttu has no custom-theme setting.
  - In e-ink mode, inject CSS that forces `.book-content { color: #000 !important; }`
    and the `::selection` override from item 4.
  - Set `localStorage.theme = 'light-theme'` (or `black-theme` for dark) on first
    run, as the app already does for `writingMode` and `fontSize` when the
    database is empty (`reader_ttu_source.dart`, `'empty'` branch).
- **Mokuro (legacy HTML).**
  - It uses panzoom with animated transitions. Inject a call to mokuro's panzoom
    instance with `{ animate: false }`, and CSS
    `* { transition: none !important; animation: none !important; }`.
  - The existing dark-mode override (`injectDarkTheme`,
    `mokuro_catalog_browse_page.dart:391`) shows the pattern.
  - For greyscale scans, add a CSS `filter: contrast(1.15)` option. Many e-ink
    users want slightly stronger blacks on screentones.
- **Native Mokuro reader** (see `mokuro_reader_feasibility.md`, option C). Build
  it with instant page swaps from the start. Decode images with
  `cacheWidth = screen width` so swaps don't stall.

## 7. Tap zones

E-ink users usually page by tapping the screen edges. Today page turns come only
from swipes (ttu's own `swipeThreshold`) or volume keys. The tap is already
intercepted for lookup (`tapToSelect`), so tap zones have to coexist with it:

- Add a setting with three zones: left 25 % = back, right 25 % = forward
  (mirrored for RTL/vertical), middle = lookup or menu.
- Implement it in the injected `tapToSelect`. If
  `e.clientX < innerWidth * 0.25` and the tap did not hit a character
  (`index === -1`), dispatch the page-turn JS instead of posting a lookup. A
  tap that lands on a character still looks it up, so mining is unaffected.
- Mokuro: the same logic against `.textBox` hits, calling `prevPage()` or
  `nextPage()`.

## 8. Hardware page-turn keys

Many e-ink devices and Bluetooth page turners send `PAGE_UP` / `PAGE_DOWN`,
`DPAD_LEFT` / `DPAD_RIGHT` or media keys rather than volume keys. The ttu and
Mokuro pages only check `LogicalKeyboardKey.audioVolumeUp/Down` in their `Focus`
`onKey` callbacks (`reader_ttu_source_page.dart:~100-145`,
`mokuro_catalog_browse_page.dart:~445-490`). Extend both checks to:

- `pageUp`/`pageDown`
- `arrowLeft`/`arrowRight`/`arrowUp`/`arrowDown`
- `mediaTrackPrevious`/`mediaTrackNext`

This is about 10 lines per page, and benefits non-e-ink users with page-turner
remotes too. While touching this, migrate the deprecated `onKey` to `onKeyEvent`.

## 9. Periodic full refresh

Ghosting accumulates over partial refreshes. Boox firmware exposes per-app
refresh modes, but there is no portable API.

A portable trick is to flash the reader area to black for one frame, then to
white, every N page turns. A `Stack` with a full-screen `ColoredBox` toggled
for ~50 ms forces most EPD controllers into a full update. Make N configurable,
with 0 meaning off.

For Onyx devices specifically, the Onyx SDK
(`com.onyx.android.sdk:onyxsdk-device`) offers `EpdController.invalidate(view,
UpdateMode.GC)` and per-view fast modes. It is distributed through Onyx's own
Maven repository. Gate it behind a manufacturer check, because it is
device-specific.

## 10. Wakelock

`AppModel.openMedia` calls `Wakelock.enable()` (`app_model.dart:2474`) for every
media type. On e-ink, a static page costs nothing to display, and the device's
own sleep timer is the main battery saver. In e-ink mode, skip the wakelock for
reader sources (`mediaSource.mediaType == ReaderMediaType.instance`) and keep it
for the video player.

## 11. Readability of dictionary results

E-ink screens are often 6–7.8" at ~300 ppi, and the dictionary popup inherits
`AppModel.textStyle` sizes:

- Add a dictionary font-scale setting, applied with a `MediaQuery` override
  around the popup.
- Increase hit-target sizes (`JidoujishoIconButton`) to at least 48 dp.
- Avoid 1 px grey separators; use black dividers or spacing.

## 12. Device detection (optional)

`DeviceInfoPlugin().androidInfo` is already loaded at startup
(`app_model.dart:~1143`). If `manufacturer` matches a short list (`ONYX`,
`Bigme`, `Hisense` A-series models, `PocketBook`, `Meebook`, `Boyue`), show a
one-time snackbar: "E-ink display detected — enable E-ink mode?". Never enable
it silently.

---

## Suggested order

1. Items 1, 2, 5 and 8: an afternoon, and immediately noticeable.
2. Items 3, 4 and 10: the theme work.
3. Items 6 and 7: reader-specific changes, best done together with the native
   Mokuro reader if that goes ahead.
4. Items 9 and 12 last, because they are device-specific.

## Compatibility notes

- WebView version: e-ink devices often ship old Android System WebView builds
  and sometimes cannot update them through Play. The updated ttu bundle targets
  the Vite 5 default browser baseline (`modules`: Chrome 87+, from late 2020),
  the same as the previous Vite 4 bundle. Any device that ran the old reader runs the new one.
- Every item above is behind the e-ink flag, or is a pure bug fix (items 6 and
  8). Existing users see no change unless they opt in.
