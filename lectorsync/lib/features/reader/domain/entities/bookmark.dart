import 'package:equatable/equatable.dart';

class Bookmark extends Equatable {
  const Bookmark({
    required this.id,
    required this.bookId,
    required this.chapterId,
    required this.chapterTitle,
    required this.wordIndex,
    required this.snippet,
    this.note,
    required this.createdAt,
  });

  final String id;
  final String bookId;
  final String chapterId;
  final String chapterTitle;
  final int wordIndex;

  /// Short text excerpt around the bookmarked position.
  final String snippet;

  /// Optional user note attached to the bookmark.
  final String? note;

  final DateTime createdAt;

  Bookmark copyWith({String? note}) => Bookmark(
        id: id,
        bookId: bookId,
        chapterId: chapterId,
        chapterTitle: chapterTitle,
        wordIndex: wordIndex,
        snippet: snippet,
        note: note ?? this.note,
        createdAt: createdAt,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'bookId': bookId,
        'chapterId': chapterId,
        'chapterTitle': chapterTitle,
        'wordIndex': wordIndex,
        'snippet': snippet,
        'note': note,
        'createdAt': createdAt.toIso8601String(),
      };

  factory Bookmark.fromJson(Map<String, dynamic> json) => Bookmark(
        id: json['id'] as String,
        bookId: json['bookId'] as String,
        chapterId: json['chapterId'] as String,
        chapterTitle: (json['chapterTitle'] as String?) ?? '',
        wordIndex: (json['wordIndex'] as num).toInt(),
        snippet: (json['snippet'] as String?) ?? '',
        note: json['note'] as String?,
        createdAt: DateTime.parse(json['createdAt'] as String),
      );

  @override
  List<Object?> get props => [id, bookId, chapterId, wordIndex, note, createdAt];
}
