import 'package:flutter/material.dart';

import '../features/map/presentation/screens/map_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Live Location Map',
      theme: ThemeData(primarySwatch: Colors.blue),
      home: const MapScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
