import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';

class VerificationStepPage extends StatefulWidget {
  final String loanId;
  final ProcessStep step;
  final String userId;

  const VerificationStepPage({
    super.key,
    required this.loanId,
    required this.step,
    required this.userId,
  });

  @override
  State<VerificationStepPage> createState() => _VerificationStepPageState();
}

class _VerificationStepPageState extends State<VerificationStepPage> {
  File? _mediaFile;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  final TextEditingController _amountController = TextEditingController();

  // Only ask for amount if it's the first step (Process ID 1)
  // You can change this logic if you want it for all steps
  bool get _showAmountInput => widget.step.processId == 1;

  Future<void> _pickMedia() async {
    try {
      final XFile? pickedFile;
      if (widget.step.dataType == 'video') {
        pickedFile = await _picker.pickVideo(
            source: ImageSource.camera,
            maxDuration: const Duration(seconds: 15));
      } else {
        pickedFile = await _picker.pickImage(
            source: ImageSource.camera, imageQuality: 80);
      }

      // This is a more robust null-check to ensure build systems see the change.
      if (pickedFile != null) {
        // Create a final, non-nullable variable to be used inside setState.
        final File file = File(pickedFile.path);
        setState(() {
          _mediaFile = file;
        });
      }
    } catch (e) {
      debugPrint("Error picking media: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to pick media: $e")),
        );
      }
    }
  }

  Future<void> _submitStep() async {
    if (_mediaFile == null) return;

    // Validation for amount input
    if (_showAmountInput && _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter utilization amount")));
      return;
    }

    setState(() => _isUploading = true);

    // 1. Save Local
    int dbId = await DatabaseHelper.instance.insertImagePath(
      userId: widget.userId,
      processId: widget.step.id,
      processIntId: widget.step.processId,
      loanId: widget.loanId,
      filePath: _mediaFile!.path,
    );

    // 2. Check Online
    bool isOnline = await SyncService.realInternetCheck();

    if (!isOnline) {
      await DatabaseHelper.instance.queueForUpload(dbId);
      if (mounted) {
        setState(() => _isUploading = false);
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Row(
                children: [
                  Icon(Icons.wifi_off, color: Colors.white),
                  SizedBox(width: 10),
                  Expanded(child: Text("Saved offline. Will sync when online.")),
                ],
              ),
              backgroundColor: Colors.orange,
            )
        );
        // Return true to indicate a step was completed/queued
        Navigator.pop(context, true);
      }
      return;
    }

    // 3. Upload Online
    try {
      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}upload'));
      request.fields['loan_id'] = widget.loanId;
      request.fields['process_id'] = widget.step.id;
      request.fields['user_id'] = widget.userId;

      // Send amount if applicable
      if (_showAmountInput) {
        request.fields['utilization_amount'] = _amountController.text;
      }

      request.files.add(await http.MultipartFile.fromPath('file', _mediaFile!.path));

      var response = await request.send();
      if (response.statusCode == 200) {
        // Cleanup local entry since server has it
        await DatabaseHelper.instance.deleteImage(dbId, deleteFile: false);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uploaded successfully!"), backgroundColor: Colors.green));
          // Return true to indicate success
          Navigator.pop(context, true);
        }
      } else {
        throw Exception("Server error ${response.statusCode}");
      }
    } catch (e) {
      // Fallback: Queue if online upload fails
      await DatabaseHelper.instance.queueForUpload(dbId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload failed. Queued for sync."), backgroundColor: Colors.orange));
        // Return true because it is now queued locally
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text("${widget.step.dataType == 'image' ? 'Photo' : 'Video'} Verification"),
        backgroundColor: Colors.white,
        foregroundColor: Colors.black,
        elevation: 0,
      ),
      backgroundColor: Colors.white,
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text("Loan ID: ${widget.loanId}", style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 4),
            Text("Please complete the steps below to submit your utilization proof.", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            const SizedBox(height: 24),

            // --- SECTION 1: Utilization Amount (Conditional) ---
            if (_showAmountInput) ...[
              const Text("Step 1 · Utilization amount & photos", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              const SizedBox(height: 4),
              Text("Enter amount used and upload asset photos.", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
              const SizedBox(height: 16),

              const Text("Utilization amount (₹)", style: TextStyle(fontWeight: FontWeight.w600)),
              const SizedBox(height: 8),
              TextField(
                controller: _amountController,
                keyboardType: TextInputType.number,
                decoration: InputDecoration(
                  hintText: "Enter amount you have used",
                  border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
                ),
              ),
              const SizedBox(height: 24),
            ],

            // --- SECTION 2: Capture Media ---
            Text(
                _showAmountInput ? "Capture images" : "Step ${widget.step.processId} · Capture ${widget.step.dataType}",
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)
            ),
            if (_showAmountInput) ...[
              const SizedBox(height: 4),
              const Row(
                children: [
                  Icon(Icons.info_outline, size: 14, color: Colors.grey),
                  SizedBox(width: 4),
                  Text("Ensure asset is clearly visible", style: TextStyle(color: Colors.grey, fontSize: 12)),
                ],
              ),
            ],
            const SizedBox(height: 12),

            GestureDetector(
              onTap: _pickMedia,
              child: Container(
                height: 180,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey[300]!),
                ),
                child: _mediaFile != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: Image.file(_mediaFile!, fit: BoxFit.cover),
                )
                    : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.file_upload_outlined, size: 40, color: Colors.grey),
                    const SizedBox(height: 8),
                    Text("Tap to capture/select", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
            ),

            const SizedBox(height: 30),

            // --- SUBMIT BUTTON ---
            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _submitStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _mediaFile == null ? Colors.grey[300] : const Color(0xFF435E91), // Active Blue vs Disabled Grey
                  foregroundColor: _mediaFile == null ? Colors.grey[600] : Colors.white,
                  elevation: _mediaFile == null ? 0 : 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)), // Pill shape
                ),
                child: _isUploading
                    ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                    : Text("Submit Step ${widget.step.processId}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}