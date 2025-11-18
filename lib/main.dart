import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'app/app.dart';

void main() async {
  // Ensure Flutter bindings are initialized
  WidgetsFlutterBinding.ensureInitialized();
  
  // Initialize Firebase - this must complete before showing any UI
  try {
    await Firebase.initializeApp();
  } catch (e) {
    // Handle Firebase initialization error
    debugPrint('Firebase initialization error: $e');
  }
  
  // Run the app - Splash screen will show first, then login, then map
  runApp(const MyApp());
}

