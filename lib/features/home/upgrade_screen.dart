import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/providers.dart';

/// Placeholder: real purchase flow is handled by the backend/payments later.
class UpgradeScreen extends ConsumerWidget {
  const UpgradeScreen({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final current = ref.watch(entitlementsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Plans')),
      body: ListView(padding: const EdgeInsets.all(16), children: [
        for (final p in Plan.values)
          Card(
            child: ListTile(
              title: Text(p.name.toUpperCase()),
              subtitle: Text(p.features.map((f) => f.name).join(', ')),
              trailing: p == current.plan ? const Icon(Icons.check_circle) : null,
            ),
          ),
        const Padding(
          padding: EdgeInsets.all(16),
          child: Text('Monthly / yearly billing will be managed from the admin backend.'),
        ),
      ]),
    );
  }
}
