import 'package:flutter/material.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/verification_step_page.dart'; // New flow page

class LoanDetailScreen extends StatelessWidget {
  final BeneficiaryLoan loan;

  const LoanDetailScreen({super.key, required this.loan});

  @override
  Widget build(BuildContext context) {
    // Calculate stats
    int completed = loan.processes.where((p) => p.status == 'verified').length;
    int total = loan.processes.length;
    double progress = total > 0 ? completed / total : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Verification Details', style: TextStyle(color: Colors.black)),
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Colors.black),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // 1. Utilization Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Loan Utilization", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text("${(progress * 100).toInt()}% Complete", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 15),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(10),
                    child: LinearProgressIndicator(
                      value: progress,
                      minHeight: 10,
                      backgroundColor: Colors.grey[100],
                      valueColor: const AlwaysStoppedAnimation(Color(0xFF138808)),
                    ),
                  ),
                  const SizedBox(height: 15),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      _buildInfoColumn("Loan ID", loan.loanId),
                      _buildInfoColumn("Status", progress == 1 ? "Verified" : "In Progress"),
                    ],
                  )
                ],
              ),
            ),

            const SizedBox(height: 25),
            const Text("Required Steps", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF000080))),
            const SizedBox(height: 15),

            // 2. Dynamic Steps List
            ...loan.processes.map((step) => _buildStepTile(context, step)),

            const SizedBox(height: 30),

            // 3. Start Button
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: () => _showRulesSheet(context, loan.processes.first), // Start with first step or logic
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF138808),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  elevation: 5,
                ),
                child: const Text("Start Verification", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInfoColumn(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: TextStyle(color: Colors.grey[500], fontSize: 12)),
        const SizedBox(height: 4),
        Text(value, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
      ],
    );
  }

  Widget _buildStepTile(BuildContext context, ProcessStep step) {
    bool isVerified = step.status == 'verified';

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: isVerified ? Colors.green.withOpacity(0.5) : Colors.transparent),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: isVerified ? Colors.green[50] : Colors.blue[50],
              shape: BoxShape.circle,
            ),
            child: Icon(
              step.dataType == 'video' ? Icons.videocam : Icons.camera_alt,
              color: isVerified ? Colors.green : Colors.blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.whatToDo, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
                const SizedBox(height: 4),
                Text(
                  isVerified ? "Completed" : "Pending • ${step.dataType.toUpperCase()}",
                  style: TextStyle(color: isVerified ? Colors.green : Colors.grey[600], fontSize: 12),
                ),
              ],
            ),
          ),
          if (isVerified)
            const Icon(Icons.check_circle, color: Colors.green),
        ],
      ),
    );
  }

  // --- Rules Bottom Sheet (From your reference) ---
  void _showRulesSheet(BuildContext context, ProcessStep firstStep) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (ctx) {
        bool agreed = false;
        return StatefulBuilder(
            builder: (context, setState) {
              return Container(
                decoration: const BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
                ),
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Center(child: Container(height: 4, width: 40, color: Colors.grey[300])),
                    const SizedBox(height: 20),
                    const Text("Rules & Regulations", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold, color: Color(0xFF000080))),
                    const SizedBox(height: 16),
                    _buildRuleItem("Funds must only be used for the sanctioned purpose."),
                    _buildRuleItem("Upload original invoices/bills for all major purchases."),
                    _buildRuleItem("Geo-tagging is mandatory for all photos."),
                    _buildRuleItem("Misuse of funds can lead to legal action."),
                    const SizedBox(height: 20),
                    CheckboxListTile(
                      value: agreed,
                      onChanged: (v) => setState(() => agreed = v!),
                      title: const Text("I agree and give consent to proceed.", style: TextStyle(fontSize: 14)),
                      contentPadding: EdgeInsets.zero,
                      activeColor: const Color(0xFF138808),
                    ),
                    const SizedBox(height: 16),
                    SizedBox(
                      width: double.infinity,
                      child: ElevatedButton(
                        onPressed: agreed
                            ? () {
                          Navigator.pop(context); // Close sheet
                          // Navigate to the Verification Page for the specific loan
                          // In a real app, you might loop through steps. For now, we open the first pending one or just the list.
                          // Let's navigate to the First Pending Step or just refresh.
                          // For better UX, we navigate to the step page for the first step.
                          Navigator.push(
                              context,
                              MaterialPageRoute(
                                  builder: (_) => VerificationStepPage(
                                    loanId: loan.loanId,
                                    step: firstStep,
                                    userId: loan.userId,
                                  )
                              )
                          );
                        }
                            : null,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF138808),
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("Start Verification"),
                      ),
                    ),
                  ],
                ),
              );
            }
        );
      },
    );
  }

  Widget _buildRuleItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("• ", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
          Expanded(child: Text(text, style: TextStyle(color: Colors.grey[700], height: 1.4))),
        ],
      ),
    );
  }
}