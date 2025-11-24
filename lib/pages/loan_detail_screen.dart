import 'package:flutter/material.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/verification_step_page.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/services/database_helper.dart';

class LoanDetailScreen extends StatefulWidget {
  final BeneficiaryLoan loan;

  const LoanDetailScreen({super.key, required this.loan});

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  late BeneficiaryLoan _currentLoan;
  final BeneficiaryService _service = BeneficiaryService();
  bool _isRefreshing = false;

  // Tracks which steps are saved locally (offline) but not yet synced
  Map<String, bool> _localUploads = {};

  // Mock utilization amount for demo (In real app, fetch from API)
  double _amountUsed = 0; 

  @override
  void initState() {
    super.initState();
    _currentLoan = widget.loan;
    
    // Refresh data from API when page enters
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLoanData();
    });
  }

  // Check local DB to see if we have pending uploads for this loan
  Future<void> _checkLocalUploads() async {
    final queued = await DatabaseHelper.instance.getQueuedForUpload();
    final Map<String, bool> statusMap = {};

    for (var row in queued) {
      final pid = row[DatabaseHelper.colProcessId] as String?;
      final lid = row[DatabaseHelper.colLoanId] as String?;

      // If the local DB has an entry for this Loan ID & Process ID, mark it as locally done
      if (pid != null && lid == _currentLoan.loanId) {
        statusMap[pid] = true;
      }
    }

    if (mounted) {
      setState(() {
        _localUploads = statusMap;
      });
    }
  }

  Future<void> _refreshLoanData() async {
    setState(() => _isRefreshing = true);

    // 1. Re-check local DB status (Critical for offline updates)
    await _checkLocalUploads();

    // 2. Fetch latest server status
    try {
      print("Fetching details for loan ID: ${_currentLoan.loanId}");
      final updatedLoan = await _service.fetchLoanDetails(_currentLoan.loanId);
      print("Fetched loan details: ${updatedLoan.applicantName}, ${updatedLoan.status}");

      if (mounted) {
        setState(() {
          _currentLoan = updatedLoan;
          _amountUsed = _currentLoan.amount * 0.45; // Mock utilization
          _isRefreshing = false;
        });
      }
    } catch (e) {
      print("Error fetching loan details: $e");
      if (mounted) {
        setState(() => _isRefreshing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to refresh: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    double sanctionedAmount = _currentLoan.amount;
    double utilizationPercent = sanctionedAmount > 0 ? (_amountUsed / sanctionedAmount).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Verification Page', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _refreshLoanData,
          )
        ],
      ),
      body: _isRefreshing
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Utilization Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Loan Utilization", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text("${(utilizationPercent * 100).toInt()}% · Provisional", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    children: [
                      Container(
                        height: 10,
                        width: double.infinity,
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)),
                      ),
                      FractionallySizedBox(
                        widthFactor: utilizationPercent,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF435E91),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text("₹${_amountUsed.toInt()} of ₹${sanctionedAmount.toInt()} used", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                      Text("${(utilizationPercent * 100).toInt()}% · Provisional", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. Loan Details Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  // Dynamic Details from _currentLoan
                  _buildDetailRow("Beneficiary", _currentLoan.applicantName),
                  _buildDetailRow("Loan ID", _currentLoan.loanId),
                  _buildDetailRow("Type", _currentLoan.loanType),
                  _buildDetailRow("Scheme", _currentLoan.scheme),
                  _buildDetailRow("Date Applied", _currentLoan.dateApplied),
                  _buildDetailRow("Sanctioned Amount", "₹${_currentLoan.amount.toInt()}"),
                  _buildDetailRow("Status", _currentLoan.status),
                ],
              ),
            ),

            const SizedBox(height: 30),

            // 3. Start Verification Button
            Builder(
                builder: (context) {
                  ProcessStep? nextStep;
                  bool allDone = true;

                  for (var step in _currentLoan.processes) {
                    bool isLocallyDone = _localUploads[step.id] == true;
                    bool isServerDone = step.status == 'verified' || step.status == 'pending_review';

                    if (!isLocallyDone && !isServerDone) {
                      nextStep = step;
                      allDone = false;
                      break;
                    }
                  }

                  if (allDone) {
                    return SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          disabledBackgroundColor: Colors.green.withOpacity(0.6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("All Steps Completed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    );
                  }

                  return SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () {
                        if (nextStep != null) {
                          _startVerification(nextStep);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF435E91),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 5,
                      ),
                      child: Text("Start ${nextStep!.whatToDo}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  );
                }
            ),

            const SizedBox(height: 30),

            // 4. Steps List
            const Text("Steps Checklist", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            ..._currentLoan.processes.map((step) => _buildStepTile(step)),
          ],
        ),
      ),
    );
  }

  void _startVerification(dynamic step) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerificationStepPage(
          loanId: _currentLoan.loanId,
          step: step,
          userId: _currentLoan.userId,
        ),
      ),
    ).then((result) {
      if (result == true) {
        _refreshLoanData();
      }
    });
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildStepTile(dynamic step) {
    bool isLocallyDone = _localUploads[step.id] == true;
    bool isServerDone = step.status == 'verified' || step.status == 'pending_review';
    bool isDone = isServerDone || isLocallyDone;

    String statusText = "Pending";
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.radio_button_unchecked;

    if (isLocallyDone) {
      statusText = "Queued (Offline)";
      statusColor = Colors.orange;
      statusIcon = Icons.cloud_upload;
    } else if (step.status == 'verified') {
      statusText = "Verified";
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (step.status == 'pending_review') {
      statusText = "In Review";
      statusColor = Colors.blue;
      statusIcon = Icons.access_time_filled;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDone ? statusColor.withOpacity(0.3) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.whatToDo, style: TextStyle(color: isDone ? Colors.black87 : Colors.grey[600], fontWeight: isDone ? FontWeight.w600 : FontWeight.normal)),
                if (isDone)
                  Text(statusText, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (!isDone)
            ElevatedButton(
              onPressed: () => _startVerification(step),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF138808),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(60, 30),
                elevation: 0,
              ),
              child: const Text("Start", style: TextStyle(fontSize: 12, color: Colors.white)),
            ),
        ],
      ),
    );
  }
}
