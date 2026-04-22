import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:uuid/uuid.dart';

import '../constants.dart';
import '../models/shooter.dart';
import '../repositories/shooter_repository.dart';
import '../services/contact_validator.dart';
import '../state/shooter_state.dart';

class ShooterPickerScreen extends StatefulWidget {
  const ShooterPickerScreen({super.key});

  @override
  State<ShooterPickerScreen> createState() => _ShooterPickerScreenState();
}

class _ShooterPickerScreenState extends State<ShooterPickerScreen> {
  late Future<List<Shooter>> _future;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  void _reload() {
    final repo = context.read<ShooterRepository>();
    _future = repo.listAll();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Select shooter')),
      body: FutureBuilder<List<Shooter>>(
        future: _future,
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final shooters = snap.data!;
          return ListView(
            children: [
              for (final s in shooters)
                ListTile(
                  leading: Icon(
                    s.id == kUnassignedShooterId
                        ? Icons.person_off_outlined
                        : Icons.person_outline,
                  ),
                  title: Text(s.displayName),
                  onTap: () async {
                    await context.read<ShooterState>().selectShooter(s.id);
                    if (mounted) Navigator.pop(context);
                  },
                ),
              const Divider(),
              ListTile(
                leading: const Icon(Icons.add),
                title: const Text('+ Add shooter'),
                onTap: () async {
                  final created = await Navigator.push<Shooter?>(
                    context,
                    MaterialPageRoute(
                      builder: (_) => MultiProvider(
                        providers: [
                          Provider<ShooterRepository>.value(
                            value: context.read<ShooterRepository>(),
                          ),
                        ],
                        child: const _AddShooterForm(),
                      ),
                    ),
                  );
                  if (created != null && mounted) {
                    await context.read<ShooterState>().selectShooter(created.id);
                    if (mounted) Navigator.pop(context);
                  } else if (mounted) {
                    setState(_reload);
                  }
                },
              ),
            ],
          );
        },
      ),
    );
  }
}

class _AddShooterForm extends StatefulWidget {
  const _AddShooterForm();

  @override
  State<_AddShooterForm> createState() => _AddShooterFormState();
}

class _AddShooterFormState extends State<_AddShooterForm> {
  final _nameCtrl = TextEditingController();
  final _emailCtrl = TextEditingController();
  final _phoneCtrl = TextEditingController();
  bool _linkOpen = false;
  String? _emailWarning;
  String? _phoneWarning;

  @override
  void dispose() {
    _nameCtrl.dispose();
    _emailCtrl.dispose();
    _phoneCtrl.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final name = _nameCtrl.text.trim();
    if (name.isEmpty) return;

    final rawEmail = _emailCtrl.text.trim();
    final rawPhone = _phoneCtrl.text.trim();
    String? savedEmail;
    String? savedPhone;

    if (rawEmail.isNotEmpty) {
      savedEmail = rawEmail;
      if (!ContactValidator.isValidEmail(rawEmail)) {
        setState(() => _emailWarning =
            'Email format looks wrong — saved anyway. Edit later if needed.');
      }
    }
    if (rawPhone.isNotEmpty) {
      final normalized = ContactValidator.normalizePhone(rawPhone);
      if (normalized != null) {
        savedPhone = normalized;
      } else {
        savedPhone = rawPhone;
        setState(() => _phoneWarning =
            'Phone format unrecognized — saved as-is. Edit later if needed.');
      }
    }

    final s = Shooter(
      id: const Uuid().v4(),
      displayName: name,
      contactEmail: savedEmail,
      contactPhone: savedPhone,
      createdAt: DateTime.now(),
    );
    await context.read<ShooterRepository>().insert(s);
    if (mounted) Navigator.pop(context, s);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add shooter')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: ListView(
          children: [
            TextField(
              controller: _nameCtrl,
              decoration: const InputDecoration(
                labelText: 'Display name',
                hintText: 'e.g. Jeremy',
              ),
            ),
            const SizedBox(height: 16),
            ExpansionTile(
              initiallyExpanded: _linkOpen,
              onExpansionChanged: (v) => setState(() => _linkOpen = v),
              title: const Text('Link for later (optional)'),
              subtitle: const Text(
                'Enter your email or phone and your training data will '
                'automatically sync when you get your own Atriarch or '
                'sign in to Range Buddy.',
              ),
              children: [
                TextField(
                  controller: _emailCtrl,
                  decoration: InputDecoration(
                    labelText: 'Email (optional)',
                    errorText: _emailWarning,
                  ),
                ),
                const SizedBox(height: 8),
                TextField(
                  controller: _phoneCtrl,
                  decoration: InputDecoration(
                    labelText: 'Phone (optional)',
                    errorText: _phoneWarning,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 24),
            FilledButton(
              onPressed: _save,
              child: const Text('Save'),
            ),
          ],
        ),
      ),
    );
  }
}
