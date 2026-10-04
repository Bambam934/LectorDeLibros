import 'package:equatable/equatable.dart';

import 'chapter_block.dart';

class Chapter extends Equatable {
  const Chapter({
    required this.id,
    required this.title,
    required this.orderIndex,
    required this.wordCount,
    this.text,
    this.words = const [],
    this.blocks = const [],
  });

  factory Chapter.fromSummaryJson(Map<String, dynamic> json) {
    return Chapter(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Sin titulo',
      orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
      wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
    );
  }

  factory Chapter.fromDetailJson(Map<String, dynamic> json) {
    final rawText = (json['text'] as String?) ?? '';
    return Chapter(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Sin titulo',
      orderIndex: (json['order_index'] as num?)?.toInt() ?? 0,
      wordCount: (json['word_count'] as num?)?.toInt() ?? 0,
      text: rawText,
      words: _tokenizeWords(rawText),
    );
  }

  final String id;
  final String title;
  final int orderIndex;
  final int wordCount;
  final String? text;
  final List<String> words;

  /// Maquetación del capítulo (ADR 13), o vacía si no la tiene.
  ///
  /// Con bloques, [text] es la unión de sus textos separados por una línea en
  /// blanco ([textOfBlocks]) y la pantalla pinta desde aquí, no desde
  /// [paragraphs]: el código lleva líneas en blanco dentro y partirlo por
  /// ellas lo rompería.
  final List<ChapterBlock> blocks;

  /// Texto de un capítulo con [blocks]. Sus palabras son, en orden, las de
  /// cada bloque, así que los índices de palabra de los bloques cuadran con
  /// [words].
  static String textOfBlocks(List<ChapterBlock> blocks) =>
      blocks.map((b) => b.text).join('\n\n');

  List<String> get paragraphs {
    final content = text;
    if (content == null || content.trim().isEmpty) {
      return const [];
    }

    return content
        .split(RegExp(r'\n\s*\n'))
        .map((paragraph) => paragraph.trim())
        .where((paragraph) => paragraph.isNotEmpty)
        .toList(growable: false);
  }

  static List<String> _tokenizeWords(String content) {
    return content
        .split(RegExp(r'\s+'))
        .map((word) => word.trim())
        .where((word) => word.isNotEmpty)
        .toList(growable: false);
  }

  @override
  List<Object?> get props =>
      [id, title, orderIndex, wordCount, text, words, blocks];
}
