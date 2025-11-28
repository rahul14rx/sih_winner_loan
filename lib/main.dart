import 'package:flutter/material.dart';
import 'package:loan2/pages/login_page.dart';
import 'package:loan2/pages/loan_process_page.dart';
import 'package:loan2/services/sync_service.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SyncService.startListener();

  runApp(const NyaySahayakApp());
}

class NyaySahayakApp extends StatelessWidget {
  const NyaySahayakApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Nyay Sahayak',
      debugShowCheckedModeBanner: false,
      theme: _buildTheme(),
      home: const LoginPage(),
      routes: {
        '/loan-process': (context) {
          final args = ModalRoute.of(context)?.settings.arguments as Map<String, dynamic>?;

          final userId = args?['userId'] as String? ?? '';
          final loanId = args?['loanId'] as String? ?? '';

          if (loanId.isEmpty) {
            return const Scaffold(body: Center(child: Text("loanId missing")));
          }
          return LoanProcessPage(loanId: loanId, userId: userId);
        },
      },


    );
  }

  ThemeData _buildTheme() {
    final base = ThemeData.light();

    return base.copyWith(
      primaryColor: const Color(0xFFD26C00), // Saffron
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),

      // 1. Typography (FIX: Removed GoogleFonts to prevent offline crash)
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
        bodyLarge: const TextStyle(fontSize: 16, color: Color(0xFF4A4A4A)),
        bodyMedium: const TextStyle(fontSize: 14, color: Color(0xFF6A6A6A)),
      ),

      // 2. Card Theme (FIX: Corrected class name)
      cardTheme: CardThemeData(
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
        color: Colors.white,
        margin: EdgeInsets.zero,
      ),

      // 3. Input Fields
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: Colors.grey.shade50,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: const BorderSide(color: Color(0xFFFF9933), width: 1.5),
        ),
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIconColor: const Color(0xFF435E91),
      ),

      // 4. Buttons
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF138808),
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color.fromRGBO(19, 136, 8, 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}