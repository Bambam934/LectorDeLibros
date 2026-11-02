import 'package:flutter/material.dart';

import '../../../../core/di/injection_container.dart';
import '../../../../core/widgets/loading_view.dart';
import '../../data/repositories/reading_stats_repository.dart';

class ReadingStatsSheet extends StatefulWidget {
  const ReadingStatsSheet({super.key});

  @override
  State<ReadingStatsSheet> createState() => _ReadingStatsSheetState();
}

class _ReadingStatsSheetState extends State<ReadingStatsSheet> {
  bool _loading = true;
  Duration _totalTime = Duration.zero;
  int _totalWords = 0;
  double _avgWpm = 0;
  int _streak = 0;
  Map<String, int> _weeklyMinutes = {};
  int _todayMinutes = 0;
  int _dailyGoalMinutes = ReadingStatsRepository.defaultDailyGoalMinutes;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = sl<ReadingStatsRepository>();
    final results = await Future.wait([
      repo.getTotalReadingTime(),
      repo.getTotalWordsRead(),
      repo.getAverageWpm(),
      repo.getStreak(),
      repo.getWeeklyMinutes(),
      repo.getTodayMinutes(),
      repo.getDailyGoalMinutes(),
    ]);
    if (mounted) {
      setState(() {
        _totalTime = results[0] as Duration;
        _totalWords = results[1] as int;
        _avgWpm = results[2] as double;
        _streak = results[3] as int;
        _weeklyMinutes = results[4] as Map<String, int>;
        _todayMinutes = results[5] as int;
        _dailyGoalMinutes = results[6] as int;
        _loading = false;
      });
    }
  }

  Future<void> _editGoal() async {
    final controller =
        TextEditingController(text: _dailyGoalMinutes.toString());
    final result = await showDialog<int>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Meta diaria de lectura'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.number,
          decoration: const InputDecoration(
            labelText: 'Minutos por día',
            hintText: '15, 30, 60…',
            suffixText: 'min',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Cancelar'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.pop(ctx, int.tryParse(controller.text) ?? 30),
            child: const Text('Guardar'),
          ),
        ],
      ),
    );
    if (result != null) {
      await sl<ReadingStatsRepository>().setDailyGoalMinutes(result);
      await _load();
    }
  }

  String _formatDuration(Duration d) {
    if (d.inHours > 0) {
      return '${d.inHours}h ${d.inMinutes.remainder(60)}m';
    }
    if (d.inMinutes > 0) {
      return '${d.inMinutes}m';
    }
    return '${d.inSeconds}s';
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return DraggableScrollableSheet(
      initialChildSize: 0.55,
      minChildSize: 0.3,
      maxChildSize: 0.85,
      expand: false,
      builder: (context, scrollController) => SingleChildScrollView(
        controller: scrollController,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Icon(Icons.bar_chart_rounded, color: scheme.primary),
                  const SizedBox(width: 8),
                  const Text('Estadísticas de lectura',
                      style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                ],
              ),
            ),
            const Divider(height: 1),
            if (_loading)
              const LoadingView(message: 'Calculando tus estadísticas')
            else ...[
              const SizedBox(height: 16),
              // Daily goal widget
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: _DailyGoalCard(
                  todayMinutes: _todayMinutes,
                  goalMinutes: _dailyGoalMinutes,
                  onEditGoal: _editGoal,
                ),
              ),
              const SizedBox(height: 16),
              // Stats grid
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(child: _StatCard(
                      icon: Icons.timer_rounded,
                      label: 'Tiempo total',
                      value: _formatDuration(_totalTime),
                      color: scheme.primary,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard(
                      icon: Icons.text_fields_rounded,
                      label: 'Palabras leídas',
                      value: _totalWords > 1000
                          ? '${(_totalWords / 1000).toStringAsFixed(1)}K'
                          : '$_totalWords',
                      color: scheme.tertiary,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Row(
                  children: [
                    Expanded(child: _StatCard(
                      icon: Icons.speed_rounded,
                      label: 'Velocidad media',
                      value: '${_avgWpm.round()} ppm',
                      color: scheme.secondary,
                    )),
                    const SizedBox(width: 12),
                    Expanded(child: _StatCard(
                      icon: Icons.local_fire_department_rounded,
                      label: 'Racha de días',
                      value: '$_streak ${_streak == 1 ? 'día' : 'días'}',
                      color: Colors.orange,
                    )),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              // Weekly chart
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Últimos 7 días',
                        style: TextStyle(
                          fontSize: 14,
                          fontWeight: FontWeight.w600,
                          color: scheme.onSurface,
                        )),
                    const SizedBox(height: 12),
                    SizedBox(
                      height: 100,
                      child: _WeeklyChart(
                        data: _weeklyMinutes,
                        barColor: scheme.primary,
                        labelColor: scheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24),
            ],
          ],
        ),
      ),
    );
  }
}

