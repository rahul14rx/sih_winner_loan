// lib/pages/pending_verification_page.dart

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/loan_detail_screen.dart';
import 'package:loan2/pages/beneficiary_dashboard.dart';

class PendingVerificationPage extends StatefulWidget {
  final String userId;
  final List<BeneficiaryLoan> loans;

  const PendingVerificationPage({
    super.key,
    required this.userId,
    required this.loans,
  });

  @override
  State<PendingVerificationPage> createState() =>
      _PendingVerificationPageState();
}

class _PendingVerificationPageState extends State<PendingVerificationPage> {
  final TextEditingController _search = TextEditingController();

  late List<BeneficiaryLoan> _allPending; // master pending list
  late List<BeneficiaryLoan> _filtered;

  @override
  void initState() {
    super.initState();
    _allPending = _onlyPending(widget.loans);
    _filtered = List<BeneficiaryLoan>.from(_allPending);
    _search.addListener(_applySearch);
  }

  /// react to updated loans coming from the dashboard
  @override
  void didUpdateWidget(covariant PendingVerificationPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.loans != widget.loans ||
        oldWidget.userId != widget.userId) {
      _allPending = _onlyPending(widget.loans);
      _applySearch(); // keeps any search text applied
    }
  }

  @override
  void dispose() {
    _search.removeListener(_applySearch);
    _search.dispose();
    super.dispose();
  }

  // ---------- helpers ----------

  // extract `status` whether step is a model or a map
  String? _stepStatus(dynamic s) {
    try {
      if (s is Map) return s['status']?.toString();
      final d = s as dynamic;
      return d.status as String?;
    } catch (_) {
      return null;
    }
  }

  bool _isPendingStatus(String? s) {
    final t = (s ?? '').toLowerCase().replaceAll(' ', '_');
    return t.isEmpty ||
        t == 'pending' ||
        t == 'not_verified' ||
        t == 'in_review' ||
        t == 'pending_review' ||
        t == 'in_progress' ||
        t == 'submitted';
  }

  bool _isVerifiedStatus(String? s) {
    return (s ?? '').toLowerCase().trim() == 'verified';
  }

  List<BeneficiaryLoan> _onlyPending(List<BeneficiaryLoan> loans) {
    return loans.where((loan) {
      final steps = loan.processes;
      final anyPending = steps.any((st) => _isPendingStatus(_stepStatus(st)));
      // keep only the current user's loans (or all, if userId was intentionally empty)
      final mine = (loan.userId ?? '') == widget.userId || widget.userId.isEmpty;
      return anyPending && mine;
    }).toList();
  }

  void _applySearch() {
    final q = _search.text.trim().toLowerCase();
    setState(() {
      if (q.isEmpty) {
        _filtered = List<BeneficiaryLoan>.from(_allPending);
        return;
      }
      _filtered = _allPending.where((loan) {
        final id = (loan.loanId ?? '').toLowerCase();
        final type = (loan.loanType ?? '').toLowerCase();
        final name = (loan.applicantName ?? '').toLowerCase();
        return id.contains(q) || type.contains(q) || name.contains(q);
      }).toList();
    });
  }

  void _goHome() {
    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => BeneficiaryDashboard(userId: widget.userId),
      ),
          (route) => false,
    );
  }

  // ---------- UI ----------

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: () async {
        _goHome();
        return false;
      },
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F9FC),
        appBar: AppBar(
          leading: IconButton(
            icon: const Icon(Icons.arrow_back),
            onPressed: _goHome,
          ),
          title: Text(
            "Pending Verification",
            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
          ),
          centerTitle: true,
          elevation: 0,
          backgroundColor: const Color(0xFF1F6FEB),
          foregroundColor: Colors.white,
        ),
        body: Column(
          children: [
            // search
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 16, 6),
              child: Container(
                height: 52,
                padding: const EdgeInsets.symmetric(horizontal: 14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withOpacity(0.06),
                      blurRadius: 14,
                      offset: const Offset(0, 6),
                    )
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search, color: Color(0xFF6B7C9A)),
                    const SizedBox(width: 10),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          hintText: "Search by Loan ID, Type or Name",
                          border: InputBorder.none,
                        ),
                      ),
                    )
                  ],
                ),
              ),
            ),

            // list
            Expanded(
              child: _filtered.isEmpty
                  ? const Center(
                child: Text(
                  "No loans found.",
                  style: TextStyle(fontSize: 16),
                ),
              )
                  : ListView.builder(
                padding: const EdgeInsets.fromLTRB(16, 14, 16, 20),
                itemCount: _filtered.length,
                itemBuilder: (_, i) => Padding(
                  padding: const EdgeInsets.only(bottom: 14),
                  child: _loanCard(_filtered[i]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _loanCard(BeneficiaryLoan loan) {
    final total = loan.processes.length;
    final done =
        loan.processes.where((p) => _isVerifiedStatus(_stepStatus(p))).length;

    final progress = total > 0 ? done / total : 0.0;
    final percentage = (progress * 100).toInt();

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
          MaterialPageRoute(builder: (_) => LoanDetailScreen(loan: loan)),
        );
      },
      borderRadius: BorderRadius.circular(20),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 20,
              offset: const Offset(0, 8),
            ),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // header row
            Row(
              children: [
                const CircleAvatar(
                  radius: 24,
                  backgroundColor: Color(0xFFEEF7FF),
                  child: Icon(Icons.inventory_2_outlined,
                      color: Color(0xFF1F6FEB)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Loan #${loan.loanId ?? ''}",
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text("Beneficiary: ${loan.userId ?? ''}",
                          style: TextStyle(
                              color: Colors.grey[600], fontSize: 13)),
                    ],
                  ),
                ),
                Container(
                  padding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      colors: [
                        statusColor.withOpacity(0.95),
                        statusColor.withOpacity(0.65),
                      ],
                    ),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Text(
                    statusText,
                    style: GoogleFonts.inter(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                )
              ],
            ),

            const SizedBox(height: 18),

            // progress
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text("Verification Progress",
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.w600, fontSize: 14)),
                Text("$percentage%",
                    style: GoogleFonts.inter(
                        fontWeight: FontWeight.bold, fontSize: 14)),
              ],
            ),
            const SizedBox(height: 8),
            ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: LinearProgressIndicator(
                value: progress,
                minHeight: 10,
                backgroundColor: Colors.grey[200],
                valueColor: AlwaysStoppedAnimation(statusColor),
              ),
            ),

            const SizedBox(height: 12),

            // actions
            Row(
              children: [
                TextButton.icon(
                  onPressed: () {
                    Navigator.push(
                        context,
                        MaterialPageRoute(
                            builder: (_) => LoanDetailScreen(loan: loan)));
                  },
                  icon: const Icon(Icons.visibility_outlined, size: 18),
                  label: const Text("View details"),
                ),
                const Spacer(),
                IconButton(
                  onPressed: () {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text("More actions soon")),
                    );
                  },
                  icon: const Icon(Icons.more_vert),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
