import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:isar/isar.dart';
import 'package:yuuna/dictionary.dart';
import 'package:yuuna/models.dart';

/// Number of rows prepared in memory before they are written to the database
/// in one batch during dictionary import.
const int dictionaryImportBatchSize = 5000;

/// Rate-limits progress messages sent from an import isolate. Sending one
/// message per row floods the UI isolate with hundreds of thousands of
/// messages and rebuilds, which costs more than the import itself.
class ImportProgressReporter {
  /// Create a reporter that sends at most one message per [interval].
  ImportProgressReporter(
    this.sendPort, {
    this.interval = const Duration(milliseconds: 100),
  });

  /// Port to send progress messages through.
  final SendPort sendPort;

  /// Minimum time between two messages.
  final Duration interval;

  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _lastSent;

  /// Send the message built by [message] if enough time has passed since the
  /// last one, or if [force] is true. The message is only built when sent.
  void report(String Function() message, {bool force = false}) {
    final Duration now = _stopwatch.elapsed;
    final Duration? lastSent = _lastSent;
    if (!force && lastSent != null && now - lastSent < interval) {
      return;
    }

    _lastSent = now;
    sendPort.send(message());
  }
}

/// Count the items of a top-level JSON array without decoding it. Works on
/// raw UTF-8 bytes, as the structural characters are all ASCII and never
/// appear inside multi-byte sequences. Used to get progress totals without
/// paying for a full `jsonDecode` of every file twice.
int countJsonArrayItems(Uint8List bytes) {
  int depth = 0;
  int commas = 0;
  bool hasItem = false;
  bool inString = false;
  bool escaped = false;

  for (int i = 0; i < bytes.length; i++) {
    final int c = bytes[i];
    if (inString) {
      if (escaped) {
        escaped = false;
      } else if (c == 0x5C) {
        escaped = true;
      } else if (c == 0x22) {
        inString = false;
      }
      continue;
    }

    switch (c) {
      case 0x22: // "
        inString = true;
        if (depth == 1) {
          hasItem = true;
        }
        break;
      case 0x5B: // [
      case 0x7B: // {
        if (depth == 1) {
          hasItem = true;
        }
        depth++;
        break;
      case 0x5D: // ]
      case 0x7D: // }
        depth--;
        break;
      case 0x2C: // ,
        if (depth == 1) {
          commas++;
        }
        break;
      case 0x20: // space
      case 0x09: // tab
      case 0x0A: // line feed
      case 0x0D: // carriage return
      case 0xEF: // UTF-8 byte order mark
      case 0xBB:
      case 0xBF:
        break;
      default:
        if (depth == 1) {
          hasItem = true;
        }
    }
  }

  return hasItem ? commas + 1 : 0;
}

/// Looks up the tags of a dictionary by name during import, reading each tag
/// from the database only once.
class DictionaryTagCache {
  /// Create a cache for the tags of the dictionary with [dictionaryId].
  DictionaryTagCache({required this.isar, required this.dictionaryId});

  /// Database to read tags from.
  final Isar isar;

  /// Dictionary the tags belong to.
  final int dictionaryId;

  final Map<String, DictionaryTag?> _tags = {};

  /// Get the stored tags with the given names, skipping unknown names.
  List<DictionaryTag> lookup(Iterable<String> names) {
    final List<DictionaryTag> tags = [];
    for (final String name in names) {
      final DictionaryTag? tag = _tags.putIfAbsent(
        name,
        () => isar.dictionaryTags.getSync(
          DictionaryTag.hash(dictionaryId: dictionaryId, name: name),
        ),
      );
      if (tag != null) {
        tags.add(tag);
      }
    }

    return tags;
  }
}

/// Collects the [DictionaryHeading]s touched by one batch of imported rows,
/// so that each heading is read and written at most once per batch instead of
/// once per row.
///
/// Call [flush] before writing any object that links to a heading from this
/// batch: Isar only stores a link when both of its objects already exist.
class DictionaryHeadingBatch {
  /// Create a batch that reads and writes headings in [isar].
  DictionaryHeadingBatch(this.isar);

