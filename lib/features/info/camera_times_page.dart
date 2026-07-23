import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../services/camera_times.dart';
import '../../theme/app_theme.dart';
import 'camera_timer.dart';
import 'info_screen.dart';

/// Camera Times (Info tab): expected point-to-point travel times between
/// average-speed camera points, grouped by corridor (city pair). The hub page
/// lists corridors; tapping one opens [CameraCorridorPage] with a direction
/// toggle and the leg-by-leg times.

Future<List<CameraCorridor>>? _corridorsFuture;

/// Loads and parses the bundled CSV once per app run.
Future<List<CameraCorridor>> loadCameraCorridors() =>
    _corridorsFuture ??= rootBundle
        .loadString('assets/camera_times.csv')
        .then((csv) => groupCorridors(parseCameraTimesCsv(csv)));

const _cameraTimesNote =
    'Expected time is the travel time between camera points at the legal '
    'average speed — arriving sooner means your average was over the limit. '
    'Community-compiled guide only; always follow signage.';

class CameraTimesPage extends StatelessWidget {
  const CameraTimesPage({super.key, this.corridors});

  /// Injectable for widget tests; defaults to the bundled asset.
  final List<CameraCorridor>? corridors;

  @override
  Widget build(BuildContext context) {
    return _WhenLoaded(
      corridors: corridors,
      title: 'Camera Times',
      builder: (context, corridors) => [
        const Padding(
          padding: EdgeInsets.only(left: 4, right: 4, bottom: 2),
          child: Text(
            _cameraTimesNote,
            style: TextStyle(
              color: AppTheme.textSecondary,
              fontSize: 13,
              height: 1.35,
            ),
          ),
        ),
        for (final corridor in corridors)
          InfoLinkRow(
            icon: Icons.route_outlined,
            title: corridor.title,
            subtitle:
                '${corridor.forward.totalKm} km · '
                '${formatCameraDuration(corridor.forward.totalSeconds)}',
            onTap: () => context.go('/info/cameras/${corridor.slug}'),
          ),
      ],
    );
  }
}

class CameraCorridorPage extends ConsumerStatefulWidget {
  const CameraCorridorPage({super.key, required this.slug, this.corridors});

  final String slug;

  /// Injectable for widget tests; defaults to the bundled asset.
  final List<CameraCorridor>? corridors;

  @override
  ConsumerState<CameraCorridorPage> createState() =>
      _CameraCorridorPageState();
}

class _CameraCorridorPageState extends ConsumerState<CameraCorridorPage> {
  int _direction = 0;

  /// Tap-selected consecutive legs (partial run); reset on direction flip.
  LegRange? _selection;

  void _startTimer(CameraRoute route, {LegRange? range}) {
    ref.read(cameraTimerProvider.notifier).start(
          targetTitle: range == null
              ? 'Full run · ${route.title}'
              : route.rangeTitle(range),
          distanceKm: range == null ? route.totalKm : route.rangeKm(range),
          expectedSeconds:
              range == null ? route.totalSeconds : route.rangeSeconds(range),
        );
  }

  @override
  Widget build(BuildContext context) {
    return _WhenLoaded(
      corridors: widget.corridors,
      title: 'Camera Times',
      titleOf: (corridors) {
        final matches = corridors.where((c) => c.slug == widget.slug);
        return matches.isEmpty ? 'Camera Times' : matches.first.title;
      },
      builder: (context, corridors) {
        final matches = corridors.where((c) => c.slug == widget.slug);
        if (matches.isEmpty) {
          return const [
            InfoBlock(
              icon: Icons.error_outline_rounded,
              title: 'Route not found',
              body: 'This camera route does not exist. Go back and pick one '
                  'from the list.',
            ),
          ];
        }
        final corridor = matches.first;
        final route =
            corridor.directions[_direction < corridor.directions.length
                ? _direction
                : 0];
        final selection = _selection;
        return [
          if (ref.watch(cameraTimerProvider) != null) const CameraTimerPanel(),
          if (corridor.directions.length > 1)
            SegmentedButton<int>(
              segments: [
                for (final (i, dir) in corridor.directions.indexed)
                  ButtonSegment(value: i, label: Text('To ${dir.destination}')),
              ],
              selected: {_direction},
              onSelectionChanged: (sel) => setState(() {
                _direction = sel.first;
                _selection = null;
              }),
              showSelectedIcon: false,
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor:
                    AppTheme.accent.withValues(alpha: 0.2),
                selectedForegroundColor: AppTheme.accent,
                foregroundColor: AppTheme.textSecondary,
                side: const BorderSide(color: AppTheme.border),
                textStyle: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          const Padding(
            padding: EdgeInsets.only(left: 4, right: 4),
            child: Text(
              'Tap a leg to select it, tap another to extend — then Time me '
              'a partial run.',
              style: TextStyle(color: AppTheme.textSecondary, fontSize: 12),
            ),
          ),
          for (final (i, leg) in route.legs.indexed)
            _LegRow(
              leg: leg,
              selected: selection?.contains(i) ?? false,
              onTap: () => setState(
                () => _selection = nextLegSelection(_selection, i),
              ),
            ),
          if (selection != null)
            _PartialRunRow(
              route: route,
              range: selection,
              onTimeMe: () => _startTimer(route, range: selection),
              onClear: () => setState(() => _selection = null),
            ),
          _TotalRow(route: route, onTimeMe: () => _startTimer(route)),
          const Padding(
            padding: EdgeInsets.only(left: 4, right: 4, top: 2),
            child: Text(
              _cameraTimesNote,
              style: TextStyle(
                color: AppTheme.textSecondary,
                fontSize: 12,
                height: 1.35,
              ),
            ),
          ),
        ];
      },
    );
  }
}

/// Shared loader: uses injected corridors when given (tests), otherwise the
/// cached asset future, and renders the sub-page once data is ready.
class _WhenLoaded extends StatelessWidget {
  const _WhenLoaded({
    required this.corridors,
    required this.title,
    required this.builder,
    this.titleOf,
  });

