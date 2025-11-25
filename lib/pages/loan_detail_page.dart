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
  String _error = '';

  @override
  void initState() {
    super.initState();
    _fetchDetails();
  }

  Future<void> _fetchDetails() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final data = await getJson('loan_details?loan_id=${widget.loanId}');
      if (mounted) {
        setState(() {
          // CORRECTED: Ensure we are using the 'loan_details' key from the Python response
          _details = data['loan_details'];
          _loading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = "Failed to load details: $e";
        });
      }
      debugPrint("Error fetching details: $e");
    }
  }

  Future<void> _verifyProcess(String processId, String status) async {
    try {
      final response = await http.post(
        Uri.parse('${kBaseUrl}bank/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'loan_id': widget.loanId,
          'process_id': processId,
          'status': status
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Marked as $status"), backgroundColor: Colors.green));
        }
        _fetchDetails(); // Refresh UI after successful verification
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error updating status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to update: $e"), backgroundColor: Colors.red));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text("Review Loan #${widget.loanId}", style: const TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18)),
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black26,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _buildBody(),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Text(_error, style: const TextStyle(color: Colors.red), textAlign: TextAlign.center),
        ),
      );
    }
    if (_details == null) {
      return const Center(child: Text("No details found."));
    }

    final processes = _details!['process'] as List? ?? [];

    return RefreshIndicator(
      onRefresh: _fetchDetails,
      child: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          _buildDetailsCard(),
          const SizedBox(height: 24),
          const Text("Verification Steps", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87)),
          const SizedBox(height: 12),
          if (processes.isEmpty)
            const Text("No verification steps for this loan.")
          else
            ...processes.map((p) => _buildProcessCard(p)),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow("Applicant", _details!['applicant_name'] ?? 'N/A', isTitle: true),
            const SizedBox(height: 16),
            _buildDetailRow("Loan ID", _details!['loan_id'] ?? 'N/A'),
            _buildDetailRow("Amount", "₹${_details!['amount']?.toString() ?? '0'}"),
            _buildDetailRow("Loan Type", _details!['loan_type'] ?? 'N/A'),
            _buildDetailRow("Scheme", _details!['scheme'] ?? 'N/A'),
            _buildDetailRow("Applied On", _details!['date_applied'] ?? 'N/A'),
            _buildDetailRow("Overall Status", _details!['status'] ?? 'N/A', highlight: true),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool isTitle = false, bool highlight = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14, fontWeight: isTitle ? FontWeight.bold : FontWeight.normal)),
          Text(
            value,
            style: TextStyle(
              color: highlight ? Colors.blueAccent : Colors.black87,
              fontSize: 14,
              fontWeight: isTitle || highlight ? FontWeight.bold : FontWeight.w600,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessCard(Map<String, dynamic> p) {
    final fileId = p['data'];
    final status = p['process_status'];
    bool isVerified = status == 'verified';
    bool isRejected = status == 'rejected';

    return Card(
      elevation: 2,
      margin: const EdgeInsets.only(bottom: 16),
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (fileId != null && fileId.toString().length > 5)
            ClipRRect(
              borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
              child: Image.network(
                "${kBaseUrl}file/$fileId",
                height: 220,
                width: double.infinity,
                fit: BoxFit.cover,
                loadingBuilder: (ctx, child, progress) => (progress == null) ? child : Container(height: 220, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator())),
                errorBuilder: (_, __, ___) => Container(height: 220, color: Colors.grey[200], child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 40))),
              ),
            ) else Container(height: 220, color: Colors.grey[200], child: const Center(child: Text("No Image Uploaded"))),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p['what_to_do'] ?? 'N/A', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87)),
                if (p['score'] != null && p['score'] > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text("AI Confidence Score: ${p['score']}%", style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold)),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isVerified ? null : () => _verifyProcess(p['id'], 'verified'),
                        icon: const Icon(Icons.check_circle_outline, size: 18),
                        label: const Text("Approve"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green[600],
                          disabledBackgroundColor: Colors.green[200],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isRejected ? null : () => _verifyProcess(p['id'], 'rejected'),
                        icon: const Icon(Icons.highlight_off, size: 18),
                        label: const Text("Reject"),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.red[600],
                          disabledBackgroundColor: Colors.red[200],
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
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
  }
}
