import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan2/services/bank_service.dart';
import 'package:loan2/models/loan_application.dart';
import 'package:loan2/pages/loan_detail_page.dart';
import 'package:loan2/pages/create_beneficiary_page.dart';
import 'package:loan2/pages/help_support_page.dart';
import 'package:loan2/pages/history_page.dart';
import 'package:loan2/pages/reports_page.dart';
import 'package:loan2/pages/history_page.dart';

class BankDashboardPage extends StatefulWidget {
  final String officerId;
  const BankDashboardPage({super.key, required this.officerId});

  @override
  State<BankDashboardPage> createState() => _BankDashboardPageState();
}

class _BankDashboardPageState extends State<BankDashboardPage> {
  final BankService _bankService = BankService();
  Map<String, int> _stats = {'pending': 0, 'verified': 0, 'rejected': 0};
  List<LoanApplication> _loans = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final statsFuture = _bankService.fetchDashboardStats(widget.officerId);
      final loansFuture = _bankService.fetchPendingLoans(widget.officerId);
      final results = await Future.wait([statsFuture, loansFuture]);

      if (mounted) {
        setState(() {
          _stats = results[0] as Map<String, int>;
          _loans = results[1] as List<LoanApplication>;
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint("Dashboard Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA), // Clean off-white
      appBar: AppBar(
        title: Text(
          'Officer Dashboard',
          style: GoogleFonts.poppins(
            color: Colors.white,
            fontWeight: FontWeight.w600,
            fontSize: 20,
          ),
        ),
        flexibleSpace: Container(
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [Color(0xFFFF9933), Color(0xFFFF7722)], // Saffron Gradient
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
          ),
        ),
        centerTitle: true,
        elevation: 0,
        leading: Builder(builder: (context) {
          return IconButton(
            icon: const Icon(Icons.menu_rounded, color: Colors.white),
            onPressed: () => Scaffold.of(context).openDrawer(),
          );
        }),
      ),
      drawer: _buildProDrawer(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
                builder: (context) =>
                    CreateBeneficiaryPage(officerId: widget.officerId)),
          ).then((_) => _loadData());
        },
        label: Text(
          "New Beneficiary",
          style: GoogleFonts.inter(fontWeight: FontWeight.bold, fontSize: 15),
        ),
        icon: const Icon(Icons.person_add_alt_1_rounded),
        backgroundColor: const Color(0xFF138808), // Green
        foregroundColor: Colors.white,
        elevation: 4,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const BouncingScrollPhysics(),
          slivers: [
            // 1. Welcome Header with Curve
            SliverToBoxAdapter(
              child: Stack(
                children: [
                  Container(
                    height: 120,
                    decoration: const BoxDecoration(
                      gradient: LinearGradient(
                        colors: [Color(0xFFFF9933), Color(0xFFFF7722)],
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                      ),
                      borderRadius: BorderRadius.only(
                        bottomLeft: Radius.circular(32),
                        bottomRight: Radius.circular(32),
                      ),
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 10, 24, 40),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          "Welcome, ${widget.officerId}",
                          style: GoogleFonts.poppins(
                            color: Colors.white,
                            fontSize: 26,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        Text(
                          "Here's your daily verification summary.",
                          style: GoogleFonts.inter(
                            color: Colors.white.withOpacity(0.9),
                            fontSize: 14,
                          ),
                        ),
                      ],
                    ),
                  ),
                  // Stats Cards Floating Over Header
                  Padding(
                    padding: const EdgeInsets.only(top: 80, left: 16, right: 16),
                    child: _buildStatsRow(),
                  ),
                ],
              ),
            ),

            // 2. Section Title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(24, 24, 24, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      "Pending Reviews",
                      style: GoogleFonts.poppins(
                        fontSize: 18,
                        fontWeight: FontWeight.w700,
                        color: const Color(0xFF000080), // Navy
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.blue.withOpacity(0.1),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        "${_loans.length} Cases",
                        style: GoogleFonts.inter(
                          color: Colors.blue[800],
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // 3. Loan List
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _loans.isEmpty
                  ? SliverToBoxAdapter(child: _buildEmptyState())
                  : SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildProLoanCard(_loans[index]),
                  childCount: _loans.length,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)),
          ],
        ),
      ),
    );
  }

  // --- PRO STATS CARDS ---
  Widget _buildStatsRow() {
    return Row(
      children: [
        _buildGlassStatCard(
          "Pending",
          _stats['pending']!,
          Colors.orange,
          Icons.hourglass_top_rounded,
        ),
        const SizedBox(width: 12),
        _buildGlassStatCard(
          "Verified",
          _stats['verified']!,
          Colors.green,
          Icons.verified_rounded,
        ),
        const SizedBox(width: 12),
        _buildGlassStatCard(
          "Rejected",
          _stats['rejected']!,
          Colors.red,
          Icons.cancel_rounded,
        ),
      ],
    );
  }

  Widget _buildGlassStatCard(String title, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(20),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 15,
              offset: const Offset(0, 8),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: color.withOpacity(0.1),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, color: color, size: 24),
            ),
            const SizedBox(height: 12),
            Text(
              count.toString(),
              style: GoogleFonts.poppins(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: const Color(0xFF1A1A1A),
              ),
            ),
            Text(
              title,
              style: GoogleFonts.inter(
                color: Colors.grey[600],
                fontSize: 12,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }

  // --- PRO LOAN CARD ---
  Widget _buildProLoanCard(LoanApplication loan) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: Colors.grey.shade100),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: loan.loanId)),
            ).then((_) => _loadData());
          },
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Container(
                  width: 50,
                  height: 50,
                  decoration: BoxDecoration(
                    color: const Color(0xFFF0F4FF),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      loan.applicantName.isNotEmpty ? loan.applicantName[0] : "?",
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF435E91),
                        fontWeight: FontWeight.bold,
                        fontSize: 20,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.applicantName,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 16,
                          color: const Color(0xFF1A1A1A),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.orange.withOpacity(0.1),
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "ID: ${loan.loanId}",
                              style: GoogleFonts.inter(
                                  fontSize: 11,
                                  color: Colors.deepOrange,
                                  fontWeight: FontWeight.w600
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "• ₹${loan.amount.toStringAsFixed(0)}",
                            style: GoogleFonts.inter(
                              color: Colors.grey[600],
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: Colors.grey[300]),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 80, color: Colors.grey[200]),
          const SizedBox(height: 16),
          Text(
            "All caught up!",
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: Colors.grey[400],
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "No pending loans to review.",
            style: GoogleFonts.inter(color: Colors.grey[400]),
          ),
        ],
      ),
    );
  }

  // --- PRO DRAWER ---
  Widget _buildProDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF9933), Color(0xFFFFFFFF)], // Saffron to Green
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            accountName: Text(
              widget.officerId,
              style: GoogleFonts.poppins(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.2),
                borderRadius: BorderRadius.circular(4),
              ),
              child: Text(
                "ID: ${widget.officerId} | New Delhi",
                style: GoogleFonts.inter(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 12),
              ),
            ),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                widget.officerId.isNotEmpty ? widget.officerId.substring(0, 2).toUpperCase() : "??",
                style: GoogleFonts.poppins(
                  fontSize: 24,
                  color: const Color(0xFFFF9933),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: 10),
              children: [
                _buildDrawerItem(Icons.dashboard_rounded, "Dashboard", true, () => Navigator.pop(context)),
                _buildDrawerItem(Icons.person_add_alt_1_rounded, "New Beneficiary", false, () {
                  Navigator.pop(context);
                  Navigator.push(context, MaterialPageRoute(builder: (context) => CreateBeneficiaryPage(officerId: widget.officerId)));
                }),
    _buildDrawerItem(Icons.history_rounded, "History", false, () {
    Navigator.pop(context);
    Navigator.push(
    context,
    MaterialPageRoute(
    builder: (_) => HistoryPage(officerId: widget.officerId),
    ),
    );
    }),

                _buildDrawerItem(Icons.analytics_rounded, "Reports", false, () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => ReportsPage(officerId: widget.officerId),
                    ),
                  );


                }),
                const Divider(indent: 20, endIndent: 20, height: 30),
                _buildDrawerItem(Icons.settings_rounded, "Settings", false, () {}),
                _buildDrawerItem(Icons.help_outline_rounded, "Help & Support", false, () {
                  Navigator.pop(context); // Close drawer
                  Navigator.push(
                      context,
                      MaterialPageRoute(builder: (context) => const HelpSupportPage())
                  );
                }),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(20.0),
            child: InkWell(
              borderRadius: BorderRadius.circular(12),
              onTap: () => Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false),
              child: Container(
                padding: const EdgeInsets.symmetric(vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.red.withOpacity(0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.logout_rounded, color: Colors.red, size: 20),
                    const SizedBox(width: 8),
                    Text(
                      "Logout",
                      style: GoogleFonts.poppins(
                        color: Colors.red,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, bool isSelected, VoidCallback onTap) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 24, vertical: 4),
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFFFF9933) : Colors.grey[600],
        size: 26,
      ),
      title: Text(
        title,
        style: GoogleFonts.poppins(
          color: isSelected ? const Color(0xFFFF9933) : Colors.black87,
          fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
          fontSize: 15,
        ),
      ),
      selected: isSelected,
      selectedTileColor: const Color(0xFFFF9933).withOpacity(0.08),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.only(topRight: Radius.circular(20), bottomRight: Radius.circular(20)),
      ),
      onTap: onTap,
    );
  }
}
