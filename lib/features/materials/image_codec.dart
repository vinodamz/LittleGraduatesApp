import 'dart:math' as math;
import 'dart:typed_data';

import 'package:image/image.dart' as img;

/// Longest side of a photo before it is uploaded.
const materialsImageMaxEdge = 1600;

/// JPEG quality used for every uploaded photo (70–80%).
const materialsJpegQuality = 75;

/// 720p. A video whose longer side is already within this, and whose file is
/// not huge, is uploaded without another transcode.
const materialsVideoMaxLongEdge = 1280;

const materialsVideoSkipBytes = 12 * 1024 * 1024;

/// Downscale and re-encode a photo. Throws [FormatException] when the bytes
/// are not a format the Dart decoder understands (for example HEIC).
Uint8List compressMaterialsPhoto(
  Uint8List bytes, {
  int maxEdge = materialsImageMaxEdge,
  int quality = materialsJpegQuality,
}) {
  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw const FormatException('Could not read the photo.');
  }
  var image = img.bakeOrientation(decoded);
  final longEdge = math.max(image.width, image.height);
  if (longEdge > maxEdge) {
    final scale = maxEdge / longEdge;
    image = img.copyResize(
      image,
      width: math.max(1, (image.width * scale).round()),
      height: math.max(1, (image.height * scale).round()),
      interpolation: img.Interpolation.linear,
    );
  }
  return img.encodeJpg(image, quality: quality);
}

/// One-argument wrapper so `compute` can run the encoder off the UI isolate.
Uint8List compressMaterialsPhotoBytes(Uint8List bytes) => compressMaterialsPhoto(bytes);

/// True when a clip should be transcoded to 720p or smaller.
bool videoNeedsTranscode({required int? width, required int? height, required int bytes}) {
  if (width == null || height == null || width <= 0 || height <= 0) return true;
  final longEdge = math.max(width, height);
  if (longEdge > materialsVideoMaxLongEdge) return true;
  if (bytes > materialsVideoSkipBytes) return true;
  return false;
}
