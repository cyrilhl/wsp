import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_tesseract_ocr/flutter_tesseract_ocr.dart';

class OcrResult {
  const OcrResult(this.rawText, this.elapsedMs);
  final String rawText;
  final int elapsedMs;
}

class OcrService {
  Future<OcrResult> recognize(Uint8List crop, {bool enhanced = true}) async {
    final timer = Stopwatch()..start();
    final text = await FlutterTesseractOcr.extractText(
      'data:image/png;base64,${base64Encode(crop)}',
      language: 'eng',
      args: {
        'tessedit_pageseg_mode': '7',
        'tessedit_char_whitelist': '0123456789.-',
        'preserve_interword_spaces': '1',
        'meter_enhance': enhanced,
      },
    );
    return OcrResult(text, timer.elapsedMilliseconds);
  }
}
