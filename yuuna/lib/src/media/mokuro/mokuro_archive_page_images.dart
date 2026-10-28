import 'dart:io';
import 'dart:ui' as ui;

import 'package:async_zip/async_zip.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/painting.dart';
import 'package:yuuna/media.dart';

/// Page images read straight from a .cbz or .zip archive, without extracting
/// it.
class MokuroArchivePageImages extends MokuroPageImages {
  MokuroArchivePageImages._({
    required this.archive,
    required ZipFileReader reader,
    required List<String> entryNames,
  })  : _reader = reader,
        _entryNames = entryNames;

  /// Open [archive] for reading pages.
  ///
  /// Throws a [ZipException] if it is not a readable archive.
  static Future<MokuroArchivePageImages> open(File archive) async {
    ZipFileReader reader = ZipFileReader();
    try {
      await reader.open(archive);
      List<ZipEntry> entries = await reader.entries();

      return MokuroArchivePageImages._(
        archive: archive,
        reader: reader,
        entryNames: entries
            .where((entry) => !entry.isDir)
            .map((entry) => entry.name)
            .toList(),
      );
    } catch (e) {
      await reader.close();
      rethrow;
    }
  }

  /// The archive pages are read from.
  final File archive;

  final ZipFileReader _reader;
  final List<String> _entryNames;
  final Map<String, String?> _entryNameForPath = {};

  /// Requests sent after closing would never complete, as the reader's
  /// isolate is gone.
  bool _closed = false;

  /// The archive entry holding the image at [imgPath]. Archives often keep
  /// the pages inside a single top-level folder, which mokuro leaves out of
  /// the path when it unpacks them.
  String? entryNameForPath(String imgPath) {
    return _entryNameForPath.putIfAbsent(imgPath, () {
      if (_entryNames.contains(imgPath)) {
        return imgPath;
      }

      for (String name in _entryNames) {
        if (name.endsWith('/$imgPath')) {
          return name;
        }
      }

      return null;
    });
  }

  /// Read the entry at [entryName] from the archive.
  Future<Uint8List> readEntry(String entryName) {
    if (_closed) {
      throw StateError('Archive is closed: ${archive.path}');
    }

    return _reader.read(entryName);
  }

  @override
  ImageProvider imageForPage(MokuroPage page) {
    return MokuroArchiveImage(
      images: this,
      imgPath: page.imgPath,
    );
  }

  @override
  Future<Uint8List> readPage(MokuroPage page) async {
    String? entryName = entryNameForPath(page.imgPath);
    if (entryName == null) {
      throw StateError('No entry for ${page.imgPath} in ${archive.path}');
    }

    return readEntry(entryName);
  }

  @override
  Future<void> close() async {
    if (_closed) {
      return;
    }

    _closed = true;
    await _reader.close();
  }
}

/// Decodes a page image held in a [MokuroArchivePageImages].
///
/// Images are cached by archive path and page, so a page opened again after
/// the volume is reopened is not read twice.
@immutable
class MokuroArchiveImage extends ImageProvider<MokuroArchiveImage> {
  /// Read the image at [imgPath] from [images].
  const MokuroArchiveImage({
    required this.images,
    required this.imgPath,
  });

  /// Archive holding the image.
  final MokuroArchivePageImages images;

  /// Path of the image as listed in the .mokuro file.
  final String imgPath;

  @override
  Future<MokuroArchiveImage> obtainKey(ImageConfiguration configuration) {
    return SynchronousFuture<MokuroArchiveImage>(this);
  }

  @override
  ImageStreamCompleter loadImage(
    MokuroArchiveImage key,
    ImageDecoderCallback decode,
  ) {
    return MultiFrameImageStreamCompleter(
      codec: _loadAsync(key, decode),
      scale: 1,
      debugLabel: '${key.images.archive.path}/${key.imgPath}',
    );
  }

  Future<ui.Codec> _loadAsync(
    MokuroArchiveImage key,
    ImageDecoderCallback decode,
  ) async {
    String? entryName = key.images.entryNameForPath(key.imgPath);
    if (entryName == null) {
      throw StateError('No entry for ${key.imgPath} in ${key.images.archive}');
    }

    Uint8List bytes = await key.images.readEntry(entryName);
    ui.ImmutableBuffer buffer = await ui.ImmutableBuffer.fromUint8List(bytes);

    return decode(buffer);
  }

  @override
  bool operator ==(Object other) {
    return other is MokuroArchiveImage &&
        other.images.archive.path == images.archive.path &&
        other.imgPath == imgPath;
  }

  @override
  int get hashCode => Object.hash(images.archive.path, imgPath);
}
