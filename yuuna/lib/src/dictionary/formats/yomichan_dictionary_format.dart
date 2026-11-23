import 'dart:convert';
import 'dart:io';
import 'dart:isolate';
import 'dart:math' show min;

import 'package:async_zip/async_zip.dart';
import 'package:beautiful_soup_dart/beautiful_soup.dart';
import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:html/dom.dart' as dom;
import 'package:isar/isar.dart';
import 'package:list_counter/list_counter.dart';
import 'package:path/path.dart' as path;
import 'package:recase/recase.dart';
import 'package:yuuna/dictionary.dart';
import 'package:yuuna/utils.dart';

/// A dictionary format for archives following the latest Yomichan bank schema.
/// Example dictionaries for this format may be downloaded from the Yomichan
/// website.
///
/// Details on the format can be found here:
/// https://github.com/FooSoft/yomichan/blob/master/ext/data/schemas/dictionary-term-bank-v3-schema.json
class YomichanFormat extends DictionaryFormat {
  /// Define a format with the given metadata that has its behaviour for
  /// import, search and display defined with af set of top-level helper methods.
  YomichanFormat._privateConstructor()
      : super(
          uniqueKey: 'yomichan',
          name: 'Yomichan Dictionary',
          icon: Icons.auto_stories_rounded,
          allowedExtensions: const ['zip'],
          isTextFormat: false,
          fileType: FileType.custom,
          prepareDirectory: prepareDirectoryYomichanFormat,
          prepareName: prepareNameYomichanFormat,
          prepareEntries: prepareEntriesYomichanFormat,
          prepareTags: prepareTagsYomichanFormat,
          preparePitches: preparePitchesYomichanFormat,
          prepareFrequencies: prepareFrequenciesYomichanFormat,
        );

  /// Get the singleton instance of this dictionary format.
  static YomichanFormat get instance => _instance;

  static final YomichanFormat _instance = YomichanFormat._privateConstructor();

  /// If true, uses the [customDefinitionWidget] instead.
  @override
  bool shouldUseCustomDefinitionWidget(String definition) {
    try {
      jsonDecode(definition);
      return true;
    } catch (e) {
      return false;
    }
  }

  @override
  String getCustomDefinitionText(String meaning) {
    final node =
        StructuredContent.processContent(jsonDecode(meaning))?.toNode();
    if (node == null) {
      return '';
    }

    final document = dom.Document.html('');
    document.body?.append(node);
    for (final e in document.querySelectorAll('li')) {
      final css = e.bs4.findParent('ul')?.attributes['style'] ?? '';
      final text = e.text;
      final name = css
              .split(';')
              .firstWhere((e) => e.contains('list-style-type'))
              .split(':')
              .lastOrNull ??
          'square';

      final counterStyle = CounterStyleRegistry.lookup(name);
      final counter = counterStyle.generateMarkerContent(0);
      e.text = '$counter $text';
    }
    document.querySelectorAll('table').map((e) => e.remove());
    final html = document.body?.innerHtml ?? '';

    return BeautifulSoup(html).getText(separator: '\n');
  }

  /// Recursively get HTML for a structured content definition.
  static String getStructuredContentHtml(dynamic content) {
    if (content is Map) {
      return getNodeHtml(
        tag: content['tag'],
        content: getStructuredContentHtml(content['content']),
        style: getStyle(
          content['style'] ?? {},
        ),
      );
    } else if (content is List) {
      return content.map(getStructuredContentHtml).join();
    }

    return content;
  }

  /// Convert style to appropriate format.
  static Map<String, String> getStyle(Map<String, dynamic> styleMap) {
    return Map<String, String>.fromEntries(
      styleMap.entries.map(
        (e) => MapEntry(
          ReCase(e.key).paramCase,
          e.value.toString(),
        ),
      ),
    );
  }

  /// Get the HTML for a certain node.
  static String getNodeHtml({
    required String content,
    String? tag,
    Map<String, String> style = const {},
  }) {
    if (tag == null) {
      return content;
    }

    dom.Element element = dom.Element.tag(tag);
    element.attributes.addAll(style);

    element.innerHtml = content;

    return element.outerHtml;
  }

