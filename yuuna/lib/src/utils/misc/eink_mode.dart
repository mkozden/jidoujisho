import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:progress_indicators/progress_indicators.dart';

/// Adapts the app to black-and-white e-ink displays, which refresh slowly,
/// ghost after partial updates and render colours as a few levels of grey.
///
/// The mode is read once at startup, as toggling it restarts the app, so it is
/// kept in a static flag that widgets can read without access to the model.
class EinkMode {
  EinkMode._();

  /// Whether e-ink mode is active for this run of the app.
  static bool get enabled => _enabled;
  static bool _enabled = false;

  /// Animations run this many times faster in e-ink mode, so transitions,
  /// fades, dialogs and scroll animations finish within about one frame
  /// instead of producing a series of partial refreshes.
  static const double animationTimeDilation = 0.05;

  /// Dictionary results are shown slightly larger in e-ink mode, as e-ink
  /// panels have a lower pixel density than phone screens.
  static const double dictionaryTextScale = 1.15;

  /// Apply the persisted setting. Called once during app initialisation.
  static void apply({required bool enabled}) {
    _enabled = enabled;
    timeDilation = enabled ? animationTimeDilation : 1;
  }

  /// Background of surfaces that must be fully opaque in e-ink mode, such as
  /// the dictionary pop-up.
  static Color surfaceColor({required bool dark}) =>
      dark ? Colors.black : Colors.white;

  /// Foreground for borders and text on a [surfaceColor].
  static Color foregroundColor({required bool dark}) =>
      dark ? Colors.white : Colors.black;

  /// Border drawn around pop-ups and outlined buttons in e-ink mode, where
  /// shadows and subtle background tints are not visible.
  static BorderSide border({required bool dark}) =>
      BorderSide(color: foregroundColor(dark: dark), width: 1.5);

  /// A pure black-and-white theme without transitions or ink splashes.
  static ThemeData buildTheme({
    required TextTheme textTheme,
    required bool dark,
  }) {
    final Color background = surfaceColor(dark: dark);
    final Color foreground = foregroundColor(dark: dark);
    final Color muted = foreground.withOpacity(0.54);
    final ShapeBorder outlined = RoundedRectangleBorder(
      side: border(dark: dark),
    );

    return ThemeData(
      brightness: dark ? Brightness.dark : Brightness.light,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      cardColor: background,
      dividerColor: foreground,
      unselectedWidgetColor: muted,
      iconTheme: IconThemeData(color: foreground),
      textTheme: textTheme.apply(
        bodyColor: foreground,
        displayColor: foreground,
      ),
      splashFactory: NoSplash.splashFactory,
      splashColor: Colors.transparent,
      highlightColor: Colors.transparent,
      hoverColor: Colors.transparent,
      pageTransitionsTheme: const PageTransitionsTheme(
        builders: {
          TargetPlatform.android: _NoTransitionsBuilder(),
          TargetPlatform.iOS: _NoTransitionsBuilder(),
          TargetPlatform.windows: _NoTransitionsBuilder(),
        },
      ),
      appBarTheme: AppBarTheme(
        elevation: 0,
        centerTitle: false,
        backgroundColor: background,
        foregroundColor: foreground,
      ),
      bottomNavigationBarTheme: BottomNavigationBarThemeData(
        elevation: 0,
        type: BottomNavigationBarType.fixed,
        selectedLabelStyle: textTheme.labelSmall?.copyWith(
          fontWeight: FontWeight.bold,
        ),
        unselectedLabelStyle: textTheme.labelSmall,
        showSelectedLabels: true,
        showUnselectedLabels: true,
        backgroundColor: background,
        selectedItemColor: foreground,
        unselectedItemColor: muted,
      ),
      switchTheme: SwitchThemeData(
        thumbColor: MaterialStateColor.resolveWith((states) {
          return states.contains(MaterialState.selected)
              ? foreground
              : background;
        }),
        trackColor: MaterialStateColor.resolveWith((states) {
          return states.contains(MaterialState.selected)
              ? foreground.withOpacity(0.54)
              : foreground.withOpacity(0.26);
        }),
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: MaterialStateColor.resolveWith((states) {
          return states.contains(MaterialState.selected)
              ? foreground
              : Colors.transparent;
        }),
        checkColor: MaterialStatePropertyAll(background),
        side: border(dark: dark),
      ),
      radioTheme: RadioThemeData(
        fillColor: MaterialStatePropertyAll(foreground),
      ),
      popupMenuTheme: PopupMenuThemeData(
        color: background,
        elevation: 0,
        shape: outlined,
      ),
      dialogTheme: DialogTheme(
        backgroundColor: background,
        elevation: 0,
        shape: outlined,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: background,
        elevation: 0,
        shape: outlined,
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(color: foreground),
        textStyle: TextStyle(color: background),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(foregroundColor: foreground),
      ),
      // A light grey fill keeps icons and text that set their own colour
      // readable on selected tiles.
      listTileTheme: ListTileThemeData(
        dense: true,
        selectedTileColor: foreground.withOpacity(0.15),
        selectedColor: foreground,
        horizontalTitleGap: 0,
      ),
      inputDecorationTheme: InputDecorationTheme(
        enabledBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: muted),
        ),
        focusedBorder: UnderlineInputBorder(
          borderSide: BorderSide(color: foreground, width: 2),
        ),
      ),
      textSelectionTheme: TextSelectionThemeData(
        cursorColor: foreground,
        selectionColor: foreground.withOpacity(0.3),
        selectionHandleColor: foreground,
      ),
      progressIndicatorTheme: ProgressIndicatorThemeData(
        color: foreground,
        linearTrackColor: foreground.withOpacity(0.26),
      ),
      scrollbarTheme: ScrollbarThemeData(
        thickness: MaterialStateProperty.all(3),
        thumbVisibility: MaterialStateProperty.all(true),
        thumbColor: MaterialStatePropertyAll(foreground),
      ),
      sliderTheme: SliderThemeData(
        thumbColor: foreground,
        activeTrackColor: foreground,
        inactiveTrackColor: foreground.withOpacity(0.26),
        trackShape: const RectangularSliderTrackShape(),
        trackHeight: 2,
        thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
      ),
      colorScheme: (dark
              ? const ColorScheme.dark(
                  primary: Colors.white,
                  secondary: Colors.white,
                  surface: Colors.black,
                  error: Colors.white,
                )
              : const ColorScheme.light(
                  primary: Colors.black,
                  secondary: Colors.black,
                  onSecondary: Colors.white,
                  error: Colors.black,
                ))
          .copyWith(
        background: background,
        onBackground: foreground,
      ),
    );
  }
}

