import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:loan2/widgets/officer_nav_bar.dart';

class CreateBeneficiaryPage extends StatefulWidget {
  final String officerId;
  const CreateBeneficiaryPage({super.key, required this.officerId});

  @override
  State<CreateBeneficiaryPage> createState() => _CreateBeneficiaryPageState();
}

class _CreateBeneficiaryPageState extends State<CreateBeneficiaryPage> {
  final _formKey = GlobalKey<FormState>();
  bool _isLoading = false;

  // Original Controllers
  final _nameController = TextEditingController();
  final _phoneController = TextEditingController();
  final _amountController = TextEditingController();
  final _loanIdController = TextEditingController();

  // New Controllers for the new fields (kept empty as requested)
  final _addressController = TextEditingController();
  final _assetController = TextEditingController();

  // State for dropdowns
  String? _selectedScheme;
  String? _selectedLoanType;
  String? _selectedPurpose;
  String? _selectedFloors;

  // State for the new file picker
  File? _loanAgreementFile;

  static const _accent = Color(0xFF1E5AA8);
  static const double _headerRadius = 25;

  // --- DATA FOR DROPDOWNS (UNCHANGED) ---
  final List<String> _schemes = ['NBCFDC', 'NSFDC', 'NSKFDC'];
  final List<String> _floors = List.generate(10, (i) => '${i + 1}');
  bool get _showFloorsDropdown {
    final p = (_selectedPurpose ?? '').toLowerCase();
    return p.contains('construction');
  }

  final Map<String, List<String>> _loanTypesByScheme = {
    'NBCFDC': [
      'General Term Loan',
      'Micro-credit Loan',
      'Education Loan',
      'Skill Development Loan',
      'Entrepreneurial Development Loan',
      'Livelihood Loan'
    ],
    'NSKFDC': [
      'Self-Employment Scheme for Liberation & Rehabilitation of Safai Karamchari (SRMS)',
      'Sanitation Equipment Loan',
      'Small Business Loans',
      'Skill Development Loan'
    ],
    'NSFDC': [
      'Term Loan',
      'Micro-Finance Loan',
      'Skill Development Loan',
      'Education Loan',
      'Livelihood Loan'
    ],
  };

  final Map<String, Map<String, List<String>>> _purposeBySchemeCategory = {
    'NBCFDC': {
      'General Term Loan': ['Auto Rickshaws', 'Tractors', 'Shop construction / purchase'],
      'Micro-credit Loan': ['Sewing Machines', 'Cows'],
      'Education Loan': ['Laptop', 'Fees paid for admissions', 'Courses'],
      'Skill Development Loan': ['Technical Courses', 'Non-Technical Courses'],
      'Entrepreneurial Development Loan': ['Laptop'],
      'Livelihood Loan': ['Sewing Machine', 'Cows'],
    },
    'NSKFDC': {
      'Self-Employment Scheme for Liberation & Rehabilitation of Safai Karamchari (SRMS)': [
        'E-Rickshaws',
        'Construction of shops / kiosks'
      ],
      'Sanitation Equipment Loan': ['PPE kits (Safety gears)'],
      'Small Business Loans': ['Sewing Machine'],
      'Skill Development Loan': ['Courses'],
    },
    'NSFDC': {
      'Term Loan': ['Tractor'],
      'Micro-Finance Loan': ['Sewing Machine'],
      'Skill Development Loan': ['Course', 'Laptop'],
      'Education Loan': ['Admission Fees', 'Hostel Fees', 'Laptop', 'Courses'],
      'Livelihood Loan': ['Sewing Machine', 'Cows'],
    },
  };

  List<String> get _currentLoanTypes => _loanTypesByScheme[_selectedScheme] ?? const [];

