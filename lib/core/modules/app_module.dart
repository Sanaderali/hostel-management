import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../entitlements/entitlements.dart';

/// A self-contained feature. To add a feature later: create a module, add it
/// to `appModules` (lib/core/modules/registry.dart). Nothing else changes.
class AppModule {
  const AppModule({
    required this.id,
    required this.title,
    required this.icon,
    required this.tint,
    required this.actionLabel,
    required this.routePath,
    required this.routes,
    this.requires,
  });

  final String id;
  final String title;
  final IconData icon;
  final Color tint;
  final String actionLabel;
  final String routePath;
  final List<RouteBase> routes;

  /// Subscription feature needed to open this module (null = always on).
  final Feature? requires;
}
