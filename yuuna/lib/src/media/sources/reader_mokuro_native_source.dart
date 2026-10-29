import 'dart:io';

import 'package:collection/collection.dart';
import 'package:filesystem_picker/filesystem_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:intl/intl.dart';
import 'package:material_floating_search_bar/material_floating_search_bar.dart';
import 'package:network_to_file_image/network_to_file_image.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
import 'package:subtitle/subtitle.dart';
import 'package:yuuna/media.dart';
import 'package:yuuna/models.dart';
import 'package:yuuna/pages.dart';
import 'package:yuuna/utils.dart';

/// A media source that reads manga processed by Mokuro from its .mokuro files,
/// showing the pages in a native reader rather than in a web page.
class ReaderMokuroNativeSource extends ReaderMediaSource {
  /// Define this media source.
  ReaderMokuroNativeSource._privateConstructor()
      : super(
          uniqueKey: 'reader_mokuro_native',
          sourceName: 'Mokuro (native)',
          description:
              'Read manga volumes processed by Mokuro, opened from their .mokuro files.',
          icon: Icons.auto_stories_outlined,
          implementsSearch: false,
          implementsHistory: true,
          overridesAutoImage: true,
        );

  /// Get the singleton instance of this media type.
  static ReaderMokuroNativeSource get instance => _instance;

  static final ReaderMokuroNativeSource _instance =
      ReaderMokuroNativeSource._privateConstructor();

  @override
  double get aspectRatio => 257 / 364;

  @override
  Future<void> onSearchBarTap({
    required BuildContext context,
    required WidgetRef ref,
    required AppModel appModel,
  }) async {
    launchFilePicker(context: context, ref: ref, appModel: appModel);
  }

  @override
  BaseSourcePage buildLaunchPage({
    MediaItem? item,
  }) {
    return ReaderMokuroNativePage(item: item);
  }

  @override
  BasePage buildHistoryPage({MediaItem? item}) {
    return const ReaderMokuroNativeHistoryPage();
  }

  @override
  List<Widget> getActions({
    required BuildContext context,
    required WidgetRef ref,
    required AppModel appModel,
  }) {
    return [
      buildPickFileButton(context: context, ref: ref, appModel: appModel),
    ];
  }

  /// Menu bar action.
  Widget buildPickFileButton(
      {required BuildContext context,
      required WidgetRef ref,
      required AppModel appModel}) {
    return FloatingSearchBarAction(
      child: JidoujishoIconButton(
        size: Theme.of(context).textTheme.titleLarge?.fontSize,
        tooltip: t.pick_file,
        icon: Icons.upload_file,
        onTap: () async {
          launchFilePicker(
            context: context,
            ref: ref,
            appModel: appModel,
          );
        },
      ),
    );
  }

  /// Launches a file picker for a .mokuro file and opens its volume.
  void launchFilePicker(
      {required BuildContext context,
      required WidgetRef ref,
      required AppModel appModel}) async {
    List<Directory> rootDirectories =
        await appModel.getFilePickerDirectoriesForMediaType(mediaType);

    List<String> usedFiles = appModel
        .getMediaSourceHistory(mediaSource: this)
        .map((item) => item.mediaIdentifier)
        .toList();

    Iterable<String>? filePaths;
    if (context.mounted) {
      filePaths = await FilesystemPicker.open(
        allowedExtensions: ['.mokuro'],
        context: context,
        rootDirectories: rootDirectories,
        fsType: FilesystemType.file,
        title: '',
        pickText: t.dialog_select,
        cancelText: t.dialog_cancel,
        themeData: Theme.of(context),
        folderIconColor: Theme.of(context).colorScheme.primary,
        usedFiles: usedFiles,
        currentActiveFile: appModel.currentMediaItem?.mediaIdentifier,
      );
    }

    if (filePaths == null || filePaths.isEmpty) {
      return;
    }

    String filePath = filePaths.first;
    appModel.setLastPickedDirectory(
      type: ReaderMediaType.instance,
      directory: Directory(path.dirname(filePath)),
    );

    MediaItem? item;
    try {
      item = await generateMediaItem(appModel: appModel, filePath: filePath);
    } on MokuroVolumeException catch (e) {
      Fluttertoast.showToast(msg: e.message);
      return;
    }

    appModel.openMedia(
      item: item,
      ref: ref,
      mediaSource: this,
    );
  }

