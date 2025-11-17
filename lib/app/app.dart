import 'package:flutter/material.dart';

import '../features/auth/presentation/screens/splash_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Maps',
      theme: ThemeData(primarySwatch: Colors.blue),
      // Start with splash screen - it will navigate to login or map
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
