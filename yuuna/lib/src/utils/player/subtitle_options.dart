/// Settings that are persisted for the blur widget used in the player.
class SubtitleOptions {
  /// Initialise this object.
  SubtitleOptions({
    required this.audioAllowance,
    required this.subtitleDelay,
    required this.fontSize,
    required this.fontName,
    required this.subtitleBackgroundOpacity,
    required this.regexFilter,
    required this.subtitleOutlineWidth,
    required this.subtitleBackgroundBlurRadius,
    required this.alwaysAboveBottomBar,
    required this.showFurigana,
  });

  /// Audio allowance, used for audio export, in milliseconds.
  int audioAllowance;

  /// Subtitle delay in milliseconds.
  int subtitleDelay;

  /// Subtitle font size.
  double fontSize;

  /// Name of the font preferred for the subtitle.
  String fontName;

  /// Subtitle background blur radius.
  double subtitleBackgroundBlurRadius;

  /// Subtitle background opacity.
  double subtitleBackgroundOpacity;

  /// Subtitle outline width.
  double subtitleOutlineWidth;

  /// Regex filter used for the subtitle.
  String regexFilter;

  /// Whether or not the subtitle should always be above the bottom bar.
  bool alwaysAboveBottomBar;

  /// Whether readings written in brackets after kanji, as in 漢字(かんじ),
  /// are shown above the kanji. They are left out of the text either way.
  bool showFurigana;
}
