# Feasibility: built-in Mokuro reader with `.mokuro` support

**Verdict: feasible.** The recommended first step is small, about 500–800 lines of
Dart and no new dependencies. It reuses the Mokuro reader that jidoujisho already
ships. A fully native reader is also feasible and is the better long-term
target for e-ink devices, but it is roughly a 3–5× larger job.

Sources examined:

- `kha-white/mokuro` @ `9f79b12` (v0.2.5, July 2026)
- `Gnathonic/mokuro-reader` @ `bfaeb48` (v1.10.0, October 2026)
- this repository's `yuuna/` app

---

## 1. What exists today

jidoujisho already has a Mokuro reader source (`ReaderMokuroSource`,
`yuuna/lib/src/media/sources/reader_mokuro_source.dart`). It supports only the
**legacy** mokuro output: one self-contained `.html` file per volume, with
images linked by relative path.

| Piece | Where | Role |
|---|---|---|
| Source | `reader_mokuro_source.dart` | Picks a `.html` file (`allowedExtensions: ['.html']`, l.219) or a URL. A headless WebView checks for `.pageContainer` and `#popupAbout`, then builds a `MediaItem` (title, page count, cover from the first page's CSS `background-image`). |
| Reader | `mokuro_catalog_browse_page.dart` (~1200 lines) | `InAppWebView` on the HTML file. Injected JS does tap-to-lookup with `caretRangeFromPoint` inside `.textBox`, page images for card creation (via `.pageContainer` `background-image`), progress via mokuro's `localStorage` (`page_idx`), volume-key paging (`nextPage()`/`prevPage()`) and a dark-theme CSS override. |
| Catalogs | `MokuroCatalog` (Isar) + dialogs | Browse online sites that host mokuro HTML. |
| Data model | `utils/misc/mokuro_payload.dart` | `MokuroPayload`, `MokuroImage` and `MokuroBlock`. **Unused**; this looks like groundwork for a native renderer. |

**History matters for compatibility.** `MediaItem.uniqueKey` is
`reader_mokuro/<mediaIdentifier>`. A history row whose source is no longer
registered throws when the history grid builds (`MediaItem.getMediaSource`).
`ReaderMokuroSource` and its `uniqueKey` must therefore stay registered. New
functionality should extend it, or sit beside it as a new source.

## 2. The `.mokuro` format (mokuro ≥ 0.2.0)

Upstream now treats the legacy HTML as frozen ("will not be developed further").
Its preferred output is one JSON `.mokuro` file per volume, stored next to the
image folder or archive:

```
manga_title/
  vol1/            ← images (.jpg .jpeg .png .webp .avif), any nesting
  vol1.mokuro      ← OCR + metadata
  vol2.cbz         ← or a .zip/.cbz archive of images
  vol2.mokuro
```

The volume is matched by file stem: `vol1.mokuro` belongs with `vol1/`, `vol1.cbz`
or `vol1.zip`.

```jsonc
{
  "version": "0.2.5",
  "title": "manga_title",          "title_uuid": "…",
  "volume": "vol1",                "volume_uuid": "…",
  "pages": [
    {
      "version": "0.2.5",
      "img_width": 1654, "img_height": 2400,
      "img_path": "001.jpg",            // relative to the volume folder or archive root
      "blocks": [
        {
          "box": [xmin, ymin, xmax, ymax],          // image pixels
          "vertical": true,
          "font_size": 36.0,
          "lines": ["吾輩は猫", "である"],
          "lines_coords": [[[x,y],[x,y],[x,y],[x,y]], …]   // a quadrilateral per line
        }
      ]
    }
  ]
}
```

Properties that matter for a reader:

- All geometry is in source-image pixels, so the overlay scales with the image.
- Each line has its own quadrilateral. Tap-to-character can therefore be computed
  geometrically, without laying out any text.
- Pages are already in reading order (natsorted by path). `img_path` is the only
  link to the image.
- There are no images inside the file. Typical size is 100–500 KB per volume.

## 3. Implementation options

### Option A — convert `.mokuro` to legacy HTML at import time (recommended first step)

Port mokuro's `legacy/overlay_generator.py` (`get_page_html`, `get_box_style`,
`get_container_style`; about 80 lines of logic) to Dart. When the user picks a
`.mokuro` file:

1. Locate the volume images: the sibling folder with the same stem, or a
   `.cbz`/`.zip` with the same stem. Extract archives into app storage;
   `flutter_archive` and `async_zip` are already dependencies.
2. Generate `<stem>.html` in app storage. It contains the `.pageContainer` and
   `.textBox` markup, with `background-image` pointing to `file://` image URIs,
   plus mokuro's own `script.js`, `styles.css` and `panzoom.min.js` (55 KB, GPL-3.0
   like jidoujisho) bundled as Flutter assets and inlined.
3. Hand that file to the existing `ReaderMokuroSource` and
   `MokuroCatalogBrowsePage` path, so a new `MediaItem` is created exactly as for
   a picked `.html` file.

What this reuses unchanged:

- tap-to-lookup and highlight
- card image capture
- the progress save and restore
- volume-key paging and dark mode
- history, the cover and the page count

The work is about 500–800 lines:

