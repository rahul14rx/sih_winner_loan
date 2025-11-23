import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/services/api.dart';

class LoanDetailPage extends StatefulWidget {
  final String loanId;
  const LoanDetailPage({super.key, required this.loanId});

  @override
  State<LoanDetailPage> createState() => _LoanDetailPageState();
}

class _LoanDetailPageState extends State<LoanDetailPage> {
  Map<String, dynamic>? _details;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    try {
      final res = await http.get(Uri.parse('${kBaseUrl}bank/loan/${widget.loanId}'));
      if (res.statusCode == 200) {
        setState(() { _details = jsonDecode(res.body); _loading = false; });
      }
    } catch (e) {
      setState(() => _loading = false);
    }
  }

  Future<void> _verifyProcess(String processId, String status) async {
    try {
      await http.post(
        Uri.parse('${kBaseUrl}bank/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'loan_id': widget.loanId,
          'process_id': processId,
          'status': status
        }),
      );
      _fetchDetails(); // Refresh UI
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Marked as $status")));
    } catch (e) {
      debugPrint("Error updating status");
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (_details == null) return const Scaffold(body: Center(child: Text("Error loading data")));

    final processes = _details!['process'] as List;

    return Scaffold(
      appBar: AppBar(title: Text("Loan #${widget.loanId}")),
      body: ListView.separated(
        padding: const EdgeInsets.all(16),
        itemCount: processes.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) {
          final p = processes[index];
          final fileId = p['data'];
          final status = p['process_status'];

          return Card(
            elevation: 3,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Image Preview from GridFS
                ClipRRect(
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
                  child: fileId != null && fileId.toString().length > 5
                      ? Image.network(
                    "${kBaseUrl}file/$fileId", // Crucial: Loading from our new Python endpoint
                    height: 200,
                    width: double.infinity,
                    fit: BoxFit.cover,
                    loadingBuilder: (ctx, child, progress) {
                      if (progress == null) return child;
                      return Container(height: 200, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator()));
                    },
                    errorBuilder: (_,__,___) => Container(height: 200, color: Colors.grey[200], child: const Icon(Icons.broken_image)),
                  )
                      : Container(height: 200, color: Colors.grey[200], child: const Center(child: Text("No Image Uploaded"))),
                ),
                Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(p['what_to_do'], style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Text("AI Confidence Score: ${p['score']}%", style: const TextStyle(color: Colors.blue, fontWeight: FontWeight.bold)),
                      const SizedBox(height: 16),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: status == 'verified' ? null : () => _verifyProcess(p['id'], 'verified'),
                              icon: const Icon(Icons.check, color: Colors.green),
                              label: const Text("Approve"),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.green, side: const BorderSide(color: Colors.green)),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: OutlinedButton.icon(
                              onPressed: status == 'rejected' ? null : () => _verifyProcess(p['id'], 'rejected'),
                              icon: const Icon(Icons.close, color: Colors.red),
                              label: const Text("Reject"),
                              style: OutlinedButton.styleFrom(foregroundColor: Colors.red, side: const BorderSide(color: Colors.red)),
                            ),
                          ),
                        ],
                      )
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}