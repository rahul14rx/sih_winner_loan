import 'package:flutter/material.dart';
import 'package:loan2/pages/beneficiary_login_page.dart';
import 'package:loan2/pages/bank_dashboard_page.dart';
import 'package:loan2/services/api.dart'; // Import api service

class LoginPage extends StatelessWidget {
  const LoginPage({super.key});

  void _showBankOfficialLogin(BuildContext context) {
    final TextEditingController idController = TextEditingController();
    final TextEditingController passController = TextEditingController();

    showDialog(
      context: context,
      builder: (BuildContext context) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          title: const Text(
            'Bank Official Login',
            textAlign: TextAlign.center,
            style: TextStyle(fontWeight: FontWeight.bold),
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: <Widget>[
              TextField(
                controller: idController,
                decoration: InputDecoration(
                  labelText: 'Login ID',
                  prefixIcon: const Icon(Icons.person),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              TextField(
                controller: passController,
                obscureText: true,
                decoration: InputDecoration(
                  labelText: 'Password',
                  prefixIcon: const Icon(Icons.lock),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
            ],
          ),
          actions: <Widget>[
            TextButton(
              child: const Text('Cancel'),
              onPressed: () {
                Navigator.of(context).pop();
              },
            ),
            ElevatedButton(
              child: const Text('Login'),
              onPressed: () async {
                // Validate inputs
                final loginId = idController.text.trim();
                final password = passController.text.trim();

                if (loginId.isEmpty || password.isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Please enter both ID and Password')),
                  );
                  return;
                }

                // Show loading indicator or disable button?
                // Ideally, we'd update state, but in a dialog it's simpler to just proceed or use a StatefulBuilder.
                // For now, let's assume the user waits a moment.

                try {
                  final response = await postJson(
                    'login', // Assuming your flask route is /login
                    body: {
                      'login_id': loginId,
                      'password': password,
                      'role': 'officer',
                    },
                  );

                  // If we reach here, status code was 2xx (success) due to postJson logic
                  if (context.mounted) {
                    Navigator.of(context).pop(); // Close dialog
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BankDashboardPage(),
                      ),
                    );
                  }
                } catch (e) {
                  // Handle error (401, 400, etc. throws Exception in postJson)
                  if (context.mounted) {
                    // Show error message
                     ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text(e.toString().replaceAll('Exception:', '').trim())),
                    );
                    // We do NOT pop the dialog, so user can re-enter password
                  }
                }
              },
            ),
          ],
        );
      },
    );
  }



  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            colors: [
              const Color(0xFFFF9933).withOpacity(0.8), // Saffron
              Colors.white,
              const Color(0xFF138808).withOpacity(0.8), // Green
            ],
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            stops: const [0.0, 0.5, 1.0],
          ),
        ),
        child: Center(
          child: Padding(
            padding: const EdgeInsets.all(20.0),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: <Widget>[
                // Emblem
                Image.network(
                  'https://upload.wikimedia.org/wikipedia/commons/thumb/5/55/Emblem_of_India.svg/1200px-Emblem_of_India.svg.png',
                  height: 150,
                   errorBuilder: (context, error, stackTrace) {
                    // This widget prevents the app from crashing if the image fails to load
                    return const Icon(Icons.broken_image, size: 100, color: Colors.grey);
                  },
                ),
                const SizedBox(height: 20),
                const Text(
                  'NYAY SAHAYAK',
                  style: TextStyle(
                    fontSize: 32,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFF000080), // Navy Blue
                  ),
                ),
                const Text(
                  'Ministry of Social Justice and Empowerment',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w500,
                    color: Color(0xFF000080), // Navy Blue
                  ),
                ),
                const SizedBox(height: 50),
                ElevatedButton(
                  onPressed: () => _showBankOfficialLogin(context),
                  child: const Text('Bank Official Login'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const BeneficiaryLoginPage()),
                    );
                  },
                  child: const Text('Beneficiary Login'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
