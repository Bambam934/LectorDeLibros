import 'package:equatable/equatable.dart';

/// A coloured text highlight inside a chapter — lighter weight than a
/// full bookmark (no note, no list of all highlights at the top of the
/// reader). Used to mark passages while reading without breaking flow.
///
/// Highlights are stored locally per-book and identified by the
/// `[startWordIndex, endWordIndex)` range within the chapter.
class Highlight extends Equatable {
  const Highlight({
    required this.id,
    required this.bookId,
    required this.chapterId,
    required this.startWordIndex,
    required this.endWordIndex,
    required this.colorIndex,
    required this.snippet,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final String chapterId;
  final int startWordIndex;
  final int endWordIndex;
  /// Index into [HighlightColors.palette]. We store an index (not a
  /// raw colour value) so the rendered colour adapts to light/dark
  /// theme.
  final int colorIndex;
  final String snippet;
  final DateTime createdAt;

  Highlight copyWith({
    int? colorIndex,
  }) {
    return Highlight(
      id: id,
      bookId: bookId,
      chapterId: chapterId,
      startWordIndex: startWordIndex,
      endWordIndex: endWordIndex,
      colorIndex: colorIndex ?? this.colorIndex,
      snippet: snippet,
      createdAt: createdAt,
    );
  }

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'chapterId': chapterId,
        'startWordIndex': startWordIndex,
        'endWordIndex': endWordIndex,
        'colorIndex': colorIndex,
        'snippet': snippet,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Highlight.fromJson(Map<String, dynamic> json) {
    return Highlight(
      id: json['id'] as String,
      bookId: json['bookId'] as String,
      chapterId: json['chapterId'] as String,
      startWordIndex: (json['startWordIndex'] as num).toInt(),
      endWordIndex: (json['endWordIndex'] as num).toInt(),
      colorIndex: (json['colorIndex'] as num?)?.toInt() ?? 0,
      snippet: (json['snippet'] as String?) ?? '',
      createdAt: DateTime.tryParse(json['createdAt'] as String? ?? '') ??
          DateTime.now(),
    );
  }

  @override
  List<Object?> get props => [
        id,
        bookId,
        chapterId,
        startWordIndex,
        endWordIndex,
        colorIndex,
      ];
}

/// Fixed 4-colour highlight palette (yellow / green / pink / blue).
/// Index 0 is the default (yellow) when the user taps the highlight
/// action without choosing a colour.
class HighlightColors {
  static const palette = <_HighlightColor>[
    _HighlightColor(name: 'Amarillo', light: 0xFFFFF59D, dark: 0xFF665A14),
    _HighlightColor(name: 'Verde', light: 0xFFC8E6C9, dark: 0xFF1F4D24),
    _HighlightColor(name: 'Rosa', light: 0xFFF8BBD0, dark: 0xFF5C2436),
    _HighlightColor(name: 'Azul', light: 0xFFBBDEFB, dark: 0xFF1D3557),
  ];
}

class _HighlightColor {
  const _HighlightColor({
    required this.name,
    required this.light,
    required this.dark,
  });
  final String name;
  final int light;
  final int dark;
}