- a generator, about 150 lines
- a volume locator and archive extraction, about 150 lines
- picker changes (`.html` plus `.mokuro`), about 50 lines
- a small "regenerate" path for when the cache is cleared, about 100 lines
- tests: the generated DOM must match the Python output for a sample volume

Risks and limitations:

- Storage: extracted archives take as much space again as the archive. Offer
  "delete extracted images when removed from history".
- Android scoped storage: picking a folder through `FilesystemPicker` already
  works (the app holds `MANAGE_EXTERNAL_STORAGE`). Reading a sibling folder next to
  a picked file needs that same permission, which the existing `.html` flow
  already relies on.
- It inherits the legacy reader's UX limits: CSS zoom, a WebView, and animated
  panzoom transitions. The animations are a problem on e-ink; see the e-ink report.

### Option B — bundle `mokuro-reader` (the official web reader), like ttu

`Gnathonic/mokuro-reader` is a SvelteKit 2 / Svelte 5 SPA:

- license GPL-3.0, which is compatible
- `ssr = false`
- storage in Dexie (IndexedDB)
- imports `.mokuro` together with folders, `.zip` or `.cbz`

It could be served from the APK by the new `LocalWebAssetsServer`
(`yuuna/lib/src/utils/misc/local_web_assets_server.dart`), as the ttu reader is.

Required changes:

- swap `adapter-auto` for `adapter-static` with an `index.html` fallback
- add an SPA fallback to `LocalWebAssetsServer` for its `[...catchall]` route
  (about 10 lines)
- write new injected lookup JS against its `TextBoxes.svelte` DOM
- read history from its Dexie schema, which is versioned and has changed often
  (see its `db-v3` tests)

Pros: the most complete feature set (catalog, series, progress, cloud sync,
reading stats) at the lowest jidoujisho-side code cost.

Cons:

- Import goes through the WebView file chooser. Android WebView cannot pick
  directories (`webkitdirectory`), so users would need `.cbz`/`.zip` plus `.mokuro`.
- All images are copied into IndexedDB, which doubles storage.
- Upstream moves fast (renovate-driven, schema churn), so each update needs a
  coupling re-check like the ttu one in `yuuna/tool/ttu/README.md`.
- The JS bundle is heavy, and old WebViews on e-ink devices may fail on Svelte 5
  output.

### Option C — native Flutter reader (best long-term, best for e-ink)

Parse `.mokuro` into the existing (unused) `MokuroPayload`, `MokuroImage` and
`MokuroBlock` classes. Render each page as an `Image` in an
`InteractiveViewer`, with the blocks as hit-test regions in image coordinates.

**Lookup without text layout.** On tap, find the block and then the line whose
`lines_coords` quad contains the point. Project the point onto the line's main
axis (top→bottom for vertical, left→right for horizontal) and take
`index = floor(t * line.length)`. Join the block's lines into the lookup text,
offsetting the index by the lengths of the previous lines. Highlight the
matched span by drawing that fraction of the quad. Flutter has no vertical text
layout, and this avoids needing it.

**Integration** is the standard source pattern:

- a new `ReaderMokuroNativeSource` with a new `uniqueKey`, so legacy history
  rows keep working
- a `BaseSourcePage` subclass, which provides the dictionary popup,
  `searchDictionaryResult` and creator hooks for free
- export it from `media.dart` and `pages.dart`, and register it in
  `AppModel.populateMediaSources()`
- volume keys via the same `Focus`/`onKey` pattern used by the ttu and Mokuro
  pages
- card images: the page image file is already on disk, which is simpler than
  today's `background-image` scraping
- progress: `MediaItem.position` and `duration` (page index and count), as the
  current Mokuro source does

| Area | Estimate |
|---|---|
| Parsing, volume discovery and archives (shared with option A) | ~300 lines |
| Page view: paging, zoom, double-page spread and RTL order | ~600–900 lines |
| Hit-testing and highlight | ~250 lines |
| Settings dialog: direction, single/double page, tap zones, zoom mode | ~250 lines |
| History page | ~150 lines (or reuse `HistoryReaderPage`) |
| **Total** | **~1.5–2k lines**, plus tests on the geometry code |

Pros:

- full control over page turns (no animation, instant redraw), which matters
  for e-ink
- no WebView memory overhead and no IndexedDB duplication
- images are decoded once at screen resolution (`cacheWidth`), so large scans
  are cheap

Cons:

- the most code
- the double-page and spread logic has to be re-implemented
- cannot reuse upstream reader improvements

## 4. Recommendation

1. **Ship option A now.** It is the smallest change that makes `.mokuro` files
   work, it reuses everything already tested, and it keeps existing Mokuro
   history intact. Accept `.mokuro` in the existing picker next to `.html`.
2. **Build option C as a second source** if e-ink is a priority. Start from the
   shared parser and volume locator written for option A. Keep the legacy source
   registered for existing history.
3. Option B is not recommended for jidoujisho. Its import UX inside an Android
   WebView (no folder picking), double storage and fast-moving internals make it
   a poor fit, even though it gives the most features per line of code.

## 5. Open questions for the maintainer

- Should extracted archive images live in app-private storage (deleted on
  uninstall) or next to the archive (survives reinstall, needs write access)?
- Should progress sync with the official mokuro-reader? It stores progress by
  `volume_uuid`, which `.mokuro` files carry, so a native reader could key
  history by `volume_uuid` instead of by file path. That would also survive
  moving files.
