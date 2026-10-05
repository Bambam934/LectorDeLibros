import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' show Rect;

import 'package:flutter_test/flutter_test.dart';
import 'package:lectorsync/features/reader/domain/entities/chapter_block.dart';
import 'package:lectorsync/features/reader/presentation/widgets/pdf_crop_image.dart';
import 'package:pdfrx/pdfrx.dart' show Pdfrx;
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Una página con un rectángulo negro dibujado en (100, 100)-(300, 140).
Uint8List _pdfWithShape() {
  final document = PdfDocument();
  document.pages.add().graphics.drawRectangle(
        brush: PdfSolidBrush(PdfColor(0, 0, 0)),
        bounds: const Rect.fromLTWH(100, 100, 200, 40),
      );
  final bytes = Uint8List.fromList(document.saveSync());
  document.dispose();
  return bytes;
}

void main() {
  late Directory dir;

  setUp(() async {
    dir = await Directory.systemTemp.createTemp('lectorsync_crop_');
    Pdfrx.cacheDirectoryPath = dir.path;
  });

  tearDown(() async {
    await PdfCropCache.instance.clear();
    await dir.delete(recursive: true);
  });

  test('el recorte termina, también con dos peticiones a la vez', () async {
    final path = '${dir.path}${Platform.pathSeparator}figura.pdf';
    await File(path).writeAsBytes(_pdfWithShape());
    const rect = PageRect(90, 90, 310, 150);

    // Con `whenComplete(() => _pending.remove(key))` el futuro se esperaba a
    // sí mismo: el recorte se pintaba y nunca llegaba a la pantalla.
    final images = await Future.wait([
      PdfCropCache.instance
          .crop(pdfPath: path, pageIndex: 0, rect: rect, pixelWidth: 220),
      PdfCropCache.instance
          .crop(pdfPath: path, pageIndex: 0, rect: rect, pixelWidth: 220),
    ]).timeout(const Duration(seconds: 30));

    for (final image in images) {
      expect(image, isNotNull);
      expect(image!.width, 220);
      expect(image.height, 60);
      image.dispose();
    }

    // Desde la caché, sin volver a pintar.
    final again = await PdfCropCache.instance
        .crop(pdfPath: path, pageIndex: 0, rect: rect, pixelWidth: 220)
        .timeout(const Duration(seconds: 5));
    expect(again, isNotNull);
    again!.dispose();
  });
}
