import 'dart:convert';
import 'dart:typed_data';

/// Decodifica un TXT o MD importado.
///
/// Prueba UTF-8 (quitando el BOM) y, si los bytes no lo son, Windows-1252: el
/// "ANSI" con el que el Bloc de notas guardaba los textos en español. Con
/// `readAsString()`, que solo admite UTF-8, esos libros no se podían abrir.
/// El backend decodifica igual (`text-parser.ts`); Windows-1252 coincide con
/// Latin-1 en todas las letras y además recupera comillas, rayas y puntos
/// suspensivos tipográficos.
String decodeTextBytes(Uint8List bytes) {
  final hasBom = bytes.length >= 3 &&
      bytes[0] == 0xEF &&
      bytes[1] == 0xBB &&
      bytes[2] == 0xBF;
  final body = hasBom ? Uint8List.sublistView(bytes, 3) : bytes;
  try {
    return utf8.decode(body);
  } on FormatException {
    return _decodeWindows1252(body);
  }
}

/// 0x80-0x9F de Windows-1252; el resto de bytes coincide con Latin-1. Los
/// cinco huecos sin asignar (0x81, 0x8D, 0x8F, 0x90, 0x9D) quedan como en
/// Latin-1.
const _cp1252High = <int>[
  0x20AC, 0x0081, 0x201A, 0x0192, 0x201E, 0x2026, 0x2020, 0x2021, // 80-87
  0x02C6, 0x2030, 0x0160, 0x2039, 0x0152, 0x008D, 0x017D, 0x008F, // 88-8F
  0x0090, 0x2018, 0x2019, 0x201C, 0x201D, 0x2022, 0x2013, 0x2014, // 90-97
  0x02DC, 0x2122, 0x0161, 0x203A, 0x0153, 0x009D, 0x017E, 0x0178, // 98-9F
];

String _decodeWindows1252(Uint8List bytes) {
  final units = Uint16List(bytes.length);
  for (var i = 0; i < bytes.length; i++) {
    final b = bytes[i];
    units[i] = (b >= 0x80 && b < 0xA0) ? _cp1252High[b - 0x80] : b;
  }
  return String.fromCharCodes(units);
}
