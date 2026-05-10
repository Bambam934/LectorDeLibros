import 'package:equatable/equatable.dart';

class WordTimestamp extends Equatable {
  const WordTimestamp({
    required this.wordIndex,
    required this.timestampMs,
  });

  final int wordIndex;
  final int timestampMs;

  factory WordTimestamp.fromJson(Map<String, dynamic> json) {
    return WordTimestamp(
      wordIndex: (json['word_index'] as num?)?.toInt() ?? 0,
      timestampMs: (json['timestamp_ms'] as num?)?.toInt() ?? 0,
    );
  }

  @override
  List<Object?> get props => [wordIndex, timestampMs];
}

class ChapterAudio extends Equatable {
  const ChapterAudio({
    required this.chapterId,
    required this.provider,
    this.audioUrl,
    this.durationMs = 0,
    this.wordTimestamps = const [],
    this.source,
  });

  final String chapterId;
  final String provider;
  final String? audioUrl;
  final int durationMs;
  final List<WordTimestamp> wordTimestamps;
  final String? source;

  bool get hasAudio => audioUrl != null && audioUrl!.isNotEmpty;

  factory ChapterAudio.fromJson(Map<String, dynamic> json) {
    final rawTimestamps = json['word_timestamps'];
    final timestamps = <WordTimestamp>[];
    if (rawTimestamps is List) {
      for (final item in rawTimestamps) {
        if (item is Map<String, dynamic>) {
          timestamps.add(WordTimestamp.fromJson(item));
        }
      }
    }

    return ChapterAudio(
      chapterId: json['chapter_id'] as String? ?? '',
      provider: json['provider'] as String? ?? 'mock',
      audioUrl: json['audio_url'] as String?,
      durationMs: (json['duration_ms'] as num?)?.toInt() ?? 0,
      wordTimestamps: timestamps,
      source: json['source'] as String?,
    );
  }

  @override
  List<Object?> get props => [
        chapterId,
        provider,
        audioUrl,
        durationMs,
        wordTimestamps,
        source,
      ];
}
