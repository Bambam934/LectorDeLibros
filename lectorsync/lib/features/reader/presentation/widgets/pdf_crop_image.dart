import 'dart:async';
import 'dart:collection';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../domain/entities/chapter_block.dart';

/// Recortes de páginas del PDF ya pintados, compartidos por las figuras de un
/// libro (ADR 13).
///
/// Cada recorte se pinta solo cuando su bloque va a verse y se guarda en
/// memoria con un tope: volver unas líneas atrás no lo repinta, y un capítulo
/// lleno de ecuaciones no se come la memoria. El documento se abre una vez
/// por libro y se cierra con [clear], al salir del lector.
class PdfCropCache {
  PdfCropCache._();

  static final PdfCropCache instance = PdfCropCache._();

  /// Recortes que se guardan. A ancho de columna y con la densidad de un
  /// móvil cada uno ronda 1-2 MB.
  static const _maxImages = 16;

  final Map<String, Future<PdfDocument>> _documents = {};
  final LinkedHashMap<String, ui.Image> _images = LinkedHashMap();
  final Map<String, Future<ui.Image?>> _pending = {};

  /// Recorte de [rect] (puntos del PDF) de la página [pageIndex], pintado a
  /// [pixelWidth] píxeles de ancho. Devuelve una copia que el llamador debe
  /// liberar con `dispose`, o `null` si no se pudo pintar.
  Future<ui.Image?> crop({
    required String pdfPath,
    required int pageIndex,
    required PageRect rect,
    required int pixelWidth,
  }) async {
    final key = '$pdfPath|$pageIndex|${rect.left},${rect.top},'
        '${rect.right},${rect.bottom}|$pixelWidth';
    final cached = _images.remove(key);
    if (cached != null) {
      _images[key] = cached;
      return cached.clone();
    }
    final image = await (_pending[key] ??= _render(
      pdfPath,
      pageIndex,
      rect,
      pixelWidth,
    ).whenComplete(() => _pending.remove(key)));
    if (image == null) return null;
    if (!_images.containsKey(key)) {
      _images[key] = image;
      while (_images.length > _maxImages) {
        _images.remove(_images.keys.first)?.dispose();
      }
    }
    return _images[key]?.clone();
  }

  Future<ui.Image?> _render(
    String pdfPath,
    int pageIndex,
    PageRect rect,
    int pixelWidth,
  ) async {
    try {
      await pdfrxFlutterInitialize();
      final document = await (_documents[pdfPath] ??=
          PdfDocument.openFile(pdfPath));
      if (pageIndex < 0 || pageIndex >= document.pages.length) return null;
      if (rect.width <= 0 || rect.height <= 0) return null;
      final page = document.pages[pageIndex];
      final scale = pixelWidth / rect.width;
      final rendered = await page.render(
        x: (rect.left * scale).round(),
        y: (rect.top * scale).round(),
        width: pixelWidth,
        height: (rect.height * scale).round(),
        fullWidth: page.width * scale,
        fullHeight: page.height * scale,
        annotationRenderingMode: PdfAnnotationRenderingMode.none,
      );
      if (rendered == null) return null;
      try {
        return await rendered.createImage();
      } finally {
        rendered.dispose();
      }
    } catch (e) {
      debugPrint('[PdfCropCache] no se pudo recortar la página $pageIndex: $e');
      return null;
    }
  }

  /// Libera los recortes y cierra los documentos.
  Future<void> clear() async {
    for (final image in _images.values) {
      image.dispose();
    }
    _images.clear();
    final documents = _documents.values.toList();
    _documents.clear();
    for (final document in documents) {
      try {
        await (await document).dispose();
      } catch (_) {}
    }
  }
}

/// Recorte de una página del PDF, del tamaño indicado.
///
/// Mientras se pinta ocupa ya su sitio con la proporción del recorte, para
/// que el texto de alrededor no salte cuando aparece.
class PdfCropImage extends StatefulWidget {
  const PdfCropImage({
    required this.pdfPath,
    required this.pageIndex,
    required this.rect,
    required this.width,
    required this.height,
    super.key,
  });

  final String pdfPath;
  final int pageIndex;
  final PageRect rect;
  final double width;
  final double height;

  @override
  State<PdfCropImage> createState() => _PdfCropImageState();
}

class _PdfCropImageState extends State<PdfCropImage> {
  ui.Image? _image;
  bool _failed = false;
  int _request = 0;
  int? _pixelWidth;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _load();
  }

  @override
  void didUpdateWidget(covariant PdfCropImage old) {
    super.didUpdateWidget(old);
    if (old.pdfPath != widget.pdfPath ||
        old.pageIndex != widget.pageIndex ||
        old.rect != widget.rect ||
        old.width != widget.width) {
      _load();
    }
  }

  void _load() {
    final dpr = MediaQuery.devicePixelRatioOf(context);
    final pixelWidth = (widget.width * dpr).round().clamp(16, 4096);
    if (pixelWidth == _pixelWidth && (_image != null || _failed)) return;
    _pixelWidth = pixelWidth;
    final request = ++_request;
    unawaited(PdfCropCache.instance
        .crop(
      pdfPath: widget.pdfPath,
      pageIndex: widget.pageIndex,
      rect: widget.rect,
      pixelWidth: pixelWidth,
    )
        .then((image) {
      if (!mounted || request != _request) {
        image?.dispose();
        return;
      }
      setState(() {
        _image?.dispose();
        _image = image;
        _failed = image == null;
      });
    }));
  }

  @override
  void dispose() {
    _request++;
    _image?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final image = _image;
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: image != null
          ? RawImage(image: image, fit: BoxFit.fill)
          : _failed
              ? Center(
                  child: Icon(
                    Icons.broken_image_outlined,
                    color: Theme.of(context).colorScheme.outline,
                  ),
                )
              : null,
    );
  }
}
