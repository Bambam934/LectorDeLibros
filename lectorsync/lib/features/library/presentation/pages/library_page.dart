import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import '../../../../core/constants/route_constants.dart';
import '../../../../core/di/injection_container.dart';
import '../../../../core/layout/breakpoints.dart';
import '../../../../core/theme/theme_cubit.dart';
import '../../../../shared/widgets/empty_state.dart';
import '../../../auth/presentation/cubit/auth_cubit.dart';
import '../../domain/entities/book.dart';
import '../bloc/library_bloc.dart';
import '../bloc/library_event.dart';
import '../bloc/library_state.dart';
import '../widgets/book_card.dart';

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          LibraryBloc(libraryRepository: sl())..add(LibraryFetched()),
      child: const _LibraryView(),
    );
  }
}

class _LibraryView extends StatefulWidget {
  const _LibraryView();

  @override
  State<_LibraryView> createState() => _LibraryViewState();
}

class _LibraryViewState extends State<_LibraryView> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  int _selectedNavIndex = 0;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _importBook(BuildContext context) async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['epub', 'pdf', 'txt', 'md'],
      withData: true,
    );

    if (result == null || result.files.isEmpty) return;
    final picked = result.files.single;
    final bytes = picked.bytes;

    if (bytes == null) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('No se pudo leer el archivo seleccionado.'),
          ),
        );
      }
      return;
    }

    if (context.mounted) {
      context.read<LibraryBloc>().add(
            LibraryBookImported(filename: picked.name, bytes: bytes),
          );
    }
  }

  void _openBook(BuildContext context, Book book) {
    context
        .push(
      RouteConstants.bookRead(book.id),
      extra: {
        'bookTitle': book.title,
        'initialChapterId': book.progressChapterId,
        'initialWordIndex': book.progressWordIndex,
      },
    )
        .then((_) {
      if (!context.mounted) return;
      context.read<LibraryBloc>().add(LibraryFetched());
    });
  }

  List<Book> _filterBooks(List<Book> books) {
    if (_searchQuery.trim().isEmpty) return books;
    final q = _searchQuery.toLowerCase();
    return books.where((b) {
      return b.title.toLowerCase().contains(q) ||
          (b.author?.toLowerCase().contains(q) ?? false);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final bp = breakpointOf(context);

    return Scaffold(
      body: SafeArea(
        child: BlocConsumer<LibraryBloc, LibraryState>(
          listenWhen: (prev, curr) =>
              curr.status == LibraryStatus.failure &&
              prev.errorMessage != curr.errorMessage,
          listener: (context, state) {
            if (state.errorMessage != null) {
              ScaffoldMessenger.of(context)
                  .showSnackBar(SnackBar(content: Text(state.errorMessage!)));
            }
          },
          builder: (context, state) {
            if (state.status == LibraryStatus.loading && state.books.isEmpty) {
              return const Center(child: CircularProgressIndicator());
            }

            return bp.when(
              compact: () => _CompactLayout(
                searchController: _searchController,
                searchQuery: _searchQuery,
                onSearchChanged: (v) => setState(() => _searchQuery = v),
                onImport: () => _importBook(context),
                onOpenBook: (b) => _openBook(context, b),
                state: state,
                filtered: _filterBooks(state.books),
              ),
              medium: () => _MediumLayout(
                searchController: _searchController,
                searchQuery: _searchQuery,
                onSearchChanged: (v) => setState(() => _searchQuery = v),
                onImport: () => _importBook(context),
                onOpenBook: (b) => _openBook(context, b),
                state: state,
                filtered: _filterBooks(state.books),
              ),
              expanded: () => _ExpandedLayout(
                searchController: _searchController,
                searchQuery: _searchQuery,
                onSearchChanged: (v) => setState(() => _searchQuery = v),
                onImport: () => _importBook(context),
                onOpenBook: (b) => _openBook(context, b),
                state: state,
                filtered: _filterBooks(state.books),
                selectedNavIndex: _selectedNavIndex,
                onNavIndexChanged: (i) => setState(() => _selectedNavIndex = i),
              ),
            );
          },
        ),
      ),
    );
  }
}

// ── Compact (<600): single-column mobile layout ──

class _CompactLayout extends StatelessWidget {
  const _CompactLayout({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onImport,
    required this.onOpenBook,
    required this.state,
    required this.filtered,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onImport;
  final ValueChanged<Book> onOpenBook;
  final LibraryState state;
  final List<Book> filtered;

  @override
  Widget build(BuildContext context) {
  final readingBooks = state.books
      .where((b) => b.progress > 0 && b.progress < 1)
      .toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
  final continueReading =
      readingBooks.isNotEmpty ? readingBooks.first : null;

  return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: _LibraryTopBar(onImport: onImport),
        ),
        SliverToBoxAdapter(
          child: _SearchField(
            controller: searchController,
            onChanged: onSearchChanged,
            searchQuery: searchQuery,
            onCleared: () {
              searchController.clear();
              onSearchChanged('');
            },
          ),
        ),
        if (continueReading != null && searchQuery.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
              child: _ContinueReadingHero(
                book: continueReading,
                onTap: () => onOpenBook(continueReading),
              ),
            ),
          ),
        if (state.books.isNotEmpty)
          SliverToBoxAdapter(
            child: _SectionHeader(
              title: searchQuery.isEmpty
                  ? 'Mi biblioteca'
                  : '${filtered.length} resultado(s)',
              count: state.books.length,
            ),
          ),
        if (state.books.isEmpty)
          SliverFillRemaining(
            hasScrollBody: false,
            child: _EmptyLibrary(onImport: onImport),
          )
        else if (filtered.isEmpty)
          const SliverFillRemaining(
            hasScrollBody: false,
            child: EmptyState(
              icon: Icons.search_off_rounded,
              title: 'Sin resultados',
              message: 'Prueba con otro título o autor.',
            ),
          )
        else
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 32),
            sliver: _BookGrid(
              books: filtered,
              maxExtent: 200,
              onTap: onOpenBook,
            ),
          ),
      ],
    );
  }
}

