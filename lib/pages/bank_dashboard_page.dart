import 'package:flutter/material.dart';
import 'package:loan2/services/bank_service.dart';
import 'package:loan2/models/loan_application.dart';
import 'package:loan2/pages/loan_detail_page.dart';
import 'package:loan2/pages/create_beneficiary_page.dart'; // Import new page

class BankDashboardPage extends StatefulWidget {
  const BankDashboardPage({super.key});

  @override
  State<BankDashboardPage> createState() => _BankDashboardPageState();
}

class _BankDashboardPageState extends State<BankDashboardPage> {
  final BankService _bankService = BankService();

  // Dashboard State
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
      // Fetch data concurrently for speed
      final statsFuture = _bankService.fetchDashboardStats();
      final loansFuture = _bankService.fetchPendingLoans();

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
      backgroundColor: const Color(0xFFF5F7FA), // Light grey-blue background
      appBar: AppBar(
        title: const Text('Officer Dashboard'),
        backgroundColor: const Color(0xFFFF9933), // Saffron
        foregroundColor: Colors.white,
        centerTitle: true,
        elevation: 0,
      ),
      drawer: _buildModernDrawer(context),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const CreateBeneficiaryPage()),
          ).then((_) => _loadData()); // Refresh dashboard when returning
        },
        label: const Text("New Beneficiary"),
        icon: const Icon(Icons.person_add),
        backgroundColor: const Color(0xFF138808), // Green
        foregroundColor: Colors.white,
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            // Header Section with Gradient
            SliverToBoxAdapter(
              child: Container(
                decoration: const BoxDecoration(
                  color: Color(0xFFFF9933),
                  borderRadius: BorderRadius.only(
                    bottomLeft: Radius.circular(30),
                    bottomRight: Radius.circular(30),
                  ),
                ),
                padding: const EdgeInsets.fromLTRB(20, 0, 20, 40),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Welcome back, Rahul",
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      "Here is your daily verification summary.",
                      style: TextStyle(
                        color: Colors.white.withOpacity(0.9),
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            // Stats Cards (Overlapping the Header)
            SliverToBoxAdapter(
              child: Transform.translate(
                offset: const Offset(0, -20),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  child: _buildStatsSection(),
                ),
              ),
            ),

            // Section Title
            SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 10, 20, 10),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      "Pending Actions",
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF000080), // Navy
                      ),
                    ),
                    Text(
                      "${_loans.length} Items",
                      style: TextStyle(color: Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            ),

            // List of Loans
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: _loans.isEmpty
                  ? SliverToBoxAdapter(child: _buildEmptyState())
                  : SliverList(
                delegate: SliverChildBuilderDelegate(
                      (context, index) => _buildLoanCard(_loans[index]),
                  childCount: _loans.length,
                ),
              ),
            ),

            const SliverToBoxAdapter(child: SizedBox(height: 80)), // Bottom padding
          ],
        ),
      ),
    );
  }

  // --- DRAWER COMPONENT ---
  Widget _buildModernDrawer(BuildContext context) {
    return Drawer(
      child: Column(
        children: [
          UserAccountsDrawerHeader(
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                colors: [Color(0xFFFF9933), Color(0xFFFF6600)],
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
              ),
            ),
            accountName: const Text(
              "Rahul Kumar",
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            accountEmail: const Text("ID: OFF1001 | Branch: New Delhi"),
            currentAccountPicture: CircleAvatar(
              backgroundColor: Colors.white,
              child: Text(
                "RK",
                style: TextStyle(
                  fontSize: 24,
                  color: Theme.of(context).primaryColor,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: EdgeInsets.zero,
              children: [
                _buildDrawerItem(Icons.dashboard, "Dashboard", true, () => Navigator.pop(context)),
                _buildDrawerItem(Icons.person_add, "Create Beneficiary", false, () {
                  Navigator.pop(context); // Close drawer
                  Navigator.push(
                    context,
                    MaterialPageRoute(builder: (context) => const CreateBeneficiaryPage()),
                  ).then((_) => _loadData());
                }),
                _buildDrawerItem(Icons.history, "Verification History", false, () {}),
                _buildDrawerItem(Icons.analytics, "Reports", false, () {}),
                const Divider(),
                _buildDrawerItem(Icons.settings, "Settings", false, () {}),
                _buildDrawerItem(Icons.help_outline, "Help & Support", false, () {}),
              ],
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.logout, color: Colors.red),
            title: const Text(
              "Logout",
              style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold),
            ),
            onTap: () {
              Navigator.pushNamedAndRemoveUntil(context, '/', (route) => false);
            },
          ),
          const SizedBox(height: 20),
        ],
      ),
    );
  }

  Widget _buildDrawerItem(IconData icon, String title, bool isSelected, VoidCallback onTap) {
    return ListTile(
      leading: Icon(
        icon,
        color: isSelected ? const Color(0xFFFF9933) : Colors.grey[700],
      ),
      title: Text(
        title,
        style: TextStyle(
          color: isSelected ? const Color(0xFFFF9933) : Colors.black87,
          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      selected: isSelected,
      selectedTileColor: const Color(0xFFFF9933).withOpacity(0.1),
      onTap: onTap,
    );
  }

  // --- STATS SECTION ---
  Widget _buildStatsSection() {
    return Row(
      children: [
        _statCard('Pending', _stats['pending']!, Colors.orange, Icons.hourglass_empty),
        const SizedBox(width: 12),
        _statCard('Verified', _stats['verified']!, Colors.green, Icons.check_circle_outline),
        const SizedBox(width: 12),
        _statCard('Rejected', _stats['rejected']!, Colors.red, Icons.cancel_outlined),
      ],
    );
  }

  Widget _statCard(String title, int count, Color color, IconData icon) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withOpacity(0.05),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: color, size: 28),
            const SizedBox(height: 8),
            Text(
              count.toString(),
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.bold,
                color: Colors.black87,
              ),
            ),
            Text(
              title,
              style: TextStyle(color: Colors.grey[600], fontSize: 12),
            ),
          ],
        ),
      ),
    );
  }

  // --- LOAN LIST COMPONENTS ---
  Widget _buildEmptyState() {
    return Container(
      padding: const EdgeInsets.all(40),
      child: Column(
        children: [
          Icon(Icons.check_circle_outline, size: 80, color: Colors.grey[300]),
          const SizedBox(height: 16),
          Text(
            "All caught up!",
            style: TextStyle(
              fontSize: 18,
              color: Colors.grey[600],
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "No pending loans to review.",
            style: TextStyle(color: Colors.grey[500]),
          ),
        ],
      ),
    );
  }

  Widget _buildLoanCard(LoanApplication loan) {
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
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
              // Avatar
              CircleAvatar(
                radius: 24,
                backgroundColor: const Color(0xFFE0F2F1),
                child: Text(
                  loan.applicantName.isNotEmpty ? loan.applicantName[0] : "?",
                  style: const TextStyle(
                    color: Color(0xFF00695C),
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
              ),
              const SizedBox(width: 16),

              // Details
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      loan.applicantName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                        color: Colors.black87,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: Colors.blue[50],
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue[100]!),
                          ),
                          child: Text(
                            "ID: ${loan.loanId}",
                            style: TextStyle(fontSize: 10, color: Colors.blue[800], fontWeight: FontWeight.w600),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Text(
                          "•  ₹${loan.amount.toStringAsFixed(0)}",
                          style: const TextStyle(
                            color: Colors.black54,
                            fontSize: 12,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),

              // Arrow
              const Icon(Icons.chevron_right, color: Colors.grey),
            ],
          ),
        ),
      ),
    );
  }
}