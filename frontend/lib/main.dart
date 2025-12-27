import 'package:flutter/material.dart';
import 'screens/delivery_dashboard.dart'; // Make sure this path is correct!

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Bot2Door Terminal',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.blue),
        useMaterial3: true,
      ),
      debugShowCheckedModeBanner: false,
      home: const DeliveryDashboardScreen(),
    );
  }
}