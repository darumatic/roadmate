import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models/enums.dart';
import '../models/site.dart';
import '../services/geo.dart';
import '../services/providers.dart';
import '../theme/app_theme.dart';
import 'coordinate_fields.dart';

/// The direction values shipped clients render as a tag; null means no tag
/// (a site serving both directions). Must stay the four normalised strings
/// `Site._normaliseDirection` accepts.
const siteDirections = ['northbound', 'southbound', 'eastbound', 'westbound'];

/// Admin editor for every describing field of a site — name, type, state,
/// suburb, address, direction, note and the pin. Pops `true` once the write
/// lands. Derived data (live status, vote tallies) is deliberately absent:
/// that is moderated through the reports feed, never hand-edited.
///
/// Clearing both coordinate fields is allowed and meaningful: it retracts a
/// position an admin believes is wrong, rather than leaving drivers chasing
/// a bad pin. Name, suburb and address can only be corrected, never blanked;
/// direction and note can be cleared outright.
class EditSiteDialog extends ConsumerStatefulWidget {
  const EditSiteDialog({super.key, required this.site});

  final Site site;

  @override
  ConsumerState<EditSiteDialog> createState() => _EditSiteDialogState();
}

class _EditSiteDialogState extends ConsumerState<EditSiteDialog> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _name = TextEditingController(
    text: widget.site.name,
  );
  late final TextEditingController _suburb = TextEditingController(
    text: widget.site.suburb,
  );
  late final TextEditingController _address = TextEditingController(
    text: widget.site.address,
  );
  late final TextEditingController _note = TextEditingController(
    text: widget.site.note ?? '',
  );
  late final TextEditingController _lat = TextEditingController(
    text: widget.site.lat?.toString() ?? '',
  );
  late final TextEditingController _lng = TextEditingController(
    text: widget.site.lng?.toString() ?? '',
  );
  late SiteType _type = widget.site.type;
  late AusState _state = widget.site.state;
  // A shipped site can carry a non-normalised direction; treat it as unset
  // rather than crashing the dropdown.
  late String? _direction = siteDirections.contains(widget.site.direction)
      ? widget.site.direction
      : null;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _suburb.dispose();
    _address.dispose();
    _note.dispose();
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
          .updateSiteDetails(
            widget.site.id,
            name: _name.text.trim(),
            type: _type,
            state: _state,
            suburb: _suburb.text.trim(),
            address: _address.text.trim(),
            direction: _direction,
            note: _note.text,
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

  String? _required(String? v) =>
      (v == null || v.trim().isEmpty) ? 'Required' : null;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppTheme.surface,
      title: const Text('Edit site'),
      content: SingleChildScrollView(
        child: Form(
          key: _formKey,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              TextFormField(
                controller: _name,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Site name'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _suburb,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Suburb/town'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _address,
                textCapitalization: TextCapitalization.words,
                decoration: const InputDecoration(labelText: 'Address'),
                validator: _required,
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<SiteType>(
                initialValue: _type,
                decoration: const InputDecoration(labelText: 'Type'),
                dropdownColor: AppTheme.surface,
                items: [
                  for (final type in SiteType.values)
                    DropdownMenuItem(value: type, child: Text(type.label)),
                ],
                onChanged: (v) => setState(() => _type = v ?? _type),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<AusState>(
                initialValue: _state,
                decoration: const InputDecoration(labelText: 'State'),
                dropdownColor: AppTheme.surface,
                items: [
                  for (final state in AusState.values)
                    DropdownMenuItem(
                      value: state,
                      child: Text('${state.code} — ${state.fullName}'),
                    ),
                ],
                onChanged: (v) => setState(() => _state = v ?? _state),
              ),
              const SizedBox(height: 16),
              DropdownButtonFormField<String?>(
                initialValue: _direction,
                decoration: const InputDecoration(labelText: 'Direction'),
                dropdownColor: AppTheme.surface,
                items: [
                  const DropdownMenuItem<String?>(
                    value: null,
                    child: Text('None / both'),
                  ),
                  for (final d in siteDirections)
                    DropdownMenuItem<String?>(
                      value: d,
                      child: Text('${d[0].toUpperCase()}${d.substring(1)}'),
                    ),
                ],
                onChanged: (v) => setState(() => _direction = v),
              ),
              const SizedBox(height: 16),
              TextFormField(
                controller: _note,
                maxLines: 2,
                decoration: const InputDecoration(
                  labelText: 'Note',
                  helperText: 'Optional — clear to remove',
                ),
              ),
              const SizedBox(height: 16),
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