  /// For [prepareEntriesYomichanFormat].
  static String? processDefinition(var definition) {
    if (definition is String) {
      final plainText = definition;
      return plainText;
    } else if (definition is Map) {
      final type = definition['type'];

      switch (type) {
        case 'text':
          final plainText = definition['text'];
          return plainText;
        case 'structured-content':
        case 'image':
          return jsonEncode(definition['content']);
      }
    }

    return null;
  }
}

/// Top-level function for use in compute. See [DictionaryFormat] for details.
Future<void> prepareDirectoryYomichanFormat(
    PrepareDirectoryParams params) async {
  /// Extraction is synchronous, so it runs in its own isolate to keep the UI
  /// responsive. Only sendable values are captured by the closure.
  final File file = params.file;
  final Directory resourceDirectory = params.resourceDirectory;
  final SendPort sendPort = params.sendPort;

  await Isolate.run(() {
    final ImportProgressReporter progress = ImportProgressReporter(sendPort);
    int n = 0;
    extractZipArchiveSync(file, resourceDirectory, callback: (_, __) {
      n++;
      progress.report(() => t.import_extract_count(n: n));
    });
    progress.report(() => t.import_extract_count(n: n), force: true);
  });
}

/// Top-level function for use in compute. See [DictionaryFormat] for details.
Future<String> prepareNameYomichanFormat(PrepareDirectoryParams params) async {
  /// Get the index, which contains the name of the dictionary contained by
  /// the archive.
  String indexFilePath = path.join(params.resourceDirectory.path, 'index.json');
  File indexFile = File(indexFilePath);
  String indexJson = indexFile.readAsStringSync();
  Map<String, dynamic> index = jsonDecode(indexJson);

  String dictionaryName = (index['title'] as String).trim();
  return dictionaryName;
}

/// Files in the extracted dictionary whose name starts with one of
/// [prefixes].
List<File> _yomichanBankFiles(
  PrepareDictionaryParams params,
  List<String> prefixes,
) {
  return params.resourceDirectory.listSync().whereType<File>().where((file) {
    String filename = path.basename(file.path);
    return prefixes.any((prefix) => filename.startsWith(prefix));
  }).toList();
}

/// Count the items in [files] without decoding them, reporting the running
/// total with [message].
int _countYomichanBankItems({
  required List<File> files,
  required ImportProgressReporter progress,
  required String Function(int count) message,
}) {
  int total = 0;
  for (File file in files) {
    total += countJsonArrayItems(file.readAsBytesSync());
    progress.report(() => message(total));
  }
  progress.report(() => message(total), force: true);

  return total;
}

/// Top-level function for use in compute. See [DictionaryFormat] for details.
void prepareEntriesYomichanFormat({
  required PrepareDictionaryParams params,
  required Isar isar,
}) {
  final ImportProgressReporter progress =
      ImportProgressReporter(params.sendPort);
  final List<File> files =
      _yomichanBankFiles(params, const ['term_bank', 'kanji_bank']);

  final int total = _countYomichanBankItems(
    files: files,
    progress: progress,
    message: (count) => t.import_found_entry(count: count),
  );

  final DictionaryTagCache tagCache = DictionaryTagCache(
    isar: isar,
    dictionaryId: params.dictionary.id,
  );

  int n = 0;

  for (File file in files) {
    String filename = path.basename(file.path);
    bool isKanjiBank = filename.startsWith('kanji_bank');
    List<dynamic> items = jsonDecode(file.readAsStringSync());

    for (int start = 0;
        start < items.length;
        start += dictionaryImportBatchSize) {
      final List<dynamic> batch = items.sublist(
        start,
        min(start + dictionaryImportBatchSize, items.length),
      );

      final DictionaryHeadingBatch headings = DictionaryHeadingBatch(isar);
      final List<DictionaryEntry> entries = [];

      if (isKanjiBank) {
        for (List<dynamic> item in batch) {
          final DictionaryEntry? entry = _prepareYomichanKanjiEntry(
            item: item,
            params: params,
            headings: headings,
            tagCache: tagCache,
          );
          if (entry != null) {
            entries.add(entry);
          }
        }
      } else {
        headings.prefetch(batch.cast<List<dynamic>>().map(
              (item) => DictionaryHeading.hash(
                term: item[0] as String,
                reading: item[1] as String,
              ),
            ));

        for (List<dynamic> item in batch) {
          entries.add(_prepareYomichanTermEntry(
            item: item,
            params: params,
            headings: headings,
            tagCache: tagCache,
          ));
        }
      }

      /// Headings must be stored before the entries that link to them.
      headings.flush();
      isar.dictionaryEntrys.putAllSync(entries);

      n += batch.length;
      progress.report(() => t.import_write_entry(count: n, total: total));
    }
  }

  progress.report(
    () => t.import_write_entry(count: n, total: total),
    force: true,
  );
}

