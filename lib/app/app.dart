import 'package:flutter/material.dart';

import '../features/auth/presentation/widgets/auth_wrapper.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Google Maps',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}
