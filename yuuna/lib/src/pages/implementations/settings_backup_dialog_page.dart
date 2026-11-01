import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:document_file_save_plus/document_file_save_plus.dart';
import 'package:external_path/external_path.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:path/path.dart' as path;
import 'package:restart_app/restart_app.dart';
import 'package:spaces/spaces.dart';
import 'package:yuuna/pages.dart';
import 'package:yuuna/utils.dart';

/// The dialog for backing up the app's settings to a file and restoring
/// them, including from the data of the original app. See [SettingsBackup].
class SettingsBackupDialogPage extends BasePage {
  /// Create an instance of this page.
  const SettingsBackupDialogPage({super.key});

  @override
  BasePageState createState() => _SettingsBackupDialogPageState();
}

class _SettingsBackupDialogPageState
    extends BasePageState<SettingsBackupDialogPage> {
  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(t.backup_title),
      contentPadding: Spacing.of(context).insets.exceptBottom.big,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(t.backup_description),
            const Space.normal(),
            buildOption(
              icon: Icons.save_alt,
              label: t.backup_create,
              onTap: backUp,
            ),
            buildOption(
              icon: Icons.restore,
              label: t.backup_restore_file,
              hint: t.backup_restore_file_hint,
              onTap: restoreFromFile,
            ),
            buildOption(
              icon: Icons.folder_open,
              label: t.backup_restore_folder,
              hint: t.backup_restore_folder_hint,
              onTap: restoreFromFolder,
            ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(t.dialog_close),
          onPressed: () => Navigator.pop(context),
        ),
      ],
    );
  }

  Widget buildOption({
    required IconData icon,
    required String label,
    required VoidCallback onTap,
    String? hint,
  }) {
    return ListTile(
      contentPadding: EdgeInsets.zero,
      leading: Icon(icon),
      title: Text(label),
      subtitle: hint == null ? null : Text(hint),
      onTap: onTap,
    );
  }

  /// Folders shown when picking a backup: the device's storage volumes.
  Future<List<Directory>> get pickerRoots async {
    List<String> paths = await ExternalPath.getExternalStorageDirectories();
    return paths.map(Directory.new).toList();
  }

  /// Working folder for the copies of another install's data files.
  Directory get migrationDirectory =>
      Directory(path.join(appModel.temporaryDirectory.path, 'migration'));

  Future<void> backUp() async {
    _SectionsChoice? choice = await showDialog<_SectionsChoice>(
      context: context,
      builder: (context) => _SectionsDialog(
        title: t.backup_choose_export,
        sections: SettingsBackupSection.values,
        showApiKeyOption: true,
        actionLabel: t.dialog_back_up,
      ),
    );
    if (choice == null || choice.sections.isEmpty || !mounted) {
      return;
    }

    await runWithProgress(() async {
      SettingsBackup backup = await SettingsBackup.collect(
        appModel: appModel,
        ref: ref,
        sections: choice.sections,
        includeSecrets: choice.includeApiKey,
      );

      String fileName = 'jidoujisho-backup-'
          '${DateFormat('yyyy-MM-dd-HHmm').format(backup.createdAt)}.json';
      await DocumentFileSavePlus().saveFile(
        Uint8List.fromList(utf8.encode(backup.encode())),
        fileName,
        'application/json',
      );
      Fluttertoast.showToast(msg: t.backup_saved(name: fileName));
    });
  }

  Future<void> restoreFromFile() async {
    List<Directory> roots = await pickerRoots;
    if (!mounted) {
      return;
    }
    Iterable<String>? paths = await FilesystemPicker.open(
      context: context,
      rootDirectories: roots,
      fsType: FilesystemType.file,
      allowedExtensions: ['.json', '.ab'],
      title: '',
      pickText: t.dialog_select,
      cancelText: t.dialog_cancel,
      themeData: Theme.of(context),
      folderIconColor: Theme.of(context).colorScheme.primary,
    );
    if (paths == null || paths.isEmpty) {
      return;
    }

    File file = File(paths.first);
    SettingsBackup? backup = await runWithProgress(() async {
      if (await AndroidBackupReader.isAndroidBackup(file)) {
        return readAppData(() => AppDataFiles.fromAndroidBackup(
              backup: file,
              directory: migrationDirectory,
            ));
      }
      return SettingsBackup.readFile(file);
    });

    if (backup != null) {
      await confirmRestore(backup);
    }
  }

  Future<void> restoreFromFolder() async {
    List<Directory> roots = await pickerRoots;
    if (!mounted) {
      return;
    }
    Iterable<String>? paths = await FilesystemPicker.open(
      context: context,
      rootDirectories: roots,
      fsType: FilesystemType.folder,
      title: '',
      pickText: t.dialog_select,
      cancelText: t.dialog_cancel,
      themeData: Theme.of(context),
      folderIconColor: Theme.of(context).colorScheme.primary,
    );
    if (paths == null || paths.isEmpty) {
      return;
    }

    Directory source = Directory(paths.first);
    SettingsBackup? backup = await runWithProgress(
      () => readAppData(() => AppDataFiles.fromFolder(
            source: source,
            directory: migrationDirectory,
          )),
    );

    if (backup != null) {
      await confirmRestore(backup);
    }
  }

  /// Make a backup from the data files that [find] copies to the migration
  /// folder, which is deleted afterwards.
  Future<SettingsBackup> readAppData(
      Future<AppDataFiles> Function() find) async {
    Directory directory = migrationDirectory;
    if (directory.existsSync()) {
      await directory.delete(recursive: true);
    }

    try {
      AppDataFiles files = await find();
      if (files.isEmpty) {
        throw SettingsBackupException(t.backup_no_data);
      }

      SettingsBackup backup = await SettingsBackup.fromAppDataFiles(
        knownBoxNames: SettingsBackup.boxNames(appModel),
        files: files,
      );
      if (backup.sections.isEmpty) {
        throw SettingsBackupException(t.backup_no_data);
      }
      return backup;
    } finally {
      if (directory.existsSync()) {
        await directory.delete(recursive: true);
      }
    }
  }

  Future<void> confirmRestore(SettingsBackup backup) async {
    if (!mounted) {
      return;
    }

    String date = DateFormat('yyyy-MM-dd HH:mm').format(backup.createdAt);
    String origin = backup.appVersion.isEmpty
        ? t.backup_from_app_data(package: backup.packageName, date: date)
        : t.backup_made_by(
            app: backup.appName,
            version: backup.appVersion,
            date: date,
          );

    _SectionsChoice? choice = await showDialog<_SectionsChoice>(
      context: context,
      builder: (context) => _SectionsDialog(
        title: t.backup_choose_import,
        description: '$origin\n\n${t.backup_import_warning}',
        sections: SettingsBackupSection.values
            .where((section) => backup.sections.containsKey(section))
            .toList(),
        counts: {
          for (SettingsBackupSection section in backup.sections.keys)
            section: backup.countOf(section),
        },
        showApiKeyOption: false,
        actionLabel: t.dialog_restore,
      ),
    );
    if (choice == null || choice.sections.isEmpty || !mounted) {
      return;
    }

    bool? restored = await runWithProgress(() async {
      await backup.restore(
        appModel: appModel,
        ref: ref,
        sections: choice.sections,
      );
      return true;
    });

    if (restored == true) {
      Restart.restartApp();
    }
  }

  /// Run [task] behind a dialog that cannot be closed, and show a message
  /// if it fails. Returns null if it fails.
  Future<T?> runWithProgress<T>(Future<T> Function() task) async {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => WillPopScope(
        onWillPop: () async => false,
        child: AlertDialog(
          content: Row(
            children: [
              const CircularProgressIndicator(),
              const Space.big(),
              Expanded(child: Text(t.backup_working)),
            ],
          ),
        ),
      ),
    );

    try {
      return await task();
    } on SettingsBackupException catch (e) {
      Fluttertoast.showToast(msg: e.message, toastLength: Toast.LENGTH_LONG);
      return null;
    } catch (e, stack) {
      debugPrint('$e\n$stack');
      Fluttertoast.showToast(
        msg: t.backup_failed(error: '$e'),
        toastLength: Toast.LENGTH_LONG,
      );
      return null;
    } finally {
      if (mounted) {
        Navigator.pop(context);
      }
    }
  }
}

