import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'login_screen.dart';
import '../../../../features/map/presentation/screens/map_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    // Navigate after splash duration
    _navigateToNext();
  }

  Future<void> _navigateToNext() async {
    // Wait for 2 seconds to show splash screen
    await Future.delayed(const Duration(seconds: 2));
    
    if (!mounted) return;
    
    // Check if user is already authenticated
    final user = FirebaseAuth.instance.currentUser;
    
    if (user != null) {
      // User is already logged in, go to map screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const MapScreen()),
      );
    } else {
      // User is not logged in, go to login screen
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (context) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // App Logo/Icon
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Colors.black,
                  width: 2,
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.1),
                    blurRadius: 20,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: const Icon(
                Icons.map,
                size: 80,
                color: Colors.black,
              ),
            ),
            const SizedBox(height: 32),
            
            // App Title - using theme headlineMedium (medium weight, black)
            Text(
              'Google Maps App',
              style: Theme.of(context).textTheme.headlineMedium,
            ),
            const SizedBox(height: 8),
            
            // Subtitle - using theme bodyLarge (light weight, gray)
            Text(
              'Navigate with confidence',
              style: Theme.of(context).textTheme.bodyLarge,
            ),
            const SizedBox(height: 48),
            
            // Loading indicator
            const CircularProgressIndicator(
              valueColor: AlwaysStoppedAnimation<Color>(Colors.black),
            ),
          ],
        ),
      ),
    );
  }
}

