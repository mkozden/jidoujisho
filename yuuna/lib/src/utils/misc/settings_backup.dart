import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:collection/collection.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:hive/hive.dart';
import 'package:isar/isar.dart';
import 'package:path/path.dart' as path;
import 'package:yuuna/creator.dart';
import 'package:yuuna/dictionary.dart';
import 'package:yuuna/language.dart';
import 'package:yuuna/media.dart';
import 'package:yuuna/models.dart';
import 'package:yuuna/utils.dart';

/// The parts of the app's data that a [SettingsBackup] can hold. Each one
/// can be backed up and restored on its own.
enum SettingsBackupSection {
  /// The app's own settings and those of every media source, as kept in
  /// their Hive boxes. This includes the card types checked for duplicates,
  /// the last used deck and profile, the stash, saved tags and the player,
  /// subtitle and reader settings.
  preferences('preferences'),

  /// Card creator profiles: the card type, which field goes where, the order
  /// and visibility of creator fields, the enhancements assigned to each
  /// field, quick actions and tags.
  profiles('profiles'),

  /// The order of dictionaries, and in which languages each one is hidden
  /// or collapsed. Dictionaries themselves are not included.
  dictionarySettings('dictionary_settings'),

  /// History of read and watched media, with the position reached.
  mediaHistory('media_history'),

  /// Search history of the dictionary and of media sources.
  searchHistory('search_history'),

  /// Mokuro catalogs and browser bookmarks.
  catalogs('catalogs'),

  /// The settings of the ッツ Ebook Reader, which it keeps in its own web
  /// storage. Books are not included.
  ttuSettings('ttu_settings');

  const SettingsBackupSection(this.key);

  /// Name of this section in the backup file.
  final String key;
}

/// Thrown when a file cannot be read as a [SettingsBackup].
class SettingsBackupException implements Exception {
  /// Create an exception with a message for the user.
  SettingsBackupException(this.message);

  /// Explains to the user what went wrong.
  final String message;

  @override
  String toString() => message;
}

/// Encodes values stored in Hive boxes as JSON, keeping their exact types.
///
/// Settings are read back with casts such as `as List<String>`, so a list of
/// strings must come back as a `List<String>` and a double as a double, even
/// where plain JSON would lose the difference. The type checks follow the
/// order Hive uses to pick how it stores a value, so that a restored value
/// reads back exactly as the original did.
class HiveValueCodec {
  /// Encode [value] as a JSON-compatible tagged map.
  ///
  /// Throws an [UnsupportedError] for values Hive stores with a custom type
  /// adapter, which the app does not use.
  static Map<String, dynamic> encode(Object? value) {
    if (value == null) {
      return {'t': 'null'};
    } else if (value is int) {
      return {'t': 'int', 'v': value};
    } else if (value is double) {
      return {'t': 'double', 'v': _encodeDouble(value)};
    } else if (value is bool) {
      return {'t': 'bool', 'v': value};
    } else if (value is String) {
      return {'t': 'string', 'v': value};
    } else if (value is Uint8List) {
      return {'t': 'bytes', 'v': base64Encode(value)};
    } else if (value is List<int>) {
      return {'t': 'int_list', 'v': value};
    } else if (value is List<double>) {
      return {'t': 'double_list', 'v': value.map(_encodeDouble).toList()};
    } else if (value is List<bool>) {
      return {'t': 'bool_list', 'v': value};
    } else if (value is List<String>) {
      return {'t': 'string_list', 'v': value};
    } else if (value is List) {
      return {'t': 'list', 'v': value.map(encode).toList()};
    } else if (value is Map) {
      return {
        't': 'map',
        'v': value.entries
            .map((entry) => [encode(entry.key), encode(entry.value)])
            .toList(),
      };
    } else if (value is DateTime) {
      return {
        't': 'datetime',
        'v': value.microsecondsSinceEpoch,
        'utc': value.isUtc,
      };
    }

    throw UnsupportedError('Cannot back up a ${value.runtimeType}');
  }

  /// Decode a value encoded by [encode].
  static Object? decode(Object? json) {
    Map<String, dynamic> map = json as Map<String, dynamic>;
    Object? value = map['v'];

    switch (map['t']) {
      case 'null':
        return null;
      case 'int':
        return (value as num).toInt();
      case 'double':
        return _decodeDouble(value);
      case 'bool':
        return value as bool;
      case 'string':
        return value as String;
      case 'bytes':
        return base64Decode(value as String);
      case 'int_list':
        return (value as List).map((e) => (e as num).toInt()).toList();
      case 'double_list':
        return (value as List).map(_decodeDouble).toList();
      case 'bool_list':
        return List<bool>.from(value as List);
      case 'string_list':
        return List<String>.from(value as List);
      case 'list':
        return (value as List).map(decode).toList();
      case 'map':
        return Map<dynamic, dynamic>.fromEntries(
          (value as List).map((entry) {
            List<dynamic> pair = entry as List<dynamic>;
            return MapEntry(decode(pair[0]), decode(pair[1]));
          }),
        );
      case 'datetime':
        return DateTime.fromMicrosecondsSinceEpoch(
          (value as num).toInt(),
          isUtc: map['utc'] as bool? ?? false,
        );
    }

    throw FormatException('Unknown value type ${map['t']}');
  }

