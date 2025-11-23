import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loan2/pages/beneficiary_dashboard.dart';

// ---------------------------------------------------------------------------
// NOTE: Ensure you have your api.dart, loan_process_page.dart, etc. set up
// as per your project structure so the navigation routes work.
// ---------------------------------------------------------------------------

class BeneficiaryLoginPage extends StatefulWidget {
  const BeneficiaryLoginPage({super.key});

  @override
  State<BeneficiaryLoginPage> createState() => _BeneficiaryLoginPageState();
}

enum BeneficiaryStep { phone, otp }

class _BeneficiaryLoginPageState extends State<BeneficiaryLoginPage> {
  BeneficiaryStep _step = BeneficiaryStep.phone;

  final _phoneFormKey = GlobalKey<FormState>();
  final _otpFormKey = GlobalKey<FormState>();

  final _phoneController = TextEditingController();
  final _otpController = TextEditingController();

  bool _isSendingOtp = false;
  String? _generatedOtp; // For local simulation, matching your old logic

  @override
  void dispose() {
    _phoneController.dispose();
    _otpController.dispose();
    super.dispose();
  }

  // --- Logic from your old citizen_login.dart ---

  Future<void> _sendOtp() async {
    if (!(_phoneFormKey.currentState?.validate() ?? false)) {
      return;
    }

    setState(() => _isSendingOtp = true);

    try {
      // Simulate network delay
      await Future.delayed(const Duration(seconds: 2));

      // Local Mock OTP logic from your old file
      const mockOtp = '200';
      _generatedOtp = mockOtp;

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('OTP Generated Locally: 200')),
        );
        setState(() => _step = BeneficiaryStep.otp);
      }
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Failed to send OTP: $e')),
      );
    } finally {
      if (mounted) setState(() => _isSendingOtp = false);
    }
  }

  void _verifyOtp() {
    if (!(_otpFormKey.currentState?.validate() ?? false)) return;

    final enteredOtp = _otpController.text.trim();

    // Check against the locally generated mock OTP
    if (_generatedOtp == null || enteredOtp != _generatedOtp) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Invalid OTP. Try 200.')),
      );
      return;
    }

    // Success! Navigate to the next screen.
    // Make sure '/loan-process' is defined in your main.dart routes,
    // or use MaterialPageRoute directly if you prefer.
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(content: Text('OTP Verified! Logging in...')),
    );

    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(
        builder: (context) => BeneficiaryDashboard(
          userId: _phoneController.text.trim(),
        ),
      ),
          (route) => false,
    );
  }

  // --- UI Construction ---

  @override
  Widget build(BuildContext context) {
    final primaryColor = Theme.of(context).primaryColor; // Saffron from main.dart

    return Scaffold(
      appBar: AppBar(
        title: const Text('Beneficiary Login'),
        backgroundColor: primaryColor,
        foregroundColor: Colors.white,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(24.0),
          child: _step == BeneficiaryStep.phone
              ? _buildPhoneStep()
              : _buildOtpStep(),
        ),
      ),
    );
  }

  Widget _buildPhoneStep() {
    return Form(
      key: _phoneFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Welcome Beneficiary',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF000080), // Navy Blue
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Please enter your mobile number to verify your identity.',
            style: TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _phoneController,
            keyboardType: TextInputType.phone,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(10),
            ],
            decoration: InputDecoration(
              labelText: 'Mobile Number',
              prefixIcon: const Icon(Icons.phone_android),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter your mobile number';
              }
              if (value.trim().length != 10) {
                return 'Mobile number must be 10 digits';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _isSendingOtp ? null : _sendOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF138808), // Green
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: _isSendingOtp
                ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
                : const Text(
              'Send OTP',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOtpStep() {
    return Form(
      key: _otpFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            'Verify OTP',
            style: TextStyle(
              fontSize: 24,
              fontWeight: FontWeight.bold,
              color: Color(0xFF000080),
            ),
          ),
          const SizedBox(height: 8),
          Text(
            'Enter the 3-digit code sent to ${_phoneController.text}.',
            style: const TextStyle(fontSize: 16, color: Colors.grey),
          ),
          const SizedBox(height: 32),
          TextFormField(
            controller: _otpController,
            keyboardType: TextInputType.number,
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              LengthLimitingTextInputFormatter(3), // Mock OTP is 3 digits
            ],
            decoration: InputDecoration(
              labelText: 'Enter OTP',
              prefixIcon: const Icon(Icons.lock_outline),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            validator: (value) {
              if (value == null || value.trim().isEmpty) {
                return 'Please enter the OTP';
              }
              return null;
            },
          ),
          const SizedBox(height: 24),
          ElevatedButton(
            onPressed: _verifyOtp,
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF138808),
              padding: const EdgeInsets.symmetric(vertical: 15),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(10),
              ),
            ),
            child: const Text(
              'Verify & Login',
              style: TextStyle(fontSize: 18, color: Colors.white),
            ),
          ),
          const SizedBox(height: 16),
          TextButton(
            onPressed: () {
              setState(() {
                _step = BeneficiaryStep.phone;
                _otpController.clear();
              });
            },
            child: const Text('Change Mobile Number'),
          ),
        ],
      ),
    );
  }
}