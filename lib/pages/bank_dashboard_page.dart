import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan2/services/bank_service.dart';
import 'package:loan2/models/loan_application.dart';
import 'package:loan2/pages/loan_detail_page.dart';
import 'package:loan2/pages/create_beneficiary_page.dart';
import 'package:loan2/pages/help_support_page.dart';
import 'package:loan2/pages/history_page.dart';
import 'package:loan2/pages/reports_page.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:loan2/pages/profile_settings_page.dart';
import 'dart:async';
import 'package:loan2/widgets/officer_nav_bar.dart';
import 'package:loan2/services/app_theme.dart';
import 'package:loan2/pages/login_page.dart';
import 'package:loan2/services/theme_ext.dart';

enum _UserMenu { profile, settings, logout }

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

  String _reviewQuery = '';
  String _officerName = '';

  final ScrollController _scroll = ScrollController();
  final GlobalKey _pendingKey = GlobalKey();

  final PageController _pageController = PageController(viewportFraction: 0.92);
  int _bannerIndex = 0;
  Timer? _bannerTimer;

  final List<_BannerItem> _banners = const [
    _BannerItem(asset: 'assets/banners/banner1.png', url: 'https://www.india.gov.in/'),
    _BannerItem(asset: 'assets/banners/banner2.png', url: 'https://www.myscheme.gov.in/'),
    _BannerItem(asset: 'assets/banners/banner3.png', url: 'https://www.pmindia.gov.in/'),
    _BannerItem(asset: 'assets/banners/banner4.jpg', url: 'https://www.digitalindia.gov.in/'),
    _BannerItem(asset: 'assets/banners/banner5.jpg', url: 'https://www.uidai.gov.in/'),
    _BannerItem(asset: 'assets/banners/banner6.jpg', url: 'https://www.uidai.gov.in/'),
  ];

  final List<_ServiceItem> _services = const [
    _ServiceItem(label: 'NSKFDC', asset: 'assets/services/nskfdc.png', url: 'https://nskfdc.nic.in/'),
    _ServiceItem(label: 'NSFDC', asset: 'assets/services/nsfdc.png', url: 'https://nsfdc.nic.in/'),
    _ServiceItem(label: 'NBCFDC', asset: 'assets/services/nbcfdc.png', url: 'https://nbcfdc.gov.in/'),
    _ServiceItem(label: 'PMSSS', asset: 'assets/services/pmsss.png', url: 'https://www.aicte-india.org/'),
    _ServiceItem(label: 'PM-AJAY', asset: 'assets/services/pmajay.png', url: 'https://socialjustice.gov.in/'),
  ];

  @override
  void initState() {
    super.initState();

    _loadData();
    _loadOfficerName();

    _pageController.addListener(() {
      final p = _pageController.page;
      if (p == null) return;
      final i = p.round();
      if (i != _bannerIndex && mounted) setState(() => _bannerIndex = i);
    });

    _bannerTimer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (!mounted || !_pageController.hasClients || _banners.isEmpty) return;
      final next = (_bannerIndex + 1) % _banners.length;
      _pageController.animateToPage(
        next,
        duration: const Duration(milliseconds: 450),
        curve: Curves.easeInOut,
      );
    });
  }

  @override
  void dispose() {
    _bannerTimer?.cancel();
    _pageController.dispose();
    _scroll.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final statsFuture = _bankService.fetchDashboardStats(widget.officerId);
      final loansFuture = _bankService.fetchPendingLoans(widget.officerId);
      final results = await Future.wait([statsFuture, loansFuture]);

      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, int>;
        _loans = results[1] as List<LoanApplication>;
        _isLoading = false;
      });
    } catch (e) {
      debugPrint("Dashboard Load Error: $e");
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadOfficerName() async {
    try {
      final raw = await _bankService.fetchOfficerProfile(widget.officerId);
      final m = _unwrapProfile(raw);

      final name = _pickStr(m, ["name", "officer_name", "full_name"], "");
      if (!mounted) return;
      setState(() => _officerName = name);
    } catch (_) {
      if (!mounted) return;
      setState(() => _officerName = "");
    }
  }

  Map<String, dynamic> _unwrapProfile(Map<String, dynamic> m) {
    final d = m['data'];
    if (d is Map) return Map<String, dynamic>.from(d as Map);
    return m;
  }

  String _pickStr(Map<String, dynamic> m, List<String> keys, String fallback) {
    for (final k in keys) {
      final v = m[k];
      if (v != null && v.toString().trim().isNotEmpty) return v.toString().trim();
    }
    return fallback;
  }

  static const double _reviewsCardH = 225.0;

  Future<void> _openUrl(String url) async {
    final u = Uri.parse(url);
    final ok = await launchUrl(u, mode: LaunchMode.externalApplication);
    if (!ok && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Couldn't open link", style: GoogleFonts.inter())),
      );
    }
  }

  List<LoanApplication> get _filteredPending {
    final q = _reviewQuery.trim().toLowerCase();
    if (q.isEmpty) return _loans;
    return _loans.where((x) {
      final a = x.applicantName.toLowerCase();
      final id = x.loanId.toLowerCase();
      return a.contains(q) || id.contains(q);
    }).toList();
  }

  void _scrollToPending() {
    final ctx = _pendingKey.currentContext;
    if (ctx == null) return;
    Scrollable.ensureVisible(
      ctx,
      duration: const Duration(milliseconds: 520),
      curve: Curves.easeInOut,
      alignment: 0.05,
    );
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    const blue = Color(0xFF1E5AA8);

    // theme helpers
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Theme.of(context).cardColor;
    final border = context.appBorder;
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final subColor = isDark ? const Color(0xFFCBD5E1) : Colors.grey[600]!;

    final pendingItems = _filteredPending;

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : RefreshIndicator(
          onRefresh: _loadData,
          child: LayoutBuilder(
            builder: (context, c) {
              final w = c.maxWidth;
              final pad = w >= 900 ? 28.0 : (w >= 600 ? 20.0 : 16.0);

              return CustomScrollView(
                controller: _scroll,
                physics: const AlwaysScrollableScrollPhysics(
                    parent: BouncingScrollPhysics()),
                slivers: [
                  SliverToBoxAdapter(
                    child: _buildTopHeaderAndReviews(blue, pad, w),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                      child: _buildBannerSlider(),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 18, pad, 10),
                      child: Text(
                        "Recently Used Services",
                        style: GoogleFonts.poppins(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: titleColor,
                        ),
                      ),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                      child: _buildServicesSlider(w),
                    ),
                  ),
                  SliverToBoxAdapter(
                    child: Padding(
                      key: _pendingKey,
                      padding: EdgeInsets.fromLTRB(pad, 18, pad, 10),
                      child: Row(
                        children: [
                          Text(
                            "Pending Reviews",
                            style: GoogleFonts.poppins(
                              fontSize: 16,
                              fontWeight: FontWeight.w700,
                              color: titleColor,
                            ),
                          ),
                          const Spacer(),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                              color: blue.withOpacity(0.10),
                              borderRadius: BorderRadius.circular(999),
                              border:
                              Border.all(color: blue.withOpacity(0.18)),
                            ),
                            child: Text(
                              "${pendingItems.length}",
                              style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900, color: blue),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  if (pendingItems.isEmpty)
                    SliverToBoxAdapter(
                      child: Padding(
                        padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                        child: _buildEmptyStateCompact(),
                      ),
                    )
                  else
                    SliverList(
                      delegate: SliverChildBuilderDelegate(
                            (context, i) => Padding(
                          padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                          child: _buildProLoanCard(pendingItems[i]),
                        ),
                        childCount: pendingItems.length,
                      ),
                    ),
                  const SliverToBoxAdapter(child: SizedBox(height: 110)),
                ],
              );
            },
          ),
        ),
      ),
      bottomNavigationBar:
      OfficerNavBar(currentIndex: 0, officerId: widget.officerId),
    );
  }

  Widget _buildTopHeaderAndReviews(Color blue, double pad, double w) {
    final headerH = w >= 600 ? 170.0 : 160.0;
    final overlap = 30.0;
    final bottomGap = w >= 600 ? 18.0 : 16.0;
    final totalH = headerH + _reviewsCardH - overlap + bottomGap;

    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Theme.of(context).cardColor;

    return SizedBox(
      height: totalH,
      child: Stack(
        children: [
          Container(
            height: headerH,
            decoration: const BoxDecoration(
              color: Color(0xFF1E5AA8),
              borderRadius: BorderRadius.only(
                bottomLeft: Radius.circular(28),
                bottomRight: Radius.circular(28),
              ),
            ),
          ),
          Positioned(
            left: pad,
            right: pad,
            top: 14,
            child: Row(
              children: [
                Row(
                  children: [
                    Container(
                      width: 42,
                      height: 42,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.14),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Center(
                        child: Image.asset(
                          'assets/logo.png',
                          width: 22,
                          height: 22,
                          errorBuilder: (_, __, ___) => const Icon(
                              Icons.gavel_rounded, color: Colors.white),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Text(
                      "Nyay Sahayak",
                      style: GoogleFonts.poppins(
                        color: Colors.white,
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ],
                ),
                const Spacer(),
                Container(
                  width: 42,
                  height: 42,
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.14),
                    shape: BoxShape.circle,
                  ),
                  child: IconButton(
                    onPressed: () {},
                    icon: const Icon(Icons.notifications_none_rounded,
                        color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                PopupMenuButton<_UserMenu>(
                  offset: const Offset(0, 44),
                  elevation: 10,
                  shape:
                  RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) {
                    switch (value) {
                      case _UserMenu.profile:
                      case _UserMenu.settings:
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) =>
                                  ProfileSettingsPage(officerId: widget.officerId)),
                        );
                        break;
                      case _UserMenu.logout:
                        Navigator.of(context).pushAndRemoveUntil(
                          MaterialPageRoute(builder: (_) => const LoginPage()),
                              (route) => false,
                        );
                        break;
                    }
                  },
                  itemBuilder: (context) => [
                    PopupMenuItem(
                      value: _UserMenu.profile,
                      child: Row(
                        children: const [
                          Icon(Icons.person_outline_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Profile'),
                        ],
                      ),
                    ),
                    PopupMenuItem(
                      enabled: false,
                      child: StatefulBuilder(
                        builder: (context, setSt) {
                          return Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Row(children: const [
                                Icon(Icons.dark_mode_outlined, size: 20),
                                SizedBox(width: 10),
                                Text('Dark mode'),
                              ]),
                              Switch(
                                value: AppTheme.isDark,
                                onChanged: (v) {
                                  AppTheme.toggle(v);
                                  setSt(() {});
                                },
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    PopupMenuItem(
                      value: _UserMenu.settings,
                      child: Row(
                        children: const [
                          Icon(Icons.settings_outlined, size: 20),
                          SizedBox(width: 10),
                          Text('Settings'),
                        ],
                      ),
                    ),
                    const PopupMenuDivider(),
                    PopupMenuItem(
                      value: _UserMenu.logout,
                      child: Row(
                        children: const [
                          Icon(Icons.logout_rounded, size: 20),
                          SizedBox(width: 10),
                          Text('Logout'),
                        ],
                      ),
                    ),
                  ],
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.14),
                      shape: BoxShape.circle,
                    ),
                    child: CircleAvatar(
                      radius: 18,
                      backgroundColor: Colors.white,
                      child: Text(
                        widget.officerId.isNotEmpty
                            ? widget.officerId.substring(0, 2).toUpperCase()
                            : "OF",
                        style: GoogleFonts.poppins(
                            fontWeight: FontWeight.w800, color: blue),
                      ),
                    ),
                  ),
                )
              ],
            ),
          ),
          Positioned(
            left: pad,
            right: pad,
            top: 74,
            child: Container(
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(18),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.10),
                    blurRadius: 18,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: TextField(
                onChanged: (v) => setState(() => _reviewQuery = v),
                style: GoogleFonts.inter(
                    fontWeight: FontWeight.w700,
                    color: isDark ? Colors.white : const Color(0xFF111827)),
                decoration: InputDecoration(
                  hintText: "Search reviews",
                  hintStyle: GoogleFonts.inter(
                    color: isDark ? const Color(0xFF9CA3AF) : Colors.grey[500],
                    fontWeight: FontWeight.w700,
                  ),
                  border: InputBorder.none,
                  contentPadding:
                  const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefixIcon: Icon(Icons.search_rounded,
                      color:
                      isDark ? const Color(0xFF9CA3AF) : Colors.grey[500]),
                ),
              ),
            ),
          ),
          Positioned(
            left: pad,
            right: pad,
            top: headerH - overlap,
            child: _buildReviewsCardLikePhoto(),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsCardLikePhoto() {
    const blue = Color(0xFF1E5AA8);
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Theme.of(context).cardColor;
    final border = context.appBorder;
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final muted = isDark ? Colors.white70 : Colors.grey[700];

    final displayName =
    _officerName.trim().isNotEmpty ? _officerName.trim() : widget.officerId;

    return Container(
      height: _reviewsCardH,
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: border),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.08),
            blurRadius: 18,
            offset: const Offset(0, 10),
          ),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "Your Reviews",
              style: GoogleFonts.poppins(
                fontSize: 14,
                fontWeight: FontWeight.w700,
                color: titleColor,
              ),
            ),
            const SizedBox(height: 8),
            RichText(
              text: TextSpan(
                style: GoogleFonts.poppins(color: titleColor),
                children: [
                  TextSpan(
                    text: "Good afternoon, ",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: muted,
                    ),
                  ),
                  TextSpan(
                    text: displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 20,
                      fontWeight: FontWeight.w800,
                      color: titleColor,
                    ),
                  ),
                ],
              ),
            ),
            const Spacer(),
            _buildStatCardsRowLikePhoto(blue),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCardsRowLikePhoto(Color blue) {
    return Padding(
      padding: const EdgeInsets.only(top: 10),
      child: Row(
        children: [
          _photoStatCard(
            title: "Pending",
            count: _stats['pending'] ?? 0,
            icon: Icons.hourglass_top_rounded,
            iconBg: const Color(0xFFFFF3E0),
            iconColor: const Color(0xFFFF8A00),
            onTap: _scrollToPending,
          ),
          const SizedBox(width: 12),
          _photoStatCard(
            title: "Verified",
            count: _stats['verified'] ?? 0,
            icon: Icons.verified_rounded,
            iconBg: const Color(0xFFE8F5E9),
            iconColor: const Color(0xFF16A34A),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => HistoryPage(officerId: widget.officerId)),
              );
            },
          ),
          const SizedBox(width: 12),
          _photoStatCard(
            title: "Rejected",
            count: _stats['rejected'] ?? 0,
            icon: Icons.cancel_rounded,
            iconBg: const Color(0xFFFFEBEE),
            iconColor: const Color(0xFFDC2626),
            onTap: () {
              Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => HistoryPage(officerId: widget.officerId)),
              );
            },
          ),
        ],
      ),
    );
  }

  Widget _photoStatCard({
    required String title,
    required int count,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required VoidCallback onTap,
    Color? cardBg,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = isDark ? const Color(0xFF12233D) : (cardBg ?? Colors.white);
    final border = context.appBorder;
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final subColor = isDark ? const Color(0xFFCBD5E1) : Colors.grey[600]!;

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 106,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 14,
                offset: const Offset(0, 8),
              ),
            ],
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(height: 10),
              Text(
                "$count",
                style: GoogleFonts.poppins(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: titleColor,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: subColor,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBannerSlider() {
    return Column(
      children: [
        LayoutBuilder(
          builder: (context, c) {
            const bannerAspect = 1800 / 500;
            final viewportW = c.maxWidth;
            final pageW = viewportW * 0.92;
            final h = (pageW / bannerAspect).clamp(165.0, 230.0).toDouble();

            return SizedBox(
              height: h,
              child: PageView.builder(
                controller: _pageController,
                itemCount: _banners.length,
                itemBuilder: (context, i) {
                  final b = _banners[i];
                  return GestureDetector(
                    onTap: () => _openUrl(b.url),
                    child: Container(
                      margin: const EdgeInsets.symmetric(horizontal: 6),
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.10),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      clipBehavior: Clip.antiAlias,
                      child: Image.asset(
                        b.asset,
                        fit: BoxFit.cover,
                        errorBuilder: (_, __, ___) => Container(
                          color: const Color(0xFF0F172A),
                          child: Center(
                            child: Text(
                              "Banner ${i + 1}",
                              style: GoogleFonts.poppins(
                                  color: Colors.white,
                                  fontWeight: FontWeight.w700),
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 10),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: List.generate(_banners.length, (i) {
            final active = i == _bannerIndex;
            return AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              margin: const EdgeInsets.symmetric(horizontal: 4),
              height: 7,
              width: active ? 18 : 7,
              decoration: BoxDecoration(
                color: active ? const Color(0xFF1E5AA8) : const Color(0xFFD1D5DB),
                borderRadius: BorderRadius.circular(999),
              ),
            );
          }),
        ),
      ],
    );
  }

  Widget _buildServicesSlider(double w) {
    final tileW = w >= 900 ? 100.0 : (w >= 600 ? 94.0 : 84.0);

    final card = Theme.of(context).cardColor;
    final border = context.appBorder;
    final titleColor =
    Theme.of(context).brightness == Brightness.dark ? Colors.white : const Color(0xFF111827);

    return SizedBox(
      height: 88,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: _services.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, i) {
          final s = _services[i];
          return InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => _openUrl(s.url),
            child: Container(
              width: tileW,
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: border),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.06),
                    blurRadius: 14,
                    offset: const Offset(0, 8),
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(10, 10, 10, 8),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Image.asset(
                      s.asset,
                      height: 32,
                      fit: BoxFit.contain,
                      errorBuilder: (_, __, ___) => Icon(
                        Icons.account_balance_rounded,
                        color: Colors.grey[500],
                        size: 32,
                      ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      s.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textAlign: TextAlign.center,
                      style: GoogleFonts.inter(
                        fontSize: 11,
                        fontWeight: FontWeight.w800,
                        color: titleColor,
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

  Widget _buildProLoanCard(LoanApplication loan) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF12233D) : Colors.white;
    final border = context.appBorder;
    final titleColor = isDark ? Colors.white : const Color(0xFF1A1A1A);
    final subColor = isDark ? const Color(0xFFCBD5E1) : Colors.grey[600]!;

    final chipBg = const Color(0xFF1E5AA8).withOpacity(isDark ? 0.25 : 0.10);
    final chipText = isDark ? Colors.white : const Color(0xFF1E5AA8);

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.03),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
        border: Border.all(color: border),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                  builder: (_) => LoanDetailPage(loanId: loan.loanId)),
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
                    color: const Color(0xFF0F1B2D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Center(
                    child: Text(
                      loan.applicantName.isNotEmpty ? loan.applicantName[0] : "?",
                      style: GoogleFonts.poppins(
                        color: const Color(0xFF60A5FA),
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
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: chipBg,
                              borderRadius: BorderRadius.circular(6),
                            ),
                            child: Text(
                              "ID: ${loan.loanId}",
                              style: GoogleFonts.inter(
                                fontSize: 11,
                                color: chipText,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            "• ₹${loan.amount.toStringAsFixed(0)}",
                            style: GoogleFonts.inter(
                              color: subColor,
                              fontSize: 13,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded,
                    size: 16, color: subColor.withOpacity(0.4)),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyStateCompact() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = Theme.of(context).cardColor;
    final border = context.appBorder;
    final subColor = isDark ? const Color(0xFFCBD5E1) : Colors.grey[600]!;

    return Container(
      padding: const EdgeInsets.all(26),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded,
              size: 70, color: subColor.withOpacity(0.25)),
          const SizedBox(height: 14),
          Text(
            "All caught up!",
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: subColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            "No pending loans to review.",
            style: GoogleFonts.inter(color: subColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}

class _BannerItem {
  final String asset;
  final String url;
  const _BannerItem({required this.asset, required this.url});
}

class _ServiceItem {
  final String label;
  final String asset;
  final String url;
  const _ServiceItem({required this.label, required this.asset, required this.url});
}
