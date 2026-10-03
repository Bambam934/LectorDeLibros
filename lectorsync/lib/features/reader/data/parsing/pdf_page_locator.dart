import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:syncfusion_flutter_pdf/pdf.dart';

/// Encuentra en qué página de un PDF aparece un fragmento de texto.
///
/// Sirve para llevar al lector de una fórmula aplanada a la página original
/// donde la ecuación se ve maquetada. Se resuelve **en el momento de pulsar**
/// en lugar de rastrear el número de página durante el parseo: así no hay que
/// tocar el pipeline de extracción, ni la entidad `Chapter`, ni migrar la
/// caché de capítulos ya generada en los dispositivos.
///
/// El índice de texto por página se construye una vez por libro, **en un
/// isolate**, y se guarda en memoria: a partir de ahí cada búsqueda es
/// instantánea.
class PdfPageLocator {
  PdfPageLocator();

  /// Texto normalizado de cada página, por ruta de fichero.
  final Map<String, List<String>> _indexByPath = {};

  /// Índices en construcción, para que dos pulsaciones seguidas sobre el
  /// mismo libro compartan el trabajo en vez de lanzar dos isolates.
  final Map<String, Future<List<String>?>> _pending = {};

  /// Número de páginas indexadas de un libro ya cargado, o `null`.
  int? pageCountOf(String pdfPath) => _indexByPath[pdfPath]?.length;

  /// Descarta el índice de un libro (al cerrarlo, o si el fichero cambió).
  void evict(String pdfPath) {
    _indexByPath.remove(pdfPath);
    _pending.remove(pdfPath);
  }

  void clear() {
    _indexByPath.clear();
    _pending.clear();
  }

  /// Índice **base 0** de la página que contiene [fragment], o `null`.
  ///
  /// Devuelve `null` en lugar de lanzar cuando el fichero no existe o el
  /// fragmento no aparece: no encontrar la página original es un resultado
  /// normal (un TXT no tiene páginas, el PDF pudo moverse), no un error que
  /// deba interrumpir la lectura.
  Future<int?> locate({
    required String pdfPath,
    required String fragment,
  }) async {
    final needle = normalizeForSearch(fragment);
    if (needle.isEmpty) return null;

    final pages = await _indexOf(pdfPath);
    if (pages == null) return null;

    for (var i = 0; i < pages.length; i++) {
      if (pages[i].contains(needle)) return i;
    }

    // Segundo intento con la mitad más larga del fragmento: la extracción de
    // la fórmula pudo unir texto de dos columnas o arrastrar un carácter que
    // el índice no tiene, y una coincidencia parcial sigue llevando a la
    // página correcta.
    final half = needle.substring(0, needle.length ~/ 2);
    if (half.length < 6) return null;
    for (var i = 0; i < pages.length; i++) {
      if (pages[i].contains(half)) return i;
    }

    return null;
  }

  Future<List<String>?> _indexOf(String pdfPath) async {
    final cached = _indexByPath[pdfPath];
    if (cached != null) return cached;

    final inFlight = _pending[pdfPath];
    if (inFlight != null) return inFlight;

    final future = _buildIndex(pdfPath);
    _pending[pdfPath] = future;
    try {
      return await future;
    } finally {
      _pending.remove(pdfPath);
    }
  }

  Future<List<String>?> _buildIndex(String pdfPath) async {
    if (!await File(pdfPath).exists()) return null;

    // En un isolate: abrir el documento y extraer el texto son llamadas
    // SÍNCRONAS de Syncfusion, una por página. En el hilo de UI, un libro de
    // 300 páginas se lleva varios segundos enteros — con el agravante de que
    // el `LoadingView` que cubre la espera se queda congelado, porque su
    // animación depende del mismo hilo, y Android acaba mostrando un ANR.
    //
    // Se pasa la ruta y no los bytes para que la lectura del fichero también
    // ocurra fuera del hilo de UI y no haya que copiar el PDF entre isolates.
    final pages = await compute(extractNormalizedPdfPages, pdfPath);
    if (pages == null) return null;

    _indexByPath[pdfPath] = pages;
    return pages;
  }
}

/// Punto de entrada del isolate de [compute]: debe ser de nivel superior.
///
/// Devuelve `null` si el PDF está cifrado, corrupto, desaparecido o con una
/// estructura que Syncfusion rechaza.
List<String>? extractNormalizedPdfPages(String pdfPath) {
  PdfDocument? document;
  try {
    document = PdfDocument(inputBytes: File(pdfPath).readAsBytesSync());
    final extractor = PdfTextExtractor(document);
    return <String>[
      for (var i = 0; i < document.pages.count; i++)
        normalizeForSearch(
          extractor.extractText(startPageIndex: i, endPageIndex: i),
        ),
    ];
  } catch (_) {
    return null;
  } finally {
    document?.dispose();
  }
}

/// Forma canónica para comparar texto del capítulo con texto del PDF crudo.
///
/// Quita el espacio en blanco, baja a minúsculas **y borra los guiones**.
///
/// Los guiones son imprescindibles: el fragmento que llega del capítulo ya
/// pasó por el reflow, que une las palabras que el corte de línea partió
/// ("consu- mismo" → "consumismo"), mientras que el índice se extrae del PDF
/// en crudo y conserva ese guion. Sin borrarlo, cualquier párrafo con una
/// palabra partida fallaba el `contains` y el lector veía "No se encontró la
/// página" — precisamente en los libros de texto justificado con hifenación
/// frecuente, que son el caso que motiva la función. Borrarlo en AMBOS lados
/// deja la comparación un poco más laxa y, sobre todo, simétrica.
String normalizeForSearch(String text) => text
    .replaceAll(_whitespaceOrHyphen, '')
    .toLowerCase();

/// Espacio en blanco y toda la familia de guiones que puede colarse en el
/// corte de línea: guion normal, guion suave, guion unicode y raya corta.
final RegExp _whitespaceOrHyphen = RegExp(r'[\s\-­‐‑–]+');
