/// Every gated capability. Add a value here to introduce a new feature.
enum Feature { students, bills, notifications, reports, multiHostel }

enum BillingCycle { monthly, yearly }

enum Plan {
  basic({Feature.students}),
  standard({Feature.students, Feature.bills, Feature.notifications}),
  pro({
    Feature.students,
    Feature.bills,
    Feature.notifications,
    Feature.reports,
    Feature.multiHostel,
  });

  const Plan(this.features);
  final Set<Feature> features;
}

/// What the current hostel is allowed to use. Fetched from the server and
/// cached locally so gating keeps working offline.
class Entitlements {
  const Entitlements({
    required this.plan,
    required this.features,
    this.cycle = BillingCycle.monthly,
    this.expiresAt,
  });

  factory Entitlements.forPlan(
    Plan plan,
    DateTime? expiresAt, {
    BillingCycle cycle = BillingCycle.monthly,
  }) => Entitlements(plan: plan, features: plan.features, cycle: cycle, expiresAt: expiresAt);

  /// Fallback when nothing is cached or the subscription lapsed.
  static const free = Entitlements(plan: Plan.basic, features: {Feature.students});

  final Plan plan;
  final Set<Feature> features;
  final BillingCycle cycle;
  final DateTime? expiresAt;

  bool get expired => expiresAt != null && expiresAt!.isBefore(DateTime.now());

  /// Lapsed subscriptions fall back to the free tier.
  bool has(Feature f) => (expired ? free.features : features).contains(f);

  factory Entitlements.fromJson(Map<String, dynamic> j) => Entitlements(
    plan: Plan.values.byName(j['plan'] as String),
    features: {for (final f in (j['features'] as List)) Feature.values.byName(f as String)},
    cycle: BillingCycle.values.byName(j['cycle'] as String? ?? 'monthly'),
    expiresAt: j['expiresAt'] == null ? null : DateTime.parse(j['expiresAt'] as String),
  );

  Map<String, dynamic> toJson() => {
    'plan': plan.name,
    'features': [for (final f in features) f.name],
    'cycle': cycle.name,
    'expiresAt': expiresAt?.toIso8601String(),
  };
}
