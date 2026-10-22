import 'dart:io';

import 'package:flutter/services.dart';

import 'materials_queue.dart';

const materialsUploadChannel = MethodChannel('in.thelittlegraduates.app/materials_upload');

/// Phone encoders and, on iOS, a background URLSession upload.
class ChannelMaterialsBridge implements MaterialsBridge {
  ChannelMaterialsBridge({MethodChannel? channel}) : _channel = channel ?? materialsUploadChannel;

  final MethodChannel _channel;

  @override
  bool get supportsBackgroundUpload => Platform.isIOS;

  @override
  bool get canTranscode => Platform.isAndroid || Platform.isIOS;

  @override
  Future<VideoInfo?> videoInfo(String path) async {
    final raw = await _invoke('videoInfo', {'path': path});
    if (raw is! Map) return null;
    final width = (raw['width'] as num?)?.toInt() ?? 0;
    final height = (raw['height'] as num?)?.toInt() ?? 0;
    if (width <= 0 || height <= 0) return null;
    return VideoInfo(width, height);
  }

  @override
  Future<void> transcodeVideo(String source, String dest) async {
    await _invoke('transcodeVideo', {'source': source, 'dest': dest});
  }

  @override
  Future<void> compressImageNative(String source, String dest) async {
    await _invoke('compressImage', {'source': source, 'dest': dest, 'maxEdge': 1600, 'quality': 75});
  }

  @override
  Future<void> enqueueBackgroundUpload(BackgroundUploadRequest request) async {
    await _invoke('enqueueUpload', {
      'clientKey': request.clientKey,
      'url': request.url,
      'headers': request.headers,
      'fields': request.fields,
      'filePath': request.filePath,
      'filename': request.filename,
      'mime': request.mime,
    });
  }

  @override
  Future<List<BackgroundUploadResult>> takeUploadResults() async {
    // The Android worker's engine has no Activity, so this channel is absent.
    // That is "no finished background uploads", not a reason to abort the queue.
    final Object? raw;
    try {
      raw = await _invoke('takeUploadResults');
    } on NeedsDeviceCompressor {
      return const [];
    }
    if (raw is! List) return const [];
    return [
      for (final item in raw)
        if (item is Map)
          BackgroundUploadResult(
            clientKey: item['clientKey'] as String? ?? '',
            status: (item['status'] as num?)?.toInt() ?? 0,
            body: item['body'] as String? ?? '',
            error: item['error'] as String?,
          ),
    ];
  }

  @override
  Future<Set<String>> inFlightUploads() async {
    final Object? raw;
    try {
      raw = await _invoke('inFlightUploads');
    } on NeedsDeviceCompressor {
      return const {};
    }
    if (raw is! List) return const {};
    return {for (final key in raw) '$key'};
  }

  Future<Object?> _invoke(String method, [Map<String, Object?>? args]) async {
    try {
      return await _channel.invokeMethod<Object>(method, args);
    } on MissingPluginException {
      throw NeedsDeviceCompressor();
    }
  }
}
