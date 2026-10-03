import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../../../core/widgets/loading_view.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../data/parsing/pdf_page_locator.dart';

/// Muestra la página original del PDF donde vive una fórmula.
///
/// El extractor de texto aplana las ecuaciones y no hay filtro que las
/// recupere: `10.50.5(1)2+1=` no se puede reconstruir a partir de sí mismo.
/// La única forma de que el lector vea la fórmula de verdad es enseñarle la
/// página tal y como está maquetada en el libro.
///
/// La página se localiza al abrir la hoja, buscando el texto de la fórmula
/// en el PDF. Es un instante en un libro ya indexado y evita tener que
/// arrastrar el número de página por todo el pipeline de parseo.
class FormulaSourceSheet extends StatefulWidget {
  const FormulaSourceSheet({
    required this.pdfPath,
    required this.fragment,
    required this.locator,
    super.key,
  });

  /// Ruta del PDF original en el dispositivo.
  final String pdfPath;

  /// Texto de la fórmula tal y como aparece en el capítulo.
  final String fragment;

  final PdfPageLocator locator;

  /// Abre la hoja a pantalla casi completa.
  static Future<void> show(
    BuildContext context, {
    required String pdfPath,
    required String fragment,
    required PdfPageLocator locator,
  }) {
    return showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => FormulaSourceSheet(
        pdfPath: pdfPath,
        fragment: fragment,
        locator: locator,
      ),
    );
  }

  @override
  State<FormulaSourceSheet> createState() => _FormulaSourceSheetState();
}

class _FormulaSourceSheetState extends State<FormulaSourceSheet> {
  late final Future<int?> _pageIndex;

  @override
  void initState() {
    super.initState();
    _pageIndex = widget.locator.locate(
      pdfPath: widget.pdfPath,
      fragment: widget.fragment,
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;

    return DraggableScrollableSheet(
      initialChildSize: 0.85,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) => Material(
        color: Theme.of(context).bottomSheetTheme.backgroundColor ??
            scheme.surface,
        child: Column(
          children: [
            const SizedBox(height: 8),
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: scheme.outlineVariant,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            FutureBuilder<int?>(
              future: _pageIndex,
              builder: (context, snapshot) => _Header(
                pageNumber: snapshot.data != null ? snapshot.data! + 1 : null,
                onClose: () => Navigator.of(context).maybePop(),
              ),
            ),
            const Divider(height: 1),
            Expanded(
              child: FutureBuilder<int?>(
                future: _pageIndex,
                builder: (context, snapshot) {
                  if (snapshot.connectionState != ConnectionState.done) {
                    // Localizar la fórmula exige extraer el texto de todas
                    // las páginas del PDF. En un libro largo es un segundo
                    // largo la primera vez; luego el índice queda cacheado.
                    return const LoadingView(
                      message: 'Buscando la fórmula en el libro',
                      detail: 'Se revisan las páginas del archivo original. '
                          'La primera búsqueda es la más lenta.',
                    );
                  }
                  final index = snapshot.data;
                  if (index == null) {
                    return _notFound(context, widget.fragment);
                  }
                  return _PageView(
                    pdfPath: widget.pdfPath,
                    pageNumber: index + 1,
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({required this.onClose, this.pageNumber});

  final int? pageNumber;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 12, 8, 8),
      child: Row(
        children: [
          Icon(Icons.functions_rounded, color: scheme.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Fórmula en el libro',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.w700),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                if (pageNumber != null)
                  Text(
                    'Página $pageNumber',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.onSurfaceVariant,
                    ),
                  ),
              ],
            ),
          ),
          IconButton(
            onPressed: onClose,
            tooltip: 'Cerrar',
            icon: const Icon(Icons.close_rounded),
          ),
        ],
      ),
    );
  }
}

/// Página renderizada, con zoom y desplazamiento.
///
/// El zoom no es un extra: una fórmula ocupa una franja pequeña de la página
/// y en un móvil se ve diminuta si solo se muestra la hoja entera.
class _PageView extends StatefulWidget {
  const _PageView({required this.pdfPath, required this.pageNumber});

  final String pdfPath;
  final int pageNumber;

  @override
  State<_PageView> createState() => _PageViewState();
}

class _PageViewState extends State<_PageView> {
  /// La referencia se crea UNA vez y no dentro de `build`.
  ///
  /// `PdfDocumentRef` no define `operator ==`, así que
  /// `PdfDocumentViewBuilder.didUpdateWidget` compara por identidad y una
  /// instancia nueva le parece otro documento: quita su listener antes de
  /// añadir el nuevo, el contador de referencias llega a cero y pdfrx llama a
  /// `dispose()` sobre el documento. Como esta hoja lee `Theme.of(context)`,
  /// cualquier cambio de tema —incluido el automático del modo programado a
  /// las 20:00— reconstruía el árbol, cerraba el PDF, lo reabría desde cero y
  /// tiraba el zoom que el lector acababa de ajustar sobre la fórmula.
  late final PdfDocumentRefFile _documentRef;

  @override
  void initState() {
    super.initState();
    _documentRef = PdfDocumentRefFile(widget.pdfPath);
  }

  @override
  Widget build(BuildContext context) {
    final pageNumber = widget.pageNumber;
    return PdfDocumentViewBuilder(
      documentRef: _documentRef,
      loadingBuilder: (context) =>
          LoadingView(message: 'Abriendo la página $pageNumber'),
      errorBuilder: (context, error, stackTrace) => const EmptyState(
        icon: Icons.broken_image_outlined,
        title: 'No se pudo abrir el PDF',
        message: 'El archivo puede estar protegido o dañado.',
      ),
      builder: (context, document) {
        if (document == null) {
          return LoadingView(message: 'Abriendo la página $pageNumber');
        }
        return InteractiveViewer(
          maxScale: 6,
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: PdfPageView(
              document: document,
              pageNumber: pageNumber,
              alignment: Alignment.topCenter,
            ),
          ),
        );
      },
    );
  }
}

/// Estado de "no se encontró la página", con la fórmula buscada a la vista.
///
/// Usa [EmptyState] —el componente de estado vacío de la app— en vez de
/// repetir aquí un icono, un título y un subtítulo centrados con sus propios
/// tamaños: eran dos versiones del mismo bloque que había que mantener a mano
/// cada vez que cambiara el criterio visual.
///
/// El fragmento va en el hueco de `action` porque es lo accionable: se puede
/// seleccionar y copiar para buscarlo a mano en el libro.
Widget _notFound(BuildContext context, String fragment) {
  final scheme = Theme.of(context).colorScheme;
  return EmptyState(
    icon: Icons.search_off_rounded,
    title: 'No se encontró la página',
    message: 'La fórmula no coincide con ninguna página del archivo '
        'original. Puede que el libro se haya importado desde otro '
        'formato.',
    action: Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(6),
      ),
      child: SelectableText(
        fragment,
        textAlign: TextAlign.center,
        style: const TextStyle(
          fontSize: 13,
          fontFamily: 'monospace',
          fontFamilyFallback: ['Menlo', 'Consolas'],
        ),
      ),
    ),
  );
}
