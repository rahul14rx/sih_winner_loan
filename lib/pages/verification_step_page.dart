import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/movement_verification_page.dart';
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

  bool get _showAmountInput => widget.step.processId == 1;

  void _pickMedia() {
    if (widget.step.dataType.trim().toLowerCase() == 'movement') {
      _pickMovement();
    } else {
      _pickImageOrVideo();
    }
  }

  Future<void> _pickMovement() async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const MovementScreen()),
    );

    if (result is String && result.isNotEmpty) {
      setState(() {
        _mediaFile = File(result);
      });
    }
  }

  Future<void> _pickImageOrVideo() async {
    try {
      final XFile? pickedFile;
      if (widget.step.dataType.toLowerCase() == 'video') {
        pickedFile = await _picker.pickVideo(
            source: ImageSource.camera, maxDuration: const Duration(seconds: 15));
      } else {
        pickedFile = await _picker.pickImage(
            source: ImageSource.camera, imageQuality: 80);
      }

      if (pickedFile != null) {
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
    if (_mediaFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please capture the required media first.")));
      return;
    }

    if (_showAmountInput && _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please enter utilization amount")));
      return;
    }

    setState(() => _isUploading = true);

    int dbId = await DatabaseHelper.instance.insertImagePath(
      userId: widget.userId,
      processId: widget.step.id,
      processIntId: widget.step.processId,
      loanId: widget.loanId,
      filePath: _mediaFile!.path,
    );

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
        Navigator.pop(context, true);
      }
      return;
    }

    try {
      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}upload'));
      request.fields['loan_id'] = widget.loanId;
      request.fields['process_id'] = widget.step.id;
      request.fields['user_id'] = widget.userId;

      if (_showAmountInput) {
        request.fields['utilization_amount'] = _amountController.text;
      }

      request.files.add(await http.MultipartFile.fromPath('file', _mediaFile!.path));

      // FIX: Added a timeout to prevent infinite loading
      var response = await request.send().timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await DatabaseHelper.instance.deleteImage(dbId, deleteFile: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uploaded successfully!"), backgroundColor: Colors.green));
          Navigator.pop(context, true);
        }
      } else {
        throw Exception("Server error ${response.statusCode}");
      }
    } catch (e) {
      await DatabaseHelper.instance.queueForUpload(dbId);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: ${e.toString()}"), backgroundColor: Colors.red));
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
        title: Text(widget.step.whatToDo),
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
            Text("Please complete the step below to submit your utilization proof.", style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            const SizedBox(height: 24),

            Text(
              "Step ${widget.step.processId} · ${widget.step.whatToDo}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18)
            ),
            const SizedBox(height: 4),
            Text(
              "Please capture a ${widget.step.dataType} of the asset as instructed.",
              style: TextStyle(color: Colors.grey[600], fontSize: 12)
            ),
            const SizedBox(height: 16),

            if (_showAmountInput) ...[
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
                          Icon(Icons.camera_alt, size: 40, color: Colors.grey[700]),
                          const SizedBox(height: 8),
                          Text("Tap to capture ${widget.step.dataType}", style: TextStyle(color: Colors.grey[600], fontWeight: FontWeight.bold)),
                        ],
                      ),
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: _isUploading ? null : _submitStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _mediaFile == null ? Colors.grey[300] : const Color(0xFF435E91),
                  foregroundColor: _mediaFile == null ? Colors.grey[600] : Colors.white,
                  elevation: _mediaFile == null ? 0 : 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
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
