import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../domain/entities/reading_preferences.dart';
import '../cubit/preferences_cubit.dart';

/// Modal bottom sheet that lets the user customize reader typography & palette.
///
/// Show with:
/// ```dart
/// showModalBottomSheet(
///   context: context,
///   isScrollControlled: true,
///   builder: (_) => const ReadingCustomizationSheet(),
/// );
/// ```
class ReadingCustomizationSheet extends StatelessWidget {
  const ReadingCustomizationSheet({super.key});

  @override
  Widget build(BuildContext context) {
    final cubit = context.read<PreferencesCubit>();

    return DraggableScrollableSheet(
      initialChildSize: 0.7,
      minChildSize: 0.4,
      maxChildSize: 0.95,
      expand: false,
      builder: (context, scrollController) {
        return BlocBuilder<PreferencesCubit, ReadingPreferences>(
          builder: (context, prefs) {
            return SingleChildScrollView(
              controller: scrollController,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Icon(
                        Icons.tune_rounded,
                        color: Theme.of(context).colorScheme.primary,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Text(
                          'Personalizar lectura',
                          style: Theme.of(context).textTheme.titleLarge,
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      TextButton.icon(
                        onPressed: cubit.resetToDefaults,
                        icon: const Icon(Icons.restart_alt_rounded, size: 18),
                        label: const Text('Restablecer'),
                      ),
                    ],
                  ),
                  const SizedBox(height: 24),

                  // ── Palette presets ──
                  _SectionLabel('Paleta de página'),
                  const SizedBox(height: 12),
                  _PaletteSelector(
                    value: prefs.palette,
                    onChanged: cubit.setPalette,
                  ),
                  const SizedBox(height: 24),

                  // ── Font family ──
                  _SectionLabel('Tipografía'),
                  const SizedBox(height: 12),
                  SegmentedButton<ReadingFontFamily>(
                    segments: const [
                      ButtonSegment(
                        value: ReadingFontFamily.serif,
                        label: Text('Serif'),
                      ),
                      ButtonSegment(
                        value: ReadingFontFamily.sansSerif,
                        label: Text('Sans'),
                      ),
                      ButtonSegment(
                        value: ReadingFontFamily.mono,
                        label: Text('Mono'),
                      ),
                    ],
                    selected: {prefs.fontFamily},
                    onSelectionChanged: (s) => cubit.setFontFamily(s.first),
                  ),
                  const SizedBox(height: 24),

                  // ── Font size ──
                  _SliderRow(
                    label: 'Tamaño',
                    valueLabel: '${prefs.fontSize.toInt()} pt',
                    value: prefs.fontSize,
                    min: 14,
                    max: 32,
                    divisions: 18,
                    onChanged: cubit.setFontSize,
                  ),

                  // ── Line height ──
                  _SliderRow(
                    label: 'Interlineado',
                    valueLabel: prefs.lineHeight.toStringAsFixed(2),
                    value: prefs.lineHeight,
                    min: 1.3,
                    max: 2.4,
                    divisions: 22,
                    onChanged: cubit.setLineHeight,
                  ),

                  // ── Letter spacing ──
                  _SliderRow(
                    label: 'Espaciado',
                    valueLabel: prefs.letterSpacing.toStringAsFixed(2),
                    value: prefs.letterSpacing,
                    min: 0,
                    max: 1.5,
                    divisions: 15,
                    onChanged: cubit.setLetterSpacing,
                  ),

                  const SizedBox(height: 16),

                  // ── Justify ──
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Texto justificado'),
                    subtitle: const Text(
                      'Distribuye el espacio para alinear ambos márgenes',
                    ),
                    value: prefs.justifyText,
                    onChanged: cubit.setJustifyText,
                  ),

                  const SizedBox(height: 16),

                  // ── Column width (mostly desktop) ──
                  _SectionLabel('Ancho de columna'),
                  const SizedBox(height: 8),
                  Wrap(
                    spacing: 8,
                    children: [
                      _WidthChip(
                        label: 'Estrecha',
                        value: 480,
                        current: prefs.maxColumnWidth,
                        onSelected: cubit.setMaxColumnWidth,
                      ),
                      _WidthChip(
                        label: 'Media',
                        value: 600,
                        current: prefs.maxColumnWidth,
                        onSelected: cubit.setMaxColumnWidth,
                      ),
                      _WidthChip(
                        label: 'Ancha',
                        value: 720,
                        current: prefs.maxColumnWidth,
                        onSelected: cubit.setMaxColumnWidth,
                      ),
                      _WidthChip(
                        label: 'Completa',
                        value: double.infinity,
                        current: prefs.maxColumnWidth,
                        onSelected: cubit.setMaxColumnWidth,
                      ),
                    ],
                  ),

                  const SizedBox(height: 24),
                  // ── Live preview ──
                  _SectionLabel('Vista previa'),
                  const SizedBox(height: 8),
                  _PreviewBox(prefs: prefs),
                ],
              ),
            );
          },
        );
      },
    );
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;
  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: Theme.of(context).textTheme.labelLarge?.copyWith(
        color: Theme.of(context).colorScheme.onSurfaceVariant,
        letterSpacing: 0.6,
      ),
    );
  }
}

