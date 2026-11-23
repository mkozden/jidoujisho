import 'dart:io';

import 'package:flutter_ffmpeg/flutter_ffmpeg.dart';
import 'package:flutter_ffmpeg/media_information.dart';
import 'package:flutter_ffmpeg/stream_information.dart';
import 'package:path_provider/path_provider.dart';
import 'package:subtitle/subtitle.dart';
import 'package:path/path.dart' as path;
import 'package:yuuna/language.dart';
import 'package:yuuna/src/utils/player/ffmpeg_queue.dart';

/// Differentiates different types of [SubtitleItem].
enum SubtitleItemType {
  /// Subtitles from a file.
  externalSubtitle,

  /// Subtitle from a video.
  embeddedSubtitle,

  /// Represents an item that contains no subtitles.
  noneSubtitle,

  /// Subtitle from a separate web document.
  webSubtitle,
}

/// Represents subtitles that can be used in the player.
class SubtitleItem {
  /// Initialise an item.
  SubtitleItem({
    required this.controller,
    required this.type,
    this.source,
    this.metadata,
    this.index,
  });

  /// The controller that contains the content of the subtitle.
  SubtitleController controller;

  /// The type of the subtitle, embedded, external, etc.
  SubtitleItemType type;

  /// Used to identify the source of a subtitle. This could be a filename.
  String? source;

  /// Used to possibly identify the content of a subtitle.
  String? metadata;

  /// Used to possibly identify the order of a subtitle.
  int? index;
}

/// A subtitle stream inside a video file.
class EmbeddedSubtitleStream {
  /// Initialise a stream.
  EmbeddedSubtitleStream({
    required this.index,
    required this.codec,
    this.language,
    this.title,
  });

  /// Codecs of subtitles stored as images, which cannot become text.
  static const Set<String> bitmapCodecs = {
    'hdmv_pgs_subtitle',
    'dvd_subtitle',
    'dvb_subtitle',
    'dvb_teletext',
    'xsub',
  };

  /// Position among the subtitle streams of the file, as in `-map 0:s:index`.
  final int index;

  /// FFmpeg codec name, such as `ass` or `subrip`.
  final String codec;

  /// Language tag of the stream, such as `jpn`.
  final String? language;

  /// Title tag of the stream, such as `Signs & Songs`.
  final String? title;

  /// Whether this stream holds text that can be converted to SRT.
  bool get isText => codec.isNotEmpty && !bitmapCodecs.contains(codec);

  /// A readable name for the stream, or null if it has no tags.
  String? get label {
    List<String> parts = [
      if (language != null) language!,
      if (title != null) title!,
    ];
    return parts.isEmpty ? null : parts.join(' - ');
  }
}

/// A class for calling subtitle utility functions.
class SubtitleUtils {
  /// Fetches a subtitle from a subtitle file.
  static Future<SubtitleItem> subtitlesFromFile({
    required File file,
    required SubtitleItemType type,
    String? source,
    String? metadata,
    int? index,
  }) async {
    String fileExtension = path.extension(file.path).toLowerCase();

    if (!file.existsSync()) {
      return SubtitleItem(
        controller: SubtitleController(
          provider: SubtitleProvider.fromFile(
            file,
          ),
        ),
        metadata: metadata,
        source: source,
        type: type,
        index: index,
      );
    }

    switch (fileExtension) {
      case '.srt':
        return SubtitleItem(
          controller: SubtitleController(
            provider: SubtitleProvider.fromString(
              data: file.readAsStringSync(),
              type: SubtitleType.srt,
            ),
          ),
          metadata: metadata,
          type: type,
          index: index,
        );
      case '.ass':
      case '.ssa':
        return SubtitleItem(
          controller: SubtitleController(
            provider: SubtitleProvider.fromString(
              data: await convertAssSubtitles(file.path),
              type: SubtitleType.srt,
            ),
          ),
          metadata: metadata,
          type: type,
          index: index,
        );
    }

    return SubtitleItem(
      controller: SubtitleController(
        provider: SubtitleProvider.fromFile(
          file,
        ),
      ),
      metadata: metadata,
      type: type,
      index: index,
    );
  }

  /// Lists the subtitle streams of a video file.
  static Future<List<EmbeddedSubtitleStream>> probeSubtitleStreams(
      File file) async {
    List<EmbeddedSubtitleStream> streams = [];

    MediaInformation information;
    try {
      information = await FlutterFFprobe().getMediaInformation(file.path);
    } catch (_) {
      return streams;
    }

    int subtitleIndex = 0;
    for (StreamInformation stream in information.getStreams() ?? []) {
      Map<dynamic, dynamic> properties = stream.getAllProperties();
      if (properties['codec_type'] != 'subtitle') {
        continue;
      }

      Map<dynamic, dynamic> tags = properties['tags'] is Map
          ? properties['tags'] as Map<dynamic, dynamic>
          : {};
      String? tag(String key) {
        for (MapEntry<dynamic, dynamic> entry in tags.entries) {
          if (entry.key.toString().toLowerCase() == key) {
            String value = entry.value.toString().trim();
            return value.isEmpty ? null : value;
          }
        }
        return null;
      }

      streams.add(
        EmbeddedSubtitleStream(
          index: subtitleIndex,
          codec: properties['codec_name']?.toString() ?? '',
          language: tag('language'),
          title: tag('title'),
        ),
      );
      subtitleIndex++;
    }

    return streams;
  }

