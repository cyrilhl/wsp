import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

/// A centered landscape frame, independent of the camera's orientation.
Rect viewfinderFor(Size preview) {
  final width = (preview.width * .84).clamp(0.0, preview.height * .8);
  return Rect.fromCenter(
    center: preview.center(Offset.zero),
    width: width,
    height: width / 2,
  );
}

/// Full image bounds when the preview fills the viewport without stretching.
Rect cameraPreviewBounds(Size viewport, Size image) {
  final scale = viewport.width / image.width > viewport.height / image.height
      ? viewport.width / image.width
      : viewport.height / image.height;
  return Rect.fromCenter(
    center: viewport.center(Offset.zero),
    width: image.width * scale,
    height: image.height * scale,
  );
}

/// Bounds describe the scaled camera image, including off-screen edges.
Rect imageCrop(Rect overlay, Rect previewBounds, Size imageSize) {
  final clipped = overlay.intersect(previewBounds);
  return Rect.fromLTRB(
    (clipped.left - previewBounds.left) / previewBounds.width * imageSize.width,
    (clipped.top - previewBounds.top) / previewBounds.height * imageSize.height,
    (clipped.right - previewBounds.left) /
        previewBounds.width *
        imageSize.width,
    (clipped.bottom - previewBounds.top) /
        previewBounds.height *
        imageSize.height,
  );
}

class Capture {
  const Capture(this.photo, this.crop, this.thumbnail, this.capturedAt);
  final Uint8List photo, crop, thumbnail;
  final DateTime capturedAt;
}

class ImageService {
  Future<Capture> prepare(
    Uint8List bytes, {
    bool mirrored = false,
    Size? viewportSize,
  }) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final bounds = Offset.zero & size;
      final viewport = viewportSize ?? size;
      final cropRect = imageCrop(
        viewfinderFor(viewport),
        cameraPreviewBounds(viewport, size),
        size,
      );
      // camera_web mirrors non-rear captures; normalize before OCR/storage.
      final photo = mirrored ? await _render(image, bounds, size, true) : bytes;
      final crop = await _render(image, cropRect, cropRect.size, mirrored);
      final thumbSize = Size(320, 320 * size.height / size.width);
      final thumbnail = await _render(image, bounds, thumbSize, mirrored);
      return Capture(photo, crop, thumbnail, DateTime.now());
    } finally {
      image.dispose();
    }
  }

  Future<Uint8List> _render(
    ui.Image image,
    Rect source,
    Size target,
    bool flip,
  ) async {
    target = Size(target.width.roundToDouble(), target.height.roundToDouble());
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    if (flip) {
      canvas.translate(target.width, 0);
      canvas.scale(-1, 1);
    }
    canvas.drawImageRect(image, source, Offset.zero & target, Paint());
    final picture = recorder.endRecording();
    final rendered = await picture.toImage(
      target.width.round(),
      target.height.round(),
    );
    picture.dispose();
    try {
      final data = await rendered.toByteData(format: ui.ImageByteFormat.png);
      return data!.buffer.asUint8List();
    } finally {
      rendered.dispose();
    }
  }
}
