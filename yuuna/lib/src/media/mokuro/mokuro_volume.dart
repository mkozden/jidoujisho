import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:path/path.dart' as path;
import 'package:yuuna/media.dart';
import 'package:yuuna/utils.dart';

/// The contents of a .mokuro file, which mokuro writes next to every volume
/// it processes. It holds the text recognised on each page, while the page
/// images stay in a folder or archive named after the file.
class MokuroVolume {
  /// Define a volume with its pages.
  MokuroVolume({
    required this.version,
    required this.title,
    required this.titleUuid,
    required this.volume,
    required this.volumeUuid,
    required this.pages,
  });

  /// Read a volume from the decoded contents of a .mokuro file.
  factory MokuroVolume.fromJson(Map<String, dynamic> json) {
    return MokuroVolume(
      version: json['version'] as String? ?? '',
      title: json['title'] as String? ?? '',
      titleUuid: json['title_uuid'] as String? ?? '',
      volume: json['volume'] as String? ?? '',
      volumeUuid: json['volume_uuid'] as String? ?? '',
      pages: (json['pages'] as List<dynamic>)
          .map((page) => MokuroPage.fromJson(page as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Version of mokuro that wrote the file.
  final String version;

  /// Name of the series, taken by mokuro from the parent folder.
  final String title;

  /// Identifies the series across its volumes.
  final String titleUuid;

  /// Name of this volume.
  final String volume;

  /// Identifies this volume, and stays the same if its files are moved.
  final String volumeUuid;

  /// Pages in reading order.
  final List<MokuroPage> pages;
}

/// A page of a [MokuroVolume] and the text blocks found on it.
class MokuroPage {
  /// Define a page.
  MokuroPage({
    required this.imgWidth,
    required this.imgHeight,
    required this.imgPath,
    required this.blocks,
  });

  /// Read a page from its entry in a .mokuro file.
  factory MokuroPage.fromJson(Map<String, dynamic> json) {
    return MokuroPage(
      imgWidth: (json['img_width'] as num).toInt(),
      imgHeight: (json['img_height'] as num).toInt(),
      imgPath: json['img_path'] as String,
      blocks: (json['blocks'] as List<dynamic>)
          .map((block) => MokuroBlock.fromJson(block as Map<String, dynamic>))
          .toList(),
    );
  }

  /// Width of the page image in pixels, which [MokuroBlock] coordinates use.
  final int imgWidth;

  /// Height of the page image in pixels, which [MokuroBlock] coordinates use.
  final int imgHeight;

  /// Path of the page image, relative to the volume's folder or archive.
  final String imgPath;

  /// Text blocks on this page, such as speech bubbles.
  final List<MokuroBlock> blocks;

  /// Size of the page image in pixels.
  Size get size => Size(imgWidth.toDouble(), imgHeight.toDouble());
}

/// A block of text on a [MokuroPage], with its position in image pixels.
class MokuroBlock {
  /// Define a text block.
  MokuroBlock({
    required this.box,
    required this.vertical,
    required this.fontSize,
    required this.lines,
    required this.lineCoords,
  });

  /// Read a block from its entry in a .mokuro file.
  factory MokuroBlock.fromJson(Map<String, dynamic> json) {
    List<double> box = (json['box'] as List<dynamic>)
        .map((value) => (value as num).toDouble())
        .toList();

    return MokuroBlock(
      box: Rect.fromLTRB(box[0], box[1], box[2], box[3]),
      vertical: json['vertical'] as bool? ?? false,
      fontSize: (json['font_size'] as num?)?.toDouble() ?? 0,
      lines: (json['lines'] as List<dynamic>)
          .map((line) => line as String)
          .toList(),
      lineCoords: (json['lines_coords'] as List<dynamic>? ?? [])
          .map((line) => (line as List<dynamic>).map((point) {
                List<dynamic> xy = point as List<dynamic>;
                return Offset(
                  (xy[0] as num).toDouble(),
                  (xy[1] as num).toDouble(),
                );
              }).toList())
          .toList(),
    );
  }

  /// Bounds of the block in image pixels.
  final Rect box;

  /// Whether the text is written top to bottom.
  final bool vertical;

  /// Estimated font size in image pixels.
  final double fontSize;

  /// Text of each line, in reading order.
  final List<String> lines;

  /// The four corners of each line in image pixels, in the same order as
  /// [lines]. Empty if the file does not include them.
  final List<List<Offset>> lineCoords;
}

/// Thrown when a .mokuro file or the page images of its volume cannot be read.
class MokuroVolumeException implements Exception {
  /// Describe the failure with a message that can be shown to the user.
  MokuroVolumeException(this.message);

  /// Message shown to the user.
  final String message;

  @override
  String toString() => message;
}

/// A [MokuroVolume] together with the source of its page images.
class LoadedMokuroVolume {
  /// Pair a volume with its page images.
  LoadedMokuroVolume({
    required this.volume,
    required this.images,
  });

  /// Load the .mokuro file at [mokuroPath] and find its page images, which
  /// mokuro keeps next to it in a folder, .cbz or .zip with the same name.
  ///
  /// Throws a [MokuroVolumeException] if either cannot be read.
  static Future<LoadedMokuroVolume> load(String mokuroPath) async {
    File file = File(mokuroPath);
    if (!file.existsSync()) {
      throw MokuroVolumeException(t.mokuro_file_missing);
    }

    late MokuroVolume volume;
    try {
      volume = await compute(_parseVolume, await file.readAsString());
    } catch (e) {
      debugPrint('Invalid .mokuro file: $e');
      throw MokuroVolumeException(t.invalid_mokuro_volume_file);
    }

    if (volume.pages.isEmpty) {
      throw MokuroVolumeException(t.invalid_mokuro_volume_file);
    }

    MokuroPageImages images = await MokuroPageImages.find(mokuroPath);
    return LoadedMokuroVolume(volume: volume, images: images);
  }

  static MokuroVolume _parseVolume(String contents) {
    return MokuroVolume.fromJson(jsonDecode(contents) as Map<String, dynamic>);
  }

  /// The parsed .mokuro file.
  final MokuroVolume volume;

  /// Where the page images are read from.
  final MokuroPageImages images;
}

/// Where the page images of a [MokuroVolume] are read from.
abstract class MokuroPageImages {
  /// Find the page images that belong to the .mokuro file at [mokuroPath].
  /// Like mokuro, prefers a folder over a .cbz over a .zip.
  ///
  /// Throws a [MokuroVolumeException] if none is found.
  static Future<MokuroPageImages> find(String mokuroPath) async {
    String stem = path.basenameWithoutExtension(mokuroPath);
    Directory directory = Directory(path.dirname(mokuroPath));

    Directory pagesDirectory = Directory(path.join(directory.path, stem));
    if (pagesDirectory.existsSync()) {
      return MokuroDirectoryPageImages(pagesDirectory);
    }

    List<File> siblings = directory.listSync().whereType<File>().toList();
    for (String extension in ['.cbz', '.zip']) {
      File? archive = siblings.firstWhereOrNull((file) =>
          path.basenameWithoutExtension(file.path) == stem &&
          path.extension(file.path).toLowerCase() == extension);
      if (archive != null) {
        try {
          return await MokuroArchivePageImages.open(archive);
        } catch (e) {
          debugPrint('Cannot open ${archive.path}: $e');
          throw MokuroVolumeException(t.mokuro_archive_unreadable);
        }
      }
    }

    throw MokuroVolumeException(t.mokuro_pages_not_found(name: stem));
  }

  /// The image of [page], for display.
  ImageProvider imageForPage(MokuroPage page);

  /// The encoded image file of [page].
  Future<Uint8List> readPage(MokuroPage page);

  /// Release any resources held. No pages can be read afterwards.
  Future<void> close() async {}
}

/// Page images kept as files in a folder.
class MokuroDirectoryPageImages extends MokuroPageImages {
  /// Read pages from [directory].
  MokuroDirectoryPageImages(this.directory);

  /// Folder that [MokuroPage.imgPath] is relative to.
  final Directory directory;

  /// The image file of [page].
  File fileForPage(MokuroPage page) {
    return File(path.join(directory.path, page.imgPath));
  }

  @override
  ImageProvider imageForPage(MokuroPage page) {
    return FileImage(fileForPage(page));
  }

  @override
  Future<Uint8List> readPage(MokuroPage page) {
    return fileForPage(page).readAsBytes();
  }
}
