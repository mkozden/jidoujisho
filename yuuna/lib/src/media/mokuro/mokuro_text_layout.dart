import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:yuuna/media.dart';

/// The outline of a line of text on a page, in image pixels, along with the
/// direction it is read in. Used to tell which character was tapped and where
/// to draw a highlight, without laying out any text.
class MokuroLineShape {
  /// Define a line from the four corners of its outline, in order around it.
  /// [vertical] gives the reading direction: top to bottom if true, else left
  /// to right.
  factory MokuroLineShape.fromCorners(
    List<Offset> corners, {
    required bool vertical,
  }) {
    Offset c0 = corners[0];
    Offset c1 = corners[1];
    Offset c2 = corners[2];
    Offset c3 = corners[3];

    /// The outline has two ways of pairing up opposite edges. The ends of the
    /// line are the pair whose midpoints lie furthest apart along the reading
    /// direction. Each end is given in matching order, so that corresponding
    /// corners share a long side.
    List<List<Offset>> pairingA = [
      [c0, c1],
      [c3, c2],
    ];
    List<List<Offset>> pairingB = [
      [c0, c3],
      [c1, c2],
    ];

    double spread(List<List<Offset>> pairing) {
      Offset delta = _midpoint(pairing[1]) - _midpoint(pairing[0]);
      return vertical ? delta.dy.abs() : delta.dx.abs();
    }

    List<List<Offset>> ends =
        spread(pairingA) >= spread(pairingB) ? pairingA : pairingB;

    double position(List<Offset> end) {
      Offset midpoint = _midpoint(end);
      return vertical ? midpoint.dy : midpoint.dx;
    }

    if (position(ends[0]) > position(ends[1])) {
      ends = [ends[1], ends[0]];
    }

    return MokuroLineShape._(
      startA: ends[0][0],
      startB: ends[0][1],
      endA: ends[1][0],
      endB: ends[1][1],
    );
  }

  MokuroLineShape._({
    required this.startA,
    required this.startB,
    required this.endA,
    required this.endB,
  });

  /// One corner at the start of the line.
  final Offset startA;

  /// The other corner at the start of the line.
  final Offset startB;

  /// The corner at the end of the line that shares a side with [startA].
  final Offset endA;

  /// The corner at the end of the line that shares a side with [startB].
  final Offset endB;

  /// The corners in order around the outline.
  List<Offset> get corners => [startA, startB, endB, endA];

  /// Middle of the edge where the line starts.
  Offset get start => (startA + startB) / 2;

  /// Middle of the edge where the line ends.
  Offset get end => (endA + endB) / 2;

  /// Whether [point] is inside the outline.
  bool contains(Offset point) {
    List<Offset> polygon = corners;
    bool inside = false;
    for (int i = 0, j = polygon.length - 1; i < polygon.length; j = i++) {
      Offset a = polygon[i];
      Offset b = polygon[j];
      if ((a.dy > point.dy) != (b.dy > point.dy) &&
          point.dx < (b.dx - a.dx) * (point.dy - a.dy) / (b.dy - a.dy) + a.dx) {
        inside = !inside;
      }
    }
    return inside;
  }

  /// Distance from [point] to the outline, or zero if it is inside.
  double distanceTo(Offset point) {
    if (contains(point)) {
      return 0;
    }

    List<Offset> polygon = corners;
    double distance = double.infinity;
    for (int i = 0; i < polygon.length; i++) {
      distance = math.min(
        distance,
        _distanceToSegment(point, polygon[i], polygon[(i + 1) % 4]),
      );
    }
    return distance;
  }

  /// How far along the line [point] is, from 0 at its start to 1 at its end.
  double progressAt(Offset point) {
    Offset axis = end - start;
    double lengthSquared = axis.distanceSquared;
    if (lengthSquared == 0) {
      return 0;
    }

    Offset relative = point - start;
    double t = (relative.dx * axis.dx + relative.dy * axis.dy) / lengthSquared;
    return t.clamp(0, 1).toDouble();
  }

