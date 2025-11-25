import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart'; // For kBaseUrl

class CreateBeneficiaryPage extends StatefulWidget {
  const CreateBeneficiaryPage({super.key});

  @override
  State<CreateBeneficiaryPage> createState() => _CreateBeneficiaryPageState();
}

class _CreateBeneficiaryPageState extends State<CreateBeneficiaryPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _loanIdController = TextEditingController();

  // Dropdown Values
  String? _selectedScheme;
  String? _selectedLoanType;
  File? _selectedDoc; // Stores the loan document

  final List<String> _schemes = ['NBCFDC', 'NSFDC', 'NSKFDC'];
  final List<String> _loanTypes = [
    'Agriculture (Tractor)',
    'Small Business',
    'Education',
    'Transport (E-Rickshaw)'
  ];

  // --- File Picker Logic ---
  Future<void> _pickDocument() async {
    try {
      final picker = ImagePicker();
      // Using ImagePicker for simplicity. For PDFs, use 'file_picker' package.
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() => _selectedDoc = File(image.path));
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isLoading = true);

    try {
      // Create Multipart Request (Required for file upload)
      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}bank/beneficiary'));

      // Add Fields
      request.fields['officer_id'] = "OFF1001";
      request.fields['name'] = _nameController.text.trim();
      request.fields['phone'] = _phoneController.text.trim();
      request.fields['amount'] = _amountController.text.trim();
      request.fields['loan_id'] = _loanIdController.text.trim();
      request.fields['scheme'] = _selectedScheme ?? "";
      request.fields['loan_type'] = _selectedLoanType ?? "";

      // Add File if selected
      if (_selectedDoc != null) {
        request.files.add(await http.MultipartFile.fromPath('loan_document', _selectedDoc!.path));
      }

      // Send
      var response = await request.send();
      final respStr = await response.stream.bytesToString();

      if (response.statusCode == 201) {
        if (mounted) _showSuccessDialog();
      } else {
        throw Exception("Server Error: ${response.statusCode} - $respStr");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
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
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.green[50],
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.check_circle, color: Colors.green, size: 50),
            ),
            const SizedBox(height: 16),
            Text("Beneficiary Added", style: GoogleFonts.poppins(fontWeight: FontWeight.bold)),
          ],
        ),
        content: Text(
          "An SMS has been sent to ${_phoneController.text} with login credentials.",
          textAlign: TextAlign.center,
          style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
        ),
        actions: [
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              onPressed: () {
                Navigator.pop(ctx);
                Navigator.pop(context);
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF138808),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
              ),
              child: const Text("Done"),
            ),
          )
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
      appBar: AppBar(
        title: Text("Create Beneficiary", style: GoogleFonts.poppins(color: Colors.black, fontWeight: FontWeight.w600)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(24),
        child: Form(
          key: _formKey,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _buildSectionHeader("Personal Information"),
              _buildCard([
                _buildTextField(
                  controller: _nameController,
                  label: "Full Name",
                  icon: Icons.person_outline_rounded,
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _phoneController,
                  label: "Mobile Number",
                  icon: Icons.phone_android_rounded,
                  inputType: TextInputType.phone,
                  formatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(10)],
                  validator: (v) => v!.length != 10 ? "Invalid Number" : null,
                ),
              ]),

              const SizedBox(height: 24),
              _buildSectionHeader("Loan Details"),
              _buildCard([
                _buildTextField(
                  controller: _loanIdController,
                  label: "Loan Application ID",
                  icon: Icons.numbers_rounded,
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),
                _buildTextField(
                  controller: _amountController,
                  label: "Sanctioned Amount (₹)",
                  icon: Icons.currency_rupee_rounded,
                  inputType: TextInputType.number,
                  validator: (v) => v!.isEmpty ? "Required" : null,
                ),
                const SizedBox(height: 16),
                _buildDropdown(
                  label: "Government Scheme",
                  value: _selectedScheme,
                  items: _schemes,
                  onChanged: (v) => setState(() => _selectedScheme = v),
                  icon: Icons.account_balance_rounded,
                ),
                const SizedBox(height: 16),
                _buildDropdown(
                  label: "Loan Category",
                  value: _selectedLoanType,
                  items: _loanTypes,
                  onChanged: (v) => setState(() => _selectedLoanType = v),
                  icon: Icons.category_rounded,
                ),
              ]),

              const SizedBox(height: 24),
              _buildSectionHeader("Documents"),
              _buildUploadCard(),

              const SizedBox(height: 40),
              SizedBox(
                width: double.infinity,
                height: 56,
                child: ElevatedButton(
                  onPressed: _isLoading ? null : _submitForm,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF138808),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                    elevation: 4,
                    shadowColor: const Color(0xFF138808).withOpacity(0.4),
                  ),
                  child: _isLoading
                      ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                      : Text("Create & Send SMS", style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600)),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12, left: 4),
      child: Text(
        title,
        style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600, color: Colors.grey[600], letterSpacing: 0.5),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10, offset: const Offset(0, 4)),
        ],
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(children: children),
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
        labelStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: const Color(0xFF435E91), size: 22),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
        focusedBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: const BorderSide(color: Color(0xFFFF9933), width: 1.5)),
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
      items: items.map((e) => DropdownMenuItem(value: e, child: Text(e, style: GoogleFonts.inter()))).toList(),
      onChanged: onChanged,
      validator: (v) => v == null ? "Required" : null,
      decoration: InputDecoration(
        labelText: label,
        labelStyle: GoogleFonts.inter(fontSize: 14, color: Colors.grey[500]),
        prefixIcon: Icon(icon, color: const Color(0xFF435E91), size: 22),
        filled: true,
        fillColor: const Color(0xFFF9FAFB),
        border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
        enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: Colors.grey.shade200)),
      ),
    );
  }

  Widget _buildUploadCard() {
    return InkWell(
      onTap: _pickDocument,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: _selectedDoc != null ? Colors.green : Colors.grey.shade300, style: BorderStyle.solid),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _selectedDoc != null ? Colors.green.withOpacity(0.1) : Colors.blue.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _selectedDoc != null ? Icons.check : Icons.upload_file_rounded,
                color: _selectedDoc != null ? Colors.green : const Color(0xFF435E91),
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _selectedDoc != null ? "Document Attached" : "Upload Loan Agreement",
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              _selectedDoc != null ? _selectedDoc!.path.split('/').last : "PDF or Image (Max 5MB)",
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}