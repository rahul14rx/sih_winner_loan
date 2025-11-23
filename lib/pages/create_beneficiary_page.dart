import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:loan2/services/bank_service.dart';

class CreateBeneficiaryPage extends StatefulWidget {
  const CreateBeneficiaryPage({super.key});

  @override
  State<CreateBeneficiaryPage> createState() => _CreateBeneficiaryPageState();
}

class _CreateBeneficiaryPageState extends State<CreateBeneficiaryPage> {
  final _formKey = GlobalKey<FormState>();
  final BankService _bankService = BankService();
  bool _isLoading = false;

  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _loanIdController = TextEditingController();

  // Dropdown Values
  String? _selectedScheme;
  String? _selectedLoanType;

  final List<String> _schemes = ['NBCFDC', 'NSFDC', 'NSKFDC'];
  final List<String> _loanTypes = [
    'Agriculture (Tractor)',
    'Small Business',
    'Education',
    'Transport (E-Rickshaw)'
  ];

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    final data = {
      "officer_id": "OFF1001", // Hardcoded for demo
      "name": _nameController.text.trim(),
      "phone": _phoneController.text.trim(),
      "amount": int.parse(_amountController.text.trim()),
      "loan_id": _loanIdController.text.trim(),
      "scheme": _selectedScheme,
      "loan_type": _selectedLoanType,
    };

    try {
      await _bankService.createBeneficiary(data);
      if (mounted) {
        _showSuccessDialog();
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(e.toString()), backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _showSuccessDialog() {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(15)),
        title: const Column(
          children: [
            Icon(Icons.check_circle, color: Colors.green, size: 60),
            SizedBox(height: 10),
            Text("Beneficiary Added"),
          ],
        ),
        content: Text(
          "An SMS has been sent to ${_phoneController.text} with login instructions.",
          textAlign: TextAlign.center,
        ),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(ctx); // Close Dialog
              Navigator.pop(context); // Go back to Dashboard
            },
            child: const Text("Done", style: TextStyle(fontSize: 16)),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text("Add New Beneficiary"),
        backgroundColor: const Color(0xFFFF9933),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFFFF9933), Colors.white],
            stops: [0.0, 0.3],
          ),
        ),
        child: Form(
          key: _formKey,
          child: ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                child: Padding(
                  padding: const EdgeInsets.all(24),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        "Personal Details",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF000080)),
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _nameController,
                        label: "Full Name",
                        icon: Icons.person,
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _phoneController,
                        label: "Mobile Number",
                        icon: Icons.phone_android,
                        inputType: TextInputType.phone,
                        formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                        validator: (v) => v!.length != 10 ? "Invalid Number" : null,
                      ),
                      const Divider(height: 40, thickness: 1),
                      const Text(
                        "Loan Details",
                        style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF000080)),
                      ),
                      const SizedBox(height: 20),
                      _buildTextField(
                        controller: _loanIdController,
                        label: "Loan ID / Application No.",
                        icon: Icons.numbers,
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      ),
                      const SizedBox(height: 16),
                      _buildTextField(
                        controller: _amountController,
                        label: "Sanctioned Amount (₹)",
                        icon: Icons.currency_rupee,
                        inputType: TextInputType.number,
                        validator: (v) => v!.isEmpty ? "Required" : null,
                      ),
                      const SizedBox(height: 16),
                      _buildDropdown(
                        label: "Govt Scheme",
                        value: _selectedScheme,
                        items: _schemes,
                        onChanged: (v) => setState(() => _selectedScheme = v),
                        icon: Icons.account_balance,
                      ),
                      const SizedBox(height: 16),
                      _buildDropdown(
                        label: "Loan Category",
                        value: _selectedLoanType,
                        items: _loanTypes,
                        onChanged: (v) => setState(() => _selectedLoanType = v),
                        icon: Icons.category,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 30),
              SizedBox(
                height: 55,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF138808), // Gov Green
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    elevation: 5,
                  ),
                  child: _isLoading
                      ? const CircularProgressIndicator(color: Colors.white)
                      : const Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(Icons.send, color: Colors.white),
                      SizedBox(width: 10),
                      Text("Create & Send SMS", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildTextField({
    required TextEditingController controller,
    required String label,
    required IconData icon,
    TextInputType inputType = TextInputType.text,
    List<TextInputFormatter>? formatters,
    String? Function(String?)? validator,
  }) {
    return TextFormField(
      controller: controller,
      keyboardType: inputType,
      inputFormatters: formatters,
      validator: validator,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Color(0xFFFF9933), width: 2),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(10),
          borderSide: const BorderSide(color: Colors.red),
        ),
      ),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required Function(String?) onChanged,
    required IconData icon,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e))).toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? "Required" : null,
      decoration: InputDecoration(
        labelText: label,
        prefixIcon: Icon(icon, color: Colors.grey[600]),
        filled: true,
        fillColor: Colors.grey[50],
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(10), borderSide: BorderSide.none),
      ),
    );
  }
}