import 'dart:convert';
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
import 'package:loan2/pages/bank_dashboard_page.dart';
import 'package:loan2/services/theme_ext.dart';

class CreateBeneficiaryPage extends StatefulWidget {
  final String officerId;
  const CreateBeneficiaryPage({super.key, required this.officerId});

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
  final _addressController = TextEditingController();
  final _assetController = TextEditingController(); // auto-computed

  // ✅ Dynamic extra fields controllers
  final Map<String, TextEditingController> _extraControllers = {};
  String? _courseMode; // Online / Offline

  TextEditingController _extraCtrl(String key) =>
      _extraControllers.putIfAbsent(key, () => TextEditingController());

  // Dropdown state
  String? _selectedScheme;
  String? _selectedLoanType;
  String? _selectedPurpose;
  String? _selectedFloors;

  // File picker
  File? _loanAgreementFile;

  static const _accent = Color(0xFF1E5AA8);
  static const double _headerRadius = 25;

  // --- DATA FOR DROPDOWNS (UNCHANGED) ---
  final List<String> _schemes = ['NBCFDC', 'NSFDC', 'NSKFDC'];
  final List<String> _floors = List.generate(10, (i) => '${i + 1}');

  bool get _showFloorsDropdown {
    final p = (_selectedPurpose ?? '').toLowerCase();
    return p.contains('construction') || p.contains('shop');
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
  // --- END ---

  bool get _isFilterApplied =>
      _selectedScheme != null &&
          _selectedLoanType != null &&
          _selectedPurpose != null &&
          (_selectedPurpose!.trim().isNotEmpty);

  // ---------- Dynamic rules ----------
  String get _pKey => (_selectedPurpose ?? '').toLowerCase();

  bool get _needsBrandModel {
    final p = _pKey;
    return p.contains('tractor') ||
        p.contains('rickshaw') ||
        p.contains('auto rickshaw') ||
        p.contains('laptop') ||
        p.contains('sewing') ||
        p.contains('ppe');
  }

  bool get _isCows => _pKey.contains('cow');

  bool get _isCourse {
    final p = _pKey;
    return p.contains('course') || p.contains('technical') || p.contains('non-technical');
  }

  bool get _isFeesOrAdmission {
    final p = _pKey;
    return p.contains('fee') || p.contains('admission') || p.contains('hostel');
  }

  String get _addressLabel {
    if (_showFloorsDropdown) return "Construction Address";
    if (_isFeesOrAdmission) return "Institution Address";
    if (_isCourse && _courseMode == "Offline") return "Institution Address";
    return "Beneficiary Address";
  }

  String? _addressValidator(String? v) {
    // Course online -> no address required
    if (_isCourse && _courseMode == "Online") return null;
    return (v == null || v.trim().isEmpty) ? "Required" : null;
  }

  bool _hasLetter(String s) => RegExp(r'[A-Za-z]').hasMatch(s);

  void _clearDynamicExtras() {
    for (final c in _extraControllers.values) {
      c.clear();
    }
    _courseMode = null;
  }

  Map<String, String> _collectExtraFields() {
    final extra = <String, String>{};

    final cat = (_selectedLoanType ?? '').trim();
    final pur = (_selectedPurpose ?? '').trim();
    if (cat.isNotEmpty) extra["loan_category"] = cat;
    if (pur.isNotEmpty) extra["loan_purpose"] = pur;

    if (_showFloorsDropdown && _selectedFloors != null && _selectedFloors!.trim().isNotEmpty) {
      extra["floors"] = _selectedFloors!.trim();
    }

    if (_needsBrandModel) {
      final bm = _extraCtrl("brand_model").text.trim();
      if (bm.isNotEmpty) extra["brand_model"] = bm;
    }

    if (_isCows) {
      final n = _extraCtrl("no_of_cows").text.trim();
      if (n.isNotEmpty) extra["no_of_cows"] = n;
    }

    if (_isCourse) {
      final cn = _extraCtrl("course_name").text.trim();
      final cp = _extraCtrl("course_provider_name").text.trim();

      if (cn.isNotEmpty) extra["course_name"] = cn;
      if (cp.isNotEmpty) extra["course_provider_name"] = cp;
      if ((_courseMode ?? '').trim().isNotEmpty) extra["course_mode"] = _courseMode!.trim();

      // ✅ Institution only if Offline (your requirement)
      if (_courseMode == "Offline") {
        final inst = _extraCtrl("institution_name").text.trim();
        if (inst.isNotEmpty) extra["institution_name"] = inst;
      }
    }

    if (_isFeesOrAdmission && !_isCourse) {
      final inst = _extraCtrl("institution_name").text.trim();
      if (inst.isNotEmpty) extra["institution_name"] = inst;
    }

    return extra;
  }

  String _computeAssetPurchased(Map<String, String> extra) {
    final cat = (_selectedLoanType ?? '').trim();
    final pur = (_selectedPurpose ?? '').trim();
    final base = pur.isNotEmpty ? pur : cat;

    if (_needsBrandModel) {
      final bm = (extra["brand_model"] ?? "").trim();

      // ✅ Fix: ignore pure numbers like "8"
      if (bm.isEmpty || !_hasLetter(bm)) return base;

      return "$base - $bm";
    }

    if (_isCows) {
      final n = (extra["no_of_cows"] ?? "").trim();
      return n.isEmpty ? "Cows" : "Cows - $n";
    }

    if (_isCourse) {
      final cn = (extra["course_name"] ?? "").trim();
      return cn.isEmpty ? base : "Course - $cn";
    }

    if (_isFeesOrAdmission) {
      final inst = (extra["institution_name"] ?? "").trim();
      return inst.isEmpty ? base : "$base - $inst";
    }

    if (_showFloorsDropdown && _selectedFloors != null && _selectedFloors!.trim().isNotEmpty) {
      return "$base - ${_selectedFloors!} floors";
    }

    return base;
  }

  void _syncAssetController() {
    final extra = _collectExtraFields();
    final computed = _computeAssetPurchased(extra);
    if (_assetController.text != computed) {
      _assetController.text = computed;
    }
  }

  List<Widget> _buildDynamicFields(double gap) {
    final widgets = <Widget>[];

    if (_needsBrandModel) {
      widgets.addAll([
        SizedBox(height: gap),
        _buildTextField(
          controller: _extraCtrl("brand_model"),
          label: "Brand & Model",
          icon: Icons.sell_outlined,
          validator: (v) {
            final val = (v ?? "").trim();
            if (val.isEmpty) return "Required";
            if (!_hasLetter(val)) return "Enter valid Brand & Model";
            return null;
          },
          onChanged: (_) => _syncAssetController(),
        ),
      ]);
    }

    if (_isCows) {
      widgets.addAll([
        SizedBox(height: gap),
        _buildTextField(
          controller: _extraCtrl("no_of_cows"),
          label: "Number of Cows",
          icon: Icons.numbers_rounded,
          inputType: TextInputType.number,
          formatters: [FilteringTextInputFormatter.digitsOnly],
          validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
          onChanged: (_) => _syncAssetController(),
        ),
      ]);
    }

    if (_isCourse) {
      widgets.addAll([
        SizedBox(height: gap),
        _buildTextField(
          controller: _extraCtrl("course_name"),
          label: "Course Name",
          icon: Icons.menu_book_outlined,
          validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
          onChanged: (_) => _syncAssetController(),
        ),
        SizedBox(height: gap),
        _buildTextField(
          controller: _extraCtrl("course_provider_name"),
          label: "Course Provider Name",
          icon: Icons.business_outlined,
          validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
          onChanged: (_) => _syncAssetController(),
        ),
        SizedBox(height: gap),
        _buildDropdown(
          label: "Course Mode",
          value: _courseMode,
          items: const ["Online", "Offline"],
          onChanged: (v) => setState(() {
            _courseMode = v;
            // if switched to Online, clear institution name
            if (_courseMode == "Online") _extraCtrl("institution_name").clear();
            _syncAssetController();
          }),
          icon: Icons.wifi_tethering_outlined,
        ),
        // ✅ Institution only when OFFLINE (your requirement)
        if (_courseMode == "Offline") ...[
          SizedBox(height: gap),
          _buildTextField(
            controller: _extraCtrl("institution_name"),
            label: "Institution Name",
            icon: Icons.account_balance_outlined,
            validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
            onChanged: (_) => _syncAssetController(),
          ),
        ],
      ]);
    }

    if (_isFeesOrAdmission && !_isCourse) {
      widgets.addAll([
        SizedBox(height: gap),
        _buildTextField(
          controller: _extraCtrl("institution_name"),
          label: "Institution Name",
          icon: Icons.account_balance_outlined,
          validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
          onChanged: (_) => _syncAssetController(),
        ),
      ]);
    }

    return widgets;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _phoneController.dispose();
    _amountController.dispose();
    _loanIdController.dispose();
    _addressController.dispose();
    _assetController.dispose();

    for (final c in _extraControllers.values) {
      c.dispose();
    }

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
    _syncAssetController();

    if (!_formKey.currentState!.validate()) return;

    if (_loanAgreementFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please attach the loan agreement file."), backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _isLoading = true);

    final name = _nameController.text.trim();
    final phone = _phoneController.text.trim();
    final amount = _amountController.text.trim();
    final loanId = _loanIdController.text.trim();
    final scheme = _selectedScheme ?? "";
    final cat = _selectedLoanType ?? "";
    final pur = _selectedPurpose ?? "";
    final loanTypeFinal = pur.isEmpty ? cat : '$cat - $pur';

    String address = _addressController.text.trim();

    final extra = _collectExtraFields();
    final asset = _assetController.text.trim().isEmpty ? _computeAssetPurchased(extra) : _assetController.text.trim();
    final extraJson = jsonEncode(extra);

    // Course online: server still requires beneficiary_address -> send placeholder
    if (_isCourse && _courseMode == "Online" && address.isEmpty) {
      address = "Online";
    }

    final docPath = _loanAgreementFile?.path;

    try {
      final isOnline = await SyncService.realInternetCheck();

      if (isOnline) {
        final request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}bank/beneficiary'));
        request.fields['officer_id'] = widget.officerId;
        request.fields['name'] = name;
        request.fields['phone'] = phone;
        request.fields['amount'] = amount;
        request.fields['loan_id'] = loanId;
        request.fields['scheme'] = scheme;
        request.fields['loan_type'] = loanTypeFinal;

        request.fields['beneficiary_address'] = address;
        request.fields['asset_purchased'] = asset;

        // send extra fields individually
        extra.forEach((k, v) {
          if (v.trim().isNotEmpty) request.fields[k] = v.trim();
        });

        if (docPath != null) {
          request.files.add(await http.MultipartFile.fromPath('loan_agreement', docPath));
        }

        if (_showFloorsDropdown && _selectedFloors != null) {
          request.fields['floors'] = _selectedFloors!;
        }

        final response = await request.send();
        final respStr = await response.stream.bytesToString();

        if (response.statusCode == 201) {
          if (mounted) _showSuccessDialog(isOffline: false);
        } else {
          throw Exception("Server Error: ${response.statusCode} - $respStr");
        }
      } else {
        await _saveOffline(
          name: name,
          phone: phone,
          amount: amount,
          loanId: loanId,
          scheme: scheme,
          loanType: loanTypeFinal,
          docPath: docPath,
          address: address,
          asset: asset,
          extraJson: extraJson,
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
        address: address,
        asset: asset,
        extraJson: extraJson,
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
    String? address,
    String? asset,
    String? extraJson,
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
      address: address,
      asset: asset,
      extraJson: extraJson,
    );
  }

  void _showSuccessDialog({required bool isOffline, String? error}) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final subColor = isDark ? const Color(0xFFCBD5E1) : Colors.grey[600];

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
            style: GoogleFonts.inter(fontSize: 14, color: subColor),
          ),
          actions: [
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  if (!mounted) return;
                  Navigator.of(context).pushAndRemoveUntil(
                    MaterialPageRoute(builder: (_) => BankDashboardPage(officerId: widget.officerId)),
                        (route) => false,
                  );
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final pad = MediaQuery.of(context).size.width >= 900
        ? 28.0
        : (MediaQuery.of(context).size.width >= 600 ? 20.0 : 16.0);
    final gap = MediaQuery.of(context).size.width >= 600 ? 14.0 : 12.0;

    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
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
                    _buildSectionHeader("Personal Information", isDark),
                    _buildCard(isDark, [
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

                    _buildSectionHeader("Loan Details", isDark),
                    _buildCard(isDark, [
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
                          _clearDynamicExtras();
                          _assetController.clear();
                          _addressController.clear();
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
                          _selectedFloors = null;
                          _clearDynamicExtras();
                          _assetController.clear();
                          _addressController.clear();
                        }),
                        icon: Icons.category_rounded,
                      ),
                      SizedBox(height: gap),
                      _buildDropdown(
                        label: "Loan Purpose",
                        value: _selectedPurpose,
                        items: _currentPurposes,
                        enabled: _selectedLoanType != null,
                        onChanged: (v) => setState(() {
                          _selectedPurpose = v;
                          _selectedFloors = null;
                          _clearDynamicExtras();
                          _addressController.clear();
                          _syncAssetController();
                        }),
                        icon: Icons.task_alt_rounded,
                      ),
                      if (_showFloorsDropdown) ...[
                        SizedBox(height: gap),
                        _buildDropdown(
                          label: "Number of Floors",
                          value: _selectedFloors,
                          items: _floors,
                          onChanged: (v) => setState(() {
                            _selectedFloors = v;
                            _syncAssetController();
                          }),
                          icon: Icons.layers_rounded,
                        ),
                      ],
                    ]),
                    SizedBox(height: pad),

                    // ✅ Hide Asset section until filter applied
                    if (_isFilterApplied) ...[
                      _buildSectionHeader("Asset & Agreement Details", isDark),
                      _buildCard(isDark, [
                        _buildTextField(
                          controller: _addressController,
                          label: _addressLabel,
                          icon: Icons.location_on_outlined,
                          validator: _addressValidator,
                        ),

                        // ✅ THIS is what makes Number of Cows / Brand&Model / Course fields appear
                        ..._buildDynamicFields(gap),

                        SizedBox(height: gap),
                        _buildTextField(
                          controller: _assetController,
                          label: "Asset Purchased",
                          icon: Icons.shopping_cart_outlined,
                          readOnly: true,
                          validator: (v) => (v == null || v.trim().isEmpty) ? "Required" : null,
                        ),
                        SizedBox(height: gap),
                        _buildUploadCard(isDark),
                      ]),
                      SizedBox(height: pad),
                    ] else ...[
                      SizedBox(height: pad),
                    ],

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
  }

  // ---------- UI helpers (theme-aware) ----------

  Widget _buildSectionHeader(String title, bool isDark) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 10, left: 2),
      child: Text(
        title,
        style: GoogleFonts.inter(
          fontSize: 13,
          fontWeight: FontWeight.w700,
          color: isDark ? const Color(0xFFCBD5E1) : const Color(0xFF6B7280),
          letterSpacing: 0.2,
        ),
      ),
    );
  }

  Widget _buildCard(bool isDark, List<Widget> children) {
    final card = Theme.of(context).cardColor;
    final border = context.appBorder;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: border),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final border = context.appBorder;

    return InputDecoration(
      labelText: label,
      labelStyle: GoogleFonts.inter(
        fontSize: 13,
        color: isDark ? const Color(0xFF94A3B8) : Colors.grey[600],
        fontWeight: FontWeight.w600,
      ),
      prefixIcon: Icon(icon, color: _accent, size: 20),
      prefixIconConstraints: const BoxConstraints(minWidth: 44, minHeight: 44),
      isDense: true,
      filled: true,
      fillColor: isDark ? const Color(0xFF0B1220) : const Color(0xFFF9FAFB),
      contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(12),
        borderSide: BorderSide(color: border),
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
    bool readOnly = false,
    ValueChanged<String>? onChanged,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return TextFormField(
      controller: controller,
      keyboardType: inputType,
      inputFormatters: formatters,
      validator: validator,
      readOnly: readOnly,
      onChanged: onChanged,
      style: GoogleFonts.inter(
        fontSize: 14,
        fontWeight: FontWeight.w600,
        color: isDark ? Colors.white : null,
      ),
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
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return DropdownButtonFormField<String>(
      value: value,
      isExpanded: true,
      menuMaxHeight: 320,
      dropdownColor: isDark ? const Color(0xFF0F1B2D) : Colors.white,
      items: items
          .map(
            (e) => DropdownMenuItem(
          value: e,
          child: Text(
            e,
            overflow: TextOverflow.ellipsis,
            maxLines: 1,
            style: GoogleFonts.inter(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: isDark ? Colors.white : null,
            ),
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
          borderSide: BorderSide(color: context.appBorder),
        ),
      ),
    );
  }

  Widget _buildUploadCard(bool isDark) {
    final border = context.appBorder;

    return InkWell(
      onTap: _pickLoanAgreement,
      borderRadius: BorderRadius.circular(16),
      child: Container(
        width: double.infinity,
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: _loanAgreementFile != null ? Colors.green : border,
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
              style: GoogleFonts.inter(
                fontWeight: FontWeight.w600,
                color: isDark ? Colors.white : Colors.black87,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _loanAgreementFile != null ? _loanAgreementFile!.path.split('/').last : "PDF or Image (Max 5MB)",
              style: GoogleFonts.inter(
                fontSize: 12,
                color: isDark ? const Color(0xFF94A3B8) : Colors.grey[500],
              ),
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
