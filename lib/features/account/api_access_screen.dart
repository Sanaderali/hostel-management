import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api/account_api.dart';
import '../../core/config/app_config.dart';
import '../../core/providers.dart';
import '../../core/widgets/content_width.dart';

final _accessProvider = FutureProvider.autoDispose(
  (ref) => ref.watch(accountApiProvider).apiAccess(),
);
final _keysProvider = FutureProvider.autoDispose((ref) => ref.watch(accountApiProvider).keys());

/// Per-user API keys. The admin decides (per hostel) whether this is enabled,
/// which scopes are allowed and the rate limit.
class ApiAccessScreen extends ConsumerWidget {
  const ApiAccessScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final access = ref.watch(_accessProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('API Access')),
      body: ContentWidth(
        child: access.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Center(
            child: Padding(padding: const EdgeInsets.all(24), child: Text(errorMessage(e))),
          ),
          data: (a) => a.enabled ? _Enabled(a) : const _Disabled(),
        ),
      ),
      floatingActionButton: access.value?.enabled == true
          ? FloatingActionButton.extended(
              icon: const Icon(Icons.add),
              label: const Text('New key'),
              onPressed: () => showDialog(
                context: context,
                builder: (_) => _CreateKeyDialog(access.value!),
              ).then((_) => ref.invalidate(_keysProvider)),
            )
          : null,
    );
  }
}

class _Disabled extends StatelessWidget {
  const _Disabled();
  @override
  Widget build(BuildContext context) => const Center(
    child: Padding(
      padding: EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.lock_outline, size: 48),
          SizedBox(height: 12),
          Text(
            'API access is not enabled for your hostel.\nContact the administrator to request it.',
            textAlign: TextAlign.center,
          ),
        ],
      ),
    ),
  );
}

class _Enabled extends ConsumerWidget {
  const _Enabled(this.access);
  final ApiAccess access;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final keys = ref.watch(_keysProvider);
    final base = AppConfig.apiBaseUrl;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('Base URL', style: Theme.of(context).textTheme.labelMedium),
                SelectableText(base),
                const SizedBox(height: 8),
                Text(
                  'Limit: ${access.rateLimit} requests/min per key · '
                  'Allowed: ${access.scopes.join(', ')}',
                ),
                const SizedBox(height: 8),
                SelectableText(
                  'curl -H "X-API-Key: <your key>" $base/students',
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 8),
        keys.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error: (e, _) => Text(errorMessage(e)),
          data: (list) => list.isEmpty
              ? const Padding(
                  padding: EdgeInsets.all(24),
                  child: Center(child: Text('No API keys yet')),
                )
              : Column(
                  children: [
                    for (final k in list)
                      Card(
                        child: ListTile(
                          leading: Icon(Icons.key, color: k.revoked ? Colors.grey : null),
                          title: Text(
                            k.name,
                            style: k.revoked
                                ? const TextStyle(decoration: TextDecoration.lineThrough)
                                : null,
                          ),
                          subtitle: Text('${k.prefix}\n${k.scopes.join(', ')}'),
                          isThreeLine: true,
                          trailing: k.revoked
                              ? const Text('Revoked')
                              : IconButton(
                                  tooltip: 'Revoke',
                                  icon: const Icon(Icons.delete_outline),
                                  onPressed: () async {
                                    await ref.read(accountApiProvider).revokeKey(k.id);
                                    ref.invalidate(_keysProvider);
                                  },
                                ),
                        ),
                      ),
                  ],
                ),
        ),
        const SizedBox(height: 80),
      ],
    );
  }
}

class _CreateKeyDialog extends ConsumerStatefulWidget {
  const _CreateKeyDialog(this.access);
  final ApiAccess access;
  @override
  ConsumerState<_CreateKeyDialog> createState() => _CreateKeyDialogState();
}

class _CreateKeyDialogState extends ConsumerState<_CreateKeyDialog> {
  final _name = TextEditingController();
  late final Set<String> _scopes = {...widget.access.scopes.where((s) => s.endsWith(':read'))};
  String? _error, _createdKey;

  Future<void> _create() async {
    try {
      final k = await ref.read(accountApiProvider).createKey(_name.text.trim(), _scopes.toList());
      setState(() => _createdKey = k.fullKey);
    } catch (e) {
      setState(() => _error = errorMessage(e));
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_createdKey != null) {
      return AlertDialog(
        title: const Text('Copy your key now'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('For security it will not be shown again.'),
            const SizedBox(height: 12),
            SelectableText(_createdKey!, style: const TextStyle(fontFamily: 'monospace')),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Clipboard.setData(ClipboardData(text: _createdKey!)),
            child: const Text('Copy'),
          ),
          FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done')),
        ],
      );
    }
    return AlertDialog(
      title: const Text('New API key'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            TextField(
              controller: _name,
              decoration: const InputDecoration(hintText: 'Name, e.g. Website'),
            ),
            const SizedBox(height: 8),
            for (final s in widget.access.scopes)
              CheckboxListTile(
                dense: true,
                title: Text(s),
                value: _scopes.contains(s),
                onChanged: (v) => setState(() => v! ? _scopes.add(s) : _scopes.remove(s)),
              ),
            if (_error != null)
              Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ],
        ),
      ),
      actions: [
        TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
        FilledButton(onPressed: _scopes.isEmpty ? null : _create, child: const Text('Create')),
      ],
    );
  }
}
