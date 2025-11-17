import 'package:flutter/material.dart';
import 'package:firebase_auth/firebase_auth.dart';
import '../screens/login_screen.dart';
import '../../../../features/map/presentation/screens/map_screen.dart';

class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  bool _isInitializing = true;
  User? _currentUser;

  @override
  void initState() {
    super.initState();
    _checkAuthState();
  }

  Future<void> _checkAuthState() async {
    // Wait a bit to ensure Firebase is fully initialized
    await Future.delayed(const Duration(milliseconds: 500));
    
    // Check current user
    final user = FirebaseAuth.instance.currentUser;
    
    if (mounted) {
      setState(() {
        _currentUser = user;
        _isInitializing = false;
      });
    }

    // Listen to auth state changes
    FirebaseAuth.instance.authStateChanges().listen((User? user) {
      if (mounted) {
        setState(() {
          _currentUser = user;
        });
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    // Show loading screen while initializing
    if (_isInitializing) {
      return const Scaffold(
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              CircularProgressIndicator(),
              SizedBox(height: 16),
              Text(
                'Loading...',
                style: TextStyle(fontSize: 16, color: Colors.grey),
              ),
            ],
          ),
        ),
      );
    }

    // If user is authenticated, show home screen (MapScreen)
    if (_currentUser != null) {
      return const MapScreen();
    }

    // If user is not authenticated, show login screen FIRST
    return const LoginScreen();
  }
}