/// Build the entry for one row of a Yomichan term bank, linking it to its
/// heading and tags. The entry is not written.
DictionaryEntry _prepareYomichanTermEntry({
  required List<dynamic> item,
  required PrepareDictionaryParams params,
  required DictionaryHeadingBatch headings,
  required DictionaryTagCache tagCache,
}) {
  final String term = item[0];
  final String reading = item[1];
  final String? spaceSeparatedDefinitionTags = item[2];
  // final String ruleIdentifier = item[3];
  final num rawPopularity = item[4];
  final List<dynamic> rawDefinitions = item[5];
  // final int sequenceNumber = item[6];
  final String spaceSeparatedTermTags = item[7];

  double popularity = rawPopularity.toDouble();
  List<String> entryTagNames = spaceSeparatedDefinitionTags?.split(' ') ?? [];
  List<String> headingTagNames = spaceSeparatedTermTags.split(' ');
  final List<String> definitions = rawDefinitions
      .map(YomichanFormat.processDefinition)
      .whereType<String>()
      .toList();

  int headingId = DictionaryHeading.hash(term: term, reading: reading);
  DictionaryHeading heading = headings.obtain(
    headingId,
    () => DictionaryHeading(term: term, reading: reading),
  );
  headings.addTags(heading, tagCache.lookup(headingTagNames));

  final entry = DictionaryEntry(
    definitions: definitions,
    popularity: popularity,
    entryTagNames: entryTagNames,
    headingTagNames: headingTagNames,
  );

  entry.tags.addAll(tagCache.lookup(entryTagNames));
  entry.heading.value = heading;
  entry.dictionary.value = params.dictionary;

  return entry;
}

/// Build the entry for one row of a Yomichan kanji bank, linking it to its
/// heading and tags. Returns null if the row has no content. The entry is not
/// written.
DictionaryEntry? _prepareYomichanKanjiEntry({
  required List<dynamic> item,
  required PrepareDictionaryParams params,
  required DictionaryHeadingBatch headings,
  required DictionaryTagCache tagCache,
}) {
  String term = item[0] as String;
  List<String> onyomis = (item[1] as String).split(' ');
  List<String> kunyomis = (item[2] as String).split(' ');
  List<String> headingTagNames = (item[3] as String).split(' ');
  List<String> meanings = List<String>.from(item[4]);

  StringBuffer buffer = StringBuffer();
  if (onyomis.join().trim().isNotEmpty) {
    buffer.write('音読み\n');
    for (String onyomi in onyomis) {
      buffer.write('  • $onyomi\n');
    }
    buffer.write('\n');
  }
  if (kunyomis.join().trim().isNotEmpty) {
    buffer.write('訓読み\n');
    for (String kun in kunyomis) {
      buffer.write('  • $kun\n');
    }
    buffer.write('\n');
  }
  if (meanings.isNotEmpty) {
    buffer.write('意味\n');
    for (String meaning in meanings) {
      buffer.write('  • $meaning\n');
    }
    buffer.write('\n');
  }

  String definition = buffer.toString().trim();
  if (definition.isEmpty) {
    return null;
  }

  int headingId = DictionaryHeading.hash(term: term, reading: '');
  DictionaryHeading heading = headings.obtain(
    headingId,
    () => DictionaryHeading(term: term),
  );
  headings.addTags(heading, tagCache.lookup(headingTagNames));

  final entry = DictionaryEntry(
    definitions: [definition],
    popularity: 0,
    headingTagNames: headingTagNames,
  );

  entry.heading.value = heading;
  entry.dictionary.value = params.dictionary;

  return entry;
}

