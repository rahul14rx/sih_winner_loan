import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/loan_detail_screen.dart';

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
  late List<BeneficiaryLoan> filtered;

  @override
  void initState() {
    super.initState();
    filtered = widget.loans;
    _search.addListener(_applySearch);
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _applySearch() {
    final q = _search.text.toLowerCase().trim();

    setState(() {
      filtered = widget.loans.where((loan) {
        return loan.loanId!.toLowerCase().contains(q) ||
            (loan.loanType ?? '').toLowerCase().contains(q) ||
            (loan.applicantName ?? '').toLowerCase().contains(q);
      }).toList();
    });
  }

  // -------------------------------------------------------------------
  // SAME LOAN CARD UI FROM DASHBOARD — UPGRADED WITH LIGHT THEME
  // -------------------------------------------------------------------
  Widget _loanCard(BeneficiaryLoan loan) {
    int totalSteps = loan.processes.length;
    int completedSteps =
        loan.processes.where((p) => p.status == 'verified').length;

    double progress =
    totalSteps > 0 ? completedSteps / totalSteps : 0.0;

    int percentage = (progress * 100).toInt();

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
            builder: (_) => LoanDetailScreen(
              loan: loan,
            ),
          ),
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
            // ROW 1
            Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: const Color(0xFFEEF7FF),
                  child: const Icon(Icons.inventory_2_outlined,
                      color: Color(0xFF1F6FEB)),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Loan #${loan.loanId}",
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700, fontSize: 16)),
                      const SizedBox(height: 3),
                      Text("Beneficiary: ${loan.userId}",
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

            // PROGRESS HEADER
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

            // BUTTONS
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
                )
              ],
            ),
          ],
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // HEADER (GLASS + GRADIENT)
  // -------------------------------------------------------------------
  Widget _header(BuildContext context) {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 18,
        right: 18,
        bottom: 18,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFF1F6FEB), Color(0xFF2757D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(26)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.12),
            blurRadius: 26,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: ClipRect(
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
          child: Column(
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.white24,
                    child: Icon(Icons.verified_user_outlined,
                        color: Colors.white),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Text("Pending Verification",
                        style: GoogleFonts.inter(
                            color: Colors.white,
                            fontSize: 20,
                            fontWeight: FontWeight.w700)),
                  ),
                  const CircleAvatar(
                    radius: 18,
                    backgroundImage: NetworkImage(
                        'https://www.gravatar.com/avatar/placeholder?s=200&d=robohash'),
                  ),
                ],
              ),

              const SizedBox(height: 16),

              // SEARCH BAR (LIGHT CARD)
              Container(
                height: 56,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(18),
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.08),
                        blurRadius: 12,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Row(
                  children: [
                    const Icon(Icons.search,
                        size: 26, color: Color(0xFF6B7C9A)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _search,
                        decoration: const InputDecoration(
                          hintText: "Search by Loan ID, Type or Name",
                          border: InputBorder.none,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------
  // MAIN BUILD
  // -------------------------------------------------------------------
  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF6F9FC),
      body: Column(
        children: [
          _header(context),
          Expanded(
            child: filtered.isEmpty
                ? const Center(
                child: Text("No loans found.",
                    style: TextStyle(fontSize: 16)))
                : ListView.builder(
              padding: const EdgeInsets.fromLTRB(16, 20, 16, 20),
              itemCount: filtered.length,
              itemBuilder: (_, i) => Padding(
                padding: const EdgeInsets.only(bottom: 14),
                child: _loanCard(filtered[i]),
              ),
            ),
          )
        ],
      ),
    );
  }
}
