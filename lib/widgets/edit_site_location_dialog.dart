import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/site.dart';
import '../services/geo.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import 'coordinate_fields.dart';

/// Admin editor for a site's coordinates. Pops `true` once the write lands.
///
/// Clearing both fields is allowed and meaningful: it retracts a position an
/// admin believes is wrong, rather than leaving drivers chasing a bad pin.
class EditSiteLocationDialog extends ConsumerStatefulWidget {
  const EditSiteLocationDialog({super.key, required this.site});

  final Site site;

  @override
  ConsumerState<EditSiteLocationDialog> createState() =>
      _EditSiteLocationDialogState();
}

class _EditSiteLocationDialogState
    extends ConsumerState<EditSiteLocationDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _lat = TextEditingController(
    text: widget.site.lat?.toString() ?? '',
  );
  late final TextEditingController _lng = TextEditingController(
    text: widget.site.lng?.toString() ?? '',
  );
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _lat.dispose();
    _lng.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await ref
          .read(adminRepositoryProvider)
          .updateSiteLocation(
            widget.site.id,
            lat: parseCoordinate(_lat.text, maxAbs: maxLatitude),
            lng: parseCoordinate(_lng.text, maxAbs: maxLongitude),
          );
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Site coordinates'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                widget.site.name,
                style: const TextStyle(
                  color: AppTheme.textPrimary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 12),
              CoordinateFields(
                latController: _lat,
                lngController: _lng,
                helperText:
                    'Clear both fields to remove the pin. Seeded positions are '
                    'town-level — stand at the gate and capture to fix one.',
              ),
              if (_error != null) ...[
                const SizedBox(height: 10),
                Text(
                  _error!,
                  style: const TextStyle(color: Colors.redAccent, fontSize: 12),
                ),
              ],
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _saving ? null : () => Navigator.pop(context, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: AppTheme.accent),
          onPressed: _saving ? null : _save,
          child: _saving
              ? const SizedBox(
                  height: 16,
                  width: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('Save'),
        ),
      ],
    );
  }
}
