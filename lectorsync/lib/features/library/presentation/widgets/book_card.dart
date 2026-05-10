import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../../domain/entities/book.dart';

class BookCard extends StatefulWidget {
  const BookCard({required this.book, this.onTap, super.key});

  final Book book;
  final VoidCallback? onTap;

  @override
  State<BookCard> createState() => _BookCardState();
}

class _BookCardState extends State<BookCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverCtrl;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
      lowerBound: 0,
      upperBound: 1,
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  void _onEnter(PointerEnterEvent _) {
    _hoverCtrl.forward();
  }

  void _onExit(PointerExitEvent _) {
    _hoverCtrl.reverse();
  }

  Color _formatColor(ColorScheme scheme) => switch (widget.book.fileFormat) {
        BookFormat.epub => scheme.primary,
        BookFormat.pdf => const Color(0xFFE53935),
        BookFormat.txt => const Color(0xFF1E88E5),
        BookFormat.md => const Color(0xFF43A047),
      };

  IconData get _formatIcon => switch (widget.book.fileFormat) {
        BookFormat.epub => Icons.menu_book_rounded,
        BookFormat.pdf => Icons.picture_as_pdf_rounded,
        BookFormat.txt => Icons.description_rounded,
        BookFormat.md => Icons.code_rounded,
      };

  String get _semanticLabel {
    final b = widget.book;
    final author = b.author ?? 'Autor desconocido';
    final progress =
        b.progress > 0 ? ' Progreso ${(b.progress * 100).toInt()} porciento.' : '';
    return '${b.title}. $author. ${b.fileFormatLabel}.$progress';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isReading = widget.book.progress > 0 && widget.book.progress < 1;
    final isFinished = widget.book.progress >= 1;
    final elevation = Tween<double>(begin: 1, end: 6).animate(_hoverCtrl);
    final scale = Tween<double>(begin: 1.0, end: 1.03).animate(
      CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOutCubic),
    );

    final coverStack = Stack(
      fit: StackFit.expand,
      children: [
        if (widget.book.coverUrl != null)
          Image.network(
            widget.book.coverUrl!,
            fit: BoxFit.cover,
            errorBuilder: (_, _, _) =>
                _GradientCover(seed: widget.book.title, scheme: scheme),
          )
        else
          _GradientCover(seed: widget.book.title, scheme: scheme),
        Positioned(
          top: 8,
          left: 8,
          child: _Pill(
            icon: _formatIcon,
            label: widget.book.fileFormatLabel,
            background: _formatColor(scheme),
            foreground: Colors.white,
          ),
        ),
        if (isReading)
          Positioned(
            top: 8,
            right: 8,
            child: _Pill(
              icon: Icons.menu_book_rounded,
              label: 'Leyendo',
              background: scheme.primary,
              foreground: scheme.onPrimary,
            ),
          ),
        if (isFinished)
          Positioned(
            top: 8,
            right: 8,
            child: _Pill(
              icon: Icons.check_circle_rounded,
              label: 'Leído',
              background: scheme.tertiary,
              foreground: scheme.onPrimary,
            ),
          ),
        if (widget.book.progress > 0)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: ClipRRect(
              borderRadius: BorderRadius.zero,
              child: LinearProgressIndicator(
                value: widget.book.progress,
                minHeight: 4,
                backgroundColor: Colors.black.withValues(alpha: 0.25),
                valueColor:
                    AlwaysStoppedAnimation<Color>(scheme.primary),
              ),
            ),
          ),
      ],
    );

    final metadata = Padding(
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.book.title,
            style: Theme.of(context).textTheme.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  height: 1.2,
                ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 4),
          Text(
            widget.book.author ?? 'Autor desconocido',
            style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: scheme.onSurfaceVariant,
                ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          if (widget.book.progress > 0) ...[
            const SizedBox(height: 6),
            Text(
              '${(widget.book.progress * 100).toInt()}% completado',
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: scheme.primary,
                    fontWeight: FontWeight.w600,
                  ),
            ),
          ],
        ],
      ),
    );

    return MouseRegion(
      onEnter: _onEnter,
      onExit: _onExit,
      cursor: SystemMouseCursors.click,
      child: AnimatedBuilder(
        animation: _hoverCtrl,
        builder: (context, child) {
          return Transform.scale(
            scale: scale.value,
            child: Card(
              clipBehavior: Clip.antiAlias,
              elevation: elevation.value,
              child: child,
            ),
          );
        },
        child: Semantics(
          button: true,
          label: _semanticLabel,
          child: InkWell(
            onTap: widget.onTap,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(child: coverStack),
                metadata,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _GradientCover extends StatelessWidget {
  const _GradientCover({required this.seed, required this.scheme});

  final String seed;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    final hash = seed.hashCode;
    final palettes = [
      [scheme.primary, scheme.tertiary],
      [scheme.secondary, scheme.primary],
      [scheme.tertiary, scheme.secondary],
      [scheme.primary, scheme.secondary],
    ];
    final colors = palettes[hash.abs() % palettes.length];

    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [colors[0].withValues(alpha: 0.85), colors[1]],
        ),
      ),
      child: Center(
        child: Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                Icons.auto_stories_rounded,
                size: 36,
                color: scheme.onPrimary.withValues(alpha: 0.85),
              ),
              const SizedBox(height: 12),
              Text(
                seed,
                textAlign: TextAlign.center,
                maxLines: 3,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  height: 1.3,
                  letterSpacing: -0.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Pill extends StatelessWidget {
  const _Pill({
    required this.icon,
    required this.label,
    required this.background,
    required this.foreground,
  });

  final IconData icon;
  final String label;
  final Color background;
  final Color foreground;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: foreground),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: foreground,
              fontSize: 10,
              fontWeight: FontWeight.w700,
              letterSpacing: 0.3,
            ),
          ),
        ],
      ),
    );
  }
}