  /// JSON has no NaN or infinity, so those are written as strings, which
  /// [double.parse] reads back.
  static Object _encodeDouble(double value) {
    return value.isFinite ? value : value.toString();
  }

  static double _decodeDouble(Object? value) {
    if (value is num) {
      return value.toDouble();
    }
    return double.parse(value as String);
  }
}

/// Settings and other app data saved to, or read from, a backup file.
///
/// A backup holds only the [SettingsBackupSection]s that were chosen when it
/// was made, as JSON. It is also made from the data files of the original
/// app (see [SettingsBackup.fromAppDataFiles]), so that migrating to this
/// app uses the same restore step.
class SettingsBackup {
  /// Define a backup with its contents.
  SettingsBackup({
    required this.createdAt,
    required this.appName,
    required this.appVersion,
    required this.packageName,
    required this.sections,
  });

  /// Read a backup from the contents of a backup file.
  ///
  /// Throws a [SettingsBackupException] if it is not a backup or was made by
  /// a newer version of the app with a format this version cannot read.
  factory SettingsBackup.fromJson(Map<String, dynamic> json) {
    if (json['format'] != formatName) {
      throw SettingsBackupException(t.backup_not_a_backup);
    }
    int version = (json['format_version'] as num?)?.toInt() ?? 0;
    if (version > formatVersion) {
      throw SettingsBackupException(t.backup_too_new);
    }

    Map<String, dynamic> sectionsJson =
        Map<String, dynamic>.from(json['sections'] as Map? ?? {});
    Map<SettingsBackupSection, dynamic> sections = {};
    for (SettingsBackupSection section in SettingsBackupSection.values) {
      if (sectionsJson[section.key] != null) {
        sections[section] = sectionsJson[section.key];
      }
    }

    return SettingsBackup(
      createdAt: DateTime.tryParse(json['created_at'] as String? ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      appName: json['app_name'] as String? ?? '',
      appVersion: json['app_version'] as String? ?? '',
      packageName: json['package_name'] as String? ?? '',
      sections: sections,
    );
  }

  /// Identifies backup files of this app.
  static const String formatName = 'jidoujisho-settings-backup';

  /// Raised whenever the layout of a section changes in a way older
  /// versions cannot read.
  static const int formatVersion = 1;

  /// When this backup was made.
  final DateTime createdAt;

  /// Name of the app that made this backup.
  final String appName;

  /// Version of the app that made this backup.
  final String appVersion;

  /// Package name of the app that made this backup.
  final String packageName;

  /// The JSON contents of each section in this backup.
  final Map<SettingsBackupSection, dynamic> sections;

  /// Key of the ChatGPT API key in the ChatGPT source's box. It is only
  /// backed up when asked for, as the backup file is not encrypted.
  static const String chatgptApiKey = 'openai_api_key';

  /// Key in the app's box holding dictionary settings from a restored backup
  /// that wait for their dictionaries to be imported. It is internal, so it
  /// is never backed up itself.
  static const String pendingDictionarySettingsKey =
      'pending_dictionary_settings';

  /// Keys in the ttu reader's web storage that are not backed up: the list
  /// of imported fonts, as the fonts themselves are not included.
  static const Set<String> ttuExcludedKeys = {'userfonts'};

  /// How long to wait for the WebView to write web storage to disk.
  /// Chromium commits changes about five seconds after they are made.
  static const Duration ttuStorageCommitDelay = Duration(seconds: 8);

  /// Names of the Hive boxes holding settings: the app's own box and that of
  /// every media source.
  static List<String> boxNames(AppModel appModel) {
    return [
      'appModel',
      for (Map<String, MediaSource> sources in appModel.mediaSources.values)
        for (MediaSource source in sources.values) source.uniqueKey,
    ];
  }

  /// Whether [key] in the box [boxName] should be left out of a backup and
  /// kept as it is when restoring one.
  static bool isExcludedKey({
    required String boxName,
    required dynamic key,
    required bool includeSecrets,
  }) {
    if (boxName == 'appModel' && key == pendingDictionarySettingsKey) {
      return true;
    }
    if (boxName == ReaderChatgptSource.instance.uniqueKey &&
        key == chatgptApiKey) {
      return !includeSecrets;
    }
    return false;
  }

  /// The number of items in [section], shown when choosing what to restore.
  int countOf(SettingsBackupSection section) {
    dynamic data = sections[section];
    if (data == null) {
      return 0;
    }

    switch (section) {
      case SettingsBackupSection.preferences:
        return (data as Map)
            .values
            .fold<int>(0, (count, entries) => count + (entries as List).length);
      case SettingsBackupSection.catalogs:
        Map map = data as Map;
        return ((map['mokuro_catalogs'] as List?)?.length ?? 0) +
            ((map['browser_bookmarks'] as List?)?.length ?? 0);
      case SettingsBackupSection.ttuSettings:
        return (data as Map)
            .values
            .fold<int>(0, (count, entries) => count + (entries as Map).length);
      case SettingsBackupSection.profiles:
      case SettingsBackupSection.dictionarySettings:
      case SettingsBackupSection.mediaHistory:
      case SettingsBackupSection.searchHistory:
        return (data as List).length;
    }
  }

  /// The contents of a backup file.
  Map<String, dynamic> toJson() {
    return {
      'format': formatName,
      'format_version': formatVersion,
      'created_at': createdAt.toIso8601String(),
      'app_name': appName,
      'app_version': appVersion,
      'package_name': packageName,
      'sections': {
        for (MapEntry<SettingsBackupSection, dynamic> entry in sections.entries)
          entry.key.key: entry.value,
      },
    };
  }

  /// Contents of a backup file, indented so that it can be read and edited.
  String encode() => const JsonEncoder.withIndent(' ').convert(toJson());

  /// Read a backup file.
  static Future<SettingsBackup> readFile(File file) async {
    dynamic json;
    try {
      json = jsonDecode(await file.readAsString());
    } on FormatException {
      throw SettingsBackupException(t.backup_not_a_backup);
    }
    if (json is! Map<String, dynamic>) {
      throw SettingsBackupException(t.backup_not_a_backup);
    }
    return SettingsBackup.fromJson(json);
  }

  /// Make a backup of [sections] of the app's current data.
  ///
  /// [includeSecrets] adds the ChatGPT API key to the settings.
  static Future<SettingsBackup> collect({
    required AppModel appModel,
    required WidgetRef ref,
    required Set<SettingsBackupSection> sections,
    required bool includeSecrets,
  }) async {
    Isar database = appModel.database;
    Map<SettingsBackupSection, dynamic> data = {};

    for (SettingsBackupSection section in sections) {
      switch (section) {
        case SettingsBackupSection.preferences:
          data[section] = {
            for (String name in boxNames(appModel))
              if (Hive.isBoxOpen(name))
                name: encodeBox(
                  boxName: name,
                  entries: Hive.box(name).toMap(),
                  includeSecrets: includeSecrets,
                ),
          };
          break;
        case SettingsBackupSection.profiles:
          data[section] = database.ankiMappings
              .where()
              .sortByOrder()
              .findAllSync()
              .map(encodeMapping)
              .toList();
          break;
        case SettingsBackupSection.dictionarySettings:
          data[section] = database.dictionarys
              .where()
              .sortByOrder()
              .findAllSync()
              .map(encodeDictionary)
              .toList();
          break;
        case SettingsBackupSection.mediaHistory:
          data[section] = database.mediaItems
              .where()
              .findAllSync()
              .map((item) => item.toJson()..remove('id'))
              .toList();
          break;
        case SettingsBackupSection.searchHistory:
          data[section] = database.searchHistoryItems
              .where()
              .findAllSync()
              .map(encodeSearchHistoryItem)
              .toList();
          break;
        case SettingsBackupSection.catalogs:
          data[section] = encodeCatalogs(
            catalogs: database.mokuroCatalogs.where().findAllSync(),
            bookmarks: database.browserBookmarks.where().findAllSync(),
          );
          break;
        case SettingsBackupSection.ttuSettings:
          Map<String, Map<String, String>> ttuSettings = {};
          for (Language language in appModel.languages.values) {
            Map<String, String>? storage =
                await readTtuStorage(language: language, ref: ref);
            if (storage != null && storage.isNotEmpty) {
              ttuSettings[language.languageCountryCode] = storage;
            }
          }
          data[section] = ttuSettings;
          break;
      }
    }

    return SettingsBackup(
      createdAt: DateTime.now(),
      appName: appModel.packageInfo.appName,
      appVersion:
          '${appModel.packageInfo.version}+${appModel.packageInfo.buildNumber}',
      packageName: appModel.packageInfo.packageName,
      sections: data,
    );
  }

  /// Make a backup from the data files of an install of the app: the Hive
  /// boxes (`*.hive`) and the database (`*.isar`) in [files], such as those
  /// found in an Android backup of the original app.
  ///
  /// The files are renamed and deleted, so [files] should hold copies. Only
  /// the boxes in [knownBoxNames] (see [boxNames]) are read.
  static Future<SettingsBackup> fromAppDataFiles({
    required List<String> knownBoxNames,
    required AppDataFiles files,
  }) async {
    Map<SettingsBackupSection, dynamic> data = {};

    /// Hive lower cases box names for their file names.
    Map<String, String> boxNamesByFileName = {
      for (String name in knownBoxNames) name.toLowerCase(): name,
    };

    Map<String, dynamic> preferences = {};
    for (File file in files.hiveFiles) {
      String fileName = path.basenameWithoutExtension(file.path).toLowerCase();
      String? boxName = boxNamesByFileName[fileName];
      if (boxName == null) {
        continue;
      }

      /// Open the copy under a name no box of this app uses.
      String tempName = 'migrate_$fileName';
      File tempFile = File(path.join(file.parent.path, '$tempName.hive'));
      await file.rename(tempFile.path);

      try {
        Box box = await Hive.openBox(tempName, path: file.parent.path);
        preferences[boxName] = encodeBox(
          boxName: boxName,
          entries: box.toMap(),
          includeSecrets: true,
        );
        await box.deleteFromDisk();
      } catch (e) {
        debugPrint('Cannot read the settings in ${file.path}: $e');
      }
    }
    if (preferences.isNotEmpty) {
      data[SettingsBackupSection.preferences] = preferences;
    }

    File? isarFile = files.isarFile;
    if (isarFile != null) {
      /// Isar names databases after their file, so open the copy under a
      /// name this app's own database does not use.
      String tempName = 'migrate';
      await isarFile.rename(path.join(isarFile.parent.path, '$tempName.isar'));
      int sizeMiB =
          (await File(path.join(isarFile.parent.path, '$tempName.isar'))
                      .length() /
                  (1024 * 1024))
              .ceil();

      Isar database = await Isar.open(
        globalSchemas,
        directory: isarFile.parent.path,
        name: tempName,
        maxSizeMiB: sizeMiB + 1024,
        inspector: false,
      );

      try {
        data[SettingsBackupSection.profiles] = database.ankiMappings
            .where()
            .sortByOrder()
            .findAllSync()
            .map(encodeMapping)
            .toList();
        data[SettingsBackupSection.dictionarySettings] = database.dictionarys
            .where()
            .sortByOrder()
            .findAllSync()
            .map(encodeDictionary)
            .toList();
        data[SettingsBackupSection.mediaHistory] = database.mediaItems
            .where()
            .findAllSync()
            .map((item) => item.toJson()..remove('id'))
            .toList();
        data[SettingsBackupSection.searchHistory] = database.searchHistoryItems
            .where()
            .findAllSync()
            .map(encodeSearchHistoryItem)
            .toList();
        data[SettingsBackupSection.catalogs] = encodeCatalogs(
          catalogs: database.mokuroCatalogs.where().findAllSync(),
          bookmarks: database.browserBookmarks.where().findAllSync(),
        );
      } finally {
        await database.close(deleteFromDisk: true);
      }
    }

    /// Leave out empty sections, so that they are not offered for restoring.
    data.removeWhere((section, value) =>
        (value is List && value.isEmpty) || (value is Map && value.isEmpty));

    return SettingsBackup(
      createdAt: files.modified ?? DateTime.now(),
      appName: 'jidoujisho',
      appVersion: '',
      packageName: files.packageName ?? '',
      sections: data,
    );
  }

  /// Entries of a Hive box as a list of encoded keys and values. Values that
  /// cannot be encoded are left out.
  static List<Map<String, dynamic>> encodeBox({
    required String boxName,
    required Map<dynamic, dynamic> entries,
    required bool includeSecrets,
  }) {
    List<Map<String, dynamic>> encoded = [];
    for (MapEntry<dynamic, dynamic> entry in entries.entries) {
      if (isExcludedKey(
        boxName: boxName,
        key: entry.key,
        includeSecrets: includeSecrets,
      )) {
        continue;
      }
      try {
        encoded.add({'k': entry.key, 'v': HiveValueCodec.encode(entry.value)});
      } on UnsupportedError catch (e) {
        debugPrint('Skipping $boxName/${entry.key}: $e');
      }
    }
    return encoded;
  }

  /// A profile as JSON. Enhancements and quick actions use the same encoding
  /// as the database.
  static Map<String, dynamic> encodeMapping(AnkiMapping mapping) {
    return {
      'label': mapping.label,
      'model': mapping.model,
      'order': mapping.order,
      'export_field_keys': mapping.exportFieldKeys,
      'creator_field_keys': mapping.creatorFieldKeys,
      'creator_collapsed_field_keys': mapping.creatorCollapsedFieldKeys,
      'tags': mapping.tags,
      'enhancements': mapping.enhancements == null
          ? null
          : jsonDecode(EnhancementsConverter.toIsar(mapping.enhancements!)),
      'actions': mapping.actions == null
          ? null
          : jsonDecode(QuickActionsConverter.toIsar(mapping.actions!)),
      'export_media_tags': mapping.exportMediaTags,
      'use_br_tags': mapping.useBrTags,
      'prepend_dictionary_names': mapping.prependDictionaryNames,
    };
  }

  /// A profile read from [json]. Fields, enhancements and quick actions this
  /// version of the app does not have are left out, so that a profile from a
  /// different version cannot refer to them.
  static AnkiMapping decodeMapping({
    required AppModel appModel,
    required Map<String, dynamic> json,
  }) {
    List<String> knownFieldKeys(dynamic keys) =>
        List<String>.from(keys as List).where(fieldsByKey.containsKey).toList();

    Map<String, Map<int, String>> enhancements = {};
    if (json['enhancements'] != null) {
      Map<String, Map<int, String>> decoded =
          EnhancementsConverter.fromIsar(jsonEncode(json['enhancements']));
      for (MapEntry<String, Map<int, String>> entry in decoded.entries) {
        Field? field = fieldsByKey[entry.key];
        if (field == null) {
          continue;
        }
        Map<String, Enhancement> available = appModel.enhancements[field] ?? {};
        enhancements[entry.key] = Map<int, String>.fromEntries(entry
            .value.entries
            .where((slot) => available.containsKey(slot.value)));
      }
    }

    Map<int, String> actions = {};
    if (json['actions'] != null) {
      actions = Map<int, String>.fromEntries(
        QuickActionsConverter.fromIsar(jsonEncode(json['actions']))
            .entries
            .where((slot) => appModel.quickActions.containsKey(slot.value)),
      );
    }

    return AnkiMapping(
      label: json['label'] as String,
      model: json['model'] as String,
      order: (json['order'] as num).toInt(),
      exportFieldKeys: (json['export_field_keys'] as List)
          .map((key) => fieldsByKey.containsKey(key) ? key as String : null)
          .toList(),
      creatorFieldKeys: knownFieldKeys(json['creator_field_keys']),
      creatorCollapsedFieldKeys:
          knownFieldKeys(json['creator_collapsed_field_keys']),
      tags: List<String>.from(json['tags'] as List? ?? []),
      enhancements: enhancements,
      actions: actions,
      exportMediaTags: json['export_media_tags'] as bool?,
      useBrTags: json['use_br_tags'] as bool?,
      prependDictionaryNames: json['prepend_dictionary_names'] as bool?,
    );
  }

  /// The settings of a dictionary as JSON, without its contents.
  static Map<String, dynamic> encodeDictionary(Dictionary dictionary) {
    return {
      'name': dictionary.name,
      'format_key': dictionary.formatKey,
      'order': dictionary.order,
      'hidden_languages': dictionary.hiddenLanguages,
      'collapsed_languages': dictionary.collapsedLanguages,
    };
  }

  /// A search history item as JSON.
  static Map<String, dynamic> encodeSearchHistoryItem(SearchHistoryItem item) {
    return {
      'history_key': item.historyKey,
      'search_term': item.searchTerm,
    };
  }

  /// Mokuro catalogs and browser bookmarks as JSON.
  static Map<String, dynamic> encodeCatalogs({
    required List<MokuroCatalog> catalogs,
    required List<BrowserBookmark> bookmarks,
  }) {
    return {
      'mokuro_catalogs': (catalogs..sort((a, b) => a.order.compareTo(b.order)))
          .map((catalog) => {'name': catalog.name, 'url': catalog.url})
          .toList(),
      'browser_bookmarks': bookmarks
          .map((bookmark) => {'name': bookmark.name, 'url': bookmark.url})
          .toList(),
    };
  }

  /// Replace the app's data with [sections] of this backup. The app should
  /// be restarted afterwards, as much of it is only read at startup.
  Future<void> restore({
    required AppModel appModel,
    required WidgetRef ref,
    required Set<SettingsBackupSection> sections,
  }) async {
    Isar database = appModel.database;

    for (SettingsBackupSection section in sections) {
      dynamic data = this.sections[section];
      if (data == null) {
        continue;
      }

      switch (section) {
        case SettingsBackupSection.preferences:
          await restorePreferences(
            knownBoxNames: boxNames(appModel),
            boxes: Map<String, dynamic>.from(data as Map),
          );
          break;
        case SettingsBackupSection.profiles:
          List<AnkiMapping> mappings = (data as List)
              .map((json) => decodeMapping(
                    appModel: appModel,
                    json: Map<String, dynamic>.from(json as Map),
                  ))
              .toList();
          database.writeTxnSync(() {
            database.ankiMappings.clearSync();
            database.ankiMappings.putAllSync(mappings);

            /// The standard profile can never be deleted, and the app falls
            /// back to it.
            if (!mappings.any((mapping) =>
                mapping.label == AnkiMapping.standardProfileName)) {
              int order = mappings.fold<int>(
                      -1,
                      (max, mapping) =>
                          mapping.order > max ? mapping.order : max) +
                  1;
              database.ankiMappings.putSync(AnkiMapping.defaultMapping(
                language: appModel.targetLanguage,
                order: order,
              ));
            }
          });
          break;
        case SettingsBackupSection.dictionarySettings:
          await appModel.setPendingDictionarySettings(
              List<Map<String, dynamic>>.from(
                  List<Map>.from(data as List).map(Map<String, dynamic>.from)));
          applyPendingDictionarySettings(appModel);
          break;
        case SettingsBackupSection.mediaHistory:
          List<MediaItem> items = (data as List).map((json) {
            MediaItem item =
                MediaItem.fromJson(Map<String, dynamic>.from(json as Map));
            item.id = null;
            item.imageUrl = existingImageUrl(item.imageUrl);
            return item;
          }).toList();
          database.writeTxnSync(() {
            database.mediaItems.putAllSync(items);
          });
          break;
        case SettingsBackupSection.searchHistory:
          List<SearchHistoryItem> items = (data as List).map((json) {
            Map map = json as Map;
            return SearchHistoryItem(
              historyKey: map['history_key'] as String,
              searchTerm: map['search_term'] as String,
            );
          }).toList();
          database.writeTxnSync(() {
            database.searchHistoryItems.putAllSync(items);
          });
          break;
        case SettingsBackupSection.catalogs:
          Map map = data as Map;
          List<Map> catalogs =
              List<Map>.from(map['mokuro_catalogs'] as List? ?? []);
          List<Map> bookmarks =
              List<Map>.from(map['browser_bookmarks'] as List? ?? []);
          database.writeTxnSync(() {
            database.mokuroCatalogs.clearSync();
            for (int i = 0; i < catalogs.length; i++) {
              database.mokuroCatalogs.putSync(MokuroCatalog(
                name: catalogs[i]['name'] as String,
                url: catalogs[i]['url'] as String,
                order: i,
              ));
            }
            database.browserBookmarks.putAllSync(bookmarks
                .map((json) => BrowserBookmark(
                      name: json['name'] as String,
                      url: json['url'] as String,
                    ))
                .toList());
          });
          break;
        case SettingsBackupSection.ttuSettings:
          for (MapEntry entry in (data as Map).entries) {
            Language? language = appModel.languages.values.firstWhereOrNull(
                (language) => language.languageCountryCode == entry.key);
            if (language == null) {
              continue;
            }
            await writeTtuStorage(
              language: language,
              ref: ref,
              storage: Map<String, String>.from(entry.value as Map),
            );
          }

          /// The WebView writes web storage to disk a few seconds after it
          /// changes, and the app is restarted after restoring, which would
          /// lose the changes.
          await Future.delayed(ttuStorageCommitDelay);
          break;
      }
    }
  }

  /// Replace the contents of each settings box with the entries in [boxes].
  /// Keys left out of backups, such as the ChatGPT API key, keep their
  /// current value unless the backup has one.
  static Future<void> restorePreferences({
    required List<String> knownBoxNames,
    required Map<String, dynamic> boxes,
  }) async {
    Set<String> known = knownBoxNames.toSet();

    for (MapEntry<String, dynamic> entry in boxes.entries) {
      if (!known.contains(entry.key) || !Hive.isBoxOpen(entry.key)) {
        continue;
      }

      Box box = Hive.box(entry.key);
      Map<dynamic, dynamic> values = {};
      for (Map encoded in List<Map>.from(entry.value as List)) {
        try {
          values[encoded['k']] = HiveValueCodec.decode(encoded['v']);
        } catch (e) {
          debugPrint('Skipping ${entry.key}/${encoded['k']}: $e');
        }
      }

      List<dynamic> stale = box.keys
          .where((key) =>
              !values.containsKey(key) &&
              !isExcludedKey(
                boxName: entry.key,
                key: key,
                includeSecrets: false,
              ))
          .toList();
      await box.deleteAll(stale);
      await box.putAll(values);
      await box.flush();
    }
  }

  /// Apply the dictionary settings from a restored backup to the
  /// dictionaries that are imported, and keep those of the others for when
  /// they are imported. Run after restoring and after every import.
  ///
  /// Dictionaries named in the backup come first, in its order, followed by
  /// the others in their current order. Whether a dictionary is hidden or
  /// collapsed is set once, when it is first found, so that later changes
  /// made by the user are kept. The order is applied until every dictionary
  /// in the backup has been imported, after which the settings are deleted.
  static void applyPendingDictionarySettings(AppModel appModel) {
    List<Map<String, dynamic>> pending = appModel.pendingDictionarySettings;
    if (pending.isEmpty) {
      return;
    }

    Isar database = appModel.database;
    List<Dictionary> dictionaries =
        database.dictionarys.where().sortByOrder().findAllSync();
    Map<String, int> savedIndex = {
      for (int i = 0; i < pending.length; i++) pending[i]['name'] as String: i,
    };

    List<Dictionary> saved = dictionaries
        .where((dictionary) => savedIndex.containsKey(dictionary.name))
        .toList()
      ..sort((a, b) => savedIndex[a.name]!.compareTo(savedIndex[b.name]!));
    List<Dictionary> others = dictionaries
        .where((dictionary) => !savedIndex.containsKey(dictionary.name))
        .toList();
    List<Dictionary> ordered = [...saved, ...others];

    for (int i = 0; i < ordered.length; i++) {
      ordered[i].order = i;
    }
    for (Dictionary dictionary in saved) {
      Map<String, dynamic> settings = pending[savedIndex[dictionary.name]!];
      if (settings['applied'] == true) {
        continue;
      }
      dictionary.hiddenLanguages =
          List<String>.from(settings['hidden_languages'] as List? ?? []);
      dictionary.collapsedLanguages =
          List<String>.from(settings['collapsed_languages'] as List? ?? []);
      settings['applied'] = true;
    }

    database.writeTxnSync(() {
      database.dictionarys.putAllSync(ordered);
    });

    bool allImported = pending.every((settings) => settings['applied'] == true);
    appModel.setPendingDictionarySettings(allImported ? [] : pending);
  }

  /// [imageUrl] if it is not a file that is missing on this device, such as a
  /// thumbnail kept in the data folder of the app the backup came from.
  static String? existingImageUrl(String? imageUrl) {
    if (imageUrl == null) {
      return null;
    }
    String? filePath;
    if (imageUrl.startsWith('file://')) {
      filePath = imageUrl.replaceFirst('file://', '');
    } else if (imageUrl.startsWith('/')) {
      filePath = imageUrl;
    }
    if (filePath != null && !File(filePath).existsSync()) {
      return null;
    }
    return imageUrl;
  }

  /// The contents of the ッツ Ebook Reader's web storage for [language], or
  /// null if it could not be read.
  static Future<Map<String, String>?> readTtuStorage({
    required Language language,
    required WidgetRef ref,
  }) async {
    String? json = await _runInTtuOrigin(
      language: language,
      ref: ref,
      source: '''
(function() {
  var data = {};
  for (var i = 0; i < localStorage.length; i++) {
    var key = localStorage.key(i);
    data[key] = localStorage.getItem(key);
  }
  return JSON.stringify(data);
})();
''',
    );
    if (json == null) {
      return null;
    }

    Map<String, String> storage =
        Map<String, String>.from(jsonDecode(json) as Map);
    storage.removeWhere((key, value) => ttuExcludedKeys.contains(key));
    return storage;
  }

  /// Write [storage] into the ッツ Ebook Reader's web storage for
  /// [language]. Keys not in [storage] are kept.
  static Future<void> writeTtuStorage({
    required Language language,
    required WidgetRef ref,
    required Map<String, String> storage,
  }) async {
    Map<String, String> values = Map<String, String>.from(storage)
      ..removeWhere((key, value) => ttuExcludedKeys.contains(key));

    await _runInTtuOrigin(
      language: language,
      ref: ref,
      source: '''
(function() {
  var data = ${jsonEncode(values)};
  for (var key in data) {
    localStorage.setItem(key, data[key]);
  }
  return String(Object.keys(data).length);
})();
''',
    );
  }

  /// Run [source] in a page of the ッツ Ebook Reader's origin for
  /// [language], whose web storage it can then use, and return its result.
  ///
  /// The page is a plain file served with the reader rather than the reader
  /// itself, so that the reader cannot write its own settings back while
  /// they are being replaced. Returns null if the reader is not available
  /// for [language] or the page did not load in time.
  static Future<String?> _runInTtuOrigin({
    required Language language,
    required WidgetRef ref,
    required String source,
  }) async {
    int port;
    try {
      port = ReaderTtuSource.instance.getPortForLanguage(language);
      await ref.read(ttuServerProvider(language).future);
    } catch (e) {
      debugPrint('The ebook reader is not available for $language: $e');
      return null;
    }

    Completer<String?> completer = Completer<String?>();
    HeadlessInAppWebView webView = HeadlessInAppWebView(
      initialUrlRequest: URLRequest(
        url: WebUri('http://localhost:$port/jidoujisho-ttu-version.json'),
      ),
      initialSettings: InAppWebViewSettings(useOnRenderProcessGone: true),
      onRenderProcessGone: (controller, detail) {
        CrashDiagnostics.onWebViewRendererGone(detail, notify: false);
        if (!completer.isCompleted) {
          completer.complete(null);
        }
      },
      onReceivedError: (controller, request, error) {
        if (request.isForMainFrame ?? true) {
          if (!completer.isCompleted) {
            completer.complete(null);
          }
        }
      },
      onLoadStop: (controller, url) async {
        if (completer.isCompleted) {
          return;
        }
        try {
          dynamic result = await controller.evaluateJavascript(source: source);
          completer.complete(result?.toString());
        } catch (e) {
          debugPrint('Cannot use the ebook reader storage: $e');
          completer.complete(null);
        }
      },
    );

    try {
      await webView.run();
      return await completer.future.timeout(
        const Duration(seconds: 15),
        onTimeout: () => null,
      );
    } finally {
      await webView.dispose();
    }
  }
}

/// The data files of an install of the app found in an Android backup or in
/// a copy of its data folder, copied to a working directory.
class AppDataFiles {
  /// Define the files found.
  AppDataFiles({
    required this.directory,
    required this.hiveFiles,
    required this.isarFile,
    this.packageName,
    this.modified,
  });

