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
    FlutterLogs.logError(
      'Diagnostics',
      'WebView',
      'Renderer process gone: didCrash=${detail.didCrash}, '
          'priorityAtExit=${detail.rendererPriorityAtExit}',
    );
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
