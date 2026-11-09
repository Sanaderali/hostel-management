import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/modules/app_module.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/sync_banner.dart';
import 'bills_repository.dart';

final billsModule = AppModule(
  id: 'bills',
  title: 'Hostel Bills',
  icon: Icons.receipt_long_outlined,
  tint: AppColors.billsTint,
  actionLabel: 'View Bills',
  routePath: '/bills',
  requires: Feature.bills,
  routes: [GoRoute(path: '/bills', builder: (_, _) => const BillsScreen())],
);

class _BillFilterController extends Notifier<BillFilter> {
  @override
  BillFilter build() => BillFilter.all;
  void set(BillFilter f) => state = f;
}

final _billFilterProvider =
    NotifierProvider<_BillFilterController, BillFilter>(_BillFilterController.new);
final _billsProvider = StreamProvider<List<Bill>>(
    (ref) => ref.watch(billsRepoProvider).watch(ref.watch(_billFilterProvider)));

class BillsScreen extends ConsumerWidget {
  const BillsScreen({super.key});

  static const _style = {
    'electricity': (Icons.lightbulb_outline, AppColors.electricity, 'Electricity Bill'),
    'water': (Icons.water_drop_outlined, AppColors.water, 'Water Bill'),
    'gas': (Icons.local_fire_department_outlined, AppColors.gas, 'Gas Bill'),
  };

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final filter = ref.watch(_billFilterProvider);
    final bills = ref.watch(_billsProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Billing History')),
      body: Column(children: [
        const SyncBanner(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: SegmentedButton<BillFilter>(
            segments: [for (final f in BillFilter.values) ButtonSegment(value: f, label: Text(f.name.toUpperCase()))],
            selected: {filter},
            onSelectionChanged: (s) => ref.read(_billFilterProvider.notifier).set(s.first),
          ),
        ),
        Expanded(
          child: bills.when(
            data: (list) => ListView.separated(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              itemCount: list.length,
              separatorBuilder: (_, _) => const SizedBox(height: 12),
              itemBuilder: (_, i) {
                final b = list[i];
                final (icon, color, title) = _style[b.type] ?? (Icons.receipt, AppColors.primary, b.type);
                return Card(
                  color: color,
                  child: ListTile(
                    contentPadding: const EdgeInsets.all(16),
                    leading: Icon(icon, color: Colors.white, size: 36),
                    title: Text(title, style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
                    subtitle: Text('${b.month} · Rs ${b.amount.toStringAsFixed(0)}',
                        style: const TextStyle(color: Colors.white70)),
                    trailing: FilterChip(
                      label: Text(b.paid ? 'Paid' : 'Unpaid'),
                      avatar: Icon(Icons.circle, size: 10, color: b.paid ? Colors.green : Colors.red),
                      selected: false,
                      onSelected: (_) => ref.read(billsRepoProvider).setPaid(b, !b.paid),
                    ),
                  ),
                );
              },
            ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          ),
        ),
      ]),
    );
  }
}
