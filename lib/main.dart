import 'package:flutter/material.dart';
import 'package:loan2/pages/login_page.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:loan2/services/app_i18n.dart';
import 'package:loan2/services/app_theme.dart';
import 'package:loan2/pages/loan_process_page.dart' as lp; // defines LoanDetailPage

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  SyncService.startListener();
  runApp(const NyaySahayakApp());
}

class NyaySahayakApp extends StatelessWidget {
  const NyaySahayakApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Rebuild on language + theme changes
    return ValueListenableBuilder<String>(
      valueListenable: AppI18n.lang,
      builder: (_, __, ___) {
        return ValueListenableBuilder<ThemeMode>(
          valueListenable: AppTheme.mode,
          builder: (_, themeMode, ____) {
            return MaterialApp(
              title: 'Nyay Sahayak',
              debugShowCheckedModeBanner: false,
              theme: _lightTheme(),
              darkTheme: _darkTheme(),
              themeMode: themeMode,
              home: const LoginPage(),
              // Safer than 'routes' when passing arg maps
              onGenerateRoute: (settings) {
                if (settings.name == '/loan-process') {
                  final args = (settings.arguments as Map<String, dynamic>?) ?? {};
                  final loanId = (args['loanId'] as String?) ?? '';
                  final userId = (args['userId'] as String?) ?? ''; // pass userId too

                  if (loanId.isEmpty) {
                    return MaterialPageRoute(
                      builder: (_) => const Scaffold(
                        body: Center(child: Text('loanId missing')),
                      ),
                    );
                  }

                  // pages/loan_process_page.dart exposes: class LoanProcessPage
                  return MaterialPageRoute(
                    builder: (_) => lp.LoanProcessPage(
                      loanId: loanId,
                      userId: userId,
                    ),
                  );
                }
                return null;
              },

            );
          },
        );
      },
    );
  }

  // ---------- Light Theme ----------
  ThemeData _lightTheme() {
    final base = ThemeData.light();
    return base.copyWith(
      primaryColor: const Color(0xFFD26C00),
      scaffoldBackgroundColor: const Color(0xFFFAFAFA),
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(fontWeight: FontWeight.bold, color: Color(0xFF1A1A1A)),
        bodyLarge: const TextStyle(fontSize: 16, color: Color(0xFF4A4A4A)),
        bodyMedium: const TextStyle(fontSize: 14, color: Color(0xFF6A6A6A)),
      ),
      // Use CardThemeData (Flutter 3.38 cardTheme expects CardThemeData?)
      cardTheme: CardThemeData(
        color: Colors.white,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          // cannot be const because of .shade200
          side: BorderSide(color: Colors.grey.shade200, width: 1),
        ),
      ),
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
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFFFF9933), width: 1.5),
        ),
        labelStyle: const TextStyle(color: Colors.grey),
        prefixIconColor: const Color(0xFF435E91),
      ),
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

  // ---------- Dark Theme (Blue Night) ----------
  ThemeData _darkTheme() {
    const scaffold = Color(0xFF0B1220);
    const card = Color(0xFF0F1B2D);
    const border = Color(0xFF1F2A44);

    final base = ThemeData.dark();
    return base.copyWith(
      scaffoldBackgroundColor: scaffold,
      canvasColor: scaffold,
      cardColor: card,
      primaryColor: const Color(0xFF1E5AA8),
      appBarTheme: const AppBarTheme(
        backgroundColor: const Color(0xFF1E5AA8),
        foregroundColor: Colors.white,
        elevation: 0,
      ),
      cardTheme: CardThemeData(
        color: card,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: const BorderSide(color: border, width: 1),
        ),
      ),
      dividerColor: border,
      textTheme: base.textTheme.copyWith(
        displayLarge: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
        bodyLarge: const TextStyle(fontSize: 16, color: Color(0xFFE5E7EB)),
        bodyMedium: const TextStyle(fontSize: 14, color: Color(0xFFCBD5E1)),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: scaffold,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide.none,
        ),
        enabledBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: border),
        ),
        focusedBorder: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
          borderSide: BorderSide(color: Color(0xFF60A5FA), width: 1.5),
        ),
        labelStyle: const TextStyle(color: Color(0xFF94A3B8)),
        prefixIconColor: const Color(0xFF9CA3AF),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          backgroundColor: const Color(0xFF16A34A),
          foregroundColor: Colors.white,
          elevation: 2,
          shadowColor: const Color.fromRGBO(22, 163, 74, 0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
          padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
          textStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
        ),
      ),
    );
  }
}
