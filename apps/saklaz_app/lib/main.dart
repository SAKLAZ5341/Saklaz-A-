import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'infrastructure/providers.dart';
import 'presentation/overlay/assist_overlay.dart';
import 'presentation/saklaz_app.dart';

/// Tam uygulama.
void main() {
  WidgetsFlutterBinding.ensureInitialized();
  SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
  runApp(const ProviderScope(child: SaklazApp()));
}

/// Yan tuş paneli (Kotlin OverlayEngine bu giriş noktasını çalıştırır).
@pragma('vm:entry-point')
void assistantOverlayMain() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(ProviderScope(
    overrides: [isOverlayProvider.overrideWithValue(true)],
    child: const AssistOverlayApp(),
  ));
}
