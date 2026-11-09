import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../providers.dart';

/// Shows "Offline" and/or the number of changes waiting to sync.
class SyncBanner extends ConsumerWidget {
  const SyncBanner({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final online = ref.watch(isOnlineProvider).value ?? true;
    final pending = ref.watch(pendingChangesProvider).value ?? 0;
    if (online && pending == 0) return const SizedBox.shrink();
    final cs = Theme.of(context).colorScheme;
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      color: online ? cs.primaryContainer : cs.errorContainer,
      child: Text(
        [if (!online) 'Offline — changes are saved on this device', if (pending > 0) '$pending waiting to sync']
            .join(' · '),
        style: Theme.of(context).textTheme.labelMedium,
      ),
    );
  }
}