class _SliderRow extends StatelessWidget {
  const _SliderRow({
    required this.label,
    required this.valueLabel,
    required this.value,
    required this.min,
    required this.max,
    required this.divisions,
    required this.onChanged,
  });

  final String label;
  final String valueLabel;
  final double value;
  final double min;
  final double max;
  final int divisions;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label),
            const Spacer(),
            Text(
              valueLabel,
              style: TextStyle(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
                fontFeatures: const [FontFeature.tabularFigures()],
              ),
            ),
          ],
        ),
        Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          onChanged: onChanged,
        ),
      ],
    );
  }
}

class _WidthChip extends StatelessWidget {
  const _WidthChip({
    required this.label,
    required this.value,
    required this.current,
    required this.onSelected,
  });

  final String label;
  final double value;
  final double current;
  final ValueChanged<double> onSelected;

  @override
  Widget build(BuildContext context) {
    return ChoiceChip(
      label: Text(label),
      selected: current == value,
      onSelected: (_) => onSelected(value),
    );
  }
}

class _PaletteSelector extends StatelessWidget {
  const _PaletteSelector({required this.value, required this.onChanged});

  final ReadingPalette value;
  final ValueChanged<ReadingPalette> onChanged;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return SizedBox(
      height: 84,
      child: ListView(
        scrollDirection: Axis.horizontal,
        children: ReadingPalette.values.map((palette) {
          final colors = ReadingPaletteColors.resolve(palette, scheme);
          final isSelected = palette == value;
          return Padding(
            padding: const EdgeInsets.only(right: 12),
            child: _PaletteSwatch(
              colors: colors,
              label: _paletteLabel(palette),
              selected: isSelected,
              onTap: () => onChanged(palette),
            ),
          );
        }).toList(),
      ),
    );
  }

  String _paletteLabel(ReadingPalette p) {
    switch (p) {
      case ReadingPalette.followApp:
        return 'Auto';
      case ReadingPalette.paper:
        return 'Papel';
      case ReadingPalette.sepia:
        return 'Sepia';
      case ReadingPalette.solarized:
        return 'Solar';
      case ReadingPalette.midnight:
        return 'Noche';
      case ReadingPalette.forest:
        return 'Bosque';
    }
  }
}

class _PaletteSwatch extends StatelessWidget {
  const _PaletteSwatch({
    required this.colors,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final ReadingPaletteColors colors;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        width: 76,
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: selected ? scheme.primary : scheme.outlineVariant,
            width: selected ? 2 : 1,
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: Stack(
          children: [
            Container(color: colors.background),
            Positioned(
              left: 8,
              top: 10,
              right: 8,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Container(
                    height: 4,
                    width: 36,
                    color: colors.foreground,
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 4,
                    width: 50,
                    color: colors.foreground.withValues(alpha: 0.6),
                  ),
                  const SizedBox(height: 4),
                  Container(
                    height: 4,
                    width: 28,
                    color: colors.accent,
                  ),
                ],
              ),
            ),
            Positioned(
              bottom: 6,
              left: 0,
              right: 0,
              child: Center(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.w600,
                    color: colors.foreground,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PreviewBox extends StatelessWidget {
  const _PreviewBox({required this.prefs});
  final ReadingPreferences prefs;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final colors = ReadingPaletteColors.resolve(prefs.palette, scheme);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colors.background,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Text(
        'En un lugar de la Mancha, de cuyo nombre no quiero acordarme, '
        'no ha mucho tiempo que vivía un hidalgo de los de lanza en astillero.',
        textAlign: prefs.textAlign,
        style: TextStyle(
          color: colors.foreground,
          fontSize: prefs.fontSize,
          height: prefs.lineHeight,
          letterSpacing: prefs.letterSpacing,
          fontFamily: prefs.fontFamilyName,
        ),
      ),
    );
  }
}
