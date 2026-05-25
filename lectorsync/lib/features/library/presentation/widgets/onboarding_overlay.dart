import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// First-launch onboarding tour with 4 steps:
///   1. Importar libro
///   2. Voz y velocidad
///   3. Marcadores
///   4. Estadísticas
///
/// Shown once per device (gated by a SharedPreferences flag). The user
/// can skip at any time. Designed to be lightweight — no dependencies
/// beyond Material + SharedPreferences.
class OnboardingOverlay extends StatefulWidget {
  const OnboardingOverlay({super.key, required this.onFinish});

  final VoidCallback onFinish;

  static const _seenKey = 'onboarding_seen_v1';

  /// True iff the onboarding has been seen already.
  static Future<bool> hasBeenSeen() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool(_seenKey) ?? false;
  }

  /// Mark onboarding as completed so it won't show again.
  static Future<void> markSeen() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool(_seenKey, true);
  }

  @override
  State<OnboardingOverlay> createState() => _OnboardingOverlayState();
}

class _OnboardingOverlayState extends State<OnboardingOverlay> {
  final _pageController = PageController();
  int _page = 0;

  static const _steps = <_OnboardingStep>[
    _OnboardingStep(
      icon: Icons.add_rounded,
      title: 'Importa tu primer libro',
      body: 'Toca el botón ＋ en la esquina superior para añadir libros '
          'EPUB, PDF, TXT o Markdown desde tu dispositivo.',
    ),
    _OnboardingStep(
      icon: Icons.record_voice_over_rounded,
      title: 'Voz y velocidad',
      body: 'Dentro del lector, elige la voz que prefieras y ajusta la '
          'velocidad con el botón ⚡ — el cambio se aplica al instante.',
    ),
    _OnboardingStep(
      icon: Icons.bookmarks_rounded,
      title: 'Marcadores y notas',
      body: 'Guarda tu posición favorita en cualquier momento. Los '
          'marcadores se sincronizan entre dispositivos y se pueden '
          'exportar en Markdown o JSON.',
    ),
    _OnboardingStep(
      icon: Icons.bar_chart_rounded,
      title: 'Estadísticas y meta diaria',
      body: 'Sigue tu racha, palabras leídas y velocidad. Configura '
          'una meta diaria para mantener el hábito.',
    ),
  ];

  Future<void> _finish() async {
    await OnboardingOverlay.markSeen();
    widget.onFinish();
  }

  @override
  void dispose() {
    _pageController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isLast = _page == _steps.length - 1;
    return Material(
      color: scheme.surface.withValues(alpha: 0.95),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20),
          child: Column(
            children: [
              Align(
                alignment: Alignment.topRight,
                child: TextButton(
                  onPressed: _finish,
                  child: const Text('Saltar'),
                ),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _pageController,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemCount: _steps.length,
                  itemBuilder: (_, i) => _OnboardingStepView(step: _steps[i]),
                ),
              ),
              // Page dots
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: List.generate(
                  _steps.length,
                  (i) => AnimatedContainer(
                    duration: const Duration(milliseconds: 200),
                    width: i == _page ? 24 : 8,
                    height: 8,
                    margin: const EdgeInsets.symmetric(horizontal: 4),
                    decoration: BoxDecoration(
                      color: i == _page
                          ? scheme.primary
                          : scheme.onSurfaceVariant.withValues(alpha: 0.3),
                      borderRadius: BorderRadius.circular(4),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              SizedBox(
                width: double.infinity,
                child: FilledButton(
                  onPressed: () {
                    if (isLast) {
                      _finish();
                    } else {
                      _pageController.nextPage(
                        duration: const Duration(milliseconds: 250),
                        curve: Curves.easeOutCubic,
                      );
                    }
                  },
                  child: Text(isLast ? 'Empezar' : 'Siguiente'),
                ),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
      ),
    );
  }
}

class _OnboardingStep {
  const _OnboardingStep({
    required this.icon,
    required this.title,
    required this.body,
  });
  final IconData icon;
  final String title;
  final String body;
}

class _OnboardingStepView extends StatelessWidget {
  const _OnboardingStepView({required this.step});

  final _OnboardingStep step;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 96,
            height: 96,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [scheme.primary, scheme.tertiary],
              ),
              shape: BoxShape.circle,
            ),
            child: Icon(step.icon, size: 48, color: scheme.onPrimary),
          ),
          const SizedBox(height: 32),
          Text(
            step.title,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.4,
                ),
          ),
          const SizedBox(height: 16),
          Text(
            step.body,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: scheme.onSurfaceVariant,
                  height: 1.5,
                ),
          ),
        ],
      ),
    );
  }
}
