import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import '../features/auth/presentation/screens/splash_screen.dart';

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'maarg setu',
      theme: ThemeData(
        // Black and white color scheme
        primarySwatch: Colors.grey,
        primaryColor: Colors.black,
        scaffoldBackgroundColor: Colors.white,
        colorScheme: const ColorScheme.light(
          primary: Colors.black,
          secondary: Colors.grey,
          surface: Colors.white,
          background: Colors.white,
          error: Colors.black87,
          onPrimary: Colors.white,
          onSecondary: Colors.black,
          onSurface: Colors.black,
          onBackground: Colors.black,
          onError: Colors.white,
        ),
        // Montserrat font family
        fontFamily: GoogleFonts.montserrat().fontFamily,
        textTheme: TextTheme(
          // Headings - Medium weight, Black color
          displayLarge: GoogleFonts.montserrat(
            fontSize: 57,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          displayMedium: GoogleFonts.montserrat(
            fontSize: 45,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          displaySmall: GoogleFonts.montserrat(
            fontSize: 36,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          headlineLarge: GoogleFonts.montserrat(
            fontSize: 32,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          headlineMedium: GoogleFonts.montserrat(
            fontSize: 28,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          headlineSmall: GoogleFonts.montserrat(
            fontSize: 24,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          titleLarge: GoogleFonts.montserrat(
            fontSize: 22,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          titleMedium: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          titleSmall: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
          // Subheadings and small sections - Light weight, Gray color
          bodyLarge: GoogleFonts.montserrat(
            fontSize: 16,
            fontWeight: FontWeight.w300, // Light
            color: Colors.grey[700],
          ),
          bodyMedium: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w300, // Light
            color: Colors.grey[700],
          ),
          bodySmall: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w300, // Light
            color: Colors.grey[600],
          ),
          labelLarge: GoogleFonts.montserrat(
            fontSize: 14,
            fontWeight: FontWeight.w300, // Light
            color: Colors.grey[700],
          ),
          labelMedium: GoogleFonts.montserrat(
            fontSize: 12,
            fontWeight: FontWeight.w300, // Light
            color: Colors.grey[600],
          ),
          labelSmall: GoogleFonts.montserrat(
            fontSize: 11,
            fontWeight: FontWeight.w300, // Light
            color: Colors.grey[600],
          ),
        ),
        // AppBar theme - black and white
        appBarTheme: AppBarTheme(
          backgroundColor: Colors.white,
          foregroundColor: Colors.black,
          elevation: 0,
          iconTheme: const IconThemeData(color: Colors.black),
          titleTextStyle: GoogleFonts.montserrat(
            fontSize: 20,
            fontWeight: FontWeight.w500, // Medium
            color: Colors.black,
          ),
        ),
        // Card them
        // Input decoration theme
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: Colors.white,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: BorderSide(color: Colors.grey[400]!),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(8),
            borderSide: const BorderSide(color: Colors.black, width: 2),
          ),
          labelStyle: GoogleFonts.montserrat(
            fontWeight: FontWeight.w300,
            color: Colors.grey[700],
          ),
          hintStyle: GoogleFonts.montserrat(
            fontWeight: FontWeight.w300,
            color: Colors.grey[500],
          ),
        ),
        // Button themes
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
            textStyle: GoogleFonts.montserrat(
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: Colors.black,
            textStyle: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w300,
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: Colors.black,
            side: const BorderSide(color: Colors.black),
            textStyle: GoogleFonts.montserrat(
              fontSize: 14,
              fontWeight: FontWeight.w300,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(8),
            ),
          ),
        ),
      ),
      // Start with splash screen - it will navigate to login or map
      home: const SplashScreen(),
      debugShowCheckedModeBanner: false,
    );
  }
}