/// Top-level function for use in compute. See [DictionaryFormat] for details.
Future<void> prepareTagsYomichanFormat({
  required PrepareDictionaryParams params,
  required Isar isar,
}) async {
  final ImportProgressReporter progress =
      ImportProgressReporter(params.sendPort);
  final List<File> files = _yomichanBankFiles(params, const ['tag_bank']);

  final int total = _countYomichanBankItems(
    files: files,
    progress: progress,
    message: (count) => t.import_found_tag(count: count),
  );

  int n = 0;

  for (File file in files) {
    List<dynamic> items = jsonDecode(file.readAsStringSync());

    final List<DictionaryTag> tags = [];
    for (List<dynamic> item in items) {
      String name = item[0] as String;
      String category = item[1] as String;
      int sortingOrder = item[2] as int;
      String notes = item[3] as String;
      double popularity = (item[4] as num).toDouble();

      tags.add(DictionaryTag(
        dictionaryId: params.dictionary.id,
        name: name,
        category: category,
        sortingOrder: sortingOrder,
        notes: notes,
        popularity: popularity,
      ));
    }

    isar.dictionaryTags.putAllSync(tags);

    n += tags.length;
    progress.report(() => t.import_write_tag(count: n, total: total));
  }

  progress.report(
    () => t.import_write_tag(count: n, total: total),
    force: true,
  );
}

/// Top-level function for use in compute. See [DictionaryFormat] for details.
Future<void> preparePitchesYomichanFormat({
  required PrepareDictionaryParams params,
  required Isar isar,
}) async {
  final ImportProgressReporter progress =
      ImportProgressReporter(params.sendPort);
  final List<File> files = _yomichanBankFiles(params, const ['term_meta_bank']);

  final int total = _countYomichanBankItems(
    files: files,
    progress: progress,
    message: (count) => t.import_found_pitch(count: count),
  );

  int n = 0;

  for (File file in files) {
    List<dynamic> items = jsonDecode(file.readAsStringSync());

    for (int start = 0;
        start < items.length;
        start += dictionaryImportBatchSize) {
      final List<dynamic> batch = items.sublist(
        start,
        min(start + dictionaryImportBatchSize, items.length),
      );

      final DictionaryHeadingBatch headings = DictionaryHeadingBatch(isar);
      final List<DictionaryPitch> pitches = [];

      for (List<dynamic> item in batch) {
        String term = item[0] as String;
        String type = item[1] as String;

        if (type != 'pitch') {
          continue;
        }

        Map<String, dynamic> data = Map<String, dynamic>.from(item[2]);
        String reading = data['reading'] ?? '';
        int headingId = DictionaryHeading.hash(term: term, reading: reading);
        DictionaryHeading heading = headings.obtain(
          headingId,
          () => DictionaryHeading(term: term),
        );

        List<Map<String, dynamic>> distinctPitchJsons =
            List<Map<String, dynamic>>.from(data['pitches']);
        for (Map<String, dynamic> distinctPitch in distinctPitchJsons) {
          int downstep = distinctPitch['position'];
          DictionaryPitch pitch = DictionaryPitch(downstep: downstep);

          pitch.dictionary.value = params.dictionary;
          pitch.heading.value = heading;
          pitches.add(pitch);
        }
      }

      /// Headings must be stored before the pitches that link to them.
      headings.flush();
      isar.dictionaryPitchs.putAllSync(pitches);

      n += batch.length;
      progress.report(() => t.import_write_pitch(count: n, total: total));
    }
  }

  progress.report(
    () => t.import_write_pitch(count: n, total: total),
    force: true,
  );
}

