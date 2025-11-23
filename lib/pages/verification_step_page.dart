import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/services/api.dart';

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

  void _showGuidelines() {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(24))),
      builder: (ctx) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(height: 4, width: 40, margin: const EdgeInsets.only(bottom: 20), decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(2))),
            Text("How to capture ${widget.step.dataType}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF000080))),
            const SizedBox(height: 16),
            const Text("• Ensure good lighting condition."),
            const SizedBox(height: 8),
            const Text("• Keep the asset clearly in the center of the frame."),
            const SizedBox(height: 8),
            const Text("• Avoid blurry images or shaky videos."),
            const SizedBox(height: 8),
            const Text("• Ensure serial numbers/logos are visible."),
            const SizedBox(height: 24),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: () {
                  Navigator.pop(ctx);
                  _pickMedia();
                },
                style: ElevatedButton.styleFrom(backgroundColor: const Color(0xFF138808)),
                child: const Text("I Understand, Open Camera"),
              ),
            )
          ],
        ),
      ),
    );
  }

  Future<void> _pickMedia() async {
    XFile? pickedFile;
    try {
      if (widget.step.dataType == 'video') {
        pickedFile = await _picker.pickVideo(source: ImageSource.camera);
      } else {
        pickedFile = await _picker.pickImage(source: ImageSource.camera);
      }

      if (pickedFile != null) {
        setState(() {
          _mediaFile = File(pickedFile!.path);
        });
      }
    } catch (e) {
      debugPrint("Error: $e");
    }
  }

  Future<void> _uploadMedia() async {
    if (_mediaFile == null) return;
    setState(() => _isUploading = true);

    try {
      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}upload'));
      request.fields['loan_id'] = widget.loanId;
      request.fields['process_id'] = widget.step.id;

      // Attach file
      request.files.add(await http.MultipartFile.fromPath('file', _mediaFile!.path));

      var response = await request.send();

      if (response.statusCode == 200) {
        if (mounted) {
          Navigator.pop(context); // Close screen on success
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Proof uploaded successfully!"), backgroundColor: Colors.green));
        }
      } else {
        throw Exception("Upload failed");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text("Upload ${widget.step.dataType}")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            // Task Description
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[100]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Task Requirement:", style: TextStyle(fontSize: 12, color: Colors.grey)),
                  const SizedBox(height: 4),
                  Text(widget.step.whatToDo, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF000080))),
                ],
              ),
            ),

            const Spacer(),

            // Preview or Placeholder
            GestureDetector(
              onTap: _mediaFile == null ? _showGuidelines : null,
              child: Container(
                height: 250,
                width: double.infinity,
                decoration: BoxDecoration(
                  color: Colors.grey[100],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.grey[300]!, width: 2, style: BorderStyle.solid),
                ),
                child: _mediaFile != null
                    ? ClipRRect(
                  borderRadius: BorderRadius.circular(18),
                  child: widget.step.dataType == 'video'
                      ? Container(color: Colors.black, child: const Center(child: Icon(Icons.play_circle, color: Colors.white, size: 60)))
                      : Image.file(_mediaFile!, fit: BoxFit.cover),
                )
                    : Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(widget.step.dataType == 'video' ? Icons.videocam : Icons.camera_alt, size: 50, color: Colors.grey),
                    const SizedBox(height: 10),
                    Text("Tap to capture ${widget.step.dataType}", style: const TextStyle(color: Colors.grey)),
                  ],
                ),
              ),
            ),

            const Spacer(),

            // Buttons
            if (_mediaFile != null)
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickMedia,
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 15)),
                      child: const Text("Retake"),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton(
                      onPressed: _isUploading ? null : _uploadMedia,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF138808),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 15),
                        elevation: 0,
                      ),
                      child: _isUploading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Text("Upload Proof"),
                    ),
                  ),
                ],
              )
            else
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _showGuidelines,
                  icon: const Icon(Icons.camera),
                  label: const Text("Open Camera"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF9933), // Saffron
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 15),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}