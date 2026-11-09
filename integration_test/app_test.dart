// End-to-end check of the real app against the local backend (server/).
//   cd server && npm start     # in one terminal
//   flutter test integration_test/app_test.dart -d <emulator-or-phone-id>
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hostel_management/app.dart';
import 'package:hostel_management/core/providers.dart';
import 'package:integration_test/integration_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

Future<void> until(WidgetTester t, Finder f, {int seconds = 15}) async {
  for (var i = 0; i < seconds * 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
    if (f.evaluate().isNotEmpty) return;
  }
  final texts = find.byType(Text).evaluate().map((e) => (e.widget as Text).data).toList();
  throw TestFailure('Timed out waiting for $f. Visible texts: $texts');
}

Future<void> hold(WidgetTester t) => t.pump(const Duration(seconds: 2)); // time for a screenshot

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('login, sync, bills, API keys', (t) async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    await t.pumpWidget(
      ProviderScope(
        overrides: [
          sharedPrefsProvider.overrideWithValue(prefs),
          // Headless CI/containers may lack NetworkManager (headless Linux only); not needed on phones.
          if (const bool.fromEnvironment('ASSUME_ONLINE'))
            isOnlineProvider.overrideWith((_) => Stream.value(true)),
        ],
        child: const HostelApp(),
      ),
    );

    // Wrong password is rejected with the server's message.
    await until(t, find.text('Sign in'));
    await t.enterText(find.byType(TextField).at(0), 'owner@demo.local');
    await t.enterText(find.byType(TextField).at(1), 'wrong');
    await t.tap(find.text('Sign in'));
    await until(t, find.text('Wrong email or password'));
    await hold(t);

    await t.tap(find.byType(TextField).at(1));
    await t.pump(const Duration(milliseconds: 300));
    await t.enterText(find.byType(TextField).at(1), 'owner12345');
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('Sign in'));
    await until(t, find.text('Hostel Activity'));
    await hold(t);

    // Data arrived by sync and is read from the local DB.
    await t.ensureVisible(find.text('View students'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('View students'));
    await until(t, find.text('Moazam Naveed'));
    await hold(t);
    await t.pageBack();
    await t.pumpAndSettle();

    await t.ensureVisible(find.text('View Bills'));
    await t.pump(const Duration(milliseconds: 300));
    await t.tap(find.text('View Bills'));
    await until(t, find.text('Electricity Bill'));
    await hold(t);
    await t.pageBack();
    await t.pumpAndSettle();

    // Dark mode.
    await t.tap(find.byTooltip('Toggle dark mode'));
    await t.pumpAndSettle();
    await hold(t);

    // API access screen: create a key.
    await t.tap(find.byType(PopupMenuButton<String>));
    await t.pumpAndSettle();
    await t.tap(find.text('API access'));
    await until(t, find.text('New key'));
    await hold(t);
    await t.tap(find.text('New key'));
    await t.pumpAndSettle();
    await t.enterText(find.byType(TextField).last, 'My website');
    await t.tap(find.text('Create'));
    await until(t, find.text('Copy your key now'));
    final key = (t.widget(find.byType(SelectableText).last) as SelectableText).data!;
    // ignore: avoid_print
    print('API_KEY=$key');
    expect(key, startsWith('hk_'));
    await hold(t);
    await t.tap(find.text('Done'));
    await until(t, find.text('My website'));
    await hold(t);
  });
}
