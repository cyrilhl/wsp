/// Accept one complete decimal number. Never concatenate separate OCR tokens.
String? parseReading(String text) {
  final value = text.trim();
  return RegExp(r'^-?\d+(?:\.\d+)?$').hasMatch(value) ? value : null;
}
