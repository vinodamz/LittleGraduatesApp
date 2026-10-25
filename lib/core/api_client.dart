import 'dart:async';
import 'dart:convert';
import 'package:flutter/foundation.dart';

import 'package:http/http.dart' as http;

import 'config.dart';

class ApiException implements Exception {
  ApiException(this.message, {this.status = 0, this.code = ''});

  final String message;
  final int status;
  final String code;

  bool get isUnauthenticated => status == 401 && code != 'wrong_pin';

  @override
  String toString() => message;
}

/// JSON client for `/api/v1`. The token is the device's bearer token.
class ApiClient {
  ApiClient({http.Client? client}) : _http = client ?? http.Client();

  static const userAgent =
      'Mozilla/5.0 (Linux; Android) LittleGraduatesApp/1.0';

  final http.Client _http;
  String? token;

  /// Called when the server says the token is no longer valid.
  void Function()? onUnauthenticated;

  Uri _uri(String path, [Map<String, String>? query]) => Uri.parse(
    '${AppConfig.baseUrl}/api/v1/$path',
  ).replace(queryParameters: query);

  Map<String, String> get _headers => {
    'Accept': 'application/json',
    'Content-Type': 'application/json',
    // Browser-like agent: the host's bot filter blocks unknown clients.
    if (!kIsWeb) 'User-Agent': userAgent,
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Map<String, String> get _acceptHeaders => {
    'Accept': 'application/json',
    if (!kIsWeb) 'User-Agent': userAgent,
    if (token != null) 'Authorization': 'Bearer $token',
  };

  Future<Map<String, dynamic>> get(String path, [Map<String, String>? query]) =>
      _send(() => _http.get(_uri(path, query), headers: _headers));

  Future<Map<String, dynamic>> post(
    String path, [
    Map<String, dynamic>? body,
  ]) => _send(
    () =>
        _http.post(_uri(path), headers: _headers, body: jsonEncode(body ?? {})),
  );

  /// Multipart upload. Used for material photos and videos, which can take
  /// longer than a JSON call.
  Future<Map<String, dynamic>> postMultipart(
    String path, {
    required Map<String, String> fields,
    required String filePath,
    required String filename,
  }) {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(_acceptHeaders);
    request.fields.addAll(fields);
    return _send(() async {
      request.files.add(
        await http.MultipartFile.fromPath(
          'media',
          filePath,
          filename: filename,
        ),
      );
      final streamed = await _http.send(request);
      return http.Response.fromStream(streamed);
    }, timeout: const Duration(minutes: 5));
  }

  Future<Map<String, dynamic>> postMultipartBytes(
    String path, {
    required Map<String, String> fields,
    required List<int> bytes,
    required String filename,
  }) {
    final request = http.MultipartRequest('POST', _uri(path));
    request.headers.addAll(_acceptHeaders);
    request.fields.addAll(fields);
    request.files.add(
      http.MultipartFile.fromBytes('media', bytes, filename: filename),
    );
    return _send(
      () async => http.Response.fromStream(await _http.send(request)),
      timeout: const Duration(minutes: 5),
    );
  }

  Future<Map<String, dynamic>> _send(
    Future<http.Response> Function() request, {
    Duration timeout = const Duration(seconds: 20),
  }) async {
    http.Response res;
    try {
      res = await request().timeout(timeout);
    } on http.ClientException {
      throw ApiException(
        'Could not reach the school server. Check your connection.',
      );
    } on TimeoutException {
      throw ApiException('The school server did not respond.');
    } on Exception {
      throw ApiException('The school server did not respond.');
    }
    Map<String, dynamic> data;
    try {
      data = jsonDecode(res.body) as Map<String, dynamic>;
    } on FormatException {
      throw ApiException(
        'Unexpected reply from the server (${res.statusCode}).',
        status: res.statusCode,
      );
    }
    if (res.statusCode >= 400 || data['ok'] != true) {
      final e = ApiException(
        (data['error'] as String?) ??
            'Something went wrong (${res.statusCode}).',
        status: res.statusCode,
        code: (data['code'] as String?) ?? '',
      );
      if (e.isUnauthenticated) onUnauthenticated?.call();
      throw e;
    }
    return data;
  }
}
