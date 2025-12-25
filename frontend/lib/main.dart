import 'package:flutter/material.dart';
import 'screens/delivery_dashboard.dart'; // <-- UPDATE THIS

void main() {
  runApp(
    const Bot2DoorApp(),
  );
}

class Bot2DoorApp extends StatelessWidget {
  const Bot2DoorApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bot2Door',
      // This line removes the "DEBUG" banner from the corner
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        // Define a vibrant and modern color scheme
        colorScheme: ColorScheme.fromSeed(
          seedColor: const Color(0xFF6A1B9A), // A deep, rich purple
          primary: const Color(0xFF6A1B9A),
          secondary: const Color(0xFF42A5F5), // A vibrant blue for accents
          background: const Color(0xFFF4F6F8), // A clean, light grey background
        ),
        useMaterial3: true,
        scaffoldBackgroundColor: const Color(0xFFF4F6F8),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF6A1B9A), // Use primary color for buttons
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(30), // Pill-shaped buttons
            ),
            padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 32),
            textStyle: const TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.2,
            ),
          ),
        ),
      ),
      // The home screen of the app is the DeliveryDashboardScreen.
      home: const DeliveryDashboardScreen(),
    );
  }
}