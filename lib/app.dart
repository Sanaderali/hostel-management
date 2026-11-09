import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'core/modules/registry.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'features/home/home_screen.dart';
import 'features/home/upgrade_screen.dart';

final routerProvider = Provider<GoRouter>((ref) => GoRouter(routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/upgrade', builder: (_, _) => const UpgradeScreen()),
      for (final m in appModules) ...m.routes,
    ]));

class HostelApp extends ConsumerWidget {
  const HostelApp({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(syncCoordinatorProvider);
    return MaterialApp.router(
      title: 'Hostel Management',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: ref.watch(themeModeProvider),
      routerConfig: ref.watch(routerProvider),
    );
  }
}
