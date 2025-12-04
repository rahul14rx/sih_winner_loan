// lib/pages/beneficiary_dashboard.dart
import 'dart:async';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:loan2/pages/login_page.dart';
import 'package:loan2/pages/alerts_page.dart';
import 'package:loan2/pages/verification_history_page.dart';
import 'package:loan2/pages/pending_verification_page.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/models/beneficiary_loan.dart';


import 'package:loan2/services/sync_service.dart';

import 'package:loan2/services/database_helper.dart';
import 'package:loan2/pages/loan_detail_screen.dart';

class _BannerItem {
  final String asset;
  final String url;
  final String title;
  const _BannerItem({required this.asset, required this.url, this.title = ""});
}

class _ServiceItem {
  final String label;
  final String asset;
  final String url;
  const _ServiceItem({required this.label, required this.asset, required this.url});
}

class BeneficiaryDashboard extends StatefulWidget {
  final String userId;
  const BeneficiaryDashboard({super.key, required this.userId});
  @override
  State<BeneficiaryDashboard> createState() => _BeneficiaryDashboardState();
}

class _BeneficiaryDashboardState extends State<BeneficiaryDashboard> {
  final BeneficiaryService _service = BeneficiaryService();

  int _selectedIndex = 0;
  bool isOnline = false;
  int unsyncedCount = 0;

  List<BeneficiaryLoan> _loans = [];
  bool _isLoading = true;

  StreamSubscription? _syncSub;
  StreamSubscription? _onlineSub;

  late PageController _bannerController;
  Timer? _bannerTimer;
  int _bannerIndex = 0;

  final List<_BannerItem> _banners = const [
    _BannerItem(asset: 'assets/b_banners/banner1.png', url: 'https://nbcfdc.gov.in/', title: 'NSKFDC'),
    _BannerItem(asset: 'assets/b_banners/banner2.png', url: 'https://nskfdc.nic.in/', title: 'NSFDC'),
    _BannerItem(asset: 'assets/b_banners/banner3.png', url: 'https://nsfdc.nic.in/en/schemes/', title: 'NBCFDC'),
    _BannerItem(asset: 'assets/b_banners/banner4.png', url: 'https://www.desw.gov.in/prime-ministers-scholarship-scheme-pmss/', title: 'PMSSS'),
    _BannerItem(asset: 'assets/b_banners/banner5.png', url: 'https://pmajay.dosje.gov.in/', title: 'PM-AJAY'),
  ];

  final List<_ServiceItem> _services = const [
    _ServiceItem(label: 'NSKFDC', asset: 'assets/services/nskfdc.png', url: 'https://nskfdc.nic.in/en/node/add/loan-application/'),
    _ServiceItem(label: 'NSFDC', asset: 'assets/services/nsfdc.png', url: 'https://nsfdc.nic.in/en/form/'),
    _ServiceItem(label: 'NBCFDC', asset: 'assets/services/nbcfdc.png', url: 'https://nbcfdc.gov.in/'),
    _ServiceItem(label: 'PMSSS', asset: 'assets/services/pmsss.png', url: 'https://www.desw.gov.in/prime-ministers-scholarship-scheme-pmss'),
    _ServiceItem(label: 'PM-AJAY', asset: 'assets/services/pmajay.png', url: 'https://socialjustice.gov.in/'),
  ];

  bool _isPending(String? s) {
    final t = (s ?? '').toLowerCase().replaceAll(' ', '_');
    return t.isEmpty ||
        t == 'pending' ||
        t == 'not_verified' ||
        t == 'in_review' ||
        t == 'pending_review' ||
        t == 'in_progress' ||
        t == 'submitted';
  }

  List<BeneficiaryLoan> _onlyPending(List<BeneficiaryLoan> loans) {
    return loans.where((loan) => loan.processes.any((st) => _isPending(st.status))).toList();
  }

