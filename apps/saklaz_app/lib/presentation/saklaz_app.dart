import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../infrastructure/providers.dart';
import 'screens/home_screen.dart';
import 'screens/memory_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/saklaz_theme.dart';
import 'widgets/saklaz_logo.dart';

class SaklazApp extends StatelessWidget {
  const SaklazApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'SAKLAZ',
      debugShowCheckedModeBanner: false,
      theme: buildSaklazTheme(),
      darkTheme: buildSaklazTheme(),
      themeMode: ThemeMode.dark,
      locale: const Locale('tr', 'TR'),
      supportedLocales: const [Locale('tr', 'TR')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Bootstrap(),
      routes: {
        SettingsScreen.route: (_) => const SettingsScreen(),
        PermissionsScreen.route: (_) => const PermissionsScreen(),
        MemoryScreen.route: (_) => const MemoryScreen(),
      },
    );
  }
}

/// Şifreli hafıza açılana kadar açılış ekranı gösterir.
class _Bootstrap extends ConsumerWidget {
  const _Bootstrap();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final memory = ref.watch(memoryStoresProvider);
    return memory.when(
      data: (_) => const HomeScreen(),
      loading: () => const Scaffold(body: Center(child: SaklazMark(size: 72))),
      error: (e, _) => Scaffold(body: Center(child: Text('Başlatılamadı: $e'))),
    );
  }
}