  /// The part of the outline between [from] and [to], given as fractions of
  /// the line's length.
  List<Offset> segment(double from, double to) {
    return [
      Offset.lerp(startA, endA, from)!,
      Offset.lerp(startB, endB, from)!,
      Offset.lerp(startB, endB, to)!,
      Offset.lerp(startA, endA, to)!,
    ];
  }

  static Offset _midpoint(List<Offset> points) => (points[0] + points[1]) / 2;

  static double _distanceToSegment(Offset point, Offset a, Offset b) {
    Offset ab = b - a;
    double lengthSquared = ab.distanceSquared;
    if (lengthSquared == 0) {
      return (point - a).distance;
    }

    Offset ap = point - a;
    double t = ((ap.dx * ab.dx + ap.dy * ab.dy) / lengthSquared).clamp(0, 1);
    return (point - (a + ab * t)).distance;
  }
}

/// A tapped character in a [MokuroBlockLayout].
class MokuroTextHit {
  /// Define a hit on the character at [index] of [layout]'s text.
  MokuroTextHit({
    required this.layout,
    required this.index,
  });

  /// The block that was tapped.
  final MokuroBlockLayout layout;

  /// Offset of the tapped character in [MokuroBlockLayout.text].
  final int index;
}

/// A text block of a page, joined into a single text for lookups, with the
/// shapes of its lines for finding and highlighting characters.
class MokuroBlockLayout {
  /// Lay out [block] of a page of size [pageSize]. Lines are joined with
  /// [separator], such as a space for languages that use them between words.
  factory MokuroBlockLayout(
    MokuroBlock block, {
    required Size pageSize,
    String separator = '',
  }) {
    Rect bounds = _clampToPage(block.box, pageSize);

    List<MokuroLineShape> shapes = [];
    bool hasCoords = block.lineCoords.length == block.lines.length &&
        block.lineCoords.every((corners) => corners.length == 4);
    for (int i = 0; i < block.lines.length; i++) {
      List<Offset> corners =
          hasCoords ? block.lineCoords[i] : _estimateCorners(bounds, block, i);
      shapes.add(MokuroLineShape.fromCorners(
        corners,
        vertical: block.vertical,
      ));
    }

    List<int> lineStarts = [];
    StringBuffer buffer = StringBuffer();
    for (int i = 0; i < block.lines.length; i++) {
      if (i != 0) {
        buffer.write(separator);
      }
      lineStarts.add(buffer.length);
      buffer.write(block.lines[i]);
    }

    return MokuroBlockLayout._(
      block: block,
      bounds: bounds,
      shapes: shapes,
      lineStarts: lineStarts,
      text: buffer.toString(),
    );
  }

  MokuroBlockLayout._({
    required this.block,
    required this.bounds,
    required this.shapes,
    required this.lineStarts,
    required this.text,
  });

  /// The block laid out.
  final MokuroBlock block;

  /// The block's box, kept within the page.
  final Rect bounds;

  /// The shape of each line, in the same order as [MokuroBlock.lines].
  final List<MokuroLineShape> shapes;

  /// Offset in [text] where each line starts.
  final List<int> lineStarts;

  /// All lines of the block joined together.
  final String text;

  /// Whether [point] is on the block or any of its lines, as line outlines
  /// can stick out of the block's box.
  bool contains(Offset point) {
    return bounds.contains(point) ||
        shapes.any((shape) => shape.contains(point));
  }

  /// The character at [point], taking the nearest line if it falls between
  /// lines. Null if the block has no text.
  MokuroTextHit? hitTest(Offset point) {
    int? lineIndex;
    double nearest = double.infinity;
    for (int i = 0; i < shapes.length; i++) {
      if (block.lines[i].isEmpty) {
        continue;
      }
      double distance = shapes[i].distanceTo(point);
      if (distance < nearest) {
        nearest = distance;
        lineIndex = i;
      }
    }
    if (lineIndex == null) {
      return null;
    }

    String line = block.lines[lineIndex];
    List<int> starts = _runeStarts(line);
    double progress = shapes[lineIndex].progressAt(point);
    int rune = (progress * starts.length).floor().clamp(0, starts.length - 1);

    return MokuroTextHit(
      layout: this,
      index: lineStarts[lineIndex] + starts[rune],
    );
  }

