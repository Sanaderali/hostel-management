import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../../core/database/app_database.dart';
import '../../core/entitlements/entitlements.dart';
import '../../core/modules/app_module.dart';
import '../../core/providers.dart';
import '../../core/theme/app_theme.dart';
import '../../core/widgets/sync_banner.dart';

final studentsModule = AppModule(
  id: 'students',
  title: 'Students',
  icon: Icons.groups_outlined,
  tint: AppColors.studentsTint,
  actionLabel: 'View students',
  routePath: '/students',
  requires: Feature.students,
  routes: [GoRoute(path: '/students', builder: (_, _) => const StudentsScreen())],
);

final _studentsProvider = StreamProvider.family<List<Student>, String>(
    (ref, q) => ref.watch(studentsRepoProvider).watchAll(q));

class StudentsScreen extends ConsumerStatefulWidget {
  const StudentsScreen({super.key});
  @override
  ConsumerState<StudentsScreen> createState() => _StudentsScreenState();
}

class _StudentsScreenState extends ConsumerState<StudentsScreen> {
  String _q = '';
  @override
  Widget build(BuildContext context) {
    final students = ref.watch(_studentsProvider(_q));
    return Scaffold(
      appBar: AppBar(title: const Text('Students')),
      body: Column(children: [
        const SyncBanner(),
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            onChanged: (v) => setState(() => _q = v),
            decoration: const InputDecoration(
                hintText: 'Search for students', prefixIcon: Icon(Icons.search)),
          ),
        ),
        Expanded(
          child: students.when(
            data: (list) => list.isEmpty
                ? const Center(child: Text('No students yet'))
                : ListView.separated(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    itemCount: list.length,
                    separatorBuilder: (_, _) => const SizedBox(height: 8),
                    itemBuilder: (_, i) => _StudentTile(list[i]),
                  ),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('$e')),
          ),
        ),
      ]),
    );
  }
}

class _StudentTile extends StatelessWidget {
  const _StudentTile(this.s);
  final Student s;
  @override
  Widget build(BuildContext context) => Card(
        color: Theme.of(context).colorScheme.surfaceContainerHighest.withValues(alpha: .4),
        child: ListTile(
          leading: CircleAvatar(child: Text(s.name.isEmpty ? '?' : s.name[0])),
          title: Text(s.name),
          subtitle: Text('${s.course} · Room ${s.room}'),
          trailing: Icon(Icons.circle, size: 10, color: s.inHostel ? Colors.green : Colors.grey),
        ),
      );
}
