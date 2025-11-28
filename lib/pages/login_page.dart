import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_jailbreak_detection/flutter_jailbreak_detection.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan2/pages/bank_dashboard_page.dart';
import 'package:loan2/pages/beneficiary_dashboard.dart';
import 'package:loan2/services/api.dart';

class LoginPage extends StatefulWidget {
  const LoginPage({super.key});

  @override
  State<LoginPage> createState() => _LoginPageState();
}

class _LoginPageState extends State<LoginPage> {
  String _selectedLang = 'en';

  @override
  void initState() {
    super.initState();
    // Use a post-frame callback to safely show a dialog
    // after the first frame has been built.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkDeveloperMode();
    });
  }

  Future<void> _checkDeveloperMode() async {
    bool developerMode;
    try {
      developerMode = await FlutterJailbreakDetection.developerMode;
    } on PlatformException {
      developerMode = true; // Assume developer mode in case of error
    }

    if (developerMode && mounted) {
      showDialog(
        context: context,
        barrierDismissible: false, // User must interact with the dialog
        builder: (BuildContext context) {
          return AlertDialog(
            title: const Text('Developer Mode Enabled'),
            content: const SingleChildScrollView(
              child: ListBody(
                children: <Widget>[
                  Text('This app cannot be used with Developer Mode enabled.'),
                  SizedBox(height: 16),
                  Text('To turn it off:'),
                  Text('1. Go to your device Settings.'),
                  Text('2. Find "Developer options".'),
                  Text('3. Toggle the switch at the top to OFF.'),
                ],
              ),
            ),
            actions: <Widget>[
              TextButton(
                child: const Text('Exit App'),
                onPressed: () {
                  exit(0); // Closes the app
                },
              ),
            ],
          );
        },
      );
    }
  }


  final Map<String, Map<String, String>> _localizedStrings = {
    'en': {
      'app_title': 'NYAY SAHAYAK',
      'ministry': 'Ministry of Social Justice & Empowerment',
      'official_login': 'Official Login',
      'official_subtitle': 'Bank & Govt Officers',
      'beneficiary_login': 'Beneficiary Login',
      'beneficiary_subtitle': 'Citizens & Applicants',
      'secure_footer': 'Secure GovTech Platform',
      'officer_id': 'Officer ID',
      'password': 'Password',
      'secure_login_btn': 'Secure Login',
      'official_login_title': 'Official Login',
      'official_login_desc': 'Secure access for bank & government officers.',
      'mobile_number': 'Mobile Number',
      'send_otp': 'Send OTP',
      'verify_otp': 'Verify & Login',
      'enter_otp': 'Enter Verification Code',
      'otp_sent': 'We sent a code to',
    },
    'hi': {
      'app_title': 'न्याय सहायक',
      'ministry': 'सामाजिक न्याय और अधिकारिता मंत्रालय',
      'official_login': 'अधिकारी लॉगिन',
      'official_subtitle': 'बैंक और सरकारी अधिकारी',
      'beneficiary_login': 'लाभार्थी लॉगिन',
      'beneficiary_subtitle': 'नागरिक और आवेदक',
      'secure_footer': 'सुरक्षित गवटेक प्लेटफॉर्म',
      'officer_id': 'अधिकारी आईडी',
      'password': 'पासवर्ड',
      'secure_login_btn': 'सुरक्षित लॉगिन',
      'official_login_title': 'अधिकारी लॉगिन',
      'official_login_desc': 'बैंक और सरकारी अधिकारियों के लिए सुरक्षित पहुंच।',
      'mobile_number': 'मोबाइल नंबर',
      'send_otp': 'ओटीपी भेजें',
      'verify_otp': 'सत्यापित करें',
      'enter_otp': 'सत्यापन कोड दर्ज करें',
      'otp_sent': 'हमने कोड भेजा है',
    }
  };

  String getStr(String key) {
    return _localizedStrings[_selectedLang]?[key] ?? key;
  }

  // --- OFFICIAL LOGIN SHEET ---
  void _showBankOfficialLogin(BuildContext context) {
    final officerIdController = TextEditingController();
    final passwordController = TextEditingController();

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => _LoginBottomSheet(
        title: getStr('official_login_title'),
        subtitle: getStr('official_login_desc'),
        children: [
          TextField(
            controller: officerIdController,
            decoration: _inputDecoration(getStr('officer_id'), Icons.badge_outlined),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: passwordController,
            obscureText: true,
            decoration: _inputDecoration(getStr('password'), Icons.lock_outline_rounded),
          ),
          const SizedBox(height: 40),
          _PrimaryButton(
            text: getStr('secure_login_btn'),
            onPressed: () async {
              final officerId = officerIdController.text;
              final password = passwordController.text;

              if (officerId.isNotEmpty && password.isNotEmpty) {
                final result = await login_user(officerId, password);
                if (result.isNotEmpty && context.mounted) {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (_) => BankDashboardPage(officerId: officerId)),
                  );
                } else if (context.mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Login Failed. Check credentials.")),
                  );
                }
              } else if (context.mounted) {
                 ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text("Fields cannot be empty.")),
                );
              }
            },
          ),
        ],
      ),
    );
  }

  // --- BENEFICIARY LOGIN SHEET (Fixed State Logic) ---
  void _showBeneficiaryLogin(BuildContext context) {
    final phoneController = TextEditingController();

    // OTP Controllers
    final otp1 = TextEditingController();
    final otp2 = TextEditingController();
    final otp3 = TextEditingController();

    final focus1 = FocusNode();
    final focus2 = FocusNode();
    final focus3 = FocusNode();

    // We use a boolean variable to track state, but inside the builder we rely on setSheetState
    bool isOtpSent = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (context) => StatefulBuilder(
        builder: (BuildContext context, StateSetter setSheetState) {
          return _LoginBottomSheet(
            title: isOtpSent ? getStr('enter_otp') : getStr('beneficiary_login'),
            subtitle: isOtpSent
                ? "${getStr('otp_sent')} +91 ${phoneController.text}"
                : getStr('beneficiary_subtitle'),
            children: [
              if (!isOtpSent) ...[
                // Step 1: Phone Number
                TextField(
                  controller: phoneController,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  decoration: _inputDecoration(getStr('mobile_number'), Icons.phone_android_rounded),
                ),
                const SizedBox(height: 30),
                _PrimaryButton(
                  text: getStr('send_otp'),
                  color: const Color(0xFF138808), // Green
                  onPressed: () {
                    if (phoneController.text.length == 10) {
                      // CRITICAL FIX: Use setSheetState to rebuild the bottom sheet UI
                      setSheetState(() {
                        isOtpSent = true;
                      });
                      // Auto-focus first OTP box
                      Future.delayed(const Duration(milliseconds: 300), () {
                        if (focus1.canRequestFocus) focus1.requestFocus();
                      });
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Enter a valid 10-digit number")));
                    }
                  },
                ),
              ] else ...[
                // Step 2: OTP
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                  children: [
                    _OtpBox(controller: otp1, focusNode: focus1, nextFocus: focus2),
                    _OtpBox(controller: otp2, focusNode: focus2, nextFocus: focus3),
                    _OtpBox(controller: otp3, focusNode: focus3, nextFocus: null),
                  ],
                ),
                const SizedBox(height: 30),
                _PrimaryButton(
                  text: getStr('verify_otp'),
                  color: const Color(0xFF138808),
                  onPressed: () {
                    String otp = otp1.text + otp2.text + otp3.text;
                    // Mock OTP is 200
                    if (otp == '200') {
                      Navigator.pop(context); // Close sheet
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => BeneficiaryDashboard(userId: phoneController.text),
                        ),
                      );
                    } else {
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Invalid OTP (Try 200)")));
                    }
                  },
                ),
                Center(
                  child: TextButton(
                    onPressed: () {
                      // Use setSheetState to go back
                      setSheetState(() {
                        isOtpSent = false;
                        otp1.clear(); otp2.clear(); otp3.clear();
                      });
                    },
                    child: Text("Change Number", style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.w600)),
                  ),
                )
              ]
            ],
          );
        },
      ),
    );
  }

  InputDecoration _inputDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      prefixIcon: Icon(icon, color: const Color(0xFF435E91)),
      filled: true,
      fillColor: Colors.grey[50],
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(16), borderSide: BorderSide(color: Color(0xFF435E91))),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFFFFFFF),
      body: Stack(
        children: [
          // --- Background Shapes ---
          Positioned(
            top: -300,
            right: -300,
            child: Container(
              width: 1000,
              height: 700,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                gradient: RadialGradient(
                  colors: [const Color(0xFFFF8A18).withOpacity(0.30), Colors.transparent], // Saffron hint
                ),
              ),
            ),
          ),
          Positioned(
            bottom: -300,
            left: -300,
            child: Container(
              width: 1000,
              height: 600,
              decoration: BoxDecoration(
                shape: BoxShape.rectangle,
                gradient: RadialGradient(
                  colors: [const Color(0xFF15FB02).withOpacity(0.30), Colors.transparent], // Green hint
                ),
              ),
            ),
          ),


          // --- Language Switcher ---
          Positioned(
            top: 50,
            right: 20,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.9),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: Color(0xFF000080)),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLang,
                  icon: const Icon(Icons.language, size: 20, color: Color(0xFF000080)),
                  isDense: true,
                  onChanged: (v) => setState(() => _selectedLang = v!),
                  items: const [
                    DropdownMenuItem(value: 'en', child: Text("English", style: TextStyle(fontSize: 14))),
                    DropdownMenuItem(value: 'hi', child: Text("हिंदी", style: TextStyle(fontSize: 14))),
                  ],
                ),
              ),
            ),
          ),

          // --- Main Content ---
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: <Widget>[
                    Hero(
                      tag: 'emblem',
                      child: Container(
                        width: 150,
                        height: 120,
                        // FIX: Replaced Image.network with a placeholder Icon to prevent offline crash
                        child: const Icon(Icons.account_balance, size: 80, color: Color(0xFF000080)),
                      ),
                    ),
                    const SizedBox(height: 20),

                    Text(
                      getStr('app_title'),
                      style: GoogleFonts.poppins(fontSize: 28, fontWeight: FontWeight.bold, color: const Color(0xFF000080), letterSpacing: 0.5),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      getStr('ministry'),
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w500, color: Colors.grey[600], height: 1.5),
                    ),

                    const SizedBox(height: 60),

                    // Login Cards
                    _LoginOptionCard(
                      title: getStr('official_login'),
                      subtitle: getStr('official_subtitle'),
                      icon: Icons.admin_panel_settings_outlined,
                      color: const Color(0xFFFF2E2E),
                      isPrimary: true,
                      onTap: () => _showBankOfficialLogin(context),
                    ),

                    const SizedBox(height: 20),

                    _LoginOptionCard(
                      title: getStr('beneficiary_login'),
                      subtitle: getStr('beneficiary_subtitle'),
                      icon: Icons.person_outline_rounded,
                      color: const Color(0xFF138808),
                      isPrimary: true,
                      onTap: () => _showBeneficiaryLogin(context),
                    ),

                    const SizedBox(height: 80),

                    Row(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.verified_user_outlined, size: 16, color: Colors.grey[400]),
                        const SizedBox(width: 8),
                        Text(getStr('secure_footer'), style: GoogleFonts.inter(color: Color(0xFF083188), fontSize: 12, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- REUSABLE WIDGETS ---

class _LoginBottomSheet extends StatelessWidget {
  final String title;
  final String subtitle;
  final List<Widget> children;

  const _LoginBottomSheet({required this.title, required this.subtitle, required this.children});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
          left: 32,
          right: 32,
          top: 32,
          bottom: MediaQuery.of(context).viewInsets.bottom + 32
      ),
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(32)),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 48, height: 5, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2.5)))),
          const SizedBox(height: 32),
          Text(title, style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.bold, color: const Color(0xFF1A1A1A))),
          const SizedBox(height: 8),
          Text(subtitle, style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600])),
          const SizedBox(height: 32),
          ...children,
        ],
      ),
    );
  }
}

