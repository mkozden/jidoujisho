/// A reading shown above part of a subtitle.
class SubtitleRuby {
  /// Initialise a reading.
  const SubtitleRuby({
    required this.start,
    required this.end,
    required this.reading,
  });

  /// Start of the text the reading belongs to, in UTF-16 code units.
  final int start;

  /// End of the text the reading belongs to, exclusive.
  final int end;

  /// The reading, such as かんじ.
  final String reading;
}

/// Subtitle text with readings in brackets taken out of it.
///
/// Subtitles for learners often write readings after kanji in brackets, as
/// in 漢字(かんじ) or 超(こ)える. Left in the text, the brackets split words
/// apart, so a lookup of 超(こ)える only finds 超. This keeps the plain text,
/// 超える, for lookups and export, and the readings apart, to be drawn above
/// the kanji they belong to.
class RubySubtitle {
  /// Initialise a subtitle.
  const RubySubtitle({
    required this.text,
    required this.rubies,
  });

  /// Takes the readings out of [raw], then removes whatever [regexFilter]
  /// matches from the text that is left.
  factory RubySubtitle.parse(String raw, {String regexFilter = ''}) {
    RubySubtitle subtitle = RubySubtitle._fromRaw(raw);
    if (regexFilter.isEmpty) {
      return subtitle;
    }

    RegExp regex;
    try {
      regex = RegExp(regexFilter);
    } on FormatException {
      return subtitle;
    }

    return subtitle._removeMatches(regex);
  }

  /// Takes the readings in brackets out of [raw].
  factory RubySubtitle._fromRaw(String raw) {
    List<int> runes = raw.runes.toList();
    StringBuffer buffer = StringBuffer();
    List<SubtitleRuby> rubies = [];

    // Code unit length of the text written so far.
    int length = 0;
    // The kanji just before the current position, if any.
    int? kanjiStart;
    int kanjiEnd = 0;
    // Kana written right after those kanji.
    int okuriganaLength = 0;

    void write(int rune) {
      String character = String.fromCharCode(rune);
      buffer.write(character);
      length += character.length;
    }

    for (int i = 0; i < runes.length; i++) {
      int rune = runes[i];

      if (_isOpeningBracket(rune) && kanjiStart != null) {
        int? close = _findClosingBracket(runes, i);
        if (close != null) {
          String reading =
              String.fromCharCodes(runes.sublist(i + 1, close)).trim();
          if (reading.isNotEmpty && reading.runes.every(_isKana)) {
            int start = kanjiStart;
            int end = kanjiEnd;
            if (okuriganaLength > 0) {
              // In 超える(こえる) the reading also covers える, so only
              // こ is drawn over 超. If the endings do not match, the
              // reading is drawn over the kanji and the kana together.
              String okurigana = buffer.toString().substring(kanjiEnd);
              String readingKana = _toHiragana(reading);
              String okuriganaKana = _toHiragana(okurigana);
              if (readingKana.endsWith(okuriganaKana) &&
                  readingKana.length > okuriganaKana.length) {
                reading = reading.substring(
                    0, reading.length - okuriganaKana.length);
              } else {
                end = length;
              }
            }

            rubies.add(SubtitleRuby(start: start, end: end, reading: reading));
            kanjiStart = null;
            okuriganaLength = 0;
            i = close;
            continue;
          }
        }
      }

      int before = length;
      write(rune);

      if (_isKanji(rune)) {
        if (kanjiStart == null || okuriganaLength > 0 || kanjiEnd != before) {
          kanjiStart = before;
        }
        kanjiEnd = length;
        okuriganaLength = 0;
      } else if (kanjiStart != null &&
          _isKana(rune) &&
          okuriganaLength < _maxOkuriganaLength) {
        okuriganaLength++;
      } else {
        kanjiStart = null;
        okuriganaLength = 0;
      }
    }

    return RubySubtitle(text: buffer.toString(), rubies: rubies);
  }

  /// The text with the readings in brackets taken out.
  final String text;

  /// Readings over parts of [text], in order.
  final List<SubtitleRuby> rubies;

  /// Readings are only taken out of brackets this long or shorter.
  static const int _maxReadingLength = 20;

  /// The kana after a kanji, such as える in 超える(こえる), that can still
  /// belong to a reading written after them.
  static const int _maxOkuriganaLength = 4;

  /// Removes the matches of [regex] from [text], moving the readings to
  /// match and dropping those whose text was removed.
  RubySubtitle _removeMatches(RegExp regex) {
    List<bool> removed = List<bool>.filled(text.length, false);
    bool anyRemoved = false;
    for (RegExpMatch match in regex.allMatches(text)) {
      for (int i = match.start; i < match.end; i++) {
        removed[i] = true;
        anyRemoved = true;
      }
    }
    if (!anyRemoved) {
      return this;
    }

    // newOffsets[i] is where text[i] ends up, or the next kept code unit.
    List<int> newOffsets = List<int>.filled(text.length + 1, 0);
    StringBuffer buffer = StringBuffer();
    int kept = 0;
    for (int i = 0; i < text.length; i++) {
      newOffsets[i] = kept;
      if (!removed[i]) {
        buffer.writeCharCode(text.codeUnitAt(i));
        kept++;
      }
    }
    newOffsets[text.length] = kept;

    List<SubtitleRuby> newRubies = [];
    for (SubtitleRuby ruby in rubies) {
      int start = newOffsets[ruby.start];
      int end = newOffsets[ruby.end];
      if (end > start) {
        newRubies.add(
          SubtitleRuby(start: start, end: end, reading: ruby.reading),
        );
      }
    }

    return RubySubtitle(text: buffer.toString(), rubies: newRubies);
  }

  static int? _findClosingBracket(List<int> runes, int open) {
    for (int i = open + 1;
        i < runes.length && i <= open + _maxReadingLength + 1;
        i++) {
      if (_isClosingBracket(runes[i])) {
        return i;
      }
      if (_isOpeningBracket(runes[i])) {
        return null;
      }
    }
    return null;
  }

  static bool _isOpeningBracket(int rune) => rune == 0x28 || rune == 0xFF08;

  static bool _isClosingBracket(int rune) => rune == 0x29 || rune == 0xFF09;

  /// Kanji, and marks written as part of kanji words such as 々 and ヶ.
  static bool _isKanji(int rune) =>
      (rune >= 0x4E00 && rune <= 0x9FFF) ||
      (rune >= 0x3400 && rune <= 0x4DBF) ||
      (rune >= 0xF900 && rune <= 0xFAFF) ||
      (rune >= 0x20000 && rune <= 0x3134F) ||
      rune == 0x3005 ||
      rune == 0x3006 ||
      rune == 0x30F6;

  /// Hiragana, katakana, the long vowel mark and the middle dot, as used in
  /// readings, and spaces between them.
  static bool _isKana(int rune) =>
      (rune >= 0x3041 && rune <= 0x3096) ||
      (rune >= 0x309D && rune <= 0x309E) ||
      (rune >= 0x30A1 && rune <= 0x30FA) ||
      (rune >= 0x30FB && rune <= 0x30FE) ||
      rune == 0x20 ||
      rune == 0x3000;

  static String _toHiragana(String text) {
    return String.fromCharCodes(text.runes.map((rune) {
      if (rune >= 0x30A1 && rune <= 0x30F6) {
        return rune - 0x60;
      }
      return rune;
    }));
  }
}