/// Top-level function for use in compute. See [DictionaryFormat] for details.
Future<void> prepareFrequenciesYomichanFormat({
  required PrepareDictionaryParams params,
  required Isar isar,
}) async {
  final ImportProgressReporter progress =
      ImportProgressReporter(params.sendPort);
  final List<File> files = _yomichanBankFiles(params, const ['term_meta_bank']);

  final int total = _countYomichanBankItems(
    files: files,
    progress: progress,
    message: (count) => t.import_found_frequency(count: count),
  );

  int n = 0;

  for (File file in files) {
    List<dynamic> items = jsonDecode(file.readAsStringSync());

    for (int start = 0;
        start < items.length;
        start += dictionaryImportBatchSize) {
      final List<dynamic> batch = items.sublist(
        start,
        min(start + dictionaryImportBatchSize, items.length),
      );

      final DictionaryHeadingBatch headings = DictionaryHeadingBatch(isar);
      final List<DictionaryFrequency> frequencies = [];

      for (List<dynamic> item in batch) {
        final DictionaryFrequency? frequency = _prepareYomichanFrequency(
          item: item,
          params: params,
          headings: headings,
        );
        if (frequency != null) {
          frequencies.add(frequency);
        }
      }

      /// Headings must be stored before the frequencies that link to them.
      headings.flush();
      isar.dictionaryFrequencys.putAllSync(frequencies);

      n += batch.length;
      progress.report(() => t.import_write_frequency(count: n, total: total));
    }
  }

  progress.report(
    () => t.import_write_frequency(count: n, total: total),
    force: true,
  );
}

/// Build the frequency for one row of a Yomichan term meta bank, linking it to
/// its heading. Returns null if the row is not frequency data. The frequency
/// is not written.
DictionaryFrequency? _prepareYomichanFrequency({
  required List<dynamic> item,
  required PrepareDictionaryParams params,
  required DictionaryHeadingBatch headings,
}) {
  String term = item[0] as String;
  String type = item[1] as String;

  if (type != 'freq') {
    return null;
  }

  int? headingId;
  late double value;
  late String? displayValue;

  if (item[2] is double) {
    double number = item[2] as double;

    headingId = DictionaryHeading.hash(term: term, reading: '');
    value = number;
    displayValue =
        (number % 1 == 0) ? number.toInt().toString() : number.toString();
  } else if (item[2] is int) {
    int number = item[2] as int;
    headingId = DictionaryHeading.hash(term: term, reading: '');
    value = number.toDouble();
    displayValue = number.toString();
  } else if (item[2] is Map) {
    Map<String, dynamic> data = Map<String, dynamic>.from(item[2]);

    if (data['reading'] != null && data['frequency'] is Map) {
      Map<String, dynamic> frequencyData =
          Map<String, dynamic>.from(data['frequency']);

      String reading = data['reading'] ?? '';
      headingId = DictionaryHeading.hash(term: term, reading: reading);

      num number = frequencyData['value'] ?? 0;

      value = number.toDouble();
      displayValue = frequencyData['displayValue'];
    } else if (data['displayValue'] != null) {
      String reading = data['reading'] ?? '';
      headingId = DictionaryHeading.hash(term: term, reading: reading);

      num number = data['value'] ?? 0;

      value = number.toDouble();
      displayValue = data['displayValue'];
    } else if (data['value'] != null) {
      String reading = data['reading'] ?? '';
      headingId = DictionaryHeading.hash(term: term, reading: reading);

      num number = data['value'] ?? 0;

      value = number.toDouble();
      displayValue = number.toInt().toString();
    } else if (data['frequency'] is num) {
      num frequencyValue = data['frequency'];
      String reading = data['reading'] ?? '';
      headingId = DictionaryHeading.hash(term: term, reading: reading);

      value = frequencyValue.toDouble();
      displayValue = (frequencyValue % 1 == 0)
          ? frequencyValue.toInt().toString()
          : frequencyValue.toDouble().toString();
    }
  } else {
    headingId = DictionaryHeading.hash(term: term, reading: '');

    value = 0;
    displayValue = item[2].toString();
  }

  if (headingId == null) {
    return null;
  }

  /// Frequencies never create headings. Without a heading for the reading,
  /// the term-only heading is used. Without either, the frequency could not
  /// be linked to anything and would never be shown, so it is skipped.
  DictionaryHeading? heading = headings.find(headingId) ??
      headings.find(DictionaryHeading.hash(term: term, reading: ''));
  if (heading == null) {
    return null;
  }

  final frequency = DictionaryFrequency(
    displayValue: displayValue ?? '',
    value: value,
  );

  frequency.dictionary.value = params.dictionary;
  frequency.heading.value = heading;

  return frequency;
}
