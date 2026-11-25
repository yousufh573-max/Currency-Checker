import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import 'core/theme.dart';
import 'providers/providers.dart';
import 'screens/analysis_screen.dart';
import 'screens/payment_screen.dart';
import 'screens/result_screen.dart';
import 'screens/scanner_screen.dart';
import 'screens/settings_screen.dart';
import 'screens/summary_screen.dart';
import 'screens/welcome_screen.dart';

CustomTransitionPage<void> _fade(Widget child, GoRouterState state) => CustomTransitionPage(
      key: state.pageKey,
      child: child,
      transitionDuration: const Duration(milliseconds: 280),
      transitionsBuilder: (context, anim, _, child) => FadeTransition(opacity: CurvedAnimation(parent: anim, curve: Curves.easeOut), child: child),
    );

GoRouter buildRouter({String initialLocation = '/'}) => GoRouter(
      initialLocation: initialLocation,
      routes: [
        GoRoute(path: '/', pageBuilder: (c, s) => _fade(const WelcomeScreen(), s)),
        GoRoute(path: '/scan', pageBuilder: (c, s) => _fade(const ScannerScreen(), s)),
        GoRoute(path: '/analyze', pageBuilder: (c, s) => _fade(const AnalysisScreen(), s)),
        GoRoute(path: '/result', pageBuilder: (c, s) => _fade(const ResultScreen(), s)),
        GoRoute(path: '/payment', pageBuilder: (c, s) => _fade(const PaymentScreen(), s)),
        GoRoute(path: '/summary', pageBuilder: (c, s) => _fade(const SummaryScreen(), s)),
        GoRoute(path: '/settings', builder: (c, s) => const SettingsScreen()),
      ],
    );

class BanknoteAssistantApp extends ConsumerStatefulWidget {
  const BanknoteAssistantApp({super.key, this.initialLocation = '/'});
  final String initialLocation;

  @override
  ConsumerState<BanknoteAssistantApp> createState() => _BanknoteAssistantAppState();
}

class _BanknoteAssistantAppState extends ConsumerState<BanknoteAssistantApp> with WidgetsBindingObserver {
  late final GoRouter _router = buildRouter(initialLocation: widget.initialLocation);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _configureVoice();
  }

  void _configureVoice() {
    final st = ref.read(settingsProvider);
    final s = ref.read(stringsProvider);
    ref.read(voiceProvider).configure(ttsLocale: s.ttsLocale, sttLocale: s.sttLocale, rate: st.speechRate, preferOffline: st.preferOfflineSpeech);
  }

  /// Release the microphone and stop speech when the app is backgrounded.
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final v = ref.read(voiceProvider);
    if (state == AppLifecycleState.paused || state == AppLifecycleState.hidden) {
      v.setPaused(true);
    } else if (state == AppLifecycleState.resumed) {
      v.setPaused(false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _router.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(settingsProvider, (_, _) => _configureVoice());
    return MaterialApp.router(
      title: 'Banknote Assistant',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(),
      routerConfig: _router,
      builder: (context, child) {
        // Honour Android font scaling, capped so layouts stay usable.
        final mq = MediaQuery.of(context);
        return MediaQuery(data: mq.copyWith(textScaler: mq.textScaler.clamp(minScaleFactor: 1.0, maxScaleFactor: 1.8)), child: child!);
      },
    );
  }
}