  /// Database the headings live in.
  final Isar isar;

  /// Headings looked up so far. A null value means the heading is not stored.
  final Map<int, DictionaryHeading?> _lookup = {};

  /// Headings that do not exist yet and must be written.
  final Map<int, DictionaryHeading> _created = {};

  /// Stored headings that gained tags and must have their tag links saved.
  final Map<int, DictionaryHeading> _retagged = {};

  /// Read the headings with [ids] in one call, so that [obtain] does not have
  /// to read them one by one.
  void prefetch(Iterable<int> ids) {
    final List<int> missing =
        ids.where((id) => !_lookup.containsKey(id)).toSet().toList();
    if (missing.isEmpty) {
      return;
    }

    final List<DictionaryHeading?> headings =
        isar.dictionaryHeadings.getAllSync(missing);
    for (int i = 0; i < missing.length; i++) {
      _lookup[missing[i]] = headings[i];
    }
  }

  /// Get the heading with [id]. If it is not stored, the heading returned by
  /// [create] is used instead. Its own ID may differ from [id], in which case
  /// a stored heading with that ID takes precedence.
  DictionaryHeading obtain(int id, DictionaryHeading Function() create) {
    if (!_lookup.containsKey(id)) {
      _lookup[id] = isar.dictionaryHeadings.getSync(id);
    }

    final DictionaryHeading? heading = _lookup[id];
    if (heading != null) {
      return heading;
    }

    final DictionaryHeading created = create();
    if (created.id != id) {
      return obtain(created.id, () => created);
    }

    _lookup[id] = created;
    _created[id] = created;
    return created;
  }

  /// Get the heading with [id] if it is stored or was created in this batch.
  DictionaryHeading? find(int id) {
    if (!_lookup.containsKey(id)) {
      _lookup[id] = isar.dictionaryHeadings.getSync(id);
    }

    return _lookup[id];
  }

  /// Link [tags] to [heading]. The links are saved on [flush].
  void addTags(DictionaryHeading heading, Iterable<DictionaryTag> tags) {
    bool changed = false;
    for (final DictionaryTag tag in tags) {
      if (heading.tags.add(tag)) {
        changed = true;
      }
    }

    if (changed && !_created.containsKey(heading.id)) {
      _retagged[heading.id] = heading;
    }
  }

  /// Write new headings and save new tag links, then forget the batch.
  void flush() {
    if (_created.isNotEmpty) {
      isar.dictionaryHeadings.putAllSync(_created.values.toList());
    }
    for (final DictionaryHeading heading in _retagged.values) {
      heading.tags.saveSync();
    }

    _lookup.clear();
    _created.clear();
    _retagged.clear();
  }
}

/// FNV-1a 64bit hash algorithm optimized for Dart Strings.
/// This is used to generate integer IDs that can be hard assigned to entities
/// with string IDs with microscopically low collision. This allows for example,
/// a [DictionaryHeading]'s ID to always be determinable by its composite
/// parameters.
int fastHash(String string) {
  var hash = 0xcbf29ce484222325;

  var i = 0;
  while (i < string.length) {
    final codeUnit = string.codeUnitAt(i++);
    hash ^= codeUnit >> 8;
    hash *= 0x100000001b3;
    hash ^= codeUnit & 0xFF;
    hash *= 0x100000001b3;
  }

  return hash;
}

