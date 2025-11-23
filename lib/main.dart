import 'package:flutter/material.dart';
import 'package:loan2/pages/login_page.dart';
import 'package:loan2/pages/loan_process_page.dart';
import 'package:loan2/services/sync_service.dart'; // <-- Added this import

void main() {
  WidgetsFlutterBinding.ensureInitialized(); // <-- Added this
  SyncService.startListener(); // <-- Added this to start auto-sync
  runApp(const NyaySahayakApp());
}

class NyaySahayakApp extends StatelessWidget {
  const NyaySahayakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nyay Sahayak',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        primaryColor: const Color(0xFFFF9933), // Saffron
        colorScheme: ColorScheme.fromSwatch().copyWith(
          primary: const Color(0xFFFF9933), // Saffron
          secondary: const Color(0xFF138808), // Green
        ),
        scaffoldBackgroundColor: Colors.white,
        appBarTheme: const AppBarTheme(
          backgroundColor: Color(0xFFFF9933),
          elevation: 0,
          titleTextStyle: TextStyle(
            color: Colors.white,
            fontSize: 20,
            fontWeight: FontWeight.bold,
          ),
          iconTheme: IconThemeData(color: Colors.white),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF138808), // Green
            foregroundColor: Colors.white,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(10),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 50, vertical: 15),
          ),
        ),
      ),
      // Start with the Login Page
      home: const LoginPage(),

      // Define your Named Routes here
      routes: {
        // The route name we used in beneficiary_login_page.dart
        '/loan-process': (context) {
          // Extract the arguments passed from Navigator.pushNamed
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;
          final userId = args?['userId'] as String? ?? '';

          // Return the Loan Process Page with the user ID
          return LoanProcessPage(userId: userId);
        },
      },
    );
  }
}