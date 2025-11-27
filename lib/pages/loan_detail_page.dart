import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';

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
  bool _isOnline = true;

  bool _verificationTriggered = false;

  @override
  void initState() {
    super.initState();
    _checkOnline();
    _fetchDetails();
  }

  Future<void> _checkOnline() async {
    _isOnline = await SyncService.realInternetCheck();
    if (mounted) setState(() {});
  }

  Future<File> _getCacheFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'loan_detail_cache_${widget.loanId}.json'));
  }

  Future<void> _writeToCache(Map<String, dynamic> data) async {
    try {
      final file = await _getCacheFile();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Failed to write cache: $e");
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _details = data;
            _loading = false;
            _error = '';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You are offline. Viewing cached data."),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) setState(() => _error = "No offline data available.");
      }
    } catch (e) {
      debugPrint("Failed to load cache: $e");
      if (mounted) setState(() => _error = "Failed to load offline data.");
    }
  }

  Future<void> _fetchDetails() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final isOnline = await SyncService.realInternetCheck();
      if (!isOnline) {
        setState(() => _loading = false);
        await _loadFromCache();
        return;
      }

      final data = await getJson('loan_details?loan_id=${widget.loanId}');

      if (!mounted) return;
      final details = data['loan_details'] as Map<String, dynamic>?;

      setState(() {
        _details = details;
        _loading = false;
      });

      if (details != null) {
        await _writeToCache(details);

        final status = (details['status'] ?? '').toString().toLowerCase();
        if (_verificationTriggered && status == 'verified') {
          _verificationTriggered = false;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("All steps verified. Moved to History."),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint("Error fetching details: $e");
      if (mounted) {
        setState(() => _loading = false);
        await _loadFromCache();
      }
    }
  }

  Future<void> _verifyProcess(String processId, String status) async {
    _verificationTriggered = true;

    bool isOnline = await SyncService.realInternetCheck();

    if (!isOnline) {
      try {
        await DatabaseHelper.instance.insertOfficerAction(
          loanId: widget.loanId,
          processId: processId,
          actionType: status,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Offline: Action queued ($status). Will sync when online."),
              backgroundColor: Colors.orange,
            ),
          );
          _optimisticUpdate(processId, status);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to save action: $e")),
          );
        }
      }
      return;
    }

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
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Marked as $status"),
              backgroundColor: Colors.green,
            ),
          );
        }
        _fetchDetails();
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error updating status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _optimisticUpdate(String processId, String status) {
    if (_details == null) return;

    final processes = List<Map<String, dynamic>>.from(_details!['process'] ?? []);
    final index = processes.indexWhere((p) => p['id'] == processId);

    if (index != -1) {
      processes[index]['process_status'] = status;
      setState(() {
        _details!['process'] = processes;
      });
      _writeToCache(_details!);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: Text(
          "Review Loan #${widget.loanId}",
          style: const TextStyle(
            color: Colors.black,
            fontWeight: FontWeight.bold,
            fontSize: 18,
          ),
        ),
        backgroundColor: Colors.white,
        elevation: 1,
        shadowColor: Colors.black26,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          FutureBuilder<bool>(
            future: SyncService.realInternetCheck(),
            builder: (context, snapshot) {
              bool online = snapshot.data ?? false;
              return Padding(
                padding: const EdgeInsets.all(16.0),
                child: Icon(
                  online ? Icons.cloud_done : Icons.cloud_off,
                  color: online ? Colors.green : Colors.grey,
                ),
              );
            },
          )
        ],
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
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
              const SizedBox(height: 16),
              Text(_error, style: const TextStyle(color: Colors.black54), textAlign: TextAlign.center),
              const SizedBox(height: 16),
              ElevatedButton(onPressed: _fetchDetails, child: const Text("Retry"))
            ],
          ),
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
          const Text(
            "Verification Steps",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
          ),
          const SizedBox(height: 12),
          if (processes.isEmpty)
            const Text("No verification steps for this loan.")
          else
            ...processes.map((p) => _buildProcessCard(Map<String, dynamic>.from(p))),
        ],
      ),
    );
  }

  Widget _buildDetailsCard() {
    final loanPurpose = (_details!['loan_purpose'] ?? 'N/A').toString();

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.1),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildDetailRow("Applicant", (_details!['applicant_name'] ?? 'N/A').toString(), isTitle: true),
            const SizedBox(height: 16),

            _buildDetailRow("Loan ID", (_details!['loan_id'] ?? 'N/A').toString()),
            _buildDetailRow("Amount", "₹${_details!['amount']?.toString() ?? '0'}"),
            _buildDetailRow("Scheme", (_details!['scheme'] ?? 'N/A').toString()),
            _buildDetailRow("Loan Type", (_details!['loan_type'] ?? 'N/A').toString(), wrapValue: true),
            _buildDetailRow("Loan Purpose", loanPurpose, wrapValue: true),
            _buildDetailRow("Applied On", (_details!['date_applied'] ?? 'N/A').toString()),
            _buildDetailRow("Overall Status", (_details!['status'] ?? 'N/A').toString(), highlight: true),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(
      String label,
      String value, {
        bool isTitle = false,
        bool highlight = false,
        bool wrapValue = false,
      }) {
    final labelStyle = TextStyle(
      color: Colors.grey[600],
      fontSize: 14,
      fontWeight: isTitle ? FontWeight.bold : FontWeight.normal,
    );

    final valueStyle = TextStyle(
      color: highlight ? Colors.blueAccent : Colors.black87,
      fontSize: 14,
      fontWeight: isTitle || highlight ? FontWeight.bold : FontWeight.w600,
    );

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6.0),
      child: Row(
        crossAxisAlignment: wrapValue ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            flex: 4,
            child: Text(label, style: labelStyle),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: valueStyle,
                maxLines: wrapValue ? 2 : 1,
                overflow: TextOverflow.ellipsis,
                softWrap: wrapValue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessCard(Map<String, dynamic> p) {
    final fileId = p['data'];
    final status = (p['process_status'] ?? '').toString();
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
                loadingBuilder: (ctx, child, progress) => (progress == null)
                    ? child
                    : Container(
                  height: 220,
                  color: Colors.grey[200],
                  child: const Center(child: CircularProgressIndicator()),
                ),
                errorBuilder: (_, __, ___) => Container(
                  height: 220,
                  color: Colors.grey[200],
                  child: const Center(child: Icon(Icons.broken_image, color: Colors.grey, size: 40)),
                ),
              ),
            )
          else
            Container(
              height: 220,
              color: Colors.grey[200],
              child: const Center(child: Text("No Image Uploaded")),
            ),
          Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  (p['what_to_do'] ?? 'N/A').toString(),
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.black87),
                ),
                if (p['score'] != null && (p['score'] is num) && (p['score'] as num) > 0)
                  Padding(
                    padding: const EdgeInsets.only(top: 8.0),
                    child: Text(
                      "AI Confidence Score: ${p['score']}%",
                      style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.bold),
                    ),
                  ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: isVerified ? null : () => _verifyProcess((p['id'] ?? '').toString(), 'verified'),
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
                        onPressed: isRejected ? null : () => _verifyProcess((p['id'] ?? '').toString(), 'rejected'),
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
