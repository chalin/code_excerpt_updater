// ignore_for_file: type_annotate_public_apis

/// String to int conversion
int toInt(String s, {int radix = 10, int errorValue}) {
  try {
    return int.parse(s, radix: radix);
  } on FormatException {
    return errorValue;
  }
}

//-----------------------------------------------------------------------------
// TODO: consider writing the following conversions as a string transformer.

const backslash = '\\';
final escapedSlashRE = new RegExp(r'\\/');
const zeroChar = '\u{0}';

final _slashHexCharRE = new RegExp(r'\\x(..)');
final _slashLetterRE = new RegExp(r'\\([\\nt])');

/// Encode special characters: '\t', `\n`, and `\xHH` where `HH` are hex digits.
String encodeSlashChar(String s) {
  return s
      .replaceAllMapped(_slashLetterRE, (Match m) => _slashCharToChar(m[1]))
      // At this point, escaped `\` is encoded as [zeroChar].
      .replaceAllMapped(_slashHexCharRE,
          (Match m) => _hexToChar(m[1], errorValue: '\\x${m[1]}'))
      // Recover `\` characters.
      .replaceAll(zeroChar, backslash);
}

String _hexToChar(String hexDigits, {String errorValue}) {
  final charCode = toInt(hexDigits, radix: 16);
  return charCode == null ? errorValue : new String.fromCharCode(charCode);
}

//
String _slashCharToChar(String char) {
  switch (char) {
    case 'n':
      return '\n';
    case 't':
      return '\t';
    case backslash:
      return zeroChar;
    default:
      return '\\$char';
  }
}
