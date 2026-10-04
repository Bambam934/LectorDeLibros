import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/entities/chapter_block.dart';

/// Comprueba si una zona de una página del PDF tiene algo pintado.
///
/// Los huecos entre líneas son candidatos a ecuación o figura, pero también
/// los deja el aire sobre un título o el final de un capítulo. Solo pintando
/// el hueco se sabe si hay algo: sin esta comprobación la lectura se llenaría
/// de fórmulas inventadas en huecos vacíos (ADR 13).
abstract interface class InkProbe {
  /// Para cada zona `(página base 0, rectángulo en puntos)`, la caja que ocupa
  /// la tinta dentro de ella, o `null` si está en blanco o no se pudo pintar.
  Future<List<PageRect?>> inkBounds(
    String pdfPath,
    List<(int, PageRect)> regions,
  );
}

/// [InkProbe] con PDFium, a través de pdfrx.
///
/// pdfrx ejecuta PDFium en su propio isolate de trabajo, así que pintar no
/// bloquea la interfaz. Cada página con candidatos se pinta **una sola vez**
/// y a baja resolución: para saber si hay tinta y dónde basta con medio píxel
/// por punto.
class PdfrxInkProbe implements InkProbe {
  const PdfrxInkProbe({this.pixelsPerPoint = 0.5});

  final double pixelsPerPoint;

  /// Un píxel con menos luminancia que esta cuenta como tinta.
  static const _inkLuminance = 200;

  /// Píxeles de tinta necesarios para dar la zona por pintada: menos es una
  /// mota, no una ecuación.
  static const _minInkPixels = 4;

  @override
  Future<List<PageRect?>> inkBounds(
    String pdfPath,
    List<(int, PageRect)> regions,
  ) async {
    final result = List<PageRect?>.filled(regions.length, null);
    if (regions.isEmpty) return result;

    PdfDocument? document;
    try {
      await pdfrxFlutterInitialize();
      document = await PdfDocument.openFile(pdfPath);
      final byPage = <int, List<int>>{};
      for (var i = 0; i < regions.length; i++) {
        (byPage[regions[i].$1] ??= []).add(i);
      }
      for (final entry in byPage.entries) {
        if (entry.key < 0 || entry.key >= document.pages.length) continue;
        final page = document.pages[entry.key];
        final scale = pixelsPerPoint;
        final width = (page.width * scale).ceil();
        final height = (page.height * scale).ceil();
        final image = await page.render(
          fullWidth: width.toDouble(),
          fullHeight: height.toDouble(),
          width: width,
          height: height,
          annotationRenderingMode: PdfAnnotationRenderingMode.none,
        );
        if (image == null) continue;
        try {
          for (final i in entry.value) {
            result[i] = _scan(image.pixels, image.width, image.height,
                regions[i].$2, scale);
          }
        } finally {
          image.dispose();
        }
      }
    } catch (e) {
      // Un PDF que PDFium no abre se queda sin figuras: la lectura sigue.
      debugPrint('[InkProbe] no se pudo pintar $pdfPath: $e');
    } finally {
      await document?.dispose();
    }
    return result;
  }

  /// Caja de la tinta de [region] en una imagen BGRA de la página entera.
  ///
  /// Se encoge un par de puntos por arriba y por abajo: el rectángulo del
  /// hueco va de una línea de texto a la siguiente y no debe contar sus
  /// descendentes ni sus acentos como tinta propia.
  ///
  /// Un recuadro o un filete no son una figura: los huecos que rodean una
  /// "Nota:" enmarcada solo tienen el borde del marco (la línea de arriba y
  /// los arranques de los lados). Por eso hace falta tinta **dentro** de la
  /// caja, sin contar las filas que la cruzan casi entera ni sus columnas de
  /// los bordes.
  static PageRect? _scan(
    Uint8List pixels,
    int width,
    int height,
    PageRect region,
    double scale,
  ) {
    const inset = 2.0;
    final x0 = math.max(0, (region.left * scale).floor());
    final x1 = math.min(width, (region.right * scale).ceil());
    final y0 = math.max(0, ((region.top + inset) * scale).floor());
    final y1 = math.min(height, ((region.bottom - inset) * scale).ceil());
    if (x1 <= x0 || y1 <= y0) return null;

    bool isInk(int offset) =>
        // BGRA. Luminancia aproximada en enteros.
        (pixels[offset + 2] * 299 +
                pixels[offset + 1] * 587 +
                pixels[offset] * 114) ~/
            1000 <
        _inkLuminance;

    var count = 0;
    final rowInk = List<int>.filled(y1 - y0, 0);
    var minX = x1, maxX = x0 - 1, minY = y1, maxY = y0 - 1;
    for (var y = y0; y < y1; y++) {
      var offset = (y * width + x0) * 4;
      for (var x = x0; x < x1; x++, offset += 4) {
        if (!isInk(offset)) continue;
        count++;
        rowInk[y - y0]++;
        if (x < minX) minX = x;
        if (x > maxX) maxX = x;
        if (y < minY) minY = y;
        if (y > maxY) maxY = y;
      }
    }
    if (count < _minInkPixels) return null;

    final boxWidth = maxX - minX + 1;
    final edge = boxWidth >= 12 ? 2 : 0;
    var interior = 0;
    for (var y = minY; y <= maxY; y++) {
      if (rowInk[y - y0] >= 0.6 * boxWidth) continue;
      var offset = (y * width + minX + edge) * 4;
      for (var x = minX + edge; x <= maxX - edge; x++, offset += 4) {
        if (isInk(offset)) interior++;
      }
    }
    if (interior < _minInkPixels) return null;
    return PageRect(
      minX / scale,
      minY / scale,
      (maxX + 1) / scale,
      (maxY + 1) / scale,
    );
  }
}
