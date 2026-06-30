import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/enums.dart';
import '../../models/site.dart';
import '../../services/providers.dart';
import '../../theme/app_theme.dart';

/// Form for submitting a new community site. Validates required fields and
/// writes through [siteRepositoryProvider].
class AddSiteScreen extends ConsumerStatefulWidget {
  const AddSiteScreen({super.key, this.initialState = AusState.nsw});

  final AusState initialState;

  @override
  ConsumerState<AddSiteScreen> createState() => _AddSiteScreenState();
}

class _AddSiteScreenState extends ConsumerState<AddSiteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _suburb = TextEditingController();
  late AusState _state;
  SiteType _type = SiteType.checkingStation;
  String? _direction;
  bool _submitting = false;

  @override
  void initState() {
    super.initState();
    _state = widget.initialState;
  }

  @override
  void dispose() {
    _name.dispose();
    _address.dispose();
    _suburb.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _submitting = true);
    final site = Site(
      id: '', // repository assigns an id
      name: _name.text.trim(),
      type: _type,
      state: _state,
      suburb: _suburb.text.trim(),
      address: _address.text.trim(),
      direction: _direction,
    );
    try {
      await ref.read(siteRepositoryProvider).addSite(site);
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Submitted for review — thanks!')),
      );
      context.canPop() ? context.pop() : context.go('/home');
    } catch (e) {
      if (!mounted) return;
      setState(() => _submitting = false);
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Could not submit: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: Colors.transparent,
        title: const Text('Add Site'),
        leading: IconButton(
          icon: const Icon(Icons.close),
          onPressed: () =>
              context.canPop() ? context.pop() : context.go('/home'),
        ),
      ),
      body: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              _label('Site name'),
              TextFormField(
                controller: _name,
                decoration: const InputDecoration(
                  hintText: 'e.g. Marulan Checking Station',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _label('State'),
              DropdownButtonFormField<AusState>(
                initialValue: _state,
                items: [
                  for (final s in AusState.values)
                    DropdownMenuItem(
                      value: s,
                      child: Text('${s.code} — ${s.fullName}'),
                    ),
                ],
                onChanged: (v) => setState(() => _state = v!),
              ),
              const SizedBox(height: 16),
              _label('Type'),
              DropdownButtonFormField<SiteType>(
                initialValue: _type,
                items: [
                  for (final t in SiteType.values)
                    DropdownMenuItem(value: t, child: Text(t.label)),
                ],
                onChanged: (v) => setState(() => _type = v!),
              ),
              const SizedBox(height: 16),
              _label('Suburb / locality'),
              TextFormField(
                controller: _suburb,
                decoration: const InputDecoration(hintText: 'e.g. Marulan'),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _label('Address / route'),
              TextFormField(
                controller: _address,
                decoration: const InputDecoration(
                  hintText: 'e.g. Hume Highway',
                ),
                validator: (v) =>
                    (v == null || v.trim().isEmpty) ? 'Required' : null,
              ),
              const SizedBox(height: 16),
              _label('Direction (optional)'),
              DropdownButtonFormField<String?>(
                initialValue: _direction,
                items: const [
                  DropdownMenuItem(value: null, child: Text('Not applicable')),
                  DropdownMenuItem(
                    value: 'northbound',
                    child: Text('Northbound'),
                  ),
                  DropdownMenuItem(
                    value: 'southbound',
                    child: Text('Southbound'),
                  ),
                ],
                onChanged: (v) => setState(() => _direction = v),
              ),
              const SizedBox(height: 28),
              FilledButton(
                style: FilledButton.styleFrom(
                  backgroundColor: AppTheme.accent,
                  foregroundColor: Colors.white,
                  minimumSize: const Size.fromHeight(50),
                ),
                onPressed: _submitting ? null : _submit,
                child: _submitting
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Text('Submit site'),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _label(String text) => Padding(
    padding: const EdgeInsets.only(bottom: 6),
    child: Text(
      text,
      style: const TextStyle(
        color: AppTheme.textSecondary,
        fontSize: 13,
        fontWeight: FontWeight.w600,
      ),
    ),
  );
}