class _OtpBox extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final FocusNode? nextFocus;

  const _OtpBox({required this.controller, required this.focusNode, this.nextFocus});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 60,
      height: 60,
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        autofocus: true,
        textAlign: TextAlign.center,
        keyboardType: TextInputType.number,
        style: GoogleFonts.poppins(fontSize: 24, fontWeight: FontWeight.w600),
        inputFormatters: [LengthLimitingTextInputFormatter(1), FilteringTextInputFormatter.digitsOnly],
        decoration: InputDecoration(
          filled: true,
          fillColor: Colors.grey[50],
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
          enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Color(0xFF138808))),
          focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFF138808), width: 2)),
        ),
        onChanged: (value) {
          if (value.length == 1 && nextFocus != null) {
            FocusScope.of(context).requestFocus(nextFocus);
          }
        },
      ),
    );
  }
}

class _LoginOptionCard extends StatelessWidget {
  final String title, subtitle;
  final IconData icon;
  final Color color;
  final VoidCallback onTap;
  final bool isPrimary;

  const _LoginOptionCard({
    required this.title,
    required this.subtitle,
    required this.icon,
    required this.color,
    required this.onTap,
    this.isPrimary = false
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        splashColor: color.withOpacity(0.1),
        child: Ink(
          padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 20),
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.9),
            borderRadius: BorderRadius.circular(16),
            border: isPrimary ? Border.all(color: color.withOpacity(0.3), width: 1.5) : Border.all(color: Colors.white),
            boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 15, offset: const Offset(0, 5))],
          ),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: color.withOpacity(0.1), shape: BoxShape.circle),
                child: Icon(icon, color: color, size: 24),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: const Color(0xFF1A1A1A))),
                    Text(subtitle, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
                  ],
                ),
              ),
              Icon(Icons.arrow_forward_ios_rounded, color: Colors.grey[300], size: 16),
            ],
          ),
        ),
      ),
    );
  }
}

class _PrimaryButton extends StatelessWidget {
  final String text;
  final VoidCallback onPressed;
  final Color color;

  const _PrimaryButton({required this.text, required this.onPressed, this.color = const Color(0xFF000080)});

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: double.infinity,
      height: 56,
      child: ElevatedButton(
        onPressed: onPressed,
        style: ElevatedButton.styleFrom(
          backgroundColor: color,
          foregroundColor: Colors.white,
          elevation: 4,
          shadowColor: color.withOpacity(0.4),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        ),
        child: Text(text, style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
      ),
    );
  }
}