  @override
  void initState() {
    super.initState();
    _bannerController = PageController(viewportFraction: 0.92);

    _initDashboard();
    _startBannerAutoSlide();

    _syncSub = SyncService.onSync.listen((_) {
      _loadLoans();
      _updateUnsyncedCount();
    });

    _onlineSub = SyncService.onOnlineStatusChanged.listen((online) async {
      if (!mounted) return;
      setState(() => isOnline = online);
      if (online) {
        await _loadLoans();
        await _updateUnsyncedCount();
      }
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _bannerController.dispose();
    _syncSub?.cancel();
    _onlineSub?.cancel();
    super.dispose();
  }

  Future<void> _initDashboard() async {
    isOnline = await SyncService.realInternetCheck();
    await _updateUnsyncedCount();
    await _loadLoans();
  }

  Future<void> _updateUnsyncedCount() async {
    final c = await DatabaseHelper.instance.getQueuedForUploadCount();
    if (mounted) setState(() => unsyncedCount = c);
  }

  Future<void> _loadLoans() async {
    try {
      final data = await _service.fetchUserLoans(widget.userId);
      final filtered = data.where((l) => (l.userId ?? "") == widget.userId).toList();
      if (mounted) {
        setState(() {
          _loans = filtered;
          _isLoading = false;
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  void _startBannerAutoSlide() {
    _bannerTimer?.cancel();
    _bannerTimer = Timer.periodic(const Duration(seconds: 4), (_) {
      if (_bannerController.hasClients && mounted) {
        final next = (_bannerIndex + 1) % _banners.length;
        _bannerController.animateToPage(
          next,
          duration: const Duration(milliseconds: 650),
          curve: Curves.easeInOut,
        );
      }
    });
  }

  Future<void> _openUrl(String url) async {
    try {
      await launchUrl(Uri.parse(url), mode: LaunchMode.externalApplication);
    } catch (_) {}
  }

  void _selectTab(int index) => setState(() => _selectedIndex = index);

  @override
  Widget build(BuildContext context) {
    final pendingLoans = _onlyPending(_loans);

    return WillPopScope(
      // Block system back on Dashboard so it never reveals Login underneath
      onWillPop: () async => false,
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F9FC),
        bottomNavigationBar: _buildBottomNav(),
        body: IndexedStack(
          index: _selectedIndex,
          children: [
            _homeTab(),
            PendingVerificationPage(userId: widget.userId, loans: pendingLoans),
            VerificationHistoryPage(userId: widget.userId),
            AlertsPage(userId: widget.userId),
            _helpTab(),
          ],
        ),
      ),
    );
  }

  Widget _homeTab() {
    return Column(
      children: [
        _header(),
        Expanded(child: _homeBody()),
      ],
    );
  }

  Widget _helpTab() {
    return Scaffold(
      appBar: AppBar(title: const Text("Help & Support")),
      body: const Center(child: Text("Help content here")),
    );
  }

  Widget _header() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 16,
        left: 16,
        right: 16,
        bottom: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F6FEB), Color(0xFF2757D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(26)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              const CircleAvatar(
                radius: 20,
                backgroundColor: Colors.white24,
                child: Icon(Icons.account_balance_wallet, color: Colors.white),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  "Nyay Sahayak",
                  style: GoogleFonts.inter(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.w700,
                  ),
                ),
              ),
              const Icon(Icons.notifications_none, color: Colors.white),
              const SizedBox(width: 12),
              PopupMenuButton<String>(
                onSelected: (v) {
                  if (v == 'profile') {
                    showDialog(
                      context: context,
                      builder: (_) => AlertDialog(
                        title: const Text("Profile"),
                        content: Text("User ID: ${widget.userId}"),
                        actions: [
                          TextButton(
                            onPressed: () => Navigator.pop(context),
                            child: const Text("Close"),
                          )
                        ],
                      ),
                    );
                  } else if (v == 'logout') {
                    Navigator.pushAndRemoveUntil(
                      context,
                      MaterialPageRoute(builder: (_) => const LoginPage()),
                          (route) => false,
                    );
                  }

                },
                color: Colors.white,
                offset: const Offset(0, 48),
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                itemBuilder: (context) => const [
                  PopupMenuItem(
                    value: 'profile',
                    child: ListTile(leading: Icon(Icons.person), title: Text('Profile')),
                  ),
                  PopupMenuItem(
                    value: 'logout',
                    child: ListTile(leading: Icon(Icons.logout), title: Text('Logout')),
                  ),
                ],
                child: const CircleAvatar(
                  radius: 18,
                  backgroundImage: NetworkImage(
                    "https://www.gravatar.com/avatar/placeholder?s=200&d=robohash",
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 14),
          Container(
            height: 54,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18)),
            child: Row(
              children: const [
                Icon(Icons.search, color: Color(0xFF6B7C9A)),
                SizedBox(width: 8),
                Expanded(child: Text("Search for loan corporations & schemes")),
                Icon(Icons.mic_none, color: Color(0xFF6B7C9A)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _homeBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator());
    }

    return SingleChildScrollView(
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _categoryRow(),
          const SizedBox(height: 20),
          _bannerCarousel(),
          const SizedBox(height: 20),
          _serviceSection(),
          const SizedBox(height: 20),
          _requestsHeader(),
          const SizedBox(height: 12),
          if (_loans.isEmpty) _emptyCard() else ..._loans.map(_loanCard),
          const SizedBox(height: 40),
        ],
      ),
    );
  }

  Widget _categoryRow() {
    return Row(
      children: [
        Expanded(child: _categoryTile(icon: Icons.verified_user_outlined, label: "Requests", onTap: () => _selectTab(1))),
        const SizedBox(width: 12),
        Expanded(child: _categoryTile(icon: Icons.history, label: "History", onTap: () => _selectTab(2))),
        const SizedBox(width: 12),
        Expanded(child: _categoryTile(icon: Icons.notifications_none, label: "Alerts", onTap: () => _selectTab(3))),
      ],
    );
  }

  Widget _categoryTile({required IconData icon, required String label, required VoidCallback onTap}) {
    return InkWell(
      onTap: onTap,
      child: Container(
        height: 100,
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(16)),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(icon, color: const Color(0xFF1F6FEB), size: 32),
            const SizedBox(height: 8),
            Text(label, style: GoogleFonts.inter(fontSize: 13)),
          ],
        ),
      ),
    );
  }

