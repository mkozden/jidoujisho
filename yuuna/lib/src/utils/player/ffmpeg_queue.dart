/// Runs FFmpeg work one task at a time.
///
/// flutter_ffmpeg reports results such as the last command output globally,
/// and its media information call does not support running alongside other
/// executions. Running several commands at once over the same large video
/// also makes each of them, and the player reading that file, slower.
class FfmpegQueue {
  static Future<void> _tail = Future<void>.value();

  /// Runs [task] once every task queued before it has finished.
  static Future<T> run<T>(Future<T> Function() task) {
    Future<T> result = _tail.then((_) => task());
    _tail = result.then<void>((_) {}, onError: (_) {});
    return result;
  }
}