/// Performed in another isolate with compute. This is a top-level utility
/// function that makes use of Isar allowing instances to be opened through
/// multiple isolates. The function for preparing entries and tags according to
/// the [DictionaryFormat] is also done in the same isolate, to remove having
/// to communicate potentially hundreds of thousands of entries to another
/// newly opened isolate.
Future<void> depositDictionaryDataHelper(PrepareDictionaryParams params) async {
  try {
    /// Create a new instance of Isar as this is a different isolate.
    final Isar isar = await Isar.open(
      globalSchemas,
      directory: params.directoryPath,
      maxSizeMiB: 8192,
    );

    /// Write as one transaction. If anything fails, no changes should occur.
    await isar.writeTxnSync(() async {
      /// Write the [Dictionary] entity.
      isar.dictionarys.putSync(params.dictionary);

      /// Write entities.
      params.dictionaryFormat.prepareTags(params: params, isar: isar);
      params.dictionaryFormat.prepareEntries(params: params, isar: isar);
      params.dictionaryFormat.preparePitches(params: params, isar: isar);
      params.dictionaryFormat.prepareFrequencies(params: params, isar: isar);
    });
  } catch (e, stack) {
    debugPrint('$e');
    debugPrint('$stack');

    params.send('$stack');

    rethrow;
  }
}

/// Preloads the entities linked to a search result.
void preloadResultSync(int id) {
  /// Create a new instance of Isar as this is a different isolate.
  final Isar database = Isar.getInstance()!;
  DictionarySearchResult result = database.dictionarySearchResults.getSync(id)!;

  result.headings.loadSync();

  for (DictionaryHeading heading in result.headings) {
    heading.entries.loadSync();
    for (DictionaryEntry entry in heading.entries) {
      entry.dictionary.loadSync();
      entry.tags.loadSync();
    }
    heading.pitches.loadSync();
    heading.frequencies.loadSync();
    for (DictionaryFrequency frequency in heading.frequencies) {
      frequency.dictionary.loadSync();
    }
    heading.tags.loadSync();
  }
}

/// Add a [DictionarySearchResult] to the dictionary history. If the maximum value
/// is exceed, the dictionary history is cut down to the newest values.
Future<void> updateDictionaryHistoryHelper(
  UpdateDictionaryHistoryParams params,
) async {
  final Isar database = await Isar.open(
    globalSchemas,
    directory: params.directoryPath,
    maxSizeMiB: 8192,
  );

  DictionarySearchResult result =
      database.dictionarySearchResults.getSync(params.resultId)!;

  database.writeTxnSync(() {
    result.scrollPosition = params.newPosition;
    database.dictionarySearchResults.putSync(result);
  });
}

/// Clears all data from the dictionary database.
Future<void> deleteDictionariesHelper(DeleteDictionaryParams params) async {
  final Isar database = await Isar.open(
    globalSchemas,
    directory: params.directoryPath,
    maxSizeMiB: 8192,
  );

  database.writeTxnSync(() {
    database.dictionarySearchResults.clearSync();
    database.dictionaryTags.clearSync();
    database.dictionaryEntrys.clearSync();
    database.dictionaryHeadings.clearSync();
    database.dictionaryPitchs.clearSync();
    database.dictionaryFrequencys.clearSync();
    database.dictionarys.clearSync();
  });
}

/// Clears single dictionary data from the dictionary database.
Future<void> deleteDictionaryHelper(DeleteDictionaryParams params) async {
  final Isar database = await Isar.open(
    globalSchemas,
    directory: params.directoryPath,
    maxSizeMiB: 8192,
  );

  int id = params.dictionaryId!;
  Dictionary dictionary = database.dictionarys.getSync(id)!;

  database.writeTxnSync(() {
    database.dictionarySearchResults.clearSync();
    database.dictionaryEntrys
        .filter()
        .dictionary((q) => q.idEqualTo(id))
        .deleteAllSync();
    database.dictionaryTags
        .filter()
        .dictionary((q) => q.idEqualTo(id))
        .deleteAllSync();
    database.dictionaryPitchs
        .filter()
        .dictionary((q) => q.idEqualTo(id))
        .deleteAllSync();
    database.dictionaryFrequencys
        .filter()
        .dictionary((q) => q.idEqualTo(id))
        .deleteAllSync();
    database.dictionaryHeadings
        .filter()
        .entriesIsEmpty()
        .and()
        .tagsIsEmpty()
        .and()
        .pitchesIsEmpty()
        .and()
        .frequenciesIsEmpty()
        .deleteAllSync();
    database.dictionarys.deleteSync(dictionary.id);
  });
}