/// The sections chosen in a [_SectionsDialog].
class _SectionsChoice {
  _SectionsChoice({required this.sections, required this.includeApiKey});

  final Set<SettingsBackupSection> sections;

  final bool includeApiKey;
}

/// Lets the user choose which sections to back up or restore.
class _SectionsDialog extends StatefulWidget {
  const _SectionsDialog({
    required this.title,
    required this.sections,
    required this.showApiKeyOption,
    required this.actionLabel,
    this.description,
    this.counts,
  });

  final String title;

  final String? description;

  final List<SettingsBackupSection> sections;

  /// Number of items in each section, if known.
  final Map<SettingsBackupSection, int>? counts;

  final bool showApiKeyOption;

  final String actionLabel;

  @override
  State<_SectionsDialog> createState() => _SectionsDialogState();
}

class _SectionsDialogState extends State<_SectionsDialog> {
  late final Set<SettingsBackupSection> _chosen = widget.sections.toSet();

  bool _includeApiKey = false;

  static String labelOf(SettingsBackupSection section) {
    switch (section) {
      case SettingsBackupSection.preferences:
        return t.backup_section_preferences;
      case SettingsBackupSection.profiles:
        return t.backup_section_profiles;
      case SettingsBackupSection.dictionarySettings:
        return t.backup_section_dictionary_settings;
      case SettingsBackupSection.mediaHistory:
        return t.backup_section_media_history;
      case SettingsBackupSection.searchHistory:
        return t.backup_section_search_history;
      case SettingsBackupSection.catalogs:
        return t.backup_section_catalogs;
      case SettingsBackupSection.ttuSettings:
        return t.backup_section_ttu_settings;
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(widget.title),
      contentPadding: Spacing.of(context).insets.exceptBottom.big,
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (widget.description != null) ...[
              Text(widget.description!),
              const Space.normal(),
            ],
            for (SettingsBackupSection section in widget.sections)
              CheckboxListTile(
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                value: _chosen.contains(section),
                title: Text(widget.counts == null
                    ? labelOf(section)
                    : '${labelOf(section)} (${widget.counts![section] ?? 0})'),
                onChanged: (value) {
                  setState(() {
                    if (value == true) {
                      _chosen.add(section);
                    } else {
                      _chosen.remove(section);
                    }
                  });
                },
              ),
            if (widget.showApiKeyOption &&
                _chosen.contains(SettingsBackupSection.preferences))
              SwitchListTile(
                contentPadding: EdgeInsets.zero,
                value: _includeApiKey,
                title: Text(t.backup_include_api_key),
                onChanged: (value) => setState(() => _includeApiKey = value),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          child: Text(t.dialog_cancel),
          onPressed: () => Navigator.pop(context),
        ),
        TextButton(
          onPressed: _chosen.isEmpty
              ? null
              : () => Navigator.pop(
                    context,
                    _SectionsChoice(
                      sections: _chosen,
                      includeApiKey: _includeApiKey,
                    ),
                  ),
          child: Text(widget.actionLabel),
        ),
      ],
    );
  }
}
