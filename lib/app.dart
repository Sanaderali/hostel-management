import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'core/modules/registry.dart';
import 'core/providers.dart';
import 'core/theme/app_theme.dart';
import 'core/auth/auth_controller.dart';
import 'features/account/api_access_screen.dart';
import 'features/account/login_screen.dart';
import 'features/home/home_screen.dart';
import 'features/home/upgrade_screen.dart';

final routerProvider = Provider<GoRouter>((ref) {
  final authChanged = ValueNotifier(0);
  ref.listen(authProvider, (_, _) => authChanged.value++);
  ref.onDispose(authChanged.dispose);
  return GoRouter(
    refreshListenable: authChanged,
    redirect: (_, state) {
      final signedIn = ref.read(authProvider) != null;
      final atLogin = state.matchedLocation == '/login';
      if (!signedIn) return atLogin ? null : '/login';
      return atLogin ? '/' : null;
    },
    routes: [
      GoRoute(path: '/', builder: (_, _) => const HomeScreen()),
      GoRoute(path: '/login', builder: (_, _) => const LoginScreen()),
      GoRoute(path: '/upgrade', builder: (_, _) => const UpgradeScreen()),
      GoRoute(path: '/account/api', builder: (_, _) => const ApiAccessScreen()),
      for (final m in appModules) ...m.routes,
    ],
  );
});

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