/// Shows pushed pages immediately, without a transition.
class _NoTransitionsBuilder extends PageTransitionsBuilder {
  const _NoTransitionsBuilder();

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return child;
  }
}

/// Scrolling without overscroll bounce or glow, which only cause extra
/// refreshes on e-ink displays.
class EinkScrollBehavior extends MaterialScrollBehavior {
  /// Create the scroll behavior.
  const EinkScrollBehavior();

  @override
  ScrollPhysics getScrollPhysics(BuildContext context) {
    return const ClampingScrollPhysics();
  }

  @override
  Widget buildOverscrollIndicator(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    return child;
  }
}

/// A loading indicator that is a static image in e-ink mode, where a spinning
/// indicator would keep the display refreshing.
class JidoujishoLoadingIndicator extends StatelessWidget {
  /// Create a loading indicator.
  const JidoujishoLoadingIndicator({
    this.color,
    super.key,
  });

  /// Colour of the indicator. Defaults to the theme's primary colour.
  final Color? color;

  @override
  Widget build(BuildContext context) {
    Color color = this.color ?? Theme.of(context).colorScheme.primary;
    if (!EinkMode.enabled) {
      return CircularProgressIndicator(
        valueColor: AlwaysStoppedAnimation<Color>(color),
      );
    }

    // Sized like a CircularProgressIndicator: it fills a box it is given and
    // is 36 pixels otherwise.
    return ConstrainedBox(
      constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
      child: FittedBox(
        child: Icon(
          Icons.hourglass_empty_rounded,
          size: 36,
          color: color,
        ),
      ),
    );
  }
}

/// Jumping dots that are a static ellipsis in e-ink mode.
class JidoujishoJumpingDots extends StatelessWidget {
  /// Create the dots.
  const JidoujishoJumpingDots({
    this.color = Colors.black,
    this.fontSize = 10,
    super.key,
  });

  /// Colour of the dots.
  final Color color;

  /// Font size of the dots.
  final double fontSize;

  @override
  Widget build(BuildContext context) {
    if (!EinkMode.enabled) {
      return JumpingDotsProgressIndicator(color: color, fontSize: fontSize);
    }

    return Text(
      '...',
      maxLines: 1,
      softWrap: false,
      overflow: TextOverflow.visible,
      style: TextStyle(color: color, fontSize: fontSize),
    );
  }
}
