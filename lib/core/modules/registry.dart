import '../../features/bills/bills_module.dart';
import '../../features/students/students_module.dart';
import 'app_module.dart';

/// THE place to plug in new features (notifications, rooms, reports, ...).
final appModules = <AppModule>[studentsModule, billsModule];
