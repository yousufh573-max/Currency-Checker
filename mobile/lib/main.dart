import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:material_ui/material_ui.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'app.dart';
import 'providers/providers.dart';
import 'services/storage/session_repository.dart';
import 'services/storage/temp_images.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await SystemChrome.setPreferredOrientations([DeviceOrientation.portraitUp]);
  // Real system status bar (time, Wi-Fi, battery) with light icons on navy.
  await SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  SystemChrome.setSystemUIOverlayStyle(const SystemUiOverlayStyle(
    statusBarColor: Colors.transparent,
    statusBarIconBrightness: Brightness.light,
    systemNavigationBarColor: Color(0xFF07152A),
    systemNavigationBarIconBrightness: Brightness.light,
  ));

  final prefs = await SharedPreferences.getInstance();
  final repo = await SessionRepository.open();
  final temp = await TempImageStore.create(); // also wipes leftover captures
  final active = await repo.loadActive();

  runApp(ProviderScope(
    overrides: [
      sharedPrefsProvider.overrideWithValue(prefs),
      sessionRepoProvider.overrideWithValue(repo),
      tempImagesProvider.overrideWithValue(temp),
      initialSessionProvider.overrideWithValue(active),
    ],
    child: const BanknoteAssistantApp(),
  ));
}
