import 'dart:async';
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
  bool _isRefreshing = true;

  Map<String, bool> _localUploads = {};
  // This is mock data, in a real app, you would fetch this.
  double _amountUsed = 27000;

  @override
  void initState() {
    super.initState();
    _currentLoan = widget.loan;
    _refreshLoanData();
  }

  Future<void> _checkLocalUploads() async {
    final queued = await DatabaseHelper.instance.getQueuedForUpload();
    final Map<String, bool> statusMap = {};
    for (var row in queued) {
      final pid = row[DatabaseHelper.colProcessId] as String?;
      final lid = row[DatabaseHelper.colLoanId] as String?;
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
    if (!_isRefreshing) setState(() => _isRefreshing = true);
    // Always check for local changes first
    await _checkLocalUploads();
    try {
      // Then, fetch the latest data from the server
      final updatedLoan = await _service.fetchLoanDetails(_currentLoan.loanId);
      if (mounted) {
        setState(() {
          _currentLoan = updatedLoan;
          _isRefreshing = false;
        });
      }
    } catch (e) {
      // If fetching fails (e.g., offline), still stop the refresh indicator
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  // Navigation logic is separated for clarity
  Future<void> _navigateToVerification(ProcessStep step) async {
    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerificationStepPage(
          loanId: _currentLoan.loanId,
          step: step,
          userId: _currentLoan.userId,
        ),
      ),
    );
    // When we return from the verification page, refresh the data
    if (result == true) {
      _refreshLoanData();
    }
  }

  @override
  Widget build(BuildContext context) {
    // This should probably come from your API in a real app
    double sanctionedAmount = 60000;
    double utilizationPercent = (_amountUsed / sanctionedAmount).clamp(0.0, 1.0);

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Verification Page', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: _isRefreshing
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: _refreshLoanData,
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildUtilizationCard(utilizationPercent, sanctionedAmount),
                    const SizedBox(height: 20),
                    _buildLoanDetailsCard(sanctionedAmount),
                    const SizedBox(height: 30),
                    _buildStartVerificationButton(),
                    const SizedBox(height: 30),
                    const Text("Steps Checklist", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
                    const SizedBox(height: 10),
                    ..._currentLoan.processes.map((step) => _buildStepTile(step)),
                  ],
                ),
              ),
            ),
    );
  }

  // --- WIDGET BUILDER METHODS ---

  Widget _buildUtilizationCard(double utilizationPercent, double sanctionedAmount) {
    return Container(
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
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoanDetailsCard(double sanctionedAmount) {
    return Container(
      padding: const EdgeInsets.all(20),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
      ),
      child: Column(
        children: [
          _buildDetailRow("Asset", "Laptop Loan"),
          _buildDetailRow("Beneficiary", "Rahul Kumar"),
          _buildDetailRow("Loan ID", _currentLoan.loanId),
          _buildDetailRow("Scheme", "NBCFDC"),
          _buildDetailRow("Category", "Education Loan"),
          _buildDetailRow("Bank", "State Bank of India"),
          _buildDetailRow("Sanctioned Amount", "₹${sanctionedAmount.toInt()}"),
          _buildDetailRow("Status", "Pending"),
        ],
      ),
    );
  }

  Widget _buildStartVerificationButton() {
    return Builder(builder: (context) {
      ProcessStep? nextStep = _findNextStep();

      if (nextStep == null) {
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
          // MODIFIED: This onPressed now refreshes data before navigating
          onPressed: () async {
            await _refreshLoanData(); // API Call is made here
            final refreshedNextStep = _findNextStep(); // Check again with new data
            if (refreshedNextStep != null && mounted) {
              _navigateToVerification(refreshedNextStep);
            }
          },
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(0xFF435E91),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            elevation: 5,
          ),
          child: Text("Start ${nextStep.whatToDo}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
        ),
      );
    });
  }

  Widget _buildStepTile(ProcessStep step) {
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
                if (isDone) Text(statusText, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (!isDone)
            ElevatedButton(
              // MODIFIED: This onPressed now refreshes data before navigating
              onPressed: () async {
                await _refreshLoanData(); // API Call is made here
                // Find the specific step again from the refreshed list
                final refreshedStep = _currentLoan.processes.firstWhere((s) => s.id == step.id);
                // Only navigate if the step is still not done after refresh
                if (refreshedStep.status != 'verified' && refreshedStep.status != 'pending_review' && mounted) {
                  _navigateToVerification(refreshedStep);
                }
              },
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
  
  // Helper to find the next step to be done
  ProcessStep? _findNextStep() {
    for (var step in _currentLoan.processes) {
      bool isLocallyDone = _localUploads[step.id] == true;
      bool isServerDone = step.status == 'verified' || step.status == 'pending_review';
      if (!isLocallyDone && !isServerDone) {
        return step;
      }
    }
    return null;
  }
}
