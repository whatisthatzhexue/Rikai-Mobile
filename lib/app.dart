import 'package:flutter/material.dart';

import 'features/home/home_page.dart';

class RikaiApp extends StatelessWidget {
  const RikaiApp({super.key});

  @override
  Widget build(BuildContext context) {
    const seed = Color(0xFF3F5F90);

    return MaterialApp(
      title: 'Rikai',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: seed),
        useMaterial3: true,
      ),
      darkTheme: ThemeData(
        colorScheme: ColorScheme.fromSeed(
          seedColor: seed,
          brightness: Brightness.dark,
        ),
        useMaterial3: true,
      ),
      themeMode: ThemeMode.system,
      home: const HomePage(),
    );
  }
}
