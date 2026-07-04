import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/geo.dart';
import '../../services/providers.dart';
import '../../services/speed_alert.dart';
import '../../theme/app_theme.dart';
import '../nearby/nearby_screen.dart' show currentPositionProvider;
import 'trip_controller.dart';

const _speedGreen = Color(0xFF4ADE80);
const _speedOver = Color(0xFFEF4444);
const _avgOrange = Color(0xFFF59E0B);

/// The live speedometer block at the top of Home: current speed, nearest site,
/// average speed + reset, manual limit + steppers, and GPS/tracking status.
class SpeedometerPanel extends ConsumerWidget {
  const SpeedometerPanel({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(tripControllerProvider);
    final limit = ref.watch(speedLimitProvider);
    final stats = state.stats;
    final over = isOverLimit(stats.currentSpeedKmh, limit);
    final speedColor = over ? _speedOver : _speedGreen;

    return Column(
      children: [
        const _Label('SPEED'),
        const SizedBox(height: 4),
        Text(
          pad3(stats.currentSpeedKmh),
          style: TextStyle(
            fontSize: 96,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: speedColor,
            letterSpacing: 2,
            shadows: [
              Shadow(color: speedColor.withValues(alpha: 0.55), blurRadius: 26),
            ],
          ),
        ),
        const SizedBox(height: 2),
        const _Label('km  /  h'),
        const SizedBox(height: 16),
        const NearestSiteCard(),
        const SizedBox(height: 16),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: _AvgColumn(
                avgKmh: stats.avgSpeedKmh,
                onReset: state.isRunning
                    ? ref.read(tripControllerProvider.notifier).reset
                    : null,
              ),
            ),
            Container(width: 1, height: 92, color: AppTheme.border),
            Expanded(
              child: _LimitColumn(
                limitKmh: limit,
                onMinus: ref.read(speedLimitProvider.notifier).decrement,
                onPlus: ref.read(speedLimitProvider.notifier).increment,
              ),
            ),
          ],
        ),
        const SizedBox(height: 14),
        _StatusLine(running: state.isRunning),
      ],
    );
  }
}

class _Label extends StatelessWidget {
  const _Label(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Text(
    text,
    style: const TextStyle(
      color: AppTheme.textSecondary,
      fontSize: 13,
      fontWeight: FontWeight.w700,
      letterSpacing: 4,
    ),
  );
}

class _AvgColumn extends StatelessWidget {
  const _AvgColumn({required this.avgKmh, required this.onReset});
  final double avgKmh;
  final VoidCallback? onReset;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Label('AVG SPEED'),
        const SizedBox(height: 6),
        Text(
          pad3(avgKmh),
          style: const TextStyle(
            fontSize: 44,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: _avgOrange,
            shadows: [Shadow(color: Color(0x66F59E0B), blurRadius: 18)],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'km/h',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppTheme.textSecondary,
            side: const BorderSide(color: AppTheme.border),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          icon: const Icon(Icons.refresh, size: 16),
          label: const Text('RESET'),
          onPressed: onReset,
        ),
      ],
    );
  }
}

class _LimitColumn extends StatelessWidget {
  const _LimitColumn({
    required this.limitKmh,
    required this.onMinus,
    required this.onPlus,
  });
  final int limitKmh;
  final VoidCallback onMinus;
  final VoidCallback onPlus;

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        const _Label('LIMIT'),
        const SizedBox(height: 6),
        Text(
          '$limitKmh',
          style: const TextStyle(
            fontSize: 44,
            height: 1.0,
            fontWeight: FontWeight.w800,
            color: _speedGreen,
            shadows: [Shadow(color: Color(0x664ADE80), blurRadius: 18)],
          ),
        ),
        const SizedBox(height: 4),
        const Text(
          'km/h',
          style: TextStyle(
            color: AppTheme.textSecondary,
            fontSize: 12,
            fontWeight: FontWeight.w700,
            letterSpacing: 2,
          ),
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _StepButton(icon: Icons.remove, onPressed: onMinus),
            const SizedBox(width: 10),
            _StepButton(icon: Icons.add, onPressed: onPlus),
          ],
        ),
      ],
    );
  }
}

class _StepButton extends StatelessWidget {
  const _StepButton({required this.icon, required this.onPressed});
  final IconData icon;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 40,
      height: 36,
      child: OutlinedButton(
        style: OutlinedButton.styleFrom(
          foregroundColor: AppTheme.textPrimary,
          side: const BorderSide(color: AppTheme.border),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        ),
        onPressed: onPressed,
        child: Icon(icon, size: 18),
      ),
    );
  }
}

class _StatusLine extends StatelessWidget {
  const _StatusLine({required this.running});
  final bool running;

  @override
  Widget build(BuildContext context) {
    if (!running) {
      return const Text(
        'GPS idle',
        style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
      );
    }
    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: const BoxDecoration(
            color: _speedGreen,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 6),
        const Text(
          'GPS active',
          style: TextStyle(color: AppTheme.textSecondary, fontSize: 13),
        ),
        const SizedBox(width: 10),
        const Text('|', style: TextStyle(color: AppTheme.border)),
        const SizedBox(width: 10),
        const Icon(Icons.navigation, size: 14, color: AppTheme.accent),
        const SizedBox(width: 4),
        const Text(
          'Tracking',
          style: TextStyle(
            color: AppTheme.accent,
            fontSize: 13,
            fontWeight: FontWeight.w700,
          ),
        ),
      ],
    );
  }
}

/// The nearest NHVR site to the driver, with distance and status. Hidden until a
/// device position and located sites are available.
class NearestSiteCard extends ConsumerWidget {
  const NearestSiteCard({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final posAsync = ref.watch(currentPositionProvider);
    final sitesAsync = ref.watch(sitesProvider);

    final pos = posAsync.asData?.value;
    final sites = sitesAsync.asData?.value;
    if (pos == null || sites == null) return const SizedBox.shrink();

    final ranked = nearestSites(sites, pos.latitude, pos.longitude);
    if (ranked.isEmpty) return const SizedBox.shrink();

    final nearest = ranked.first;
    final site = nearest.site;
    final more = ranked.length - 1;
    final km = nearest.km;

    return GestureDetector(
      onTap: () => context.go('/state/${site.state.code}'),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppTheme.surface,
          border: Border.all(color: AppTheme.border),
          borderRadius: BorderRadius.circular(14),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
          child: Row(
            children: [
              const Icon(
                Icons.location_on_outlined,
                size: 20,
                color: AppTheme.accent,
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      site.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        color: AppTheme.textPrimary,
                        fontSize: 15,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      '${km.toStringAsFixed(km < 10 ? 1 : 0)} km away'
                      '${more > 0 ? '  ·  +$more more' : ''}',
                      style: const TextStyle(
                        color: AppTheme.textSecondary,
                        fontSize: 12,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              _StatusPill(color: site.currentStatus.color, label: site.currentStatus.label),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  const _StatusPill({required this.color, required this.label});
  final Color color;
  final String label;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: color.withValues(alpha: 0.6)),
      ),
      child: Text(
        label.toUpperCase(),
        style: TextStyle(
          color: color,
          fontSize: 11,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.5,
        ),
      ),
    );
  }
}