// ── Medium (600-1199): wider grid, side search panel ──

class _MediumLayout extends StatelessWidget {
  const _MediumLayout({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onImport,
    required this.onOpenBook,
    required this.state,
    required this.filtered,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onImport;
  final ValueChanged<Book> onOpenBook;
  final LibraryState state;
  final List<Book> filtered;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final readingBooks = state.books
        .where((b) => b.progress > 0 && b.progress < 1)
        .toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    final continueReading =
        readingBooks.isNotEmpty ? readingBooks.first : null;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Sidebar
        SizedBox(
          width: 280,
          child: CustomScrollView(
            slivers: [
              SliverToBoxAdapter(child: _LibraryTopBar(onImport: onImport)),
              SliverToBoxAdapter(
                child: _SearchField(
                  controller: searchController,
                  onChanged: onSearchChanged,
                  searchQuery: searchQuery,
                  onCleared: () {
                    searchController.clear();
                    onSearchChanged('');
                  },
                ),
              ),
              if (continueReading != null && searchQuery.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                    child: _ContinueReadingHero(
                      book: continueReading,
                      onTap: () => onOpenBook(continueReading),
                    ),
                  ),
                ),
            ],
          ),
        ),
        // Vertical divider
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        // Main grid area
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (state.books.isNotEmpty)
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: searchQuery.isEmpty
                        ? 'Mi biblioteca'
                        : '${filtered.length} resultado(s)',
                    count: state.books.length,
                  ),
                ),
              if (state.books.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyLibrary(onImport: onImport),
                )
              else if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Sin resultados',
                    message: 'Prueba con otro título o autor.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(20, 12, 20, 32),
                  sliver: _BookGrid(
                    books: filtered,
                    maxExtent: 220,
                    onTap: onOpenBook,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

// ── Expanded (≥1200): NavigationRail + detail panel ──

class _ExpandedLayout extends StatelessWidget {
  const _ExpandedLayout({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.onImport,
    required this.onOpenBook,
    required this.state,
    required this.filtered,
    required this.selectedNavIndex,
    required this.onNavIndexChanged,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onImport;
  final ValueChanged<Book> onOpenBook;
  final LibraryState state;
  final List<Book> filtered;
  final int selectedNavIndex;
  final ValueChanged<int> onNavIndexChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final readingBooks = state.books
        .where((b) => b.progress > 0 && b.progress < 1)
        .toList()
      ..sort((a, b) => b.progress.compareTo(a.progress));
    final continueReading =
        readingBooks.isNotEmpty ? readingBooks.first : null;

    return Row(
      children: [
        NavigationRail(
          selectedIndex: selectedNavIndex,
          onDestinationSelected: onNavIndexChanged,
          labelType: NavigationRailLabelType.all,
          leading: Padding(
            padding: const EdgeInsets.only(top: 16, bottom: 8),
            child: IconButton.filledTonal(
              onPressed: onImport,
              icon: const Icon(Icons.add_rounded),
              tooltip: 'Importar libro',
            ),
          ),
          destinations: const [
            NavigationRailDestination(
              icon: Icon(Icons.auto_stories_rounded),
              label: Text('Biblioteca'),
            ),
            NavigationRailDestination(
              icon: Icon(Icons.search_rounded),
              label: Text('Buscar'),
            ),
          ],
        ),
        // Sidebar panel
        SizedBox(
          width: 320,
          child: _ExpandedSidebar(
            searchController: searchController,
            searchQuery: searchQuery,
            onSearchChanged: onSearchChanged,
            continueReading: continueReading,
            onOpenBook: onOpenBook,
            selectedIndex: selectedNavIndex,
            scheme: scheme,
          ),
        ),
        VerticalDivider(width: 1, color: scheme.outlineVariant),
        // Main grid
        Expanded(
          child: CustomScrollView(
            slivers: [
              if (state.books.isNotEmpty)
                SliverToBoxAdapter(
                  child: _SectionHeader(
                    title: searchQuery.isEmpty
                        ? 'Mi biblioteca'
                        : '${filtered.length} resultado(s)',
                    count: state.books.length,
                  ),
                ),
              if (state.books.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: _EmptyLibrary(onImport: onImport),
                )
              else if (filtered.isEmpty)
                const SliverFillRemaining(
                  hasScrollBody: false,
                  child: EmptyState(
                    icon: Icons.search_off_rounded,
                    title: 'Sin resultados',
                    message: 'Prueba con otro título o autor.',
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(24, 12, 24, 32),
                  sliver: _BookGrid(
                    books: filtered,
                    maxExtent: 240,
                    onTap: onOpenBook,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ExpandedSidebar extends StatelessWidget {
  const _ExpandedSidebar({
    required this.searchController,
    required this.searchQuery,
    required this.onSearchChanged,
    required this.continueReading,
    required this.onOpenBook,
    required this.selectedIndex,
    required this.scheme,
  });

  final TextEditingController searchController;
  final String searchQuery;
  final ValueChanged<String> onSearchChanged;
  final Book? continueReading;
  final ValueChanged<Book> onOpenBook;
  final int selectedIndex;
  final ColorScheme scheme;

  @override
  Widget build(BuildContext context) {
    if (selectedIndex == 1) {
      return Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const SizedBox(height: 16),
            Text(
              'Buscar',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
            ),
            const SizedBox(height: 16),
            _SearchField(
              controller: searchController,
              onChanged: onSearchChanged,
              searchQuery: searchQuery,
              onCleared: () {
                searchController.clear();
                onSearchChanged('');
              },
            ),
          ],
        ),
      );
    }

    // Library tab
    return CustomScrollView(
      slivers: [
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 24, 20, 8),
            child: Text(
              '¿Qué leemos hoy?',
              style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                    fontWeight: FontWeight.w800,
                    letterSpacing: -0.4,
                  ),
            ),
          ),
        ),
        if (continueReading != null && searchQuery.isEmpty)
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
              child: _ContinueReadingHero(
                book: continueReading!,
                onTap: () => onOpenBook(continueReading!),
              ),
            ),
          ),
        SliverToBoxAdapter(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
            child: _SearchField(
              controller: searchController,
              onChanged: onSearchChanged,
              searchQuery: searchQuery,
              onCleared: () {
                searchController.clear();
                onSearchChanged('');
              },
            ),
          ),
        ),
      ],
    );
  }
}

// ── Shared widgets ──

class _LibraryTopBar extends StatelessWidget {
  const _LibraryTopBar({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 16, 12, 16),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Hola de nuevo,',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: scheme.onSurfaceVariant,
                      ),
                ),
                const SizedBox(height: 2),
                Text(
                  '¿Qué leemos hoy?',
                  style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w800,
                        letterSpacing: -0.4,
                      ),
                ),
              ],
            ),
          ),
          IconButton.filledTonal(
            onPressed: onImport,
            icon: const Icon(Icons.add_rounded),
            tooltip: 'Importar libro',
          ),
          const SizedBox(width: 4),
        BlocBuilder<ThemeCubit, ThemeMode>(
          builder: (context, mode) {
            return AnimatedSwitcher(
              duration: const Duration(milliseconds: 300),
              switchInCurve: Curves.easeOutCubic,
              switchOutCurve: Curves.easeInCubic,
              child: IconButton(
                key: ValueKey(mode),
                onPressed: () => context.read<ThemeCubit>().cycle(),
                icon: Icon(_iconForMode(mode)),
                tooltip: 'Tema (${_labelForMode(mode)})',
              ),
            );
          },
        ),
          IconButton(
            icon: const Icon(Icons.logout_rounded),
            onPressed: () => context.read<AuthCubit>().logout(),
            tooltip: 'Cerrar sesión',
          ),
        ],
      ),
    );
  }

  IconData _iconForMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => Icons.brightness_auto_rounded,
      ThemeMode.light => Icons.light_mode_rounded,
      ThemeMode.dark => Icons.dark_mode_rounded,
    };
  }

  String _labelForMode(ThemeMode mode) {
    return switch (mode) {
      ThemeMode.system => 'Sistema',
      ThemeMode.light => 'Claro',
      ThemeMode.dark => 'Oscuro',
    };
  }
}