  /// The working directory holding the copies, which is deleted by
  /// [dispose].
  final Directory directory;

  /// Copies of the settings boxes.
  final List<File> hiveFiles;

  /// Copy of the database, if found.
  final File? isarFile;

  /// Package name of the app the files belong to, if known.
  final String? packageName;

  /// When the newest of the files was last changed, if known.
  final DateTime? modified;

  /// Whether any data was found.
  bool get isEmpty => hiveFiles.isEmpty && isarFile == null;

  /// Delete the copies.
  Future<void> dispose() async {
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }
  }

  /// Whether a file named [name] is one of the app's data files: a settings
  /// box, or the main database (the dictionaries' databases opened while
  /// importing use other names).
  static bool isDataFile(String name) {
    return name.endsWith('.hive') || name == 'default.isar';
  }

  /// Package name of the original app, which is migrated from.
  static const String originalPackageName = 'app.arianneorpilla.yuuna';

  /// Copy the data files in [backup], an Android backup made with
  /// `adb backup`, to [directory]. If the backup holds several installs of
  /// the app, those of the original app are used.
  static Future<AppDataFiles> fromAndroidBackup({
    required File backup,
    required Directory directory,
  }) async {
    Map<String, File> written = await AndroidBackupReader.extract(
      backup: backup,
      directory: directory,
      target: (archivePath) {
        List<String> parts = archivePath.split('/');
        if (parts.length < 3 ||
            parts[0] != 'apps' ||
            !parts[1].startsWith(originalPackageName) ||
            !isDataFile(parts.last)) {
          return null;
        }
        return path.join(parts[1], parts.last);
      },
    );

    Set<String> packages =
        written.keys.map((archivePath) => archivePath.split('/')[1]).toSet();
    if (packages.isEmpty) {
      return AppDataFiles(directory: directory, hiveFiles: [], isarFile: null);
    }
    String packageName = packages.contains(originalPackageName)
        ? originalPackageName
        : (packages.toList()..sort()).first;

    List<File> files = written.entries
        .where((entry) => entry.key.split('/')[1] == packageName)
        .map((entry) => entry.value)
        .toList();

    return AppDataFiles(
      directory: Directory(path.join(directory.path, packageName)),
      hiveFiles: files
          .where((file) => path.basename(file.path).endsWith('.hive'))
          .toList(),
      isarFile: files.firstWhereOrNull(
          (file) => path.basename(file.path) == 'default.isar'),
      packageName: packageName,
      modified: backup.lastModifiedSync(),
    );
  }

  /// Copy the data files in [source], a copy of the data folder of an
  /// install such as `/data/data/app.arianneorpilla.yuuna`, to [directory].
  static Future<AppDataFiles> fromFolder({
    required Directory source,
    required Directory directory,
  }) async {
    directory.createSync(recursive: true);
    List<File> hiveFiles = [];
    File? isarFile;
    DateTime? modified;

    await for (FileSystemEntity entity
        in source.list(recursive: true, followLinks: false)) {
      if (entity is! File) {
        continue;
      }
      String name = path.basename(entity.path);
      if (!isDataFile(name)) {
        continue;
      }

      File copy = await entity.copy(path.join(directory.path, name));
      if (name == 'default.isar') {
        isarFile = copy;
      } else {
        hiveFiles.add(copy);
      }

      DateTime changed = entity.lastModifiedSync();
      if (modified == null || changed.isAfter(modified)) {
        modified = changed;
      }
    }

    return AppDataFiles(
      directory: directory,
      hiveFiles: hiveFiles,
      isarFile: isarFile,
      modified: modified,
    );
  }
}
