import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/movement_verification_page.dart';
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:loan2/ai/combined_ai_gate.dart';
import 'package:exif/exif.dart';
import 'package:loan2/pages/rear_camera_capture_page.dart';

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
  String? _warnText;
  File? _mediaFile;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;
  bool _isCheckingAi = false;
  AiResult? _lastAi;
  Widget _warnBox(String t) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFFFFF3CD),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFFE69C)),
      ),
      child: Row(
        children: [
          const Icon(Icons.warning_amber_rounded, color: Color(0xFF856404)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              t,
              style: const TextStyle(
                color: Color(0xFF856404),
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
        ],
      ),
    );
  }
  final TextEditingController _amountController = TextEditingController();

  bool get _showAmountInput => widget.step.processId == 1;

  @override
  void initState() {
    super.initState();
    CombinedAiGate.instance.init();
  }

  @override
  void dispose() {
    _amountController.dispose();
    super.dispose();
  }

  void _pickMedia() {
    final dt = widget.step.dataType.trim().toLowerCase();
    if (dt == 'movement') {
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
  Future<bool> _isFrontCameraImage(File f) async {
    try {
      final bytes = await f.readAsBytes();
      final tags = await readExifFromBytes(bytes);

      final v1 = tags["EXIF LensModel"]?.printable.toLowerCase() ?? "";
      final v2 = tags["Image Model"]?.printable.toLowerCase() ?? "";
      final v3 = tags["EXIF BodySerialNumber"]?.printable.toLowerCase() ?? "";
      final v4 = tags["EXIF CameraOwnerName"]?.printable.toLowerCase() ?? "";

      final s = "$v1 $v2 $v3 $v4";
      if (s.contains("front")) return true;

      return false;
    } catch (_) {
      return false;
    }
  }

  Future<void> _showRetakeDialog(String msg) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Retake required"),
        content: Text(msg),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) _pickImageOrVideo();
            },
            child: const Text("Retake"),
          ),
        ],
      ),
    );
  }

  Future<void> _pickImageOrVideo() async {
    if (_isUploading || _isCheckingAi) return;

    final dt = widget.step.dataType.trim().toLowerCase();

    try {
      if (dt == 'video') {
        final XFile? pickedVideo = await _picker.pickVideo(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          maxDuration: const Duration(seconds: 15),
        );

        if (pickedVideo == null) return;

        setState(() {
          _mediaFile = File(pickedVideo.path);
          _warnText = null;
        });
        return;
      }

      final path = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RearCameraCapturePage()),
      );

      if (path is! String || path.isEmpty) return;

      final file = File(path);
      final bool shouldRunAi = widget.step.processId == 1;

      if (!shouldRunAi) {
        setState(() {
          _mediaFile = file;
          _warnText = null;
        });
        return;
      }

      setState(() {
        _isCheckingAi = true;
        _mediaFile = null;
        _warnText = null;
      });

      final r = await CombinedAiGate.instance.check(file);
      if (!mounted) return;

      setState(() => _isCheckingAi = false);

      if (r.verdict == AiVerdict.valid) {
        setState(() {
          _mediaFile = file;
          _warnText = null;
        });
      } else {
        final msg = (r.verdict == AiVerdict.screenInvalid)
            ? "Invalid image: Screen-captured photo detected. Please retake."
            : "Invalid image: Photo is too blurry. Please retake.";

        setState(() {
          _mediaFile = null;
          _warnText = msg;
        });

        await _showRetakeDialog(msg);
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isCheckingAi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to capture media: $e")),
      );
    }
  }


  Future<void> _submitStep() async {
    if (_mediaFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please capture the required media first.")),
      );
      return;
    }

    if (_showAmountInput && _amountController.text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter utilization amount")),
      );
      return;
    }

    setState(() => _isUploading = true);

    int? dbId;

    try {
      String finalPath = _mediaFile!.path;

      dbId = await DatabaseHelper.instance.insertImagePath(
        userId: widget.userId,
        processId: widget.step.id,
        processIntId: widget.step.processId,
        loanId: widget.loanId,
        filePath: finalPath,
      );

      bool isOnline = await SyncService.realInternetCheck();

      if (!isOnline) {
        await DatabaseHelper.instance.queueForUpload(dbId!);
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
            ),
          );
          Navigator.pop(context, true);
        }
        return;
      }
      Widget _warnBox(String t) {
        return Container(
          width: double.infinity,
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: const Color(0xFFFFF3CD),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: const Color(0xFFFFE69C)),
          ),
          child: Row(
            children: [
              const Icon(Icons.warning_amber_rounded, color: Color(0xFF856404)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  t,
                  style: const TextStyle(color: Color(0xFF856404), fontWeight: FontWeight.w600),
                ),
              ),
            ],
          ),
        );
      }

      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}upload'));
      request.fields['loan_id'] = widget.loanId;
      request.fields['process_id'] = widget.step.id;
      request.fields['user_id'] = widget.userId;

      if (_showAmountInput) {
        request.fields['utilization_amount'] = _amountController.text;
      }

      request.files.add(await http.MultipartFile.fromPath('file', finalPath));

      var response = await request.send().timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await DatabaseHelper.instance.deleteImage(dbId!, deleteFile: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Uploaded successfully!"), backgroundColor: Colors.green),
          );
          Navigator.pop(context, true);
        }
      } else {
        throw Exception("Server error ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Upload failed: $e");
      if (dbId != null) {
        await DatabaseHelper.instance.queueForUpload(dbId);
      }

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Upload failed: ${e.toString()}"), backgroundColor: Colors.red),
        );
        Navigator.pop(context, true);
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final disabledTap = _isUploading || _isCheckingAi;

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
            Text("Loan ID: ${widget.loanId}",
                style: TextStyle(color: Colors.grey[600], fontSize: 14)),
            const SizedBox(height: 4),
            Text("Please complete the step below to submit your utilization proof.",
                style: TextStyle(color: Colors.grey[500], fontSize: 12)),
            const SizedBox(height: 24),
            Text(
              "Step ${widget.step.processId} · ${widget.step.whatToDo}",
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            const SizedBox(height: 4),
            Text(
              "Please capture a ${widget.step.dataType} of the asset as instructed.",
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
            const SizedBox(height: 16),

            // if (_lastAi != null) ...[
            //   const SizedBox(height: 12),
            //   Container(
            //     width: double.infinity,
            //     padding: const EdgeInsets.all(12),
            //     decoration: BoxDecoration(
            //       color: Colors.grey[100],
            //       borderRadius: BorderRadius.circular(10),
            //       border: Border.all(color: Colors.grey[300]!),
            //     ),
            //     child: Text(
            //       "AI Debug:\n"
            //           "verdict: ${_lastAi!.verdict}\n"
            //           "blur: ${_lastAi!.blurScore.toStringAsFixed(4)}\n"
            //           "screen: ${_lastAi!.screenScore.toStringAsFixed(4)}\n"
            //           "${_lastAi!.message}",
            //       style: const TextStyle(fontSize: 12),
            //     ),
            //   ),
            // ],

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
              onTap: disabledTap ? null : _pickMedia,
              child: Stack(
                children: [
                  Container(
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
                        Text(
                          "Tap to capture ${widget.step.dataType}",
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ],
                    ),
                  ),
                  if (_warnText != null) ...[
                    const SizedBox(height: 12),
                    _warnBox(_warnText!),
                  ],

                  if (_isCheckingAi)
                    Positioned.fill(
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white.withOpacity(0.85),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Center(
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              CircularProgressIndicator(),
                              SizedBox(height: 10),
                              Text("Checking photo quality..."),
                            ],
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),

            const SizedBox(height: 30),

            SizedBox(
              width: double.infinity,
              height: 50,
              child: ElevatedButton(
                onPressed: (_isUploading || _isCheckingAi) ? null : _submitStep,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _mediaFile == null ? Colors.grey[300] : const Color(0xFF435E91),
                  foregroundColor: _mediaFile == null ? Colors.grey[600] : Colors.white,
                  elevation: _mediaFile == null ? 0 : 4,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                ),
                child: _isUploading
                    ? const SizedBox(
                  width: 24,
                  height: 24,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
                )
                    : Text(
                  "Submit Step ${widget.step.processId}",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