  final List<CameraCorridor>? corridors;

  /// Title while loading (and when [titleOf] is absent).
  final String title;

  /// Data-dependent title, e.g. the corridor name once loaded.
  final String Function(List<CameraCorridor>)? titleOf;
  final List<Widget> Function(BuildContext, List<CameraCorridor>) builder;

  @override
  Widget build(BuildContext context) {
    if (corridors != null) return _page(context, corridors!);
    return FutureBuilder<List<CameraCorridor>>(
      future: loadCameraCorridors(),
      builder: (context, snapshot) {
        final data = snapshot.data;
        if (data == null) {
          return InfoSubPage(
            title: title,
            children: const [
              Center(
                child: Padding(
                  padding: EdgeInsets.all(24),
                  child: CircularProgressIndicator(color: AppTheme.accent),
                ),
              ),
            ],
          );
        }
        return _page(context, data);
      },
    );
  }

  Widget _page(BuildContext context, List<CameraCorridor> data) => InfoSubPage(
        title: titleOf?.call(data) ?? title,
        children: builder(context, data),
      );
}

/// One camera-to-camera leg: "From → To", distance (+ slow zone), time.
/// Tapping selects it into the partial-run range.
class _LegRow extends StatelessWidget {
  const _LegRow({
    required this.leg,
    required this.selected,
    required this.onTap,
  });

  final CameraLeg leg;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final slowZone = leg.slowZoneKm != null
        ? ' · incl. ${leg.slowZoneKm} km @ ${leg.slowZoneSpeedKph} km/h'
        : '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: selected
            ? AppTheme.accent.withValues(alpha: 0.10)
            : AppTheme.surface,
        border: Border.all(
          color: selected ? AppTheme.accent : AppTheme.border,
        ),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: BorderRadius.circular(14),
          onTap: onTap,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        leg.title,
                        style: const TextStyle(
                          color: AppTheme.textPrimary,
                          fontSize: 15,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        '${leg.distanceKm} km$slowZone',
                        style: const TextStyle(
                          color: AppTheme.textSecondary,
                          fontSize: 12,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Text(
                  formatCameraDuration(leg.expectedSeconds),
                  style: const TextStyle(
                    color: AppTheme.accent,
                    fontSize: 15,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Summary of the tap-selected consecutive legs, with Time me / clear.
class _PartialRunRow extends StatelessWidget {
  const _PartialRunRow({
    required this.route,
    required this.range,
    required this.onTimeMe,
    required this.onClear,
  });

  final CameraRoute route;
  final LegRange range;
  final VoidCallback onTimeMe;
  final VoidCallback onClear;

  @override
  Widget build(BuildContext context) {
    final legs = range.length;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    route.rangeTitle(range),
                    style: const TextStyle(
                      color: AppTheme.textPrimary,
                      fontSize: 15,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    '$legs ${legs == 1 ? 'leg' : 'legs'} · '
                    '${route.rangeKm(range)} km · '
                    '${formatCameraDuration(route.rangeSeconds(range))}',
                    style: const TextStyle(
                      color: AppTheme.textSecondary,
                      fontSize: 12,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 8),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: AppTheme.accent,
                foregroundColor: Colors.white,
                visualDensity: VisualDensity.compact,
              ),
              onPressed: onTimeMe,
              icon: const Icon(Icons.play_arrow_rounded, size: 18),
              label: const Text('Time me'),
            ),
            IconButton(
              onPressed: onClear,
              icon: const Icon(Icons.close_rounded),
              color: AppTheme.textSecondary,
              visualDensity: VisualDensity.compact,
              tooltip: 'Clear selection',
            ),
          ],
        ),
      ),
    );
  }
}

/// Whole-run total for the selected direction, with its own Time me.
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.route, required this.onTimeMe});

  final CameraRoute route;
  final VoidCallback onTimeMe;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 10, 8, 10),
        child: Row(
          children: [
            const Icon(Icons.flag_outlined, color: AppTheme.accent, size: 20),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                'Full run · ${route.totalKm} km',
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontSize: 15,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ),
            Text(
              formatCameraDuration(route.totalSeconds),
              style: const TextStyle(
                color: AppTheme.accent,
                fontSize: 15,
                fontWeight: FontWeight.w800,
              ),
            ),
            IconButton(
              onPressed: onTimeMe,
              icon: const Icon(Icons.play_circle_outline_rounded),
              color: AppTheme.accent,
              visualDensity: VisualDensity.compact,
              tooltip: 'Time the full run',
            ),
          ],
        ),
      ),
    );
  }
}
