import 'package:equatable/equatable.dart';

class Chapter extends Equatable {
  const Chapter({
    required this.id,
    required this.title,
    required this.orderIndex,
    required this.wordCount,
    this.text,
    this.words = const [],
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
  List<Object?> get props => [id, title, orderIndex, wordCount, text, words];
}
