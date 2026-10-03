// ignore_for_file: experimental_member_use
//
// `StreamAudioSource` sigue marcada como experimental en just_audio 0.10.5,
// pero es la única forma de reproducir audio generado en memoria en las cinco
// plataformas: `setFilePath` obligaría a `dart:io` + `path_provider`, que no
// existen en web. Este archivo aísla la anotación para que el resto del código
// no tenga que silenciarla.

import 'dart:typed_data';

import 'package:just_audio/just_audio.dart';

/// Sirve al reproductor un audio que ya está en memoria.
///
/// just_audio pide los bytes por rangos, igual que si vinieran de la red;
/// aquí solo recortamos el trozo pedido del buffer.
class SynthAudioSource extends StreamAudioSource {
  SynthAudioSource(this._bytes, {this.contentType = 'audio/wav'});

  final Uint8List _bytes;
  final String contentType;

  @override
  Future<StreamAudioResponse> request([int? start, int? end]) async {
    // Acotado contra el buffer: los límites vienen de una cabecera Range que
    // traduce el proxy de just_audio, y un valor fuera de rango hacía estallar
    // el recorte con un RangeError que el proxy convierte en HTTP 500 — el
    // usuario solo veía "no se pudo reproducir", sin pista de la causa.
    final from = (start ?? 0).clamp(0, _bytes.length);
    final to = (end ?? _bytes.length).clamp(from, _bytes.length);
    return StreamAudioResponse(
      sourceLength: _bytes.length,
      contentLength: to - from,
      offset: from,
      // `sublistView` y no `sublist`: el buffer no se modifica una vez
      // generado, y copiarlo cuesta 1,7 MB y ~0,5 ms en CADA petición de
      // rango — con el bucle activado, en cada repetición.
      stream: Stream.value(Uint8List.sublistView(_bytes, from, to)),
      contentType: contentType,
    );
  }
}