  /// The history item for the .mokuro file at [filePath], made from the file
  /// if it has not been opened before.
  ///
  /// Throws a [MokuroVolumeException] if the volume cannot be read.
  Future<MediaItem> generateMediaItem({
    required AppModel appModel,
    required String filePath,
  }) async {
    MediaItem? item = appModel
        .getMediaSourceHistory(mediaSource: this)
        .firstWhereOrNull((item) => item.mediaIdentifier == filePath);
    if (item != null) {
      return item;
    }

    LoadedMokuroVolume loaded = await LoadedMokuroVolume.load(filePath);
    try {
      MokuroVolume volume = loaded.volume;
      String? coverPath = await getCoverPath(loaded);

      return MediaItem(
        mediaIdentifier: filePath,
        title: volume.volume.isNotEmpty
            ? volume.volume
            : path.basenameWithoutExtension(filePath),
        author: volume.title,
        extra: volume.volumeUuid,
        imageUrl: coverPath == null ? null : 'file://$coverPath',
        position: 0,
        duration: volume.pages.length,
        mediaTypeIdentifier: mediaType.uniqueKey,
        mediaSourceIdentifier: uniqueKey,
        canDelete: true,
        canEdit: true,
      );
    } finally {
      await loaded.images.close();
    }
  }

  /// Folder holding the covers of volumes read from archives, whose pages
  /// are not files that history can show.
  Future<Directory> get coversDirectory async {
    Directory appDirDoc = await getApplicationSupportDirectory();
    return Directory(path.join(appDirDoc.path, 'mokuroNativeCovers'));
  }

  /// Path of an image file showing the first page of [loaded], or null if it
  /// cannot be read.
  Future<String?> getCoverPath(LoadedMokuroVolume loaded) async {
    MokuroPage page = loaded.volume.pages.first;
    MokuroPageImages images = loaded.images;

    try {
      if (images is MokuroDirectoryPageImages) {
        File file = images.fileForPage(page);
        return file.existsSync() ? file.path : null;
      }

      Directory directory = await coversDirectory;
      directory.createSync(recursive: true);

      String name = loaded.volume.volumeUuid.isNotEmpty
          ? loaded.volume.volumeUuid
          : DateTime.now().millisecondsSinceEpoch.toString();
      File file = File(
          path.join(directory.path, '$name${path.extension(page.imgPath)}'));
      await file.writeAsBytes(await images.readPage(page));

      return file.path;
    } catch (e) {
      debugPrint('Cannot read the cover of ${loaded.volume.volume}: $e');
      return null;
    }
  }

  @override
  Future<void> onMediaItemClear(MediaItem item) async {
    String? imageUrl = item.imageUrl;
    if (imageUrl == null) {
      return;
    }

    String coverPath = imageUrl.replaceFirst('file://', '');
    Directory directory = await coversDirectory;
    if (path.isWithin(directory.path, coverPath)) {
      File cover = File(coverPath);
      if (cover.existsSync()) {
        cover.deleteSync();
      }
    }
  }

  @override
  String getDisplaySubtitleFromMediaItem(MediaItem item) {
    String? series = item.author;
    if (series != null && series.isNotEmpty) {
      return series;
    }

    return item.mediaIdentifier;
  }

  /// Whether pages are turned from right to left, as in Japanese manga.
  bool get rightToLeft {
    return getPreference<bool>(key: 'right_to_left', defaultValue: true);
  }

  /// Toggles the reading direction.
  void toggleRightToLeft() async {
    await setPreference<bool>(
      key: 'right_to_left',
      value: !rightToLeft,
    );
  }

  /// Whether the reader will highlight words on tap.
  bool get highlightOnTap {
    return getPreference<bool>(key: 'highlight_on_tap', defaultValue: true);
  }

  /// Toggles whether the reader will highlight words on tap.
  void toggleHighlightOnTap() async {
    await setPreference<bool>(
      key: 'highlight_on_tap',
      value: !highlightOnTap,
    );
  }

  /// Uses the page that was last looked up in as the card image. [data] is
  /// that page's image path, as listed in the .mokuro file of [item].
  @override
  Future<List<NetworkToFileImage>> generateImages({
    required AppModel appModel,
    required MediaItem item,
    List<Subtitle>? subtitles,
    SubtitleOptions? options,
    String? data,
  }) async {
    if (data == null) {
      return [];
    }

    Directory appDirDoc = await getApplicationSupportDirectory();
    Directory previewDir =
        Directory(path.join(appDirDoc.path, 'mokuroNativeImagePreview'));
    if (previewDir.existsSync()) {
      previewDir.deleteSync(recursive: true);
    }

    String timestamp = DateFormat('yyyyMMddTkkmmss').format(DateTime.now());
    Directory imageDir = Directory(path.join(previewDir.path, timestamp));
    imageDir.createSync(recursive: true);
    File file = appModel.getPreviewImageFile(imageDir, 0);

    try {
      MokuroPageImages images =
          await MokuroPageImages.find(item.mediaIdentifier);
      try {
        await file.writeAsBytes(await images.readImage(data));
      } finally {
        await images.close();
      }
    } catch (e) {
      debugPrint('Cannot read $data for a card image: $e');
      return [];
    }

    return [NetworkToFileImage(file: file)];
  }
}
