import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:yuuna/media.dart';

/// A character of recognised text placed on a page, in image pixels.
class MokuroGlyph {
  /// Place [character] centred on [centre], in a square cell of [size].
  MokuroGlyph({
    required this.character,
    required this.centre,
    required this.size,
    required this.angle,
  });

  /// The character drawn.
  final String character;

  /// Centre of the character's cell.
  final Offset centre;

  /// Side of the square the character is fitted into.
  final double size;

  /// Clockwise rotation in radians, which turns the character to follow its
  /// line, plus a quarter turn for characters set sideways in vertical text.
  final double angle;
}

/// Lays out and draws the recognised text of a page over the page image.
///
/// Each character is drawn in the cell a tap on it is mapped to, so what is
/// shown is what a tap looks up.
class MokuroTextOverlay {
  /// Draw text in [fontFamily].
  MokuroTextOverlay({this.fontFamily});

  /// Font the text is drawn in.
  final String? fontFamily;

  /// Characters set sideways in vertical text, as in printed Japanese.
  static const String sidewaysInVerticalText =
      'ー－～〜…‥—―–-~=＝()（）[]［］{}｛｝「」『』【】〈〉《》〔〕<>＜＞→←';

  /// Characters set in the upper right of their cell in vertical text.
  static const String upperRightInVerticalText = '、。，．';

  final Map<_GlyphStyle, TextPainter> _painters = {};

  /// The characters of [layout], placed along their lines.
  static List<MokuroGlyph> layOutGlyphs(MokuroBlockLayout layout) {
    List<MokuroGlyph> glyphs = [];
    bool vertical = layout.block.vertical;

    for (int i = 0; i < layout.shapes.length; i++) {
      MokuroLineShape shape = layout.shapes[i];
      List<String> characters =
          layout.block.lines[i].runes.map(String.fromCharCode).toList();
      if (characters.isEmpty) {
        continue;
      }

      Offset axis = shape.end - shape.start;
      double length = axis.distance;
      double thickness = ((shape.startA - shape.startB).distance +
              (shape.endA - shape.endB).distance) /
          2;
      if (length == 0 || thickness == 0) {
        continue;
      }

      Offset direction = axis / length;
      double lineAngle = vertical
          ? math.atan2(-direction.dx, direction.dy)
          : math.atan2(direction.dy, direction.dx);
      double cell = length / characters.length;
      double size = math.min(cell, thickness);

      for (int k = 0; k < characters.length; k++) {
        String character = characters[k];
        Offset centre =
            Offset.lerp(shape.start, shape.end, (k + 0.5) / characters.length)!;
        double angle = lineAngle;

        if (vertical && sidewaysInVerticalText.contains(character)) {
          angle += math.pi / 2;
        }
        if (vertical && upperRightInVerticalText.contains(character)) {
          centre += _rotate(Offset(size * 0.3, -size * 0.3), lineAngle);
        }

        glyphs.add(MokuroGlyph(
          character: character,
          centre: centre,
          size: size,
          angle: angle,
        ));
      }
    }

    return glyphs;
  }

  /// Cover [layout] on the page with [background] and draw its text in
  /// [foreground]. [scale] converts image pixels to canvas pixels.
  void paintBlock(
    Canvas canvas,
    MokuroBlockLayout layout, {
    required double scale,
    required Color background,
    required Color foreground,
  }) {
    Paint fill = Paint()..color = background;
    Rect bounds = layout.bounds;
    canvas.drawRect(
      Rect.fromLTRB(bounds.left * scale, bounds.top * scale,
          bounds.right * scale, bounds.bottom * scale),
      fill,
    );
    for (MokuroLineShape shape in layout.shapes) {
      canvas.drawPath(
        Path()
          ..addPolygon(
              shape.corners.map((corner) => corner * scale).toList(), true),
        fill,
      );
    }

    for (MokuroGlyph glyph in layOutGlyphs(layout)) {
      double fontSize = glyph.size * scale * 0.85;
      if (fontSize < 1) {
        continue;
      }

      TextPainter painter = _painterFor(_GlyphStyle(
        character: glyph.character,
        fontSize: fontSize,
        color: foreground,
      ));

      canvas.save();
      canvas.translate(glyph.centre.dx * scale, glyph.centre.dy * scale);
      canvas.rotate(glyph.angle);
      painter.paint(canvas, Offset(-painter.width / 2, -painter.height / 2));
      canvas.restore();
    }
  }

  TextPainter _painterFor(_GlyphStyle style) {
    return _painters.putIfAbsent(style, () {
      return TextPainter(
        text: TextSpan(
          text: style.character,
          style: TextStyle(
            fontFamily: fontFamily,
            fontSize: style.fontSize,
            color: style.color,
            height: 1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
    });
  }

  /// Release the laid out text.
  void dispose() {
    for (TextPainter painter in _painters.values) {
      painter.dispose();
    }
    _painters.clear();
  }

  static Offset _rotate(Offset offset, double angle) {
    double cos = math.cos(angle);
    double sin = math.sin(angle);
    return Offset(
      offset.dx * cos - offset.dy * sin,
      offset.dx * sin + offset.dy * cos,
    );
  }
}

class _GlyphStyle {
  _GlyphStyle({
    required this.character,
    required double fontSize,
    required this.color,
  }) : fontSize = (fontSize * 2).roundToDouble() / 2;

  final String character;

  /// Rounded to half a pixel, so that nearby sizes share a painter.
  final double fontSize;
  final Color color;

  @override
  bool operator ==(Object other) =>
      other is _GlyphStyle &&
      other.character == character &&
      other.fontSize == fontSize &&
      other.color == color;

  @override
  int get hashCode => Object.hash(character, fontSize, color);
}
