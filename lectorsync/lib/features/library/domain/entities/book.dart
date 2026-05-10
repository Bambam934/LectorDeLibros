import 'package:equatable/equatable.dart';

enum BookFormat { epub, pdf, txt, md }

class Book extends Equatable {
  const Book({
    required this.id,
    required this.title,
    this.author,
    this.coverUrl,
    this.fileFormat = BookFormat.epub,
    this.totalChapters = 0,
    this.totalWords = 0,
    this.progress = 0.0,
    this.progressChapterId,
    this.progressWordIndex = 0,
  });

  factory Book.fromJson(Map<String, dynamic> json) {
    final progressJson = json['progress'];
    double progress = 0.0;
    String? progressChapterId;
    int progressWordIndex = 0;
    if (progressJson is Map<String, dynamic>) {
      final raw = progressJson['percentage'];
      if (raw is num) progress = (raw.toDouble() / 100.0).clamp(0.0, 1.0);

      final chapterId = progressJson['chapter_id'];
      if (chapterId is String && chapterId.isNotEmpty) {
        progressChapterId = chapterId;
      }

      final wordIndex = progressJson['word_index'];
      if (wordIndex is num) {
        progressWordIndex = wordIndex.toInt();
      }
    }

    final rawFormat = json['file_format'] as String? ?? 'epub';
    final fileFormat = BookFormat.values.firstWhere(
      (e) => e.name == rawFormat,
      orElse: () => BookFormat.epub,
    );

    return Book(
      id: json['id'] as String,
      title: (json['title'] as String?) ?? 'Sin título',
      author: json['author'] as String?,
      coverUrl: json['cover_url'] as String?,
      fileFormat: fileFormat,
      totalChapters: (json['total_chapters'] as int?) ?? 0,
      totalWords: (json['total_words'] as int?) ?? 0,
      progress: progress,
      progressChapterId: progressChapterId,
      progressWordIndex: progressWordIndex,
    );
  }

  final String id;
  final String title;
  final String? author;
  final String? coverUrl;
  final BookFormat fileFormat;
  final int totalChapters;
  final int totalWords;
  final double progress;
  final String? progressChapterId;
  final int progressWordIndex;

  String get fileFormatLabel => switch (fileFormat) {
    BookFormat.epub => 'EPUB',
    BookFormat.pdf => 'PDF',
    BookFormat.txt => 'TXT',
    BookFormat.md => 'MD',
  };

  @override
  List<Object?> get props => [
    id,
    title,
    author,
    coverUrl,
    fileFormat,
    totalChapters,
    totalWords,
    progress,
    progressChapterId,
    progressWordIndex,
  ];
}
