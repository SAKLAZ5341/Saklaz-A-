import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'screens/home_screen.dart';
import 'screens/permissions_screen.dart';
import 'screens/settings_screen.dart';
import 'theme/saklaz_theme.dart';

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
      routes: {
        '/': (_) => const HomeScreen(),
        SettingsScreen.route: (_) => const SettingsScreen(),
        PermissionsScreen.route: (_) => const PermissionsScreen(),
      },
    );
  }
}
