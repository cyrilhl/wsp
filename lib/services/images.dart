import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';

Rect viewfinderFor(Size preview) => Rect.fromLTWH(
  preview.width * .25,
  preview.height * .25,
  preview.width * .5,
  preview.height * .5,
);

/// Bounds must describe the actual contained camera image, excluding letterbox.
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
  Future<Capture> prepare(Uint8List bytes, {bool mirrored = false}) async {
    final codec = await ui.instantiateImageCodec(bytes);
    final image = (await codec.getNextFrame()).image;
    codec.dispose();
    try {
      final size = Size(image.width.toDouble(), image.height.toDouble());
      final bounds = Offset.zero & size;
      final cropRect = imageCrop(viewfinderFor(size), bounds, size);
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
