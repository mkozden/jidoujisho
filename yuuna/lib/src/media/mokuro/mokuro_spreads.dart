import 'package:yuuna/media.dart';

/// Groups [pages] into the spreads shown together, as lists of page indices
/// in reading order.
///
/// With [twoPages], pages are paired up. The first page stays on its own if
/// [firstPageIsCover], and so do wide pages, which are usually two pages
/// scanned as one. Otherwise every page is a spread of its own.
List<List<int>> getMokuroSpreads(
  List<MokuroPage> pages, {
  required bool twoPages,
  required bool firstPageIsCover,
}) {
  if (!twoPages) {
    return List.generate(pages.length, (index) => [index]);
  }

  bool isWide(int index) => pages[index].imgWidth > pages[index].imgHeight;

  List<List<int>> spreads = [];
  int index = 0;
  while (index < pages.length) {
    bool alone = isWide(index) ||
        (index == 0 && firstPageIsCover) ||
        index + 1 >= pages.length ||
        isWide(index + 1);

    if (alone) {
      spreads.add([index]);
      index += 1;
    } else {
      spreads.add([index, index + 1]);
      index += 2;
    }
  }

  return spreads;
}