class _StatCard extends StatelessWidget {
  const _StatCard({
    required this.icon,
    required this.label,
    required this.value,
    required this.color,
  });

  final IconData icon;
  final String label;
  final String value;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.15)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(height: 8),
          Text(value,
              style: TextStyle(
                fontSize: 20,
                fontWeight: FontWeight.w800,
                color: scheme.onSurface,
              )),
          const SizedBox(height: 2),
          Text(label,
              style: TextStyle(
                fontSize: 11,
                color: scheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}

class _DailyGoalCard extends StatelessWidget {
  const _DailyGoalCard({
    required this.todayMinutes,
    required this.goalMinutes,
    required this.onEditGoal,
  });

  final int todayMinutes;
  final int goalMinutes;
  final VoidCallback onEditGoal;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final progress =
        goalMinutes > 0 ? (todayMinutes / goalMinutes).clamp(0.0, 1.0) : 0.0;
    final pct = (progress * 100).round();
    final reached = todayMinutes >= goalMinutes;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: reached
              ? [scheme.tertiary, scheme.primary]
              : [
                  scheme.primary.withValues(alpha: 0.85),
                  scheme.secondary.withValues(alpha: 0.85),
                ],
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(
                reached
                    ? Icons.emoji_events_rounded
                    : Icons.flag_circle_rounded,
                color: scheme.onPrimary,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  reached ? '¡Meta del día alcanzada!' : 'Meta diaria',
                  style: TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w700,
                    color: scheme.onPrimary,
                  ),
                ),
              ),
              IconButton(
                onPressed: onEditGoal,
                tooltip: 'Cambiar meta',
                icon: Icon(Icons.edit_rounded,
                    size: 18, color: scheme.onPrimary),
                visualDensity: VisualDensity.compact,
                padding: EdgeInsets.zero,
                constraints:
                    const BoxConstraints(minWidth: 28, minHeight: 28),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Row(
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                '$todayMinutes',
                style: TextStyle(
                  fontSize: 28,
                  fontWeight: FontWeight.w800,
                  color: scheme.onPrimary,
                  fontFeatures: const [FontFeature.tabularFigures()],
                ),
              ),
              Text(
                ' / $goalMinutes min',
                style: TextStyle(
                  fontSize: 14,
                  color: scheme.onPrimary.withValues(alpha: 0.85),
                ),
              ),
              const Spacer(),
              Text(
                '$pct%',
                style: TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w700,
                  color: scheme.onPrimary,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(99),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 6,
              backgroundColor: scheme.onPrimary.withValues(alpha: 0.25),
              valueColor:
                  AlwaysStoppedAnimation<Color>(scheme.onPrimary),
            ),
          ),
        ],
      ),
    );
  }
}

class _WeeklyChart extends StatelessWidget {
  const _WeeklyChart({
    required this.data,
    required this.barColor,
    required this.labelColor,
  });

  final Map<String, int> data;
  final Color barColor;
  final Color labelColor;

  @override
  Widget build(BuildContext context) {
    final maxValue = data.values.fold<int>(1, (a, b) => a > b ? a : b);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: data.entries.map((entry) {
        final heightFraction = maxValue > 0 ? entry.value / maxValue : 0.0;
        return Expanded(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 3),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                if (entry.value > 0)
                  Text(
                    '${entry.value}m',
                    style: TextStyle(fontSize: 9, color: labelColor),
                  ),
                const SizedBox(height: 2),
                Container(
                  height: (heightFraction * 60).clamp(4, 60),
                  decoration: BoxDecoration(
                    color: barColor.withValues(alpha: entry.value > 0 ? 0.7 : 0.15),
                    borderRadius: BorderRadius.circular(4),
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  entry.key,
                  style: TextStyle(fontSize: 9, color: labelColor),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }
}
