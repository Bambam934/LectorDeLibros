import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

import '../../../../core/constants/import_limits.dart';

/// Resultado de la lectura de un libro seleccionado desde el explorador.
sealed class PickedBookResult {
  const PickedBookResult();
}

/// El archivo se leyó con éxito y contiene los [bytes] del libro.
final class PickedBookBytes extends PickedBookResult {
  const PickedBookBytes(this.bytes);

  final Uint8List bytes;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is PickedBookBytes && _listEquals(bytes, other.bytes);

  @override
  int get hashCode => Object.hashAll(bytes);

  static bool _listEquals(Uint8List a, Uint8List b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// El archivo supera el tamaño máximo permitido para importación.
final class PickedBookTooLarge extends PickedBookResult {
  const PickedBookTooLarge();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PickedBookTooLarge;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// No se pudo obtener el contenido del archivo (sin stream ni bytes, o error de lectura).
final class PickedBookUnreadable extends PickedBookResult {
  const PickedBookUnreadable();

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is PickedBookUnreadable;

  @override
  int get hashCode => runtimeType.hashCode;
}

/// Lee el contenido de un libro seleccionado mediante el selector de archivos.
///
/// Si el archivo supera [maxBytes], devuelve [PickedBookTooLarge] sin
/// suscribirse a [PlatformFile.readStream]. Si dispone de [PlatformFile.readStream],
/// concatena sus fragmentos en un [Uint8List]. Si no dispone de stream pero sí
/// de [PlatformFile.bytes], usa esos bytes. Si no dispone de ninguno de los dos
/// o falla la lectura, devuelve [PickedBookUnreadable].
Future<PickedBookResult> readPickedBook(
  PlatformFile file, {
  int maxBytes = kMaxImportBytes,
}) async {
  if (file.size > maxBytes) {
    return const PickedBookTooLarge();
  }

  final stream = file.readStream;
  if (stream != null) {
    try {
      final builder = BytesBuilder(copy: false);
      await for (final chunk in stream) {
        builder.add(chunk);
      }
      return PickedBookBytes(builder.takeBytes());
    } catch (_) {
      return const PickedBookUnreadable();
    }
  }

  final bytes = file.bytes;
  if (bytes != null) {
    return PickedBookBytes(bytes);
  }

  return const PickedBookUnreadable();
}
