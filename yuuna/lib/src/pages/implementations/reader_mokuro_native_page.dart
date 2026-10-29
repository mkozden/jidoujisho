import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:spaces/spaces.dart';
import 'package:yuuna/media.dart';
import 'package:yuuna/pages.dart';
import 'package:yuuna/utils.dart';

/// Reads a volume opened by [ReaderMokuroNativeSource], showing its pages one
/// or two at a time.
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

  /// Pages shown together, as page indices in reading order.
  List<List<int>> _spreads = [];

  /// Whether [_spreads] pair up pages, and whether the first page is kept on
  /// its own. The spreads are made again when these change.
  (bool, bool)? _spreadSettings;

  PageController? _pageController;

  /// Changed along with [_spreads], so the page view starts afresh on the
  /// current page.
  int _layoutVersion = 0;

  /// Index in [_spreads] of the spread being shown.
  int _spreadIndex = 0;

  /// First page of the spread being shown, in reading order.
  final ValueNotifier<int> _pageNotifier = ValueNotifier<int>(0);
  final ValueNotifier<bool> _controlsShownNotifier = ValueNotifier<bool>(false);
  final ValueNotifier<_MokuroHighlight?> _highlightNotifier =
      ValueNotifier<_MokuroHighlight?>(null);

  /// Zoom and pan of the shown spread.
  final TransformationController _zoomController = TransformationController();

  /// The block whose recognised text was shown by a long press.
  final ValueNotifier<_ShownText?> _shownTextNotifier =
      ValueNotifier<_ShownText?>(null);

  /// Draws recognised text over pages, made when first needed.
  MokuroTextOverlay? _textOverlay;

  MokuroTextOverlay get textOverlay => _textOverlay ??= MokuroTextOverlay(
        fontFamily: appModelNoUpdate.targetLanguage.defaultFontFamily,
      );

  /// Pages decoded at their full size, rather than the size of the screen,
  /// as they have been zoomed into.
  final Set<int> _fullResolutionPages = {};

  /// Zoom from which the shown pages are decoded at their full size.
  static const double _fullResolutionZoom = 1.5;

  /// Keys of the shown pages' image boxes, for placing taps on them.
  final Map<int, GlobalKey> _pageKeys = {};

  /// Text layouts of pages, by page index, made when first needed.
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
    HardwareKeyboard.instance.addHandler(onKeyEvent);
    _volumeFuture = loadVolume();
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(onKeyEvent);
    _loaded?.images.close();
    _pageController?.dispose();
    _pageNotifier.dispose();
    _controlsShownNotifier.dispose();
    _highlightNotifier.dispose();
    _zoomController.dispose();
    _shownTextNotifier.dispose();
    _textOverlay?.dispose();
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
    _loaded = loaded;
    _pageNotifier.value = item.position.clamp(0, pageCount - 1);

    if (item.duration != pageCount) {
      item.duration = pageCount;
      appModel.updateMediaItem(item);
    }

    return loaded;
  }

  @override
  Widget build(BuildContext context) {
    Orientation orientation = MediaQuery.of(context).orientation;
    if (orientation != _lastOrientation) {
      if (_lastOrientation != null) {
        clearDictionaryResult();
        resetZoom();
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
          if (!snapshot.hasData || _loaded == null) {
            return Scaffold(body: buildLoading());
          }

          LoadedMokuroVolume loaded = snapshot.data!;
          updateSpreads(loaded, orientation);

          return Scaffold(
            backgroundColor: EinkMode.enabled
                ? EinkMode.surfaceColor(dark: isDark)
                : Colors.black,
            resizeToAvoidBottomInset: false,
            body: buildReader(loaded),
          );
        },
      ),
    );
  }

  bool get isDark => theme.brightness == Brightness.dark;

  /// Make the spreads for the current settings and orientation, keeping the
  /// current page in view.
  void updateSpreads(LoadedMokuroVolume loaded, Orientation orientation) {
    bool twoPages =
        mediaSource.twoPagesInLandscape && orientation == Orientation.landscape;
    (bool, bool) settings = (twoPages, mediaSource.firstPageIsCover);
    if (settings == _spreadSettings) {
      return;
    }

    _spreadSettings = settings;
    _spreads = getMokuroSpreads(
      loaded.volume.pages,
      twoPages: settings.$1,
      firstPageIsCover: settings.$2,
    );
    _spreadIndex = spreadIndexOf(_pageNotifier.value);
    _pageNotifier.value = _spreads[_spreadIndex].first;

    PageController? oldController = _pageController;
    _pageController = PageController(initialPage: _spreadIndex);
    _layoutVersion++;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      oldController?.dispose();
      precacheSpreads(_spreadIndex);
    });
  }

  /// Index of the spread holding [page].
  int spreadIndexOf(int page) {
    int index = _spreads.indexWhere((spread) => spread.contains(page));
    return index == -1 ? 0 : index;
  }

  Widget buildReader(LoadedMokuroVolume loaded) {
    return Stack(
      fit: StackFit.expand,
      children: [
        JidoujishoZoomablePageView(
          key: ValueKey(_layoutVersion),
          controller: _pageController!,
          zoomController: _zoomController,
          reverse: mediaSource.rightToLeft,
          itemCount: _spreads.length,
          onPageChanged: onPageChanged,
          onTapUp: onTapUp,
          onLongPressStart: onLongPressStart,
          onZoomEnd: onZoomEnd,
          itemBuilder: (context, index) => buildSpread(loaded, index),
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

  Widget buildSpread(LoadedMokuroVolume loaded, int spreadIndex) {
    List<int> pages = _spreads[spreadIndex];
    if (pages.length == 1) {
      return buildPage(loaded, pages.first, alignment: Alignment.center);
    }

    /// The page read first is on the right when reading right to left. Each
    /// page sits against the middle, as in a printed book.
    List<int> leftToRight =
        mediaSource.rightToLeft ? pages.reversed.toList() : pages;

    return Row(
      textDirection: TextDirection.ltr,
      children: [
        Expanded(
          child: buildPage(
            loaded,
            leftToRight[0],
            alignment: Alignment.centerRight,
          ),
        ),
        Expanded(
          child: buildPage(
            loaded,
            leftToRight[1],
            alignment: Alignment.centerLeft,
          ),
        ),
      ],
    );
  }

  Widget buildPage(
    LoadedMokuroVolume loaded,
    int index, {
    required Alignment alignment,
  }) {
    MokuroPage page = loaded.volume.pages[index];
    Widget image = Image(
      image: pageImage(loaded, index),
      fit: BoxFit.contain,
      alignment: alignment,
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

    bool inverted = mediaSource.invertPageColours;
    if (inverted) {
      image = ColorFiltered(
        colorFilter: const ColorFilter.matrix([
          -1, 0, 0, 0, 255, //
          0, -1, 0, 0, 255, //
          0, 0, -1, 0, 255, //
          0, 0, 0, 1, 0, //
        ]),
        child: image,
      );
    }

    if (page.imgWidth <= 0 || page.imgHeight <= 0) {
      return image;
    }

    /// Sized to the page's own aspect ratio, so that text positions given in
    /// image pixels can be laid over it. Kept apart from the zoom when
    /// painting, so that pinching does not redraw the text over it.
    return Align(
      alignment: alignment,
      child: AspectRatio(
        key: _pageKeys.putIfAbsent(index, GlobalKey.new),
        aspectRatio: page.imgWidth / page.imgHeight,
        child: RepaintBoundary(
          child: CustomPaint(
            foregroundPainter: _MokuroPagePainter(
              highlight: _highlightNotifier,
              shownText: _shownTextNotifier,
              pageIndex: index,
              pageSize: page.size,
              layout: pageLayoutOf(loaded, index),
              textOverlay: textOverlay,
              showAllText: mediaSource.showRecognisedText,
              showOutlines: mediaSource.showTextOutlines,
              inverted: inverted,
              highlightColor: EinkMode.enabled
                  ? (inverted ? Colors.white : Colors.black)
                  : theme.colorScheme.primary,
              highlightFilled: !EinkMode.enabled,
            ),
            child: image,
          ),
        ),
      ),
    );
  }

  /// The image of page [index], decoded at the size of the screen unless it
  /// has been zoomed into, to keep the memory held by large scans down.
  ImageProvider pageImage(LoadedMokuroVolume loaded, int index) {
    ImageProvider image =
        loaded.images.imageForPage(loaded.volume.pages[index]);
    if (_fullResolutionPages.contains(index)) {
      return image;
    }

    MediaQueryData media = MediaQuery.of(context);
    Size screen = media.size * media.devicePixelRatio;
    return ResizeImage(
      image,
      width: screen.width.ceil(),
      height: screen.height.ceil(),
      policy: ResizeImagePolicy.fit,
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

        Color foreground = EinkMode.enabled
            ? EinkMode.foregroundColor(dark: isDark)
            : Colors.white;

        return Container(
          decoration: BoxDecoration(
            color: EinkMode.enabled
                ? EinkMode.surfaceColor(dark: isDark)
                : Colors.black.withOpacity(0.75),
            border: EinkMode.enabled
                ? Border(top: EinkMode.border(dark: isDark))
                : null,
          ),
          padding: Spacing.of(context).insets.all.normal,
          child: SafeArea(
            top: false,
            child: ValueListenableBuilder<int>(
              valueListenable: _pageNotifier,
              builder: (context, page, _) {
                List<int> spread = _spreads[_spreadIndex];
                String pages = spread.length == 1
                    ? '${spread.first + 1}'
                    : '${spread.first + 1}–${spread.last + 1}';

                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${widget.item?.title ?? ''}  $pages / $pageCount',
                            style: TextStyle(color: foreground),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        JidoujishoIconButton(
                          tooltip: t.tweaks,
                          icon: Icons.tune,
                          enabledColor: foreground,
                          onTap: openSettings,
                        ),
                      ],
                    ),
                    if (pageCount > 1)
                      Directionality(
                        textDirection: mediaSource.rightToLeft
                            ? TextDirection.rtl
                            : TextDirection.ltr,
                        child: Slider(
                          value: page.toDouble(),
                          max: (pageCount - 1).toDouble(),
                          divisions: pageCount - 1,
                          onChanged: (value) => _pageController
                              ?.jumpToPage(spreadIndexOf(value.round())),
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

  Future<void> openSettings() async {
    await showDialog(
      context: context,
      builder: (context) => const MokuroNativeSettingsDialogPage(),
    );
    if (!mounted) {
      return;
    }

    clearDictionaryResult();
    setState(() {});
  }

  /// Turn pages with the volume buttons, the page up and down keys and the
  /// arrow keys, which page turn buttons on e-readers often send. Handled
  /// for the whole app while the reader is on top, rather than through
  /// focus, so that the keys reach the reader whatever has focus.
  bool onKeyEvent(KeyEvent event) {
    if (!mounted ||
        _loaded == null ||
        !(ModalRoute.of(context)?.isCurrent ?? false)) {
      return false;
    }

    LogicalKeyboardKey key = event.logicalKey;
    bool volumeUp = key == LogicalKeyboardKey.audioVolumeUp;
    bool volumeDown = key == LogicalKeyboardKey.audioVolumeDown;
    bool rightToLeft = mediaSource.rightToLeft;

    int? step;
    if (volumeUp || volumeDown) {
      if (!mediaSource.volumePageTurningEnabled) {
        return false;
      }

      /// Volume up turns to the next page unless inverted, as in the web
      /// Mokuro reader.
      step = volumeUp != mediaSource.volumePageTurningInverted ? 1 : -1;
    } else if (key == LogicalKeyboardKey.pageDown) {
      step = 1;
    } else if (key == LogicalKeyboardKey.pageUp) {
      step = -1;
    } else if (key == LogicalKeyboardKey.arrowLeft) {
      step = rightToLeft ? 1 : -1;
    } else if (key == LogicalKeyboardKey.arrowRight) {
      step = rightToLeft ? -1 : 1;
    }

    if (step == null) {
      return false;
    }
    if (event is KeyUpEvent) {
      return true;
    }

    if (isDictionaryShown) {
      clearDictionaryResult();
      mediaSource.clearCurrentSentence();
      return true;
    }

    turnBy(step);
    return true;
  }

  void onTapUp(TapUpDetails details) {
    if (lookUpAt(details.globalPosition)) {
      return;
    }

    _shownTextNotifier.value = null;
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

  /// Turn to the spread on the left or the right of the current one, which
  /// depends on the reading direction.
  void turnPage({required bool towardsLeft}) {
    turnBy(towardsLeft == mediaSource.rightToLeft ? 1 : -1);
  }

  /// Turn [step] spreads forward in reading order, or back if negative.
  void turnBy(int step) {
    PageController? controller = _pageController;
    if (controller == null) {
      return;
    }

    int spreadIndex = _spreadIndex + step;
    if (spreadIndex < 0 || spreadIndex >= _spreads.length) {
      return;
    }

    resetZoom();
    if (EinkMode.enabled) {
      controller.jumpToPage(spreadIndex);
    } else {
      controller.animateToPage(
        spreadIndex,
        duration: const Duration(milliseconds: 250),
        curve: Curves.easeOut,
      );
    }
  }

  void onPageChanged(int spreadIndex) {
    if (isDictionaryShown || _highlightNotifier.value != null) {
      clearDictionaryResult();
    }
    resetZoom();
    _shownTextNotifier.value = null;
    _fullResolutionPages.clear();

    _spreadIndex = spreadIndex;
    int page = _spreads[spreadIndex].first;
    _pageNotifier.value = page;
    precacheSpreads(spreadIndex);

    MediaItem? item = widget.item;
    if (item != null) {
      item.position = page;
      appModel.updateMediaItem(item);
    }
  }

  void resetZoom() {
    if (_zoomController.value != Matrix4.identity()) {
      _zoomController.value = Matrix4.identity();
    }
  }

  /// Decode the pages of the spreads next to [spreadIndex] ahead of time, so
  /// turning to them does not show a blank page while they load.
  void precacheSpreads(int spreadIndex) {
    LoadedMokuroVolume? loaded = _loaded;
    if (loaded == null || !mounted) {
      return;
    }

    for (int index in [spreadIndex + 1, spreadIndex - 1]) {
      if (index < 0 || index >= _spreads.length) {
        continue;
      }
      for (int page in _spreads[index]) {
        precacheImage(
          pageImage(loaded, page),
          context,
          onError: (error, stackTrace) {},
        );
      }
    }
  }

  /// The text layout of page [index].
  MokuroPageLayout pageLayoutOf(LoadedMokuroVolume loaded, int index) {
    return _pageLayouts.putIfAbsent(
      index,
      () => MokuroPageLayout(
        loaded.volume.pages[index],
        separator: appModel.targetLanguage.isSpaceDelimited ? ' ' : '',
      ),
    );
  }

  /// The text at [globalPosition] on a shown page, along with the index of
  /// that page, or null if there is no text there.
  ({int pageIndex, MokuroTextHit hit})? textAt(Offset globalPosition) {
    LoadedMokuroVolume? loaded = _loaded;
    if (loaded == null || _spreads.isEmpty) {
      return null;
    }

    for (int pageIndex in _spreads[_spreadIndex]) {
      MokuroPage page = loaded.volume.pages[pageIndex];
      RenderObject? renderObject =
          _pageKeys[pageIndex]?.currentContext?.findRenderObject();
      if (renderObject is! RenderBox || page.imgWidth <= 0) {
        continue;
      }

      Offset local = renderObject.globalToLocal(globalPosition);
      Size size = renderObject.size;
      if (!size.contains(local) || size.width == 0) {
        continue;
      }

      double scale = page.imgWidth / size.width;
      MokuroTextHit? hit = pageLayoutOf(loaded, pageIndex).hitTest(
        local * scale,
      );
      return hit == null ? null : (pageIndex: pageIndex, hit: hit);
    }

    return null;
  }

  /// Look up the word at [globalPosition] if it is on text of a shown page.
  /// Returns whether text was there.
  bool lookUpAt(Offset globalPosition) {
    ({int pageIndex, MokuroTextHit hit})? target = textAt(globalPosition);
    if (target == null) {
      return false;
    }

    lookUp(
      hit: target.hit,
      page: _loaded!.volume.pages[target.pageIndex],
      pageIndex: target.pageIndex,
      globalPosition: globalPosition,
    );
    return true;
  }

  /// Show or hide the recognised text of the block that was long pressed.
  void onLongPressStart(LongPressStartDetails details) {
    ({int pageIndex, MokuroTextHit hit})? target =
        textAt(details.globalPosition);
    if (target == null) {
      return;
    }

    MokuroBlockLayout layout = target.hit.layout;
    _shownTextNotifier.value = _shownTextNotifier.value?.layout == layout
        ? null
        : _ShownText(pageIndex: target.pageIndex, layout: layout);
    HapticFeedback.selectionClick();
  }

  /// Decode the shown pages at their full size once zoomed into far enough
  /// for the screen-sized image to look soft.
  void onZoomEnd(double zoom) {
    if (zoom < _fullResolutionZoom || _spreads.isEmpty) {
      return;
    }

    List<int> pages = _spreads[_spreadIndex];
    if (_fullResolutionPages.containsAll(pages)) {
      return;
    }

    setState(() => _fullResolutionPages.addAll(pages));
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

/// A block whose recognised text is shown.
class _ShownText {
  _ShownText({
    required this.pageIndex,
    required this.layout,
  });

  final int pageIndex;
  final MokuroBlockLayout layout;
}

/// Draws over a page image: recognised text if asked for, the outlines of
/// the recognised text if asked for, and the looked up word, each where they
/// are on this page.
class _MokuroPagePainter extends CustomPainter {
  _MokuroPagePainter({
    required this.highlight,
    required this.shownText,
    required this.pageIndex,
    required this.pageSize,
    required this.layout,
    required this.textOverlay,
    required this.showAllText,
    required this.showOutlines,
    required this.inverted,
    required this.highlightColor,
    required this.highlightFilled,
  }) : super(repaint: Listenable.merge([highlight, shownText]));

  final ValueListenable<_MokuroHighlight?> highlight;
  final ValueListenable<_ShownText?> shownText;
  final int pageIndex;

  /// Size of the page image, which all outlines are given in.
  final Size pageSize;

  /// Layout of the page's text.
  final MokuroPageLayout layout;

  final MokuroTextOverlay textOverlay;

  /// Whether the text of every block is drawn, rather than only a block
  /// that was long pressed.
  final bool showAllText;

  /// Whether to draw where lines and characters were recognised.
  final bool showOutlines;

  /// Whether the page image is shown with inverted colours, so text is
  /// drawn light on dark to match.
  final bool inverted;

  final Color highlightColor;

  /// Whether the highlight is filled in, or only outlined.
  final bool highlightFilled;

  @override
  void paint(Canvas canvas, Size size) {
    if (pageSize.isEmpty) {
      return;
    }

    double scale = size.width / pageSize.width;
    paintText(canvas, scale);
    if (showOutlines) {
      paintOutlines(canvas, scale);
    }

    _MokuroHighlight? value = highlight.value;
    if (value == null || value.pageIndex != pageIndex) {
      return;
    }

    Paint fill = Paint()..color = highlightColor.withOpacity(0.3);
    Paint outline = Paint()
      ..color = highlightColor
      ..style = PaintingStyle.stroke
      ..strokeWidth = highlightFilled ? 1.5 : 2.5;

    for (List<Offset> corners
        in value.layout.highlightOutlines(value.start, value.end)) {
      Path path = Path()
        ..addPolygon(corners.map((corner) => corner * scale).toList(), true);
      if (highlightFilled) {
        canvas.drawPath(path, fill);
      }
      canvas.drawPath(path, outline);
    }
  }

  void paintText(Canvas canvas, double scale) {
    List<MokuroBlockLayout> blocks;
    if (showAllText) {
      blocks = layout.blocks;
    } else {
      _ShownText? shown = shownText.value;
      if (shown == null || shown.pageIndex != pageIndex) {
        return;
      }
      blocks = [shown.layout];
    }

    for (MokuroBlockLayout block in blocks) {
      textOverlay.paintBlock(
        canvas,
        block,
        scale: scale,
        background: inverted ? Colors.black : Colors.white,
        foreground: inverted ? Colors.white : Colors.black,
      );
    }
  }

  /// Draw each block's box, each line's outline and the boundaries between
  /// the characters a tap is mapped to.
  void paintOutlines(Canvas canvas, double scale) {
    Paint blockPaint = Paint()
      ..color = Colors.blue.withOpacity(0.6)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    Paint linePaint = Paint()
      ..color = Colors.red
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    Paint characterPaint = Paint()
      ..color = Colors.red.withOpacity(0.5)
      ..strokeWidth = 0.5;

    for (MokuroBlockLayout block in layout.blocks) {
      Rect bounds = block.bounds;
      canvas.drawRect(
        Rect.fromLTRB(bounds.left * scale, bounds.top * scale,
            bounds.right * scale, bounds.bottom * scale),
        blockPaint,
      );

      for (int i = 0; i < block.shapes.length; i++) {
        MokuroLineShape shape = block.shapes[i];
        Path path = Path()
          ..addPolygon(
              shape.corners.map((corner) => corner * scale).toList(), true);
        canvas.drawPath(path, linePaint);

        int count = block.block.lines[i].runes.length;
        for (int k = 1; k < count; k++) {
          List<Offset> cell = shape.segment(k / count, k / count);
          canvas.drawLine(cell[0] * scale, cell[1] * scale, characterPaint);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_MokuroPagePainter oldDelegate) {
    return oldDelegate.highlight != highlight ||
        oldDelegate.shownText != shownText ||
        oldDelegate.pageIndex != pageIndex ||
        oldDelegate.pageSize != pageSize ||
        oldDelegate.layout != layout ||
        oldDelegate.showAllText != showAllText ||
        oldDelegate.showOutlines != showOutlines ||
        oldDelegate.inverted != inverted ||
        oldDelegate.highlightColor != highlightColor ||
        oldDelegate.highlightFilled != highlightFilled;
  }
}
