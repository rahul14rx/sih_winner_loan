import 'dart:async';
import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart'; // Added for phone call
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/loan_detail_screen.dart';
import 'package:loan2/widgets/beneficiary_drawer.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:loan2/services/database_helper.dart';

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

  // Added State Variables
  bool isOnline = false;
  int unsyncedCount = 0;
  StreamSubscription? _syncSubscription;
  StreamSubscription? _onlineStatusSubscription;

  @override
  void initState() {
    super.initState();
    _initPage();

    // Listen for background syncs to refresh UI (e.g., after an upload completes)
    _syncSubscription = SyncService.onSync.listen((_) {
      debugPrint("🔄 UI Refresh triggered by post-sync event");
      _loadData();
      _updateUnsyncedCount();
    });

    // Listen for connectivity changes to refresh UI
    _onlineStatusSubscription = SyncService.onOnlineStatusChanged.listen((online) {
      if (online != isOnline) {
        setState(() {
          isOnline = online;
        });

        // If the app just came online, refresh the data.
        if (online) {
          debugPrint("🚀 UI Refresh triggered by coming online");
          _loadData();
          _updateUnsyncedCount();
        }
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _onlineStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initPage() async {
    // Initial check
    isOnline = await SyncService.realInternetCheck();
    await _updateUnsyncedCount();
    await _loadData();
  }

  Future<void> _updateUnsyncedCount() async {
    final count = await DatabaseHelper.instance.getQueuedForUploadCount();
    if (mounted) {
      setState(() {
        unsyncedCount = count;
      });
    }
  }

  Future<void> _loadData() async {
    try {
      final data = await _service.fetchUserLoans(widget.userId);
      if (mounted) setState(() { _loans = data; _isLoading = false; });
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
        // Optionally show a "showing cached data" snackbar here
      }
    }
  }

  // Function to make a phone call
  Future<void> _makePhoneCall() async {
    final Uri launchUri = Uri(
      scheme: 'tel',
      path: '9150462438',
    );
    try {
      if (await canLaunchUrl(launchUri)) {
        await launchUrl(launchUri);
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text("Could not launch dialer")),
          );
        }
      }
    } catch (e) {
      debugPrint("Error launching call: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'My Requests',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold, fontSize: 18),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: false,
        automaticallyImplyLeading: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          // 1. Unsynced Count Indicator
          if (unsyncedCount > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 4, vertical: 12),
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
              decoration: BoxDecoration(
                  color: Colors.orange[50],
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange[200]!)
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync_problem, color: Colors.orange, size: 16),
                  const SizedBox(width: 4),
                  Text(
                    "$unsyncedCount Pending",
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold, fontSize: 12),
                  ),
                ],
              ),
            ),

          // 2. Online/Offline Indicator
          Container(
            margin: const EdgeInsets.only(right: 16, left: 8, top: 12, bottom: 12),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 2),
            decoration: BoxDecoration(
                color: isOnline ? Colors.green[50] : Colors.red[50],
                borderRadius: BorderRadius.circular(20),
                border: Border.all(color: isOnline ? Colors.green[200]! : Colors.red[200]!)
            ),
            child: Row(
              children: [
                Icon(
                    isOnline ? Icons.wifi : Icons.wifi_off,
                    color: isOnline ? Colors.green : Colors.red,
                    size: 16
                ),
                const SizedBox(width: 6),
                Text(
                  isOnline ? "Online" : "Offline",
                  style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      color: isOnline ? Colors.green[800] : Colors.red[800]
                  ),
                ),
              ],
            ),
          ),
        ],
      ),

      drawer: BeneficiaryDrawer(userId: widget.userId),

      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
        onRefresh: _loadData,
        child: _loans.isEmpty
            ? _buildEmptyState()
            : ListView.separated(
          padding: const EdgeInsets.all(20),
          itemCount: _loans.length,
          separatorBuilder: (_, __) => const SizedBox(height: 16),
          itemBuilder: (context, index) => _buildLoanCard(_loans[index]),
        ),
      ),
      
      // Add Call Button (Floating Action Button)
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _makePhoneCall,
        backgroundColor: const Color(0xFF138808),
        icon: const Icon(Icons.call, color: Colors.white),
        label: const Text("Call Support", style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
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
          const SizedBox(height: 8),
          Text("User ID: ${widget.userId}", style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

  Widget _buildLoanCard(BeneficiaryLoan loan) {
    int totalSteps = loan.processes.length;
    int completedSteps = loan.processes.where((p) => p.status == 'verified').length;
    double progress = totalSteps > 0 ? completedSteps / totalSteps : 0.0;
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
            builder: (_) => LoanDetailScreen(loan: loan),
          ),
        ).then((_) {
          // Refresh data when returning from details page
          _loadData();
          _updateUnsyncedCount();
        });
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
              "Beneficiary: ${loan.userId}",
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