  List<String> get _currentPurposes {
    final s = _selectedScheme;
    final c = _selectedLoanType;
    if (s == null || c == null) return const [];
    return _purposeBySchemeCategory[s]?[c] ?? const [];
  }
  // --- END OF DROPDOWN DATA ---

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _loanIdController.dispose();
    _addressController.dispose();
    _assetController.dispose();
    super.dispose();
  }

  Future<void> _pickLoanAgreement() async {
    try {
      final picker = ImagePicker();
      final XFile? image = await picker.pickImage(source: ImageSource.gallery);
      if (image != null) {
        setState(() => _loanAgreementFile = File(image.path));
      }
    } catch (e) {
      debugPrint("Error picking file: $e");
    }
  }

  Future<void> _submitForm() async {
    if (!_formKey.currentState!.validate()) return;
    if (_loanAgreementFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please attach the loan agreement file."), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    // Prepare all the data
    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final amount = _amountController.text.trim();
    final loanId = _loanIdController.text.trim();
    final scheme = _selectedScheme ?? "";
    final cat = _selectedLoanType ?? "";
    final pur = _selectedPurpose ?? "";
    final loanTypeFinal = pur.isEmpty ? cat : '$cat - $pur';
    final address = _addressController.text.trim();
    final asset = _assetController.text.trim();
    final docPath = _loanAgreementFile?.path;

    try {
      bool isOnline = await SyncService.realInternetCheck();

      if (isOnline) {
        // API CALL IS BACK!
        var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}bank/beneficiary'));
        request.fields['officer_id'] = widget.officerId;
        request.fields['name'] = name;
        request.fields['phone'] = phone;
        request.fields['amount'] = amount;
        request.fields['loan_id'] = loanId;
        request.fields['scheme'] = scheme;
        request.fields['loan_type'] = loanTypeFinal;
        request.fields['beneficiary_address'] = address; // NEW FIELD
        request.fields['asset_purchased'] = asset; // NEW FIELD

        if (docPath != null) {
          request.files.add(await http.MultipartFile.fromPath('loan_agreement', docPath)); // NEW FILE
        }
        if (_showFloorsDropdown && _selectedFloors != null) {
          request.fields['floors'] = _selectedFloors!;
        }

        var response = await request.send();
        final respStr = await response.stream.bytesToString();

        if (response.statusCode == 201) {
          if (mounted) _showSuccessDialog(isOffline: false);
        } else {
          throw Exception("Server Error: ${response.statusCode} - $respStr");
        }
      } else {
        // Save offline if no internet
        await _saveOffline(
          name: name,
          phone: phone,
          amount: amount,
          loanId: loanId,
          scheme: scheme,
          loanType: loanTypeFinal,
          docPath: docPath,
        );
        if (mounted) _showSuccessDialog(isOffline: true);
      }
    } catch (e) {
      debugPrint("API Error, saving offline: $e");
      await _saveOffline(
        name: name,
        phone: phone,
        amount: amount,
        loanId: loanId,
        scheme: scheme,
        loanType: loanTypeFinal,
        docPath: docPath,
      );

      if (mounted) _showSuccessDialog(isOffline: true, error: e.toString());
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _saveOffline({
    required String name,
    required String phone,
    required String amount,
    required String loanId,
    required String scheme,
    required String loanType,
    String? docPath,
  }) async {
    await DatabaseHelper.instance.insertPendingBeneficiary(
      officerId: widget.officerId,
      name: name,
      phone: phone,
      amount: amount,
      loanId: loanId,
      scheme: scheme,
      loanType: loanType,
      docPath: docPath,
    );
  }


  void _showSuccessDialog({required bool isOffline, String? error}) {
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isOffline ? Colors.orange[50] : Colors.green[50],
                  shape: BoxShape.circle,
                ),
                child: Icon(
                  isOffline ? Icons.cloud_queue : Icons.check_circle,
                  color: isOffline ? Colors.orange : Colors.green,
                  size: 50,
                ),
              ),
              const SizedBox(height: 16),
              Text(
                isOffline ? "Saved Offline" : "Beneficiary Added",
                style: GoogleFonts.poppins(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            isOffline
                ? (error != null
                ? "An API error occurred, but your data has been saved safely offline. It will sync automatically."
                : "No internet. Data saved locally and will sync automatically.")
                : "An SMS has been sent to ${_phoneController.text} with login credentials.",
            textAlign: TextAlign.center,
            style: GoogleFonts.inter(fontSize: 14, color: Colors.grey[600]),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx); // close ONLY the dialog

                  if (!mounted) return;

                  _formKey.currentState?.reset();
                  _nameController.clear();
                  _phoneController.clear();
                  _amountController.clear();
                  _loanIdController.clear();
                  _addressController.clear();
                  _assetController.clear();

                  setState(() {
                    _selectedScheme = null;
                    _selectedLoanType = null;
                    _selectedPurpose = null;
                    _selectedFloors = null;
                    _loanAgreementFile = null;
                  });
                },
                style: ElevatedButton.styleFrom(
                  backgroundColor: isOffline ? Colors.orange : const Color(0xFF138808),
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: const Text("Done"),
              ),
            ),
          ],
        );
      },
    );
  }


  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final pad = w >= 900 ? 28.0 : (w >= 600 ? 20.0 : 16.0);
        final gap = w >= 600 ? 14.0 : 12.0;

        return Scaffold(
          backgroundColor: const Color(0xFFF6F7FB),
          appBar: AppBar(
            backgroundColor: _accent,
            elevation: 0,
            centerTitle: true,
            iconTheme: const IconThemeData(color: Colors.white),
            title: Text(
              "Create Beneficiary",
              style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: Colors.white),
            ),
            shape: const RoundedRectangleBorder(
              borderRadius: BorderRadius.vertical(bottom: Radius.circular(_headerRadius)),
            ),
            clipBehavior: Clip.antiAlias,
          ),
          body: SafeArea(
            child: SingleChildScrollView(
              padding: EdgeInsets.all(pad),
              child: Center(
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 640),
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
                          SizedBox(height: gap),
                          _buildTextField(
                            controller: _phoneController,
                            label: "Mobile Number",
                            icon: Icons.phone_android_rounded,
                            inputType: TextInputType.phone,
                            formatters: [
                              FilteringTextInputFormatter.digitsOnly,
                              LengthLimitingTextInputFormatter(10),
                            ],
                            validator: (v) => v!.length != 10 ? "Invalid Number" : null,
                          ),
                        ]),
                        SizedBox(height: pad),

                        _buildSectionHeader("Loan Details"),
                        _buildCard([
                          _buildTextField(
                            controller: _loanIdController,
                            label: "Loan Application ID",
                            icon: Icons.numbers_rounded,
                            validator: (v) => v!.isEmpty ? "Required" : null,
                          ),
                          SizedBox(height: gap),
                          _buildTextField(
                            controller: _amountController,
                            label: "Sanctioned Amount (₹)",
                            icon: Icons.currency_rupee_rounded,
                            inputType: TextInputType.number,
                            validator: (v) => v!.isEmpty ? "Required" : null,
                          ),
                          SizedBox(height: gap),
                          _buildDropdown(
                            label: "Government Scheme",
                            value: _selectedScheme,
                            items: _schemes,
                            onChanged: (v) => setState(() {
                              _selectedScheme = v;
                              _selectedLoanType = null;
                              _selectedPurpose = null;
                              _selectedFloors = null;
                            }),
                            icon: Icons.account_balance_rounded,
                          ),
                          SizedBox(height: gap),
                          _buildDropdown(
                            label: "Loan Category",
                            value: _selectedLoanType,
                            items: _currentLoanTypes,
                            enabled: _selectedScheme != null,
                            onChanged: (v) => setState(() {
                              _selectedLoanType = v;
                              _selectedPurpose = null;
                            }),
                            icon: Icons.category_rounded,
                          ),
                          SizedBox(height: gap),
                          _buildDropdown(
                            label: "Loan Purpose",
                            value: _selectedPurpose,
                            items: _currentPurposes,
                            enabled: _selectedLoanType != null,
                            onChanged: (v) => setState(() => _selectedPurpose = v),
                            icon: Icons.task_alt_rounded,
                          ),
                          if (_showFloorsDropdown) ...[
                            SizedBox(height: gap),
                            _buildDropdown(
                              label: "Number of Floors",
                              value: _selectedFloors,
                              items: _floors,
                              onChanged: (v) => setState(() => _selectedFloors = v),
                              icon: Icons.layers_rounded,
                            ),
                          ],
                        ]),
                        SizedBox(height: pad),

                        _buildSectionHeader("Asset & Agreement Details"),
                        _buildCard([
                          _buildTextField(
                            controller: _addressController,
                            label: "Beneficiary Address",
                            icon: Icons.location_on_outlined,
                            validator: (v) => v!.isEmpty ? "Required" : null,
                          ),
                          SizedBox(height: gap),
                          _buildTextField(
                            controller: _assetController,
                            label: "Asset Purchased",
                            icon: Icons.shopping_cart_outlined,
                            validator: (v) => v!.isEmpty ? "Required" : null,
                          ),
                          SizedBox(height: gap),
                          _buildUploadCard(),
                        ]),
                        SizedBox(height: pad),

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
                                ? const SizedBox(
                              width: 24,
                              height: 24,
                              child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                            )
                                : Text(
                              "Create & Send SMS",
                              style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ),
                        const SizedBox(height: 10),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          bottomNavigationBar: OfficerNavBar(currentIndex: 1, officerId: widget.officerId),
        );
      },
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: const Color(0xFF6B7280),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildCard(List<Widget> children) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: const Color(0xFFE5E7EB)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.04),
            blurRadius: 14,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      child: Column(children: children),
    );
  }

  InputDecoration _compactDecoration(String label, IconData icon) {
    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(fontSize: 13, color: Colors.grey[600], fontWeight: FontWeight.w600),
      prefixIcon: Icon(icon, color: _accent, size: 20),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      isDense: true,
      filled: true,
      fillColor: const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: Colors.grey.shade200),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: const BorderSide(color: _accent, width: 1.5),
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
      style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
      decoration: _compactDecoration(label, icon),
    );
  }

  Widget _buildDropdown({
    required String label,
    required String? value,
    required List<String> items,
    required ValueChanged<String?>? onChanged,
    required IconData icon,
    bool enabled = true,
  }) {
    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      menuMaxHeight: 320,
      items: items
          .map(
            (e) => DropdownMenuItem(
          value: e,
          child: Text(
            e,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: GoogleFonts.inter(fontSize: 14, fontWeight: FontWeight.w600),
          ),
        ),
      )
          .toList(),
      onChanged: enabled ? onChanged : null,
      validator: (v) => (enabled && v == null) ? "Required" : null,
      icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 22),
      decoration: _compactDecoration(label, icon).copyWith(
        disabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: Colors.grey.shade200),
        ),
      ),
    );
  }

  Widget _buildUploadCard() {
    return InkWell(
      onTap: _pickLoanAgreement,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _loanAgreementFile != null ? Colors.green : Colors.grey.shade300,
            style: BorderStyle.solid,
          ),
        ),
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: _loanAgreementFile != null ? Colors.green.withOpacity(0.1) : _accent.withOpacity(0.12),
                shape: BoxShape.circle,
              ),
              child: Icon(
                _loanAgreementFile != null ? Icons.check : Icons.upload_file_rounded,
                color: _loanAgreementFile != null ? Colors.green : _accent,
                size: 28,
              ),
            ),
            const SizedBox(height: 12),
            Text(
              _loanAgreementFile != null ? "Agreement Attached" : "Upload Loan Agreement",
              style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              _loanAgreementFile != null ? _loanAgreementFile!.path.split('/').last : "PDF or Image (Max 5MB)",
              style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[500]),
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              maxLines: 1,
            ),
          ],
        ),
      ),
    );
  }
}