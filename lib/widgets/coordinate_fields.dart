import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/nearby/nearby_screen.dart' show currentPositionProvider;
import '../services/geo.dart';
import '../theme/app_theme.dart';
import 'snacks.dart';

/// Latitude/longitude inputs with a one-tap "use my current location" fill.
///
/// Shared by Add Site and the admin location editor so both validate and
/// capture coordinates identically. Coordinates stay **optional** — a site
/// without them still lists under its state, it just can't be ranked by
/// distance or raise an approach prompt, which is what the helper text says.
class CoordinateFields extends ConsumerStatefulWidget {
  const CoordinateFields({
    super.key,
    required this.latController,
    required this.lngController,
    this.helperText =
        'Optional. Without coordinates the site never appears in Nearby '
        'and never triggers an approach alert.',
  });

  final TextEditingController latController;
  final TextEditingController lngController;
  final String helperText;

  @override
  ConsumerState<CoordinateFields> createState() => _CoordinateFieldsState();
}

class _CoordinateFieldsState extends ConsumerState<CoordinateFields> {
  bool _locating = false;

  /// Fills both fields from the device's current fix. Deliberately re-reads
  /// (rather than using a cached value): the point is to pin where the user is
  /// standing right now, at the gate.
  Future<void> _useCurrentLocation() async {
    setState(() => _locating = true);
    try {
      final pos = await ref.refresh(currentPositionProvider.future);
      if (!mounted) return;
      if (pos == null) {
        showAppSnack(
          context,
          'Location unavailable — check location permission.',
        );
        return;
      }
      widget.latController.text = pos.latitude.toStringAsFixed(6);
      widget.lngController.text = pos.longitude.toStringAsFixed(6);
      showAppSnack(context, 'Location captured.');
    } catch (e) {
      if (mounted) showAppSnack(context, 'Could not read your location.');
    } finally {
      if (mounted) setState(() => _locating = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: TextFormField(
                controller: widget.latController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Latitude',
                  hintText: '-34.7123',
                ),
                validator: (v) =>
                    coordinateFieldError(
                      v,
                      maxAbs: maxLatitude,
                      label: 'Latitude',
                    ) ??
                    coordinatePairError(v, widget.lngController.text),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: TextFormField(
                controller: widget.lngController,
                keyboardType: const TextInputType.numberWithOptions(
                  signed: true,
                  decimal: true,
                ),
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9.\-]')),
                ],
                decoration: const InputDecoration(
                  labelText: 'Longitude',
                  hintText: '149.7123',
                ),
                validator: (v) => coordinateFieldError(
                  v,
                  maxAbs: maxLongitude,
                  label: 'Longitude',
                ),
              ),
            ),
          ],
        ),
        const SizedBox(height: 10),
        OutlinedButton.icon(
          style: OutlinedButton.styleFrom(
            minimumSize: const Size.fromHeight(44),
            foregroundColor: AppTheme.accent,
            side: const BorderSide(color: AppTheme.border),
          ),
          icon: _locating
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.my_location, size: 18),
          label: Text(_locating ? 'Locating…' : 'Use my current location'),
          onPressed: _locating ? null : _useCurrentLocation,
        ),
        const SizedBox(height: 6),
        Text(
          widget.helperText,
          style: const TextStyle(color: AppTheme.textSecondary, fontSize: 12),
        ),
      ],
    );
  }
}
