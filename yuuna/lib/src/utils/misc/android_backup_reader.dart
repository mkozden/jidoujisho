import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:path/path.dart' as path;
import 'package:yuuna/utils.dart';

/// Reads the files of an app out of an Android backup (`.ab`), as made by
/// `adb backup <package>`.
///
/// An Android backup is a short text header followed by a tar archive,
/// usually compressed with zlib. Files in the app's `files` folder are under
/// `apps/<package>/f/` and those in its other folders under
/// `apps/<package>/r/`. The archive is read as a stream and only the wanted
/// files are written out, as a backup can hold gigabytes of dictionaries.
class AndroidBackupReader {
  /// The header every Android backup starts with.
  static const String magic = 'ANDROID BACKUP';

  /// Whether [file] starts like an Android backup.
  static Future<bool> isAndroidBackup(File file) async {
    RandomAccessFile handle = await file.open();
    try {
      List<int> start = await handle.read(magic.length);
      return latin1.decode(start, allowInvalid: true) == magic;
    } finally {
      await handle.close();
    }
  }

  /// Write files in [backup] to [directory]. [target] is given the path of
  /// each file in the archive, and returns where to write it relative to
  /// [directory], or null to skip it. Returns the paths in the archive of the
  /// files written, mapped to the files.
  ///
  /// Throws a [SettingsBackupException] if [backup] is encrypted or is not an
  /// Android backup.
  static Future<Map<String, File>> extract({
    required File backup,
    required Directory directory,
    required String? Function(String archivePath) target,
  }) async {
    _Header header = await _readHeader(backup);
    if (header.encryption != 'none') {
      throw SettingsBackupException(t.backup_encrypted);
    }

    Stream<List<int>> tar = backup.openRead(header.length);
    if (header.compressed) {
      tar = tar.transform(zlib.decoder);
    }

    directory.createSync(recursive: true);
    _TarExtractor extractor = _TarExtractor(
      directory: directory,
      target: target,
    );
    await for (List<int> chunk in tar) {
      await extractor.add(chunk);
      if (extractor.finished) {
        break;
      }
    }
    await extractor.close();

    return extractor.written;
  }

  /// Read the four header lines: the magic, the format version, whether the
  /// archive is compressed and the encryption used.
  static Future<_Header> _readHeader(File backup) async {
    RandomAccessFile handle = await backup.open();
    try {
      List<int> start = await handle.read(1024);
      List<String> lines = [];
      int offset = 0;
      while (lines.length < 4) {
        int end = start.indexOf(0x0a, offset);
        if (end == -1) {
          throw SettingsBackupException(t.backup_not_a_backup);
        }
        lines.add(latin1.decode(start.sublist(offset, end)));
        offset = end + 1;
      }
      if (lines[0] != magic) {
        throw SettingsBackupException(t.backup_not_a_backup);
      }

      return _Header(
        length: offset,
        compressed: lines[2] == '1',
        encryption: lines[3],
      );
    } finally {
      await handle.close();
    }
  }
}

class _Header {
  _Header({
    required this.length,
    required this.compressed,
    required this.encryption,
  });

  /// Number of bytes before the archive.
  final int length;

  final bool compressed;

  final String encryption;
}

/// Extracts wanted files from a tar archive given in chunks.
///
/// Handles ustar names with a prefix, GNU long names (`L` entries) and pax
/// headers (`x` entries) giving the path, as well as GNU base-256 sizes for
/// files over 8 GB.
class _TarExtractor {
  _TarExtractor({
    required this.directory,
    required this.target,
  });

  static const int blockSize = 512;

  /// Write out at most this much before waiting for the disk.
  static const int flushInterval = 8 * 1024 * 1024;

  final Directory directory;

  final String? Function(String archivePath) target;

  /// Files written so far, by their path in the archive.
  final Map<String, File> written = {};

  /// Whether the end of the archive has been reached.
  bool finished = false;

  /// Bytes received that do not yet make up a whole header.
  final BytesBuilder _pending = BytesBuilder(copy: false);

  /// Bytes left of the data of the current entry, and of the padding that
  /// rounds it up to a whole block.
  int _dataLeft = 0;
  int _paddingLeft = 0;

  /// What the data of the current entry is used for.
  _EntryUse _use = _EntryUse.skip;

  /// The file the current entry is written to, if wanted.
  IOSink? _sink;
  int _unflushed = 0;

  /// Collects the data of a long name or pax header.
  BytesBuilder _metadata = BytesBuilder();

  /// A path given by a long name or pax header for the next entry.
  String? _nextPath;

  int _zeroBlocks = 0;

