import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'data/store.dart';
import 'ui/auth/auth_screens.dart';
import 'ui/shell.dart';
import 'ui/theme.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  AppStore? store;
  Object? error;
  try {
    store = AppStore.load();
  } catch (e) {
    error = e;
  }
  if (store == null) {
    runApp(_ErrorApp(error: error));
    return;
  }
  runApp(TarazApp(store: store));
}

class TarazApp extends StatelessWidget {
  final AppStore store;

  /// Skips the login screen (used by tests).
  final bool startUnlocked;
  final AppPage initialPage;

  const TarazApp({
    super.key,
    required this.store,
    this.startUnlocked = false,
    this.initialPage = AppPage.dashboard,
  });

  @override
  Widget build(BuildContext context) {
    return StoreScope(
      store: store,
      child: Builder(builder: (context) {
        final s = StoreScope.of(context).settings;
        final accent = Color(s.accent);
        return MaterialApp(
          title: 'تراز - حسابداری',
          debugShowCheckedModeBanner: false,
          locale: const Locale('fa', 'IR'),
          supportedLocales: const [Locale('fa', 'IR'), Locale('en', 'US')],
          localizationsDelegates: const [
            GlobalMaterialLocalizations.delegate,
            GlobalWidgetsLocalizations.delegate,
            GlobalCupertinoLocalizations.delegate,
          ],
          themeMode: switch (s.themeMode) {
            'dark' => ThemeMode.dark,
            'system' => ThemeMode.system,
            _ => ThemeMode.light,
          },
          theme: buildTheme(brightness: Brightness.light, accent: accent),
          darkTheme: buildTheme(brightness: Brightness.dark, accent: accent),
          home: _Gate(startUnlocked: startUnlocked, initialPage: initialPage),
        );
      }),
    );
  }
}

/// Decides between first-run setup, login and the main window.
class _Gate extends StatefulWidget {
  final bool startUnlocked;
  final AppPage initialPage;
  const _Gate({required this.startUnlocked, required this.initialPage});

  @override
  State<_Gate> createState() => _GateState();
}

class _GateState extends State<_Gate> {
  late bool _unlocked = widget.startUnlocked;

  @override
  Widget build(BuildContext context) {
    final s = StoreScope.of(context).settings;
    Widget child;
    if (!s.setupDone && !_unlocked) {
      child = SetupScreen(key: const ValueKey('setup'), onDone: () => setState(() => _unlocked = true));
    } else if (s.hasPassword && !_unlocked) {
      child = LoginScreen(key: const ValueKey('login'), onSuccess: () => setState(() => _unlocked = true));
    } else {
      child = Shell(
        key: const ValueKey('shell'),
        initialPage: widget.initialPage,
        onLock: s.hasPassword ? () => setState(() => _unlocked = false) : null,
      );
    }
    return AnimatedSwitcher(duration: const Duration(milliseconds: 250), child: child);
  }
}

class _ErrorApp extends StatelessWidget {
  final Object? error;
  const _ErrorApp({this.error});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(32),
            child: SelectableText(
              'Taraz could not open its data file.\n\n$error',
              textAlign: TextAlign.center,
            ),
          ),
        ),
      ),
    );
  }
}
