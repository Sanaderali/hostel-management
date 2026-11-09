import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/auth/auth_controller.dart';
import '../../core/modules/app_module.dart';
import '../../core/modules/registry.dart';
import '../../core/providers.dart';
import '../../core/widgets/content_width.dart';
import '../../core/widgets/sync_banner.dart';

class HomeScreen extends ConsumerWidget {
  const HomeScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final mode = ref.watch(themeModeProvider);
    final dark =
        mode == ThemeMode.dark ||
        (mode == ThemeMode.system && MediaQuery.platformBrightnessOf(context) == Brightness.dark);
    return Scaffold(
      appBar: AppBar(
        leading: const Icon(Icons.menu),
        title: const Text(''),
        actions: [
          IconButton(
            tooltip: 'Toggle dark mode',
            icon: Icon(dark ? Icons.light_mode_outlined : Icons.dark_mode_outlined),
            onPressed: () =>
                ref.read(themeModeProvider.notifier).set(dark ? ThemeMode.light : ThemeMode.dark),
          ),
          IconButton(icon: const Icon(Icons.notifications_none), onPressed: () {}),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'api' => context.push('/account/api'),
              'plans' => context.push('/upgrade'),
              _ => ref.read(authProvider.notifier).logout(),
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'api', child: Text('API access')),
              PopupMenuItem(value: 'plans', child: Text('Plans')),
              PopupMenuItem(value: 'out', child: Text('Sign out')),
            ],
          ),
        ],
      ),
      body: SafeArea(
        child: ContentWidth(
          child: Column(
            children: [
              const SyncBanner(),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.all(20),
                  children: [
                    Row(
                      children: [
                        const Text('👋', style: TextStyle(fontSize: 36)),
                        const SizedBox(width: 12),
                        Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('Welcome back to', style: theme.textTheme.titleMedium),
                            Text('Hostel management app', style: theme.textTheme.bodySmall),
                          ],
                        ),
                      ],
                    ),
                    const SizedBox(height: 16),
                    const TextField(
                      decoration: InputDecoration(
                        hintText: 'Search for students, bills etc',
                        prefixIcon: Icon(Icons.search),
                      ),
                    ),
                    const SizedBox(height: 24),
                    Text('Hostel Activity', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    const _ActivityCard(),
                    const SizedBox(height: 24),
                    Text('Category', style: theme.textTheme.titleLarge),
                    const SizedBox(height: 12),
                    GridView.count(
                      crossAxisCount: 2,
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      mainAxisSpacing: 12,
                      crossAxisSpacing: 12,
                      childAspectRatio: .95,
                      children: [for (final m in appModules) _ModuleCard(m)],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActivityCard extends StatelessWidget {
  const _ActivityCard();
  @override
  Widget build(BuildContext context) => Container(
    height: 160,
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      borderRadius: BorderRadius.circular(22),
      gradient: const LinearGradient(colors: [Color(0xFF0A2FD6), Color(0xFF1A8CFF)]),
    ),
    child: const Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text('● On duty Shahab', style: TextStyle(color: Colors.white70)),
        Spacer(),
        Text(
          'Water Tank Detail',
          style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
        ),
      ],
    ),
  );
}

class _ModuleCard extends ConsumerWidget {
  const _ModuleCard(this.m);
  final AppModule m;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final unlocked = m.requires == null || ref.watch(hasFeatureProvider(m.requires!));
    final dark = Theme.of(context).brightness == Brightness.dark;
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: dark ? m.tint.withValues(alpha: .18) : m.tint,
        borderRadius: BorderRadius.circular(22),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Icon(unlocked ? m.icon : Icons.lock_outline, size: 32),
          Text(
            m.title,
            style: Theme.of(context).textTheme.titleMedium,
            textAlign: TextAlign.center,
          ),
          SizedBox(
            width: double.infinity,
            child: FilledButton(
              onPressed: () => context.push(unlocked ? m.routePath : '/upgrade'),
              child: Text(unlocked ? m.actionLabel : 'Upgrade'),
            ),
          ),
        ],
      ),
    );
  }
}
