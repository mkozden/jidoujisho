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
    super.dispose();
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
            itemBuilder: (context, index) => buildPage(loaded, pages[index]),
          ),
        ),
        Align(
          alignment: Alignment.bottomCenter,
          child: buildControls(loaded),
        ),
      ],
    );
  }

  Widget buildPage(LoadedMokuroVolume loaded, MokuroPage page) {
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
        aspectRatio: page.imgWidth / page.imgHeight,
        child: image,
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
}
