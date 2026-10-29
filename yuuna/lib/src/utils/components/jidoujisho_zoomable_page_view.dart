import 'package:flutter/material.dart';

/// A [PageView] whose content can be pinched to zoom in and then panned.
///
/// Swipes turn pages until the view is zoomed in. While zoomed in, or while
/// more than one finger is down, swiping between pages is turned off so that
/// pinches and pans are not taken as page turns. A pinch that barely zooms
/// in springs back to the whole page.
class JidoujishoZoomablePageView extends StatefulWidget {
  /// Create a zoomable page view.
  const JidoujishoZoomablePageView({
    required this.controller,
    required this.zoomController,
    required this.itemCount,
    required this.itemBuilder,
    this.onPageChanged,
    this.onTapUp,
    this.onLongPressStart,
    this.onZoomEnd,
    this.reverse = false,
    this.maxScale = 5,
    super.key,
  });

  /// Controls which page is shown.
  final PageController controller;

  /// Holds the zoom and pan applied to the shown page. Set it to the
  /// identity to show the whole page again.
  final TransformationController zoomController;

  /// Number of pages.
  final int itemCount;

  /// Builds the page at an index.
  final IndexedWidgetBuilder itemBuilder;

  /// Called when the page shown changes.
  final ValueChanged<int>? onPageChanged;

  /// Called on a tap anywhere on the view.
  final GestureTapUpCallback? onTapUp;

  /// Called when a long press anywhere on the view is recognised.
  final GestureLongPressStartCallback? onLongPressStart;

  /// Called with the zoom when a pinch or pan ends.
  final ValueChanged<double>? onZoomEnd;

  /// Whether pages are laid out from right to left.
  final bool reverse;

  /// Largest zoom allowed.
  final double maxScale;

  /// Zoom below which a pinch springs back to the whole page.
  static const double minimumZoom = 1.05;

  @override
  State<JidoujishoZoomablePageView> createState() =>
      _JidoujishoZoomablePageViewState();
}

class _JidoujishoZoomablePageViewState
    extends State<JidoujishoZoomablePageView> {
  final ValueNotifier<bool> _pagingLockedNotifier = ValueNotifier<bool>(false);
  int _pointerCount = 0;

  @override
  void initState() {
    super.initState();
    widget.zoomController.addListener(updatePagingLock);
  }

  @override
  void didUpdateWidget(JidoujishoZoomablePageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.zoomController != widget.zoomController) {
      oldWidget.zoomController.removeListener(updatePagingLock);
      widget.zoomController.addListener(updatePagingLock);
      updatePagingLock();
    }
  }

  @override
  void dispose() {
    widget.zoomController.removeListener(updatePagingLock);
    _pagingLockedNotifier.dispose();
    super.dispose();
  }

  double get zoom => widget.zoomController.value.getMaxScaleOnAxis();

  void updatePointerCount(int change) {
    _pointerCount = (_pointerCount + change).clamp(0, 10);
    updatePagingLock();
  }

  void updatePagingLock() {
    _pagingLockedNotifier.value = _pointerCount >= 2 || zoom > 1.01;
  }

  void snapZoom() {
    if (zoom < JidoujishoZoomablePageView.minimumZoom) {
      widget.zoomController.value = Matrix4.identity();
    }
    widget.onZoomEnd?.call(zoom);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: (_) => updatePointerCount(1),
      onPointerUp: (_) => updatePointerCount(-1),
      onPointerCancel: (_) => updatePointerCount(-1),
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTapUp: widget.onTapUp,
        onLongPressStart: widget.onLongPressStart,
        child: InteractiveViewer(
          transformationController: widget.zoomController,
          maxScale: widget.maxScale,
          onInteractionEnd: (_) => snapZoom(),
          child: ValueListenableBuilder<bool>(
            valueListenable: _pagingLockedNotifier,
            builder: (context, locked, _) {
              return PageView.builder(
                controller: widget.controller,
                reverse: widget.reverse,
                physics: locked ? const NeverScrollableScrollPhysics() : null,
                itemCount: widget.itemCount,
                onPageChanged: widget.onPageChanged,
                itemBuilder: widget.itemBuilder,
              );
            },
          ),
        ),
      ),
    );
  }
}
