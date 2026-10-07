import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Serves a static web app bundled in the Flutter assets over HTTP.
///
/// Unlike a plain asset server, extensionless routes (such as `/b?id=1` or
/// `/manage`) fall back to their prerendered `.html` page, which static
/// SvelteKit builds like ッツ Ebook Reader rely on for full page loads,
/// auth popups and their service worker.
class LocalWebAssetsServer {
  /// Create a server for the assets under [assetsBasePath].
  LocalWebAssetsServer({
    required this.address,
    required this.port,
    required this.assetsBasePath,
  });

  /// Address to bind to.
  final InternetAddress address;

  /// Port to bind to. Web storage is scoped to the origin, so this should
  /// remain the same across app versions.
  final int port;

  /// Path of the web app root in the Flutter assets.
  final String assetsBasePath;

  HttpServer? _server;

  /// Actual port the server is listening on.
  int? get boundPort => _server?.port;

  static const Map<String, String> _contentTypes = {
    'html': 'text/html; charset=utf-8',
    'js': 'text/javascript; charset=utf-8',
    'mjs': 'text/javascript; charset=utf-8',
    'css': 'text/css; charset=utf-8',
    'json': 'application/json; charset=utf-8',
    'webmanifest': 'application/manifest+json; charset=utf-8',
    'svg': 'image/svg+xml',
    'png': 'image/png',
    'jpg': 'image/jpeg',
    'jpeg': 'image/jpeg',
    'gif': 'image/gif',
    'webp': 'image/webp',
    'ico': 'image/x-icon',
    'woff': 'font/woff',
    'woff2': 'font/woff2',
    'ttf': 'font/ttf',
    'otf': 'font/otf',
    'wasm': 'application/wasm',
    'txt': 'text/plain; charset=utf-8',
  };

  /// Start listening for requests.
  Future<void> serve() async {
    final server = await HttpServer.bind(address, port);
    server.listen(_handleRequest);
    _server = server;
  }

  /// Stop listening for requests.
  Future<void> stop() async {
    await _server?.close(force: true);
    _server = null;
  }

  Future<void> _handleRequest(HttpRequest request) async {
    final response = request.response;
    try {
      if (request.method != 'GET' && request.method != 'HEAD') {
        response.statusCode = HttpStatus.methodNotAllowed;
        return;
      }

      String path = Uri.decodeComponent(request.uri.path);
      if (path.startsWith('/')) {
        path = path.substring(1);
      }
      if (path.isEmpty || path.endsWith('/')) {
        path = '${path}index.html';
      }
      if (path.split('/').contains('..')) {
        response.statusCode = HttpStatus.forbidden;
        return;
      }

      String servedPath = path;
      ByteData? data = await _loadAsset(path);
      if (data == null && !path.split('/').last.contains('.')) {
        servedPath = '$path.html';
        data = await _loadAsset(servedPath);
      }

      if (data == null) {
        response.statusCode = HttpStatus.notFound;
        debugPrint('GET ${request.uri} - 404');
        return;
      }

      final extension = servedPath.split('.').last.toLowerCase();
      response.headers.set(
        HttpHeaders.contentTypeHeader,
        _contentTypes[extension] ?? 'application/octet-stream',
      );
      if (servedPath == 'service-worker.js') {
        response.headers.set('Service-Worker-Allowed', '/');
      }
      response.headers.contentLength = data.lengthInBytes;
      if (request.method == 'GET') {
        response.add(
          data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
        );
      }
    } catch (e) {
      debugPrint('GET ${request.uri} - $e');
      try {
        response.statusCode = HttpStatus.internalServerError;
      } catch (_) {
        // Headers were already sent.
      }
    } finally {
      try {
        await response.close();
      } catch (_) {
        // The client went away before the response completed.
      }
    }
  }

  Future<ByteData?> _loadAsset(String path) async {
    try {
      return await rootBundle.load('$assetsBasePath/$path');
    } catch (_) {
      return null;
    }
  }
}