class _SearchField extends StatelessWidget {
  const _SearchField({
    required this.controller,
    required this.onChanged,
    required this.searchQuery,
    required this.onCleared,
  });

  final TextEditingController controller;
  final ValueChanged<String> onChanged;
  final String searchQuery;
  final VoidCallback onCleared;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
      child: TextField(
        controller: controller,
        onChanged: onChanged,
        decoration: InputDecoration(
          hintText: 'Buscar título o autor…',
          prefixIcon: const Icon(Icons.search_rounded),
          suffixIcon: searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: onCleared,
                )
              : null,
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader({required this.title, required this.count});

  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
      child: Row(
        children: [
          Text(
            title,
            style: Theme.of(context)
                .textTheme
                .titleMedium
                ?.copyWith(fontWeight: FontWeight.w700),
          ),
          const Spacer(),
          Text(
            '$count libros',
            style: Theme.of(context)
                .textTheme
                .labelMedium
                ?.copyWith(color: scheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

class _BookGrid extends StatelessWidget {
  const _BookGrid({
    required this.books,
    required this.maxExtent,
    required this.onTap,
  });

  final List<Book> books;
  final double maxExtent;
  final ValueChanged<Book> onTap;

  @override
  Widget build(BuildContext context) {
    return SliverGrid(
      gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
        maxCrossAxisExtent: maxExtent,
        childAspectRatio: 0.62,
        crossAxisSpacing: 14,
        mainAxisSpacing: 14,
      ),
      delegate: SliverChildBuilderDelegate(
        (context, index) {
          final book = books[index];
          return BookCard(
            book: book,
            onTap: () => onTap(book),
          );
        },
        childCount: books.length,
      ),
    );
  }
}

class _EmptyLibrary extends StatelessWidget {
  const _EmptyLibrary({required this.onImport});

  final VoidCallback onImport;

  @override
  Widget build(BuildContext context) {
    return EmptyState(
      icon: Icons.auto_stories_rounded,
      title: 'Tu biblioteca está vacía',
      message:
          'Importa tu primer libro (EPUB, PDF, TXT o Markdown) y empieza a escuchar mientras lees.',
      action: FilledButton.icon(
        onPressed: onImport,
        icon: const Icon(Icons.file_upload_outlined),
        label: const Text('Importar libro'),
      ),
    );
  }
}

class _ContinueReadingHero extends StatefulWidget {
  const _ContinueReadingHero({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  State<_ContinueReadingHero> createState() => _ContinueReadingHeroState();
}

class _ContinueReadingHeroState extends State<_ContinueReadingHero>
    with SingleTickerProviderStateMixin {
  late final AnimationController _hoverCtrl;

  @override
  void initState() {
    super.initState();
    _hoverCtrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 200),
    );
  }

  @override
  void dispose() {
    _hoverCtrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final scale = Tween<double>(begin: 1.0, end: 1.02).animate(
      CurvedAnimation(parent: _hoverCtrl, curve: Curves.easeOutCubic),
    );

    return MouseRegion(
      onEnter: (_) => _hoverCtrl.forward(),
      onExit: (_) => _hoverCtrl.reverse(),
      cursor: SystemMouseCursors.click,
      child: AnimatedBuilder(
        animation: _hoverCtrl,
        builder: (context, child) {
          return Transform.scale(scale: scale.value, child: child);
        },
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: widget.onTap,
            borderRadius: BorderRadius.circular(20),
            child: Ink(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [scheme.primary, scheme.tertiary],
                ),
                borderRadius: BorderRadius.circular(20),
                boxShadow: [
                  BoxShadow(
                    color: scheme.primary.withValues(alpha: 0.25),
                    blurRadius: 24,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(
                  children: [
                    Container(
                      width: 64,
                      height: 92,
                      decoration: BoxDecoration(
                        color: scheme.onPrimary.withValues(alpha: 0.15),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: widget.book.coverUrl != null
                          ? ClipRRect(
                              borderRadius: BorderRadius.circular(8),
                              child: Image.network(widget.book.coverUrl!, fit: BoxFit.cover),
                            )
                          : Icon(
                              Icons.auto_stories_rounded,
                              color: scheme.onPrimary.withValues(alpha: 0.85),
                              size: 32,
                            ),
                    ),
                    const SizedBox(width: 16),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'CONTINUAR LEYENDO',
                            style: TextStyle(
                              color: scheme.onPrimary.withValues(alpha: 0.8),
                              fontSize: 10,
                              fontWeight: FontWeight.w700,
                              letterSpacing: 1.2,
                            ),
                          ),
                          const SizedBox(height: 6),
                          Text(
                            widget.book.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onPrimary,
                              fontSize: 17,
                              fontWeight: FontWeight.w800,
                              height: 1.2,
                              letterSpacing: -0.2,
                            ),
                          ),
                          const SizedBox(height: 4),
                          Text(
                            widget.book.author ?? 'Autor desconocido',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: scheme.onPrimary.withValues(alpha: 0.85),
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 10),
                          Row(
                            children: [
                              Expanded(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(99),
                                  child: LinearProgressIndicator(
                                    value: widget.book.progress,
                                    minHeight: 5,
                                    backgroundColor: scheme.onPrimary
                                        .withValues(alpha: 0.25),
                                    valueColor: AlwaysStoppedAnimation<Color>(
                                        scheme.onPrimary),
                                  ),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                '${(widget.book.progress * 100).toInt()}%',
                                style: TextStyle(
                                  color: scheme.onPrimary,
                                  fontSize: 12,
                                  fontWeight: FontWeight.w700,
                                  fontFeatures: const [
                                    FontFeature.tabularFigures(),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    Container(
                      width: 44,
                      height: 44,
                      decoration: BoxDecoration(
                        color: scheme.onPrimary.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Icons.play_arrow_rounded,
                        color: scheme.onPrimary,
                        size: 28,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