  Future<void> add(List<int> chunk) async {
    int offset = 0;
    while (offset < chunk.length && !finished) {
      if (_dataLeft > 0) {
        int take = min(_dataLeft, chunk.length - offset);
        await _consumeData(chunk, offset, take);
        offset += take;
        _dataLeft -= take;
        if (_dataLeft == 0) {
          await _finishEntry();
        }
      } else if (_paddingLeft > 0) {
        int take = min(_paddingLeft, chunk.length - offset);
        offset += take;
        _paddingLeft -= take;
      } else {
        int need = blockSize - _pending.length;
        int take = min(need, chunk.length - offset);
        _pending.add(Uint8List.sublistView(
            chunk is Uint8List ? chunk : Uint8List.fromList(chunk),
            offset,
            offset + take));
        offset += take;
        if (_pending.length == blockSize) {
          await _readHeader(_pending.takeBytes());
        }
      }
    }
  }

  Future<void> _consumeData(List<int> chunk, int offset, int length) async {
    switch (_use) {
      case _EntryUse.file:
        _sink!.add(chunk.sublist(offset, offset + length));
        _unflushed += length;
        if (_unflushed >= flushInterval) {
          await _sink!.flush();
          _unflushed = 0;
        }
        break;
      case _EntryUse.longName:
      case _EntryUse.pax:
        _metadata.add(chunk.sublist(offset, offset + length));
        break;
      case _EntryUse.skip:
        break;
    }
  }

  Future<void> _readHeader(Uint8List block) async {
    if (block.every((byte) => byte == 0)) {
      _zeroBlocks++;
      if (_zeroBlocks >= 2) {
        finished = true;
      }
      return;
    }
    _zeroBlocks = 0;

    String name = _string(block, 0, 100);
    int size = _size(block, 124, 12);
    String type = block[156] == 0 ? '0' : String.fromCharCode(block[156]);
    bool ustar = _string(block, 257, 5) == 'ustar';
    String prefix = ustar ? _string(block, 345, 155) : '';
    String entryPath = _nextPath ?? (prefix.isEmpty ? name : '$prefix/$name');

    _dataLeft = size;
    _paddingLeft = (blockSize - size % blockSize) % blockSize;

    switch (type) {
      case 'L':
        _use = _EntryUse.longName;
        _metadata = BytesBuilder();
        break;
      case 'x':
        _use = _EntryUse.pax;
        _metadata = BytesBuilder();
        break;
      case '0':
      case '7':
        _nextPath = null;
        String? relativePath = target(entryPath);
        if (relativePath != null) {
          File file = File(path.join(directory.path, relativePath));
          file.parent.createSync(recursive: true);
          _sink = file.openWrite();
          written[entryPath] = file;
          _use = _EntryUse.file;
        } else {
          _use = _EntryUse.skip;
        }
        break;
      default:
        _nextPath = null;
        _use = _EntryUse.skip;
    }

    if (size == 0) {
      await _finishEntry();
    }
  }

  Future<void> _finishEntry() async {
    switch (_use) {
      case _EntryUse.file:
        await _sink!.flush();
        await _sink!.close();
        _sink = null;
        _unflushed = 0;
        break;
      case _EntryUse.longName:
        _nextPath = _trimNulls(
            utf8.decode(_metadata.takeBytes(), allowMalformed: true));
        break;
      case _EntryUse.pax:
        String? paxPath = _paxPath(_metadata.takeBytes());
        if (paxPath != null) {
          _nextPath = paxPath;
        }
        break;
      case _EntryUse.skip:
        break;
    }
    _use = _EntryUse.skip;
  }

  Future<void> close() async {
    await _sink?.close();
    _sink = null;
  }

  /// The path in pax records, which are lines of the form
  /// `<length> <key>=<value>\n`.
  static String? _paxPath(Uint8List data) {
    String records = utf8.decode(data, allowMalformed: true);
    for (String line in records.split('\n')) {
      int space = line.indexOf(' ');
      if (space == -1) {
        continue;
      }
      String record = line.substring(space + 1);
      if (record.startsWith('path=')) {
        return record.substring('path='.length);
      }
    }
    return null;
  }

  static String _string(Uint8List block, int offset, int length) {
    return _trimNulls(utf8.decode(block.sublist(offset, offset + length),
        allowMalformed: true));
  }

  static String _trimNulls(String value) {
    int end = value.indexOf('\u0000');
    return end == -1 ? value : value.substring(0, end);
  }

  /// A size field: octal digits, or a big-endian number after a first byte
  /// with the high bit set.
  static int _size(Uint8List block, int offset, int length) {
    if (block[offset] & 0x80 != 0) {
      int value = block[offset] & 0x7f;
      for (int i = offset + 1; i < offset + length; i++) {
        value = (value << 8) | block[i];
      }
      return value;
    }

    String digits = _string(block, offset, length).trim();
    if (digits.isEmpty) {
      return 0;
    }
    return int.parse(digits, radix: 8);
  }
}

enum _EntryUse { skip, file, longName, pax }