  /// Outlines covering the text from [start] to [end] in [text], one for each
  /// line it spans.
  List<List<Offset>> highlightOutlines(int start, int end) {
    List<List<Offset>> outlines = [];
    for (int i = 0; i < block.lines.length; i++) {
      String line = block.lines[i];
      int lineStart = lineStarts[i];
      int lineEnd = lineStart + line.length;
      int from = math.max(start, lineStart) - lineStart;
      int to = math.min(end, lineEnd) - lineStart;
      if (from >= to) {
        continue;
      }

      List<int> starts = _runeStarts(line);
      double fromFraction = _runeIndexAt(starts, from) / starts.length;
      double toFraction = _runeIndexAt(starts, to) / starts.length;
      outlines.add(shapes[i].segment(fromFraction, toFraction));
    }
    return outlines;
  }

  /// Offsets in [text] at which each character of it starts, counting
  /// surrogate pairs as one character.
  static List<int> _runeStarts(String text) {
    List<int> starts = [];
    int offset = 0;
    for (int rune in text.runes) {
      starts.add(offset);
      offset += rune > 0xFFFF ? 2 : 1;
    }
    return starts;
  }

  /// Number of characters starting before [offset].
  static int _runeIndexAt(List<int> starts, int offset) {
    int count = 0;
    while (count < starts.length && starts[count] < offset) {
      count++;
    }
    return count;
  }

  static Rect _clampToPage(Rect box, Size pageSize) {
    if (pageSize.isEmpty) {
      return box;
    }

    return Rect.fromLTRB(
      box.left.clamp(0, pageSize.width).toDouble(),
      box.top.clamp(0, pageSize.height).toDouble(),
      box.right.clamp(0, pageSize.width).toDouble(),
      box.bottom.clamp(0, pageSize.height).toDouble(),
    );
  }

  /// Corners of line [index] for files without line outlines, splitting the
  /// box evenly: into columns from the right for vertical text, else into
  /// rows from the top.
  static List<Offset> _estimateCorners(
      Rect bounds, MokuroBlock block, int index) {
    int count = block.lines.length;
    if (block.vertical) {
      double width = bounds.width / count;
      double right = bounds.right - width * index;
      return [
        Offset(right - width, bounds.top),
        Offset(right, bounds.top),
        Offset(right, bounds.bottom),
        Offset(right - width, bounds.bottom),
      ];
    } else {
      double height = bounds.height / count;
      double top = bounds.top + height * index;
      return [
        Offset(bounds.left, top),
        Offset(bounds.right, top),
        Offset(bounds.right, top + height),
        Offset(bounds.left, top + height),
      ];
    }
  }
}

/// Text layouts of the blocks on a page, for finding what was tapped.
class MokuroPageLayout {
  /// Lay out the blocks of [page], joining lines with [separator].
  MokuroPageLayout(MokuroPage page, {String separator = ''})
      : blocks = page.blocks
            .map((block) => MokuroBlockLayout(
                  block,
                  pageSize: page.size,
                  separator: separator,
                ))
            .toList();

  /// Layouts of the page's blocks, in the order of [MokuroPage.blocks].
  final List<MokuroBlockLayout> blocks;

  /// The character at [point] in image pixels, or null if no block is there.
  /// Where blocks overlap, the smallest is taken, as it is drawn on top.
  MokuroTextHit? hitTest(Offset point) {
    MokuroBlockLayout? target;
    for (MokuroBlockLayout layout in blocks) {
      if (!layout.contains(point)) {
        continue;
      }
      if (target == null || _area(layout.bounds) < _area(target.bounds)) {
        target = layout;
      }
    }

    return target?.hitTest(point);
  }

  static double _area(Rect rect) => rect.width * rect.height;
}
