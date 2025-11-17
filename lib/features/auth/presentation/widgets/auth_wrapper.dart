import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/splash_screen.dart';
import '../screens/login_screen.dart';
import '../../../../features/map/presentation/screens/map_screen.dart';

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show splash screen initially
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const SplashScreen();
        }

        // If user is authenticated, show map screen (home)
        if (snapshot.hasData && snapshot.data != null) {
          return const MapScreen();
        }

        // If user is not authenticated, show login screen
        return const LoginScreen();
      },
    );
  }
}

