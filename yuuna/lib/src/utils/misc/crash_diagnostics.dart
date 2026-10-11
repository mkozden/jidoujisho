import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_logs/flutter_logs.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:spaces/spaces.dart';
import 'package:yuuna/i18n/strings.g.dart';

/// Helps find out why the app or one of its WebViews stopped unexpectedly.
class CrashDiagnostics {
  CrashDiagnostics._();

  static const MethodChannel _channel =
      MethodChannel('app.arianneorpilla.yuuna/diagnostics');

  /// Logs that a WebView renderer process is gone. With [notify], also tells
  /// the user, as the visible reader is reloaded in response.
  static void onWebViewRendererGone(
    RenderProcessGoneDetail detail, {
    bool notify = true,
  }) {
    String message = 'Renderer process gone: didCrash=${detail.didCrash}, '
        'priorityAtExit=${detail.rendererPriorityAtExit}';
    FlutterLogs.logError('Diagnostics', 'WebView', message);
    LookupLog.add(message);
    if (notify) {
      Fluttertoast.showToast(
        msg: detail.didCrash
            ? t.webview_renderer_crashed
            : t.webview_renderer_killed,
        toastLength: Toast.LENGTH_LONG,
      );
    }
  }

  /// Shows why the app's previous run ended, if Android recorded an
  /// unexpected exit (crash, freeze, low memory...) that was not shown yet.
  static Future<void> showLastExitReportIfAny(BuildContext context) async {
    Map<dynamic, dynamic>? report;
    try {
      report = await _channel
          .invokeMethod<Map<dynamic, dynamic>>('getLastExitReport');
    } catch (e) {
      debugPrint('Could not read the last exit report: $e');
      return;
    }

    if (report == null) {
      return;
    }
    if (!context.mounted) {
      return;
    }

    final String text = _formatReport(report);
    FlutterLogs.logError('Diagnostics', 'LastExit', text);

    await showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(t.last_exit_title),
        content: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(t.last_exit_hint),
              const Space.normal(),
              Flexible(
                child: SingleChildScrollView(
                  child: SelectableText(
                    text,
                    style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
                  ),
                ),
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () async {
              await Clipboard.setData(ClipboardData(text: text));
              Fluttertoast.showToast(msg: t.copied_to_clipboard);
            },
            child: Text(t.copy),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: Text(t.dialog_close),
          ),
        ],
      ),
    );
  }

  static String _formatReport(Map<dynamic, dynamic> report) {
    final StringBuffer buffer = StringBuffer();
    final Object? timestamp = report['timestamp'];
    buffer.writeln('Reason: ${report['reason']}');
    if (timestamp is int) {
      buffer.writeln(
          'Time: ${DateTime.fromMillisecondsSinceEpoch(timestamp).toLocal()}');
    }
    for (final String key in [
      'description',
      'status',
      'importance',
      'pssKb',
      'rssKb',
    ]) {
      if (report[key] != null) {
        buffer.writeln('$key: ${report[key]}');
      }
    }
    if (report['javaTrace'] != null) {
      buffer
        ..writeln()
        ..writeln('Java stack trace:')
        ..writeln(report['javaTrace']);
    }
    if (report['trace'] != null) {
      buffer
        ..writeln()
        ..writeln('Trace:')
        ..writeln(report['trace']);
    }
    return buffer.toString().trim();
  }
}

/// Keeps the recent steps of dictionary lookups in the readers, so a pop-up
/// that closes or never shows can be traced to what closed it.
class LookupLog {
  LookupLog._();

  static const int _maxEntries = 300;
  static final List<String> _entries = [];

  /// Whether anything was recorded since the app started.
  static bool get isEmpty => _entries.isEmpty;

  /// The recorded steps, oldest first.
  static String get text => _entries.join('\n');

  /// Record a step.
  static void add(String event) {
    DateTime now = DateTime.now();
    String time = '${_pad(now.hour)}:${_pad(now.minute)}:${_pad(now.second)}'
        '.${now.millisecond.toString().padLeft(3, '0')}';
    _entries.add('$time $event');
    if (_entries.length > _maxEntries) {
      _entries.removeRange(0, _entries.length - _maxEntries);
    }
  }

  /// Record a step along with the code that led to it, for steps such as
  /// closing the pop-up that many places can trigger.
  static void addWithCaller(String event) {
    List<String> frames = StackTrace.current
        .toString()
        .split('\n')
        .map((frame) => frame.replaceFirst(RegExp(r'^#\d+\s+'), '').trim())
        .where((frame) =>
            frame.isNotEmpty &&
            !frame.startsWith('LookupLog.') &&
            !frame.contains('crash_diagnostics.dart'))
        .take(6)
        .toList();
    add('$event\n    ${frames.join('\n    ')}');
  }

  static String _pad(int value) => value.toString().padLeft(2, '0');
}
