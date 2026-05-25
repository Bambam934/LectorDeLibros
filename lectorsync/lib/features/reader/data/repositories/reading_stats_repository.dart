import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Tracks reading statistics locally.
class ReadingStatsRepository {
  static const _sessionsKey = 'reading_sessions';
  static const _streakKey = 'reading_streak';
  static const _lastReadDateKey = 'last_read_date';
  static const _dailyGoalKey = 'reading_daily_goal_minutes';

  /// Default daily goal in minutes when the user hasn't set one.
  static const defaultDailyGoalMinutes = 30;

  /// Get the daily reading goal in minutes.
  Future<int> getDailyGoalMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_dailyGoalKey) ?? defaultDailyGoalMinutes;
  }

  /// Set the daily reading goal in minutes.
  Future<void> setDailyGoalMinutes(int minutes) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt(_dailyGoalKey, minutes.clamp(5, 480));
  }

  /// Get minutes read today (since midnight local time).
  Future<int> getTodayMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _getSessions(prefs);
    final now = DateTime.now();
    final midnight = DateTime(now.year, now.month, now.day);
    var totalMs = 0;
    for (final s in sessions) {
      try {
        final date = DateTime.parse(s['date'] as String);
        if (date.isAfter(midnight)) {
          totalMs += (s['durationMs'] as num?)?.toInt() ?? 0;
        }
      } catch (_) {}
    }
    return totalMs ~/ 60000;
  }

  /// Get this week's minutes (last 7 days including today).
  Future<int> getWeekMinutes() async {
    final weekly = await getWeeklyMinutes();
    return weekly.values.fold<int>(0, (a, b) => a + b);
  }

  /// Record a reading session.
  Future<void> recordSession({
    required String bookId,
    required Duration duration,
    required int wordsRead,
  }) async {
    final prefs = await SharedPreferences.getInstance();

    // Save session.
    final sessions = await _getSessions(prefs);
    sessions.add({
      'bookId': bookId,
      'durationMs': duration.inMilliseconds,
      'wordsRead': wordsRead,
      'date': DateTime.now().toIso8601String(),
    });
    // Keep only last 1000 sessions to avoid unbounded storage growth.
    if (sessions.length > 1000) {
      sessions.removeRange(0, sessions.length - 1000);
    }
    await prefs.setString(_sessionsKey, jsonEncode(sessions));

    // Update streak.
    await _updateStreak(prefs);
  }

  /// Get total reading time across all books.
  Future<Duration> getTotalReadingTime() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _getSessions(prefs);
    var totalMs = 0;
    for (final s in sessions) {
      totalMs += (s['durationMs'] as num?)?.toInt() ?? 0;
    }
    return Duration(milliseconds: totalMs);
  }

  /// Get reading time for a specific book.
  Future<Duration> getBookReadingTime(String bookId) async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _getSessions(prefs);
    var totalMs = 0;
    for (final s in sessions) {
      if (s['bookId'] == bookId) {
        totalMs += (s['durationMs'] as num?)?.toInt() ?? 0;
      }
    }
    return Duration(milliseconds: totalMs);
  }

  /// Get total words read across all books.
  Future<int> getTotalWordsRead() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _getSessions(prefs);
    var total = 0;
    for (final s in sessions) {
      total += (s['wordsRead'] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  /// Get average words per minute.
  Future<double> getAverageWpm() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _getSessions(prefs);
    var totalMs = 0;
    var totalWords = 0;
    for (final s in sessions) {
      totalMs += (s['durationMs'] as num?)?.toInt() ?? 0;
      totalWords += (s['wordsRead'] as num?)?.toInt() ?? 0;
    }
    if (totalMs == 0 || totalWords == 0) return 0;
    return totalWords / (totalMs / 60000);
  }

  /// Get current reading streak (consecutive days).
  Future<int> getStreak() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getInt(_streakKey) ?? 0;
  }

  /// Get reading sessions for the last 7 days.
  Future<Map<String, int>> getWeeklyMinutes() async {
    final prefs = await SharedPreferences.getInstance();
    final sessions = await _getSessions(prefs);
    final now = DateTime.now();
    final result = <String, int>{};

    for (var i = 6; i >= 0; i--) {
      final date = now.subtract(Duration(days: i));
      final key = '${date.month}/${date.day}';
      result[key] = 0;
    }

    for (final s in sessions) {
      try {
        final date = DateTime.parse(s['date'] as String);
        final diff = now.difference(date).inDays;
        if (diff < 7) {
          final key = '${date.month}/${date.day}';
          final minutes = ((s['durationMs'] as num?)?.toInt() ?? 0) ~/ 60000;
          result[key] = (result[key] ?? 0) + minutes;
        }
      } catch (_) {}
    }

    return result;
  }

  Future<void> _updateStreak(SharedPreferences prefs) async {
    final now = DateTime.now();
    final todayStr = '${now.year}-${now.month}-${now.day}';
    final lastStr = prefs.getString(_lastReadDateKey);

    if (lastStr == todayStr) return; // Already counted today.

    final currentStreak = prefs.getInt(_streakKey) ?? 0;

    if (lastStr != null) {
      try {
        final parts = lastStr.split('-').map(int.parse).toList();
        final lastDate = DateTime(parts[0], parts[1], parts[2]);
        final diff = now.difference(lastDate).inDays;

        if (diff == 1) {
          // Consecutive day.
          await prefs.setInt(_streakKey, currentStreak + 1);
        } else if (diff > 1) {
          // Streak broken.
          await prefs.setInt(_streakKey, 1);
        }
      } catch (e) {
        debugPrint('[ReadingStats] streak parse error: $e');
        await prefs.setInt(_streakKey, 1);
      }
    } else {
      await prefs.setInt(_streakKey, 1);
    }

    await prefs.setString(_lastReadDateKey, todayStr);
  }

  Future<List<Map<String, dynamic>>> _getSessions(SharedPreferences prefs) async {
    final raw = prefs.getString(_sessionsKey);
    if (raw == null || raw.isEmpty) return [];
    try {
      final list = jsonDecode(raw) as List;
      return list.cast<Map<String, dynamic>>();
    } catch (e) {
      debugPrint('[ReadingStats] parse error: $e');
      return [];
    }
  }
}
