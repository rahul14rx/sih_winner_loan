import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/services/api.dart'; // For kBaseUrl

class VerificationFlowPage extends StatefulWidget {
  final String loanId;
  final ProcessStep step;
  final String userId;

  const VerificationFlowPage({
    super.key,
    required this.loanId,
    required this.step,
    required this.userId,
  });

  @override
  State<VerificationFlowPage> createState() => _VerificationFlowPageState();
}

class _VerificationFlowPageState extends State<VerificationFlowPage> {
  File? _mediaFile;
  final ImagePicker _picker = ImagePicker();
  bool _isUploading = false;

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
      debugPrint("Error picking media: $e");
    }
  }

  Future<void> _uploadMedia() async {
    if (_mediaFile == null) return;

    setState(() => _isUploading = true);

    try {
      // Create Multipart Request
      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}upload'));

      // Add fields
      request.fields['loan_id'] = widget.loanId;
      request.fields['process_id'] = widget.step.id; // "P1"
      request.fields['user_id'] = widget.userId; // Though backend fetches this via loan_id, sending it is safer

      // Add File
      var file = await http.MultipartFile.fromPath('file', _mediaFile!.path);
      request.files.add(file);

      // Send
      var response = await request.send();

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Uploaded successfully!")));
          Navigator.pop(context); // Go back to dashboard
        }
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Upload failed: $e")));
      }
    } finally {
      if (mounted) setState(() => _isUploading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Verify Asset")),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Instructions Card
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: Colors.blue[50],
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.blue[200]!),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Task: ${widget.step.whatToDo}", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF000080))),
                  const SizedBox(height: 8),
                  const Text("• Ensure good lighting.\n• Keep the asset in the center.\n• Avoid blurry images.", style: TextStyle(height: 1.5)),
                ],
              ),
            ),

            const Spacer(),

            // Preview Area
            if (_mediaFile != null)
              Center(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(12),
                  child: widget.step.dataType == 'video'
                      ? Container(height: 200, width: double.infinity, color: Colors.black, child: const Center(child: Icon(Icons.play_circle, color: Colors.white, size: 50)))
                      : Image.file(_mediaFile!, height: 250, fit: BoxFit.cover),
                ),
              )
            else
              Center(
                child: Icon(
                  widget.step.dataType == 'video' ? Icons.videocam_outlined : Icons.camera_alt_outlined,
                  size: 100,
                  color: Colors.grey[300],
                ),
              ),

            const Spacer(),

            // Action Buttons
            if (_mediaFile == null)
              SizedBox(
                width: double.infinity,
                height: 50,
                child: ElevatedButton.icon(
                  onPressed: _pickMedia,
                  icon: const Icon(Icons.camera),
                  label: const Text("Capture Evidence"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF138808),
                    foregroundColor: Colors.white,
                  ),
                ),
              )
            else
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton(
                      onPressed: _pickMedia,
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
                      ),
                      child: _isUploading
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white))
                          : const Text("Upload Proof"),
                    ),
                  ),
                ],
              ),
            const SizedBox(height: 20),
          ],
        ),
      ),
    );
  }
}