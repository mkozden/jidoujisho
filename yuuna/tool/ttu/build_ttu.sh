#!/usr/bin/env bash
# Rebuilds the bundled ッツ Ebook Reader (assets/ttu-ebook-reader) from the
# pinned upstream submodule at third_party/ttu-ebook-reader.
#
# Usage (from anywhere):  bash yuuna/tool/ttu/build_ttu.sh
# Requirements: git, node (>= 22) and pnpm.
#
# To update the reader:
#   git -C yuuna/third_party/ttu-ebook-reader fetch origin
#   git -C yuuna/third_party/ttu-ebook-reader checkout <commit>
#   bash yuuna/tool/ttu/build_ttu.sh
# then commit the submodule pointer and the regenerated assets together.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
APP_DIR="$(cd "$SCRIPT_DIR/../.." && pwd)"
SRC_DIR="$APP_DIR/third_party/ttu-ebook-reader"
OUT_DIR="$APP_DIR/assets/ttu-ebook-reader"
PATCH_DIR="$SCRIPT_DIR/patches"

if [ ! -e "$SRC_DIR/package.json" ]; then
  git -C "$APP_DIR" submodule update --init third_party/ttu-ebook-reader
fi

COMMIT="$(git -C "$SRC_DIR" rev-parse HEAD)"
if [ -n "$(git -C "$SRC_DIR" status --porcelain)" ]; then
  echo "warning: $SRC_DIR has local changes; they are not part of the build" >&2
fi
PINNED="$(git -C "$APP_DIR" ls-tree HEAD third_party/ttu-ebook-reader | awk '{print $3}')"
if [ -n "$PINNED" ] && [ "$PINNED" != "$COMMIT" ]; then
  echo "note: building $COMMIT, which differs from the pinned $PINNED" >&2
fi
WORK_DIR="$(mktemp -d)"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "Building ttu ebook-reader at $COMMIT in $WORK_DIR"
git -C "$SRC_DIR" archive HEAD | tar -x -C "$WORK_DIR"

for patch in "$PATCH_DIR"/*.patch; do
  echo "Applying $(basename "$patch")"
  (cd "$WORK_DIR" && git apply --whitespace=nowarn "$patch")
done

(
  cd "$WORK_DIR"
  HUSKY=0 pnpm install --frozen-lockfile --config.engine-strict=false
  # Assets are served from the APK, so the service worker must not precache them.
  VITE_SW_PRECACHE=false pnpm --dir apps/web build
)

BUILD_DIR="$WORK_DIR/apps/web/build"

# Every font ships as .woff2 with a .woff fallback listed second in the CSS.
# Android WebView always picks .woff2, so the .woff copies only bloat the APK.
for woff in "$BUILD_DIR"/_app/immutable/assets/*.woff; do
  [ -e "$woff" ] || continue
  name="$(basename "$woff")"
  stem="${name%%.*}"
  if compgen -G "$BUILD_DIR/_app/immutable/assets/$stem.*.woff2" > /dev/null; then
    rm "$woff"
  fi
done

cat > "$BUILD_DIR/jidoujisho-ttu-version.json" <<EOF
{"upstream":"https://github.com/ttu-ttu/ebook-reader","commit":"$COMMIT"}
EOF

rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -R "$BUILD_DIR"/. "$OUT_DIR"/

# Flutter asset directories are not recursive, so each one must be in pubspec.
missing=0
while IFS= read -r dir; do
  rel="assets/ttu-ebook-reader${dir#"$OUT_DIR"}/"
  if ! sed 's/[[:space:]]*$//' "$APP_DIR/pubspec.yaml" | grep -qxF -- "    - $rel"; then
    echo "pubspec.yaml is missing asset directory: $rel" >&2
    missing=1
  fi
done < <(find "$OUT_DIR" -type d | sort)

echo "Wrote $(find "$OUT_DIR" -type f | wc -l) files ($(du -sh "$OUT_DIR" | cut -f1)) to $OUT_DIR"
exit "$missing"