  Widget _bannerCarousel() {
    return SizedBox(
      height: 170,
      child: PageView.builder(
        controller: _bannerController,
        itemCount: _banners.length,
        onPageChanged: (i) => setState(() => _bannerIndex = i),
        itemBuilder: (_, i) {
          final b = _banners[i];
          final active = i == _bannerIndex;
          return AnimatedPadding(
            duration: const Duration(milliseconds: 300),
            padding: EdgeInsets.symmetric(horizontal: active ? 4 : 12),
            child: GestureDetector(
              onTap: () => _openUrl(b.url),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(20),
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    Image.asset(b.asset, fit: BoxFit.cover),
                    Container(color: Colors.black26),
                    Positioned(
                      left: 16,
                      bottom: 16,
                      child: Text(
                        b.title,
                        style: GoogleFonts.inter(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _serviceSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text("More Loan Corporations and Schemes", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
        const SizedBox(height: 14),
        SizedBox(
          height: 100,
          child: ListView.separated(
            scrollDirection: Axis.horizontal,
            itemCount: _services.length,
            separatorBuilder: (_, __) => const SizedBox(width: 12),
            itemBuilder: (_, i) {
              final s = _services[i];
              return InkWell(
                onTap: () => _openUrl(s.url),
                child: Container(
                  width: 78,
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
                  child: Column(
                    children: [
                      Image.asset(s.asset, height: 38),
                      const SizedBox(height: 6),
                      Text(s.label, textAlign: TextAlign.center, maxLines: 2, style: GoogleFonts.inter(fontSize: 11)),
                    ],
                  ),
                ),
              );
            },
          ),
        ),
      ],
    );
  }

  Widget _requestsHeader() {
    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Text("My Requests", style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 18)),
        TextButton(onPressed: () => _selectTab(1), child: const Text("View all")),
      ],
    );
  }

  Widget _emptyCard() {
    return Container(
      height: 140,
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14)),
      child: const Center(child: Text("No active loans found")),
    );
  }

  Widget _loanCard(BeneficiaryLoan loan) {
    final total = loan.processes.length;
    final done = loan.processes.where((e) => e.status == "verified").length;
    final percent = total == 0 ? 0 : ((done / total) * 100).toInt();

    Color col = Colors.orange;
    String status = "Pending";
    if (percent == 100) {
      col = Colors.green;
      status = "Verified";
    } else if (percent > 0) {
      col = Colors.blue;
      status = "In Progress";
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () {
          Navigator.push(context, MaterialPageRoute(builder: (_) => LoanDetailScreen(loan: loan)));
        },
        child: Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(20)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const CircleAvatar(
                    radius: 22,
                    backgroundColor: Color(0xFFEFF6FF),
                    child: Icon(Icons.inventory_2_outlined, color: Color(0xFF1F6FEB)),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text("Loan #${loan.loanId}", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                        Text("Beneficiary: ${loan.userId}", style: GoogleFonts.inter(fontSize: 13)),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(color: col.withOpacity(0.12), borderRadius: BorderRadius.circular(12)),
                    child: Text(
                      status,
                      style: GoogleFonts.inter(color: col, fontWeight: FontWeight.w700),
                    ),
                  )
                ],
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Verification Progress", style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                  Text("$percent%", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                ],
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: LinearProgressIndicator(
                  value: percent / 100,
                  minHeight: 8,
                  backgroundColor: Colors.grey[300],
                  valueColor: AlwaysStoppedAnimation(col),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    final items = [
      {'icon': Icons.home_outlined, 'label': 'Home'},
      {'icon': Icons.pending_actions_outlined, 'label': 'Pending'},
      {'icon': Icons.history_rounded, 'label': 'History'},
      {'icon': Icons.notifications_none, 'label': 'Alerts'},
      {'icon': Icons.help_outline, 'label': 'Help'},
    ];

    return Padding(
      padding: const EdgeInsets.all(12),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(26),
          boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 20)],
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: List.generate(items.length, (i) {
            final active = i == _selectedIndex;
            return GestureDetector(
              onTap: () => _selectTab(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: active ? const Color(0xFFEBF4FF) : Colors.transparent,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedContainer(
                      duration: const Duration(milliseconds: 250),
                      height: active ? 42 : 36,
                      width: active ? 42 : 36,
                      decoration: BoxDecoration(
                        color: active ? const Color(0xFF1F6FEB) : Colors.transparent,
                        borderRadius: BorderRadius.circular(10),
                        boxShadow: active
                            ? [
                          BoxShadow(
                            color: const Color(0xFF1F6FEB).withOpacity(0.25),
                            blurRadius: 8,
                            offset: const Offset(0, 3),
                          )
                        ]
                            : [],
                      ),
                      child: Icon(items[i]['icon'] as IconData, color: active ? Colors.white : Colors.grey[700]),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      items[i]['label'] as String,
                      style: GoogleFonts.inter(fontSize: 11, color: active ? const Color(0xFF1F6FEB) : Colors.grey[600]),
                    ),
                  ],
                ),
              ),
            );
          }),
        ),
      ),
    );
  }
}