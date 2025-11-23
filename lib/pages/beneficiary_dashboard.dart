import 'package:flutter/material.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/loan_detail_screen.dart'; // We will build this next

class BeneficiaryDashboard extends StatefulWidget {
  final String userId;

  const BeneficiaryDashboard({super.key, required this.userId});

  @override
  State<BeneficiaryDashboard> createState() => _BeneficiaryDashboardState();
}

class _BeneficiaryDashboardState extends State<BeneficiaryDashboard> {
  final BeneficiaryService _service = BeneficiaryService();
  List<BeneficiaryLoan> _loans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final data = await _service.fetchUserLoans(widget.userId);
      if (mounted) setState(() { _loans = data; _isLoading = false; });
    } catch (e) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('My Verification Requests', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: false,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _loans.isEmpty
          ? _buildEmptyState()
          : ListView.separated(
        padding: const EdgeInsets.all(20),
        itemCount: _loans.length,
        separatorBuilder: (_, __) => const SizedBox(height: 16),
        itemBuilder: (context, index) => _buildLoanCard(_loans[index]),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.assignment_outlined, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text("No active loans found.", style: TextStyle(color: Colors.grey[600], fontSize: 16)),
        ],
      ),
    );
  }

  Widget _buildLoanCard(BeneficiaryLoan loan) {
    // Calculate progress based on real backend status
    int totalSteps = loan.processes.length;
    int completedSteps = loan.processes.where((p) => p.status == 'verified').length;
    double progress = totalSteps > 0 ? completedSteps / totalSteps : 0.0;
    int percentage = (progress * 100).toInt();

    // Determine status color
    Color statusColor = Colors.orange;
    String statusText = "Pending";
    if (percentage > 0 && percentage < 100) {
      statusColor = Colors.blue;
      statusText = "In Progress";
    } else if (percentage == 100) {
      statusColor = Colors.green;
      statusText = "Verified";
    }

    return InkWell(
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => LoanDetailScreen(loan: loan),
          ),
        ).then((_) => _loadData()); // Refresh on return
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 15,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Chip(
                  label: Text(loan.processes.isNotEmpty ? "Asset Loan" : "General", style: const TextStyle(fontSize: 12, color: Colors.white)),
                  backgroundColor: const Color(0xFF000080), // Navy
                  padding: EdgeInsets.zero,
                  materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: statusColor.withOpacity(0.1),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: TextStyle(color: statusColor, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              "Loan #${loan.loanId}",
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.black87),
            ),
            const SizedBox(height: 4),
            Text(
              "Beneficiary: ${loan.userId}", // Assuming userId is Phone/Name
              style: TextStyle(color: Colors.grey[600], fontSize: 14),
            ),
            const SizedBox(height: 20),

            // Progress Bar
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text("Verification Progress", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600)),
                    Text("$percentage%", style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                  ],
                ),
                const SizedBox(height: 8),
                ClipRRect(
                  borderRadius: BorderRadius.circular(10),
                  child: LinearProgressIndicator(
                    value: progress,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor: const AlwaysStoppedAnimation(Color(0xFF138808)), // Green
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}