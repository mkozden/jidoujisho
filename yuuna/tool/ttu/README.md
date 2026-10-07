# ッツ Ebook Reader (ttu) integration

The reader bundled in `assets/ttu-ebook-reader/` is a build of
[ttu-ttu/ebook-reader](https://github.com/ttu-ttu/ebook-reader), pinned as a git
submodule at `third_party/ttu-ebook-reader`. The built output is committed so the
Flutter build does not need Node.js; `assets/ttu-ebook-reader/jidoujisho-ttu-version.json`
records the upstream commit it was built from.

## Updating

```sh
git submodule update --init yuuna/third_party/ttu-ebook-reader
git -C yuuna/third_party/ttu-ebook-reader fetch origin
git -C yuuna/third_party/ttu-ebook-reader checkout <commit>
bash yuuna/tool/ttu/build_ttu.sh
```

Then:

1. If the script reports missing asset directories, add them to `pubspec.yaml`
   (Flutter asset directories are not recursive).
2. Commit the submodule pointer together with the regenerated assets.

No cache busting is needed: `LocalWebAssetsServer` marks pages `no-cache` and only
lets the content-hashed `_app/immutable/` files be cached. Never use the WebView
`clearCache` setting for this, because in flutter_inappwebview it also deletes all
web storage (the users' library, progress and settings).

## Patches applied on top of upstream (`patches/`)

- `0001-fix-books-db-upgrade-fall-through.patch`: upstream's IndexedDB upgrade
  `switch` breaks after each case, so a database created by the previously bundled
  reader (version 4) skipped the version 6 stores (`audioBook`, `subtitle`,
  `handle`) and deleting a book then failed with `NotFoundError`. Later cases
  now fall through and only create stores that are missing, which also repairs
  version 4 databases that older builds upgraded from version 2 without
  `storageSource`.
- `0002-optional-service-worker-precache.patch`: adds `VITE_SW_PRECACHE=false`
  so the service worker does not copy the whole bundle (~150 MB with fonts) into
  WebView storage. The service worker itself stays, because user-imported fonts
  are served through it.

The build script also drops `.woff` fonts that have a `.woff2` sibling, since the
WebView always prefers `.woff2`.

## What the app relies on

`ReaderTtuSource` and `ReaderTtuSourcePage` couple to the reader through:

- the origin `http://localhost:52059` (Japanese) / `52060` (English), which scopes
  IndexedDB and localStorage and must never change;
- routes `manage.html`, `settings.html`, `b.html?id=<id>` and `/`
  (`LocalWebAssetsServer` also serves extensionless routes such as `/b`);
- IndexedDB `books`: stores `data` (`id`, `title`, `coverImage`, `lastBookOpen`)
  and `bookmark` (`dataId`, `exploredCharCount`, `progress`);
- localStorage keys `theme` (`*-theme` values), `writingMode` and `fontSize`;
- the `.book-content` element containing `<p>` paragraphs with ruby markup, and
  the paginated reader's `wheel` listener on `document.body` (volume-key paging).