  /// Extracts the text subtitles of a video file. All of them are extracted
  /// in a single FFmpeg run, which reads the file once instead of once per
  /// track. Tracks in [language] are passed to [onItemComplete] first.
  /// [isCancelled] is checked between steps so that a closed player stops
  /// the work early.
  static Future<List<SubtitleItem>> subtitlesFromVideo({
    required File file,
    required Language language,
    required bool Function() isCancelled,
    required Function(SubtitleItem) onItemComplete,
  }) {
    return FfmpegQueue.run(() async {
      List<SubtitleItem> items = [];
      if (isCancelled()) {
        return items;
      }

      List<EmbeddedSubtitleStream> streams = (await probeSubtitleStreams(file))
          .where((stream) => stream.isText)
          .toList();
      if (streams.isEmpty || isCancelled()) {
        return items;
      }

      Directory appDocDir = await getApplicationDocumentsDirectory();
      Directory subsDir = Directory('${appDocDir.path}/subtitles');
      if (!subsDir.existsSync()) {
        subsDir.createSync(recursive: true);
      }

      Map<int, File> outputFiles = {};
      for (EmbeddedSubtitleStream stream in streams) {
        File outputFile = File('${subsDir.path}/extractSrt${stream.index}.srt');
        if (outputFile.existsSync()) {
          outputFile.deleteSync();
        }
        outputFiles[stream.index] = outputFile;
      }

      List<String> mapStream(EmbeddedSubtitleStream stream) => [
            '-map',
            '0:s:${stream.index}',
            '-c:s',
            'srt',
            outputFiles[stream.index]!.path,
          ];

      final FlutterFFmpeg flutterFFmpeg = FlutterFFmpeg();
      int returnCode = await flutterFFmpeg.executeWithArguments([
        '-loglevel',
        'error',
        '-y',
        '-i',
        file.path,
        for (EmbeddedSubtitleStream stream in streams) ...mapStream(stream),
      ]);

      if (returnCode != 0) {
        // A single track that cannot be converted fails the whole run, so
        // fall back to extracting the tracks one at a time.
        for (EmbeddedSubtitleStream stream in streams) {
          if (isCancelled()) {
            return items;
          }
          File outputFile = outputFiles[stream.index]!;
          if (outputFile.existsSync()) {
            outputFile.deleteSync();
          }
          await flutterFFmpeg.executeWithArguments([
            '-loglevel',
            'error',
            '-y',
            '-i',
            file.path,
            ...mapStream(stream),
          ]);
        }
      }

      bool isTargetLanguage(EmbeddedSubtitleStream stream) {
        String? streamLanguage = stream.language?.toLowerCase();
        return streamLanguage != null &&
            (streamLanguage == language.threeLetterCode.toLowerCase() ||
                streamLanguage == language.languageCode.toLowerCase());
      }

      List<EmbeddedSubtitleStream> orderedStreams = [
        ...streams.where(isTargetLanguage),
        ...streams.where((stream) => !isTargetLanguage(stream)),
      ];

      for (EmbeddedSubtitleStream stream in orderedStreams) {
        if (isCancelled()) {
          return items;
        }

        File outputFile = outputFiles[stream.index]!;
        if (!outputFile.existsSync() || outputFile.lengthSync() == 0) {
          continue;
        }

        SubtitleItem item = await subtitlesFromFile(
          file: outputFile,
          type: SubtitleItemType.embeddedSubtitle,
          metadata: stream.label,
          index: stream.index,
        );

        onItemComplete(item);
        items.add(item);
      }

      return items;
    });
  }

  /// Cancels FFmpeg work that is running, such as subtitle extraction for a
  /// player that has been closed.
  static Future<void> cancelExtraction() {
    return FlutterFFmpeg().cancel();
  }

  /// Converts ASS subtitles to SRT and returns the data.
  static Future<String> convertAssSubtitles(String inputPath) async {
    Directory appDocDir = await getApplicationDocumentsDirectory();
    Directory subsDir = Directory('${appDocDir.path}/subtitles');
    if (!subsDir.existsSync()) {
      subsDir.createSync(recursive: true);
    }

    String outputPath = '${subsDir.path}/assSubtitles.srt';
    File targetFile = File(outputPath);

    if (targetFile.existsSync()) {
      targetFile.deleteSync();
    }

    String command = '-i "$inputPath" "$outputPath"';

    final FlutterFFmpeg flutterFFmpeg = FlutterFFmpeg();

    await flutterFFmpeg.execute(command);

    return targetFile.readAsStringSync();
  }
}
