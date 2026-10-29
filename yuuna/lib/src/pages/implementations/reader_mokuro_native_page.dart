import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:spaces/spaces.dart';
import 'package:yuuna/media.dart';
import 'package:yuuna/pages.dart';
import 'package:yuuna/utils.dart';

/// Reads a volume opened by [ReaderMokuroNativeSource], showing its pages one
/// at a time.
class ReaderMokuroNativePage extends BaseSourcePage {
  /// Create an instance of this page.
  const ReaderMokuroNativePage({
    super.item,
    super.key,
  });

  @override
  BaseSourcePageState createState() => _ReaderMokuroNativePageState();
}

class _ReaderMokuroNativePageState
    extends BaseSourcePageState<ReaderMokuroNativePage> {
  ReaderMokuroNativeSource get mediaSource => ReaderMokuroNativeSource.instance;

  late final Future<LoadedMokuroVolume> _volumeFuture;
  LoadedMokuroVolume? _loaded;
  PageController? _pageController;

  /// Kept for the whole session, so the pages do not flip around if the
  /// preference changes while reading.
  late final bool _rightToLeft;

  final ValueNotifier<int> _pageNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _controlsShownNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<_MokuroHighlight?> _highlightNotifier =
      ValueNotifier<_MokuroHighlight?>(null);

  /// Keys of the shown pages' image boxes, for placing taps on them.
  final Map<int, GlobalKey> _pageKeys = {};

  /// Text layouts of pages that have been tapped, by page index.
  final Map<int, MokuroPageLayout> _pageLayouts = {};

  /// Counts lookups, so a slow search does not update the highlight or
  /// sentence after another word was tapped.
  int _lookupCount = 0;

  Orientation? _lastOrientation;

  /// Fraction of the screen width at each side that turns the page on tap.
  static const double _edgeTapWidth = 0.25;

  @override
  void initState() {
    super.initState();
    _rightToLeft = mediaSource.rightToLeft;
    _volumeFuture = loadVolume();
  }

  @override
  void dispose() {
    _loaded?.images.close();
    _pageController?.dispose();
    _pageNotifier.dispose();
    _controlsShownNotifier.dispose();
    _highlightNotifier.dispose();
    super.dispose();
  }

  @override
  void clearDictionaryResult() {
    super.clearDictionaryResult();
    _highlightNotifier.value = null;
  }

  Future<LoadedMokuroVolume> loadVolume() async {
    MediaItem item = widget.item!;
    LoadedMokuroVolume loaded =
        await LoadedMokuroVolume.load(item.mediaIdentifier);
    if (!mounted) {
      await loaded.images.close();
      return loaded;
    }

    int pageCount = loaded.volume.pages.length;
    int page = item.position.clamp(0, pageCount - 1);

    _loaded = loaded;
    _pageController = PageController(initialPage: page);
    _pageNotifier.value = page;

    if (item.duration != pageCount) {
      item.duration = pageCount;
      appModel.updateMediaItem(item);
    }

    WidgetsBinding.instance.addPostFrameCallback((_) => precachePages(page));

    return loaded;
  }

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(context).orientation;
    if (orientation != _lastOrientation) {
      if (_lastOrientation != null) {
        clearDictionaryResult();
      }
      _lastOrientation = orientation;
    }

    return WillPopScope(
      onWillPop: onWillPop,
      child: FutureBuilder<LoadedMokuroVolume>(
        future: _volumeFuture,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Scaffold(
              appBar: AppBar(title: Text(widget.item?.title ?? '')),
              body: buildError(error: snapshot.error),
            );
          }
          if (!snapshot.hasData || _pageController == null) {
            return Scaffold(body: buildLoading());
          }

          return Scaffold(
            backgroundColor: Colors.black,
            resizeToAvoidBottomInset: false,
            body: buildReader(snapshot.data!),
          );
        },
      ),
    );
  }

  Widget buildReader(LoadedMokuroVolume loaded) {
    List<MokuroPage> pages = loaded.volume.pages;

    return Stack(
      fit: StackFit.expand,
      children: [
        GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: onTapUp,
          child: PageView.builder(
            controller: _pageController,
            reverse: _rightToLeft,
            itemCount: pages.length,
            onPageChanged: onPageChanged,
            itemBuilder: (context, index) => buildPage(loaded, index),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: buildControls(loaded),
        ),
        Padding(
          padding: Spacing.of(context).insets.onlyTop.extraBig * 1.5,
          child: buildDictionary(),
        ),
      ],
    );
  }

  Widget buildPage(LoadedMokuroVolume loaded, int index) {
    MokuroPage page = loaded.volume.pages[index];
    Widget image = Image(
      image: loaded.images.imageForPage(page),
      fit: BoxFit.contain,
      filterQuality: FilterQuality.medium,
      gaplessPlayback: true,
      errorBuilder: (context, error, stackTrace) {
        debugPrint('Cannot show ${page.imgPath}: $error');
        return Center(
          child: JidoujishoPlaceholderMessage(
            icon: Icons.broken_image_outlined,
            message: t.mokuro_page_unreadable,
          ),
        );
      },
    );

    if (page.imgWidth <= 0 || page.imgHeight <= 0) {
      return image;
    }

    /// Sized to the page's own aspect ratio, so that text positions given in
    /// image pixels can be laid over it.
    return Center(
      child: AspectRatio(
        key: _pageKeys.putIfAbsent(index, GlobalKey.new),
        aspectRatio: page.imgWidth / page.imgHeight,
        child: CustomPaint(
          foregroundPainter: _MokuroHighlightPainter(
            highlight: _highlightNotifier,
            pageIndex: index,
            pageSize: page.size,
            color: theme.colorScheme.primary,
          ),
          child: image,
        ),
      ),
    );
  }

  Widget buildControls(LoadedMokuroVolume loaded) {
    int pageCount = loaded.volume.pages.length;

    return ValueListenableBuilder<bool>(
      valueListenable: _controlsShownNotifier,
      builder: (context, shown, _) {
        if (!shown) {
          return const SizedBox.shrink();
        }

        return Container(
          color: Colors.black.withOpacity(0.75),
          padding: Spacing.of(context).insets.all.normal,
          child: SafeArea(
            top: false,
            child: ValueListenableBuilder<int>(
              valueListenable: _pageNotifier,
              builder: (context, page, _) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${widget.item?.title ?? ''}  ${page + 1} / $pageCount',
                      style: const TextStyle(color: Colors.white),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    if (pageCount > 1)
                      Directionality(
                        textDirection: _rightToLeft
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Slider(
                          value: page.toDouble(),
                          max: (pageCount - 1).toDouble(),
                          divisions: pageCount - 1,
                          onChanged: (value) =>
                              _pageController?.jumpToPage(value.round()),
                        ),
                      ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  void onTapUp(TapUpDetails details) {
    if (lookUpAt(details.globalPosition)) {
      return;
    }

    if (isDictionaryShown) {
      clearDictionaryResult();
      mediaSource.clearCurrentSentence();
      return;
    }

    double width = MediaQuery.of(context).size.width;
    double x = details.globalPosition.dx;

    if (x < width * _edgeTapWidth) {
      turnPage(towardsLeft: true);
    } else if (x > width * (1 - _edgeTapWidth)) {
      turnPage(towardsLeft: false);
    } else {
      _controlsShownNotifier.value = !_controlsShownNotifier.value;
    }
  }

  /// Turn to the page on the left or the right of the current one, which
  /// depends on the reading direction.
  void turnPage({required bool towardsLeft}) {
    PageController? controller = _pageController;
    LoadedMokuroVolume? loaded = _loaded;
    if (controller == null || loaded == null) {
      return;
    }

    int step = towardsLeft == _rightToLeft ? 1 : -1;
    int page = _pageNotifier.value + step;
    if (page < 0 || page >= loaded.volume.pages.length) {
      return;
    }

    if (EinkMode.enabled) {
      controller.jumpToPage(page);
    } else {
      controller.animateToPage(
        page,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void onPageChanged(int page) {
    if (isDictionaryShown || _highlightNotifier.value != null) {
      clearDictionaryResult();
    }

    _pageNotifier.value = page;
    precachePages(page);

    MediaItem? item = widget.item;
    if (item != null) {
      item.position = page;
      appModel.updateMediaItem(item);
    }
  }

  /// Decode the pages next to [page] ahead of time, so turning to them does
  /// not show a blank page while they load.
  void precachePages(int page) {
    LoadedMokuroVolume? loaded = _loaded;
    if (loaded == null || !mounted) {
      return;
    }

    for (int index in [page + 1, page - 1]) {
      if (index >= 0 && index < loaded.volume.pages.length) {
        precacheImage(
          loaded.images.imageForPage(loaded.volume.pages[index]),
          context,
          onError: (error, stackTrace) {},
        );
      }
    }
  }

  /// Look up the word at [globalPosition] if it is on text of the current
  /// page. Returns whether text was there.
  bool lookUpAt(Offset globalPosition) {
    LoadedMokuroVolume? loaded = _loaded;
    if (loaded == null) {
      return false;
    }

    int pageIndex = _pageNotifier.value;
    MokuroPage page = loaded.volume.pages[pageIndex];
    RenderObject? renderObject =
        _pageKeys[pageIndex]?.currentContext?.findRenderObject();
    if (renderObject is! RenderBox || page.imgWidth <= 0) {
      return false;
    }

    Offset local = renderObject.globalToLocal(globalPosition);
    Size size = renderObject.size;
    if (!size.contains(local) || size.width == 0) {
      return false;
    }

    double scale = page.imgWidth / size.width;
    MokuroPageLayout layout = _pageLayouts.putIfAbsent(
      pageIndex,
      () => MokuroPageLayout(
        page,
        separator: appModel.targetLanguage.isSpaceDelimited ? ' ' : '',
      ),
    );

    MokuroTextHit? hit = layout.hitTest(local * scale);
    if (hit == null) {
      return false;
    }

    lookUp(
      hit: hit,
      page: page,
      pageIndex: pageIndex,
      globalPosition: globalPosition,
    );
    return true;
  }

  void lookUp({
    required MokuroTextHit hit,
    required MokuroPage page,
    required int pageIndex,
    required Offset globalPosition,
  }) {
    MokuroBlockLayout layout = hit.layout;
    String text = layout.text;
    int index = hit.index;

    _MokuroHighlight? current = _highlightNotifier.value;
    bool sameWord = current != null &&
        current.layout == layout &&
        index >= current.start &&
        index < current.end;
    if (sameWord && isDictionaryShown) {
      clearDictionaryResult();
      mediaSource.clearCurrentSentence();
      return;
    }

    String searchTerm = appModel.targetLanguage.getSearchTermFromIndex(
      text: text,
      index: index,
    );
    if (searchTerm.trim().isEmpty) {
      clearDictionaryResult();
      mediaSource.clearCurrentSentence();
      return;
    }

    int whitespaceOffset = searchTerm.length - searchTerm.trimLeft().length;
    int start =
        appModel.targetLanguage.getStartingIndex(text: text, index: index) +
            whitespaceOffset;
    int length = appModel.targetLanguage.getGuessHighlightLength(
      searchTerm: searchTerm,
    );

    int lookupId = ++_lookupCount;
    highlight(
        pageIndex: pageIndex, layout: layout, start: start, length: length);
    mediaSource.setExtraData(page.imgPath);

    searchDictionaryResult(
      searchTerm: searchTerm,
      position: popupPositionFor(globalPosition),
    ).then((_) {
      if (!mounted || lookupId != _lookupCount) {
        return;
      }

      length = appModel.targetLanguage.getFinalHighlightLength(
        result: currentResult,
        searchTerm: searchTerm,
      );
      highlight(
        pageIndex: pageIndex,
        layout: layout,
        start: start,
        length: length,
      );

      int end = (start + length).clamp(start, text.length);
      mediaSource.setCurrentSentence(
        selection: appModel.targetLanguage.getSentenceFromParagraph(
          paragraph: text,
          index: index,
          startOffset: start,
          endOffset: end,
        ),
      );
    });
  }

  void highlight({
    required int pageIndex,
    required MokuroBlockLayout layout,
    required int start,
    required int length,
  }) {
    if (!mediaSource.highlightOnTap) {
      return;
    }

    _highlightNotifier.value = _MokuroHighlight(
      pageIndex: pageIndex,
      layout: layout,
      start: start,
      end: (start + length).clamp(start, layout.text.length),
    );
  }

  /// Show the dictionary on the side of the screen away from the tapped word.
  JidoujishoPopupPosition popupPositionFor(Offset globalPosition) {
    Size screen = MediaQuery.of(context).size;
    if (MediaQuery.of(context).orientation == Orientation.portrait) {
      return globalPosition.dy < screen.height * 0.6
          ? JidoujishoPopupPosition.bottomHalf
          : JidoujishoPopupPosition.topHalf;
    } else {
      return globalPosition.dx < screen.width / 2
          ? JidoujishoPopupPosition.rightHalf
          : JidoujishoPopupPosition.leftHalf;
    }
  }
}

/// The looked up word on a page.
class _MokuroHighlight {
  _MokuroHighlight({
    required this.pageIndex,
    required this.layout,
    required this.start,
    required this.end,
  });

  final int pageIndex;
  final MokuroBlockLayout layout;

  /// Range of the word in [MokuroBlockLayout.text].
  final int start;
  final int end;
}

/// Draws the looked up word over the page image, if it is on this page.
class _MokuroHighlightPainter extends CustomPainter {
  _MokuroHighlightPainter({
    required this.highlight,
    required this.pageIndex,
    required this.pageSize,
    required this.color,
  }) : super(repaint: highlight);

  final ValueListenable<_MokuroHighlight?> highlight;
  final int pageIndex;

  /// Size of the page image, which highlight outlines are given in.
  final Size pageSize;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    _MokuroHighlight? value = highlight.value;
    if (value == null || value.pageIndex != pageIndex || pageSize.isEmpty) {
      return;
    }

    double scale = size.width / pageSize.width;
    Paint fill = Paint()..color = color.withOpacity(0.3);
    Paint outline = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    for (List<Offset> corners
        in value.layout.highlightOutlines(value.start, value.end)) {
      Path path = Path()
        ..addPolygon(corners.map((corner) => corner * scale).toList(), true);
      canvas.drawPath(path, fill);
      canvas.drawPath(path, outline);
    }
  }

  @override
  bool shouldRepaint(_MokuroHighlightPainter oldDelegate) {
    return oldDelegate.highlight != highlight ||
        oldDelegate.pageIndex != pageIndex ||
        oldDelegate.pageSize != pageSize ||
        oldDelegate.color != color;
  }
}
