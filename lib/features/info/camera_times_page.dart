import 'package:flutter/material.dart';
import 'package:flutter/services.dart' show rootBundle;
import 'package:go_router/go_router.dart';

import '../../services/camera_times.dart';
import '../../theme/app_theme.dart';
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

class CameraCorridorPage extends StatefulWidget {
  const CameraCorridorPage({super.key, required this.slug, this.corridors});

  final String slug;

  /// Injectable for widget tests; defaults to the bundled asset.
  final List<CameraCorridor>? corridors;

  @override
  State<CameraCorridorPage> createState() => _CameraCorridorPageState();
}

class _CameraCorridorPageState extends State<CameraCorridorPage> {
  int _direction = 0;

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
        return [
          if (corridor.directions.length > 1)
            SegmentedButton<int>(
              segments: [
                for (final (i, dir) in corridor.directions.indexed)
                  ButtonSegment(value: i, label: Text('To ${dir.destination}')),
              ],
              selected: {_direction},
              onSelectionChanged: (sel) =>
                  setState(() => _direction = sel.first),
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
          for (final leg in route.legs) _LegRow(leg: leg),
          _TotalRow(route: route),
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
class _LegRow extends StatelessWidget {
  const _LegRow({required this.leg});

  final CameraLeg leg;

  @override
  Widget build(BuildContext context) {
    final slowZone = leg.slowZoneKm != null
        ? ' · incl. ${leg.slowZoneKm} km @ ${leg.slowZoneSpeedKph} km/h'
        : '';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.surface,
        border: Border.all(color: AppTheme.border),
        borderRadius: BorderRadius.circular(14),
      ),
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
    );
  }
}

/// Whole-run total for the selected direction.
class _TotalRow extends StatelessWidget {
  const _TotalRow({required this.route});

  final CameraRoute route;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppTheme.accent.withValues(alpha: 0.12),
        border: Border.all(color: AppTheme.accent.withValues(alpha: 0.4)),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
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
          ],
        ),
      ),
    );
  }
}
