import 'dart:async';
import 'dart:convert';
import 'dart:convert';
import 'dart:io';
import 'dart:ui';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/models/loan_application.dart';
import 'package:loan2/pages/create_beneficiary_page.dart';
import 'package:loan2/pages/help_support_page.dart';
import 'package:loan2/pages/history_page.dart';
import 'package:loan2/pages/loan_detail_page.dart';
import 'package:loan2/pages/login_page.dart';
import 'package:loan2/pages/profile_settings_page.dart';
import 'package:loan2/pages/reports_page.dart';
import 'package:loan2/services/api.dart';
import 'package:loan2/services/app_theme.dart';
import 'package:loan2/services/bank_service.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:loan2/services/theme_ext.dart';
import 'package:loan2/widgets/officer_nav_bar.dart';
import 'package:url_launcher/url_launcher.dart';

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

  // ✅ UI-only: expand within same home page
  bool _pendingExpanded = false;

  // -------------------- OFFLINE SYNC + SNAPSHOT STATE (ADDED) --------------------
  bool _isOnline = true;
  int _offlineCount = 0;
  StreamSubscription<bool>? _onlineSub;
  StreamSubscription<bool>? _syncSub;

  // cache: loanId -> snapshot future, so cards don't refetch every rebuild
  final Map<String, Future<String?>> _snapshotFuture = {};
  // -----------------------------------------------------------------------------

  @override
  void initState() {
    super.initState();

    SyncService.startListener(); // starts online/offline listener globally

    _loadSnapshot(); // show last data immediately if available
    _loadData(); // then fetch fresh if online
    _loadOfficerName();

    // -------------------- OFFLINE SYNC LISTENERS (ADDED) --------------------
    _initOfflineSync();
    // -----------------------------------------------------------------------
  }

  @override
  void dispose() {
    _scroll.dispose();

    // -------------------- OFFLINE SYNC CLEANUP (ADDED) --------------------
    _onlineSub?.cancel();
    _syncSub?.cancel();
    // ---------------------------------------------------------------------

    super.dispose();
  }

  // -------------------- OFFLINE SYNC + SNAPSHOT HELPERS (ADDED) --------------------

  Future<void> _initOfflineSync() async {
    try {
      final online = await SyncService.realInternetCheck();
      if (!mounted) return;
      setState(() => _isOnline = online);
    } catch (_) {}

    await _refreshOfflineCount();

    _onlineSub = SyncService.onOnlineStatusChanged.listen((online) async {
      if (!mounted) return;
      setState(() => _isOnline = online);

      await _refreshOfflineCount();

      if (online) {
        try {
          await SyncService.syncAll();
        } catch (_) {}

        await _refreshOfflineCount();

        if (!mounted) return;
        // refresh dashboard data + snapshots after sync
        _snapshotFuture.clear();
        _loadData();
      }
    });

    _syncSub = SyncService.onSync.listen((_) async {
      await _refreshOfflineCount();
      if (!mounted) return;
      _snapshotFuture.clear();
      _loadData();
    });
  }

  Future<void> _refreshOfflineCount() async {
    try {
      final c = await DatabaseHelper.instance.getQueuedForUploadCount();
      if (!mounted) return;
      setState(() => _offlineCount = c);
    } catch (_) {
      if (!mounted) return;
      setState(() => _offlineCount = 0);
    }
  }

  Future<String?> _snapshotUrlForLoan(String loanId) {
    return _snapshotFuture.putIfAbsent(loanId, () async {
      if (!_isOnline) return null;

      try {
        final resp = await http
            .get(Uri.parse('${kBaseUrl}loan_details?loan_id=$loanId'))
            .timeout(const Duration(seconds: 15));

        if (resp.statusCode != 200) return null;

        final decoded = jsonDecode(resp.body);
        if (decoded is! Map) return null;

        Map<String, dynamic>? details;
        final ld = decoded['loan_details'];
        if (ld is Map) {
          details = Map<String, dynamic>.from(ld as Map);
        } else if (decoded['data'] is Map) {
          details = Map<String, dynamic>.from(decoded['data'] as Map);
        } else {
          // sometimes backend returns the object at root
          details = Map<String, dynamic>.from(decoded);
        }

        final processes = details['process'];
        if (processes is! List) return null;

        for (final item in processes) {
          if (item is! Map) continue;

          final mediaUrl =
          (item['media_url'] ?? item['mediaUrl'] ?? item['media'] ?? '')
              .toString()
              .trim();
          if (mediaUrl.isNotEmpty) return mediaUrl;

          final fileId = item['file_id'] ?? item['fileId'];
          if (fileId != null && fileId.toString().trim().isNotEmpty) {
            return '${kBaseUrl}media/${fileId.toString().trim()}';
          }
        }
        return null;
      } catch (_) {
        return null;
      }
    });
  }

  Widget _syncChip(Color blue) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.14),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: Colors.white.withOpacity(0.14)),
      ),
      child: Icon(
        _isOnline ? Icons.wifi : Icons.wifi_off,
        color: _isOnline ? Colors.greenAccent : Colors.redAccent,
        size: 18,
      ),
    );
  }

  // ---------------------------------------------------------------------------

  Future<void> _loadData() async {
    try {
      final online = await SyncService.realInternetCheck();
      if (!online) {
        final ok = await _loadSnapshot();
        if (!ok && mounted) setState(() => _isLoading = false);
        return;
      }

      final statsFuture = _bankService.fetchDashboardStats(widget.officerId);
      final loansFuture = _bankService.fetchPendingLoans(widget.officerId);
      final results = await Future.wait([statsFuture, loansFuture]);

      if (!mounted) return;
      setState(() {
        _stats = results[0] as Map<String, int>;
        _loans = results[1] as List<LoanApplication>;
        _isLoading = false;
      });
      await _saveSnapshot();
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

  // Reduced height a bit (UI-only)
  static const double _reviewsCardH = 175.0;

  Future<File> _cacheFile() async {
    final dir = await getApplicationDocumentsDirectory();
    return File(p.join(dir.path, 'dashboard_cache_${widget.officerId}.json'));
  }

  Future<void> _saveSnapshot() async {
    try {
      final f = await _cacheFile();
      final payload = {
        "stats": _stats,
        "loans": _loans.map((e) => e.toJson()).toList(),
        "saved_at": DateTime.now().millisecondsSinceEpoch,
      };
      await f.writeAsString(jsonEncode(payload));
    } catch (_) {}
  }

  Future<bool> _loadSnapshot() async {
    try {
      final f = await _cacheFile();
      if (!await f.exists()) return false;

      final raw = await f.readAsString();
      final m = jsonDecode(raw);

      final statsRaw = (m is Map) ? m["stats"] : null;
      final loansRaw = (m is Map) ? m["loans"] : null;

      if (statsRaw is! Map || loansRaw is! List) return false;

      final stats = Map<String, int>.from(
        statsRaw.map((k, v) => MapEntry(k.toString(), (v as num).toInt())),
      );

      final loans = loansRaw
          .whereType<Map>()
          .map((e) => LoanApplication.fromJson(Map<String, dynamic>.from(e)))
          .toList();

      if (!mounted) return true;
      setState(() {
        _stats = stats;
        _loans = loans;
        _isLoading = false;
      });
      return true;
    } catch (_) {
      return false;
    }
  }

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

  void _openCreateBeneficiary() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => CreateBeneficiaryPage(officerId: widget.officerId),
      ),
    ).then((_) => _loadData());
  }

  @override
  Widget build(BuildContext context) {
    final bg = Theme.of(context).scaffoldBackgroundColor;
    const blue = Color(0xFF1E5AA8);

    return Scaffold(
      backgroundColor: bg,
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : LayoutBuilder(
          builder: (context, c) {
            final w = c.maxWidth;
            final pad = w >= 900 ? 28.0 : (w >= 600 ? 20.0 : 16.0);

            // Expanded view inside same home screen
            if (_pendingExpanded) {
              return _buildPendingExpandedView(blue, pad);
            }

            // ✅ Home: no user scroll (but programmatic scroll works)
            return CustomScrollView(
              controller: _scroll,
              physics: const NeverScrollableScrollPhysics(),
              slivers: [
                SliverToBoxAdapter(
                  child: _buildTopHeaderAndReviews(blue, pad, w),
                ),

                SliverToBoxAdapter(
                  key: _pendingKey,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 10, pad, 8),
                    child: _buildPendingHeaderRow(blue),
                  ),
                ),

                SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 0, pad, 0),
                    child: _buildPendingPreview(blue),
                  ),
                ),

                // ✅ Button pinned at bottom area (fix)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: EdgeInsets.fromLTRB(pad, 12, pad, 12),
                    child: Column(
                      children: [
                        const Spacer(),
                        SizedBox(
                          width: double.infinity,
                          height: 50,
                          child: ElevatedButton.icon(
                            onPressed: _openCreateBeneficiary,
                            icon: const Icon(Icons.person_add_alt_1_rounded),
                            label: Text(
                              "Create New Beneficiary",
                              style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                            ),
                            style: ElevatedButton.styleFrom(
                              backgroundColor: blue,
                              foregroundColor: Colors.white,
                              elevation: 0,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
      bottomNavigationBar: OfficerNavBar(currentIndex: 0, officerId: widget.officerId),
    );
  }

  // -------- Pending section (Home) --------

  Widget _buildPendingHeaderRow(Color blue) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final titleColor = isDark ? Colors.white : const Color(0xFF111827);
    final pendingItems = _filteredPending;

    return Row(
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
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: blue.withOpacity(0.10),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: blue.withOpacity(0.18)),
          ),
          child: Text(
            "${pendingItems.length}",
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: blue),
          ),
        ),
      ],
    );
  }


  Widget _buildPendingPreview(Color blue) {
    final pendingItems = _filteredPending;

    // keep your existing logic
    final screenH = MediaQuery.sizeOf(context).height;
    final previewMax = screenH < 740 ? 1 : 2;
    final previewItems = pendingItems.take(previewMax).toList();

    if (pendingItems.isEmpty) {
      return _buildEmptyStateCompact();
    }

    return Column(
      children: [
        for (final loan in previewItems) _buildProLoanCard(loan),

        if (pendingItems.length > previewItems.length)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Align(
              alignment: Alignment.center,
              child: InkWell(
                borderRadius: BorderRadius.circular(12),
                onTap: () => setState(() => _pendingExpanded = true), // "redirect" to pending page
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        "View more",
                        style: GoogleFonts.inter(
                          fontSize: 12,
                          fontWeight: FontWeight.w800,
                          color: blue,
                        ),
                      ),
                      const SizedBox(width: 2),
                      Icon(Icons.keyboard_arrow_down_rounded, size: 18, color: blue),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }


  // -------- Expanded pending view (still within same Home screen) --------

  Widget _buildPendingExpandedView(Color blue, double pad) {
    final card = Theme.of(context).cardColor;
    final pendingItems = _filteredPending;

    return Column(
      children: [
        // ✅ BLUE HEADER (radius 25)
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 14, pad, 10),
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
            decoration: BoxDecoration(
              color: blue,
              borderRadius: BorderRadius.circular(25),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.10),
                  blurRadius: 16,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: Row(
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _pendingExpanded = false),
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.arrow_back_rounded, color: Colors.white, size: 18),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    "Pending Reviews",
                    style: GoogleFonts.poppins(
                      fontSize: 16,
                      fontWeight: FontWeight.w800,
                      color: Colors.white,
                    ),
                  ),
                ),
                InkWell(
                  borderRadius: BorderRadius.circular(16),
                  onTap: _loadData,
                  child: Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.16),
                      borderRadius: BorderRadius.circular(16),
                    ),
                    child: const Icon(Icons.refresh_rounded, color: Colors.white, size: 18),
                  ),
                ),
              ],
            ),
          ),
        ),

        // ✅ a bit more space before search bar
        Padding(
          padding: EdgeInsets.fromLTRB(pad, 12, pad, 10),
          child: Container(
            decoration: BoxDecoration(
              color: card,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: context.appBorder),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.05),
                  blurRadius: 14,
                  offset: const Offset(0, 8),
                ),
              ],
            ),
            child: TextField(
              onChanged: (v) => setState(() => _reviewQuery = v),
              decoration: const InputDecoration(
                hintText: "Search by name / Loan ID",
                border: InputBorder.none,
                contentPadding: EdgeInsets.symmetric(horizontal: 14, vertical: 14),
                prefixIcon: Icon(Icons.search_rounded),
              ),
            ),
          ),
        ),

        Expanded(
          child: pendingItems.isEmpty
              ? Padding(
            padding: EdgeInsets.fromLTRB(pad, 20, pad, 0),
            child: _buildEmptyStateCompact(),
          )
              : ListView.builder(
            padding: EdgeInsets.fromLTRB(pad, 0, pad, 12),
            itemCount: pendingItems.length,
            itemBuilder: (context, i) => _buildProLoanCard(pendingItems[i]),
          ),
        ),
      ],
    );
  }


  // -------- Header UI --------

  Widget _buildTopHeaderAndReviews(Color blue, double pad, double w) {
    final headerH = w >= 600 ? 170.0 : 160.0;
    final overlap = 26.0;
    final bottomGap = w >= 600 ? 14.0 : 12.0;
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
                          errorBuilder: (_, __, ___) =>
                          const Icon(Icons.gavel_rounded, color: Colors.white),
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
                    icon: const Icon(Icons.notifications_none_rounded, color: Colors.white),
                  ),
                ),
                const SizedBox(width: 10),
                _syncChip(blue),
                const SizedBox(width: 10),
                PopupMenuButton<_UserMenu>(
                  offset: const Offset(0, 44),
                  elevation: 10,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  onSelected: (value) {
                    switch (value) {
                      case _UserMenu.profile:
                      case _UserMenu.settings:
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => ProfileSettingsPage(officerId: widget.officerId),
                          ),
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
                              Row(
                                children: const [
                                  Icon(Icons.dark_mode_outlined, size: 20),
                                  SizedBox(width: 10),
                                  Text('Dark mode'),
                                ],
                              ),
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
                        style: GoogleFonts.poppins(fontWeight: FontWeight.w800, color: blue),
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
                  color: isDark ? Colors.white : const Color(0xFF111827),
                ),
                decoration: InputDecoration(
                  hintText: "Search reviews",
                  hintStyle: GoogleFonts.inter(
                    color: isDark ? const Color(0xFF9CA3AF) : Colors.grey[500],
                    fontWeight: FontWeight.w700,
                  ),
                  border: InputBorder.none,
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
                  prefixIcon: Icon(
                    Icons.search_rounded,
                    color: isDark ? const Color(0xFF9CA3AF) : Colors.grey[500],
                  ),
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

  // ✅ Change #1: remove "Your Reviews" title + move greeting to top
  Widget _buildReviewsCardLikePhoto() {
    const blue = Color(0xFF1E5AA8);
    final border = context.appBorder;

    final displayName = _officerName.trim().isNotEmpty ? _officerName.trim() : widget.officerId;

    return Container(
      height: _reviewsCardH,
      decoration: BoxDecoration(
        color: Colors.white,
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
        padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Greeting at top
            RichText(
              text: TextSpan(
                children: [
                  TextSpan(
                    text: "Good afternoon, ",
                    style: GoogleFonts.poppins(
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                      color: Colors.grey[700],
                    ),
                  ),
                  TextSpan(
                    text: displayName,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w900,
                      color: const Color(0xFF111827),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _buildStatCardsRowLikePhoto(blue),
          ],
        ),
      ),
    );
  }

  Widget _buildStatCardsRowLikePhoto(Color blue) {
    return Row(
      children: [
        _photoStatCard(
          title: "Pending",
          count: _stats['pending'] ?? 0,
          icon: Icons.hourglass_top_rounded,
          iconBg: const Color(0xFFFFF3E0),
          iconColor: const Color(0xFFFF8A00),
          tintColor: const Color(0xFFFF8A00),
          onTap: _scrollToPending,
        ),
        const SizedBox(width: 12),
        _photoStatCard(
          title: "Verified",
          count: _stats['verified'] ?? 0,
          icon: Icons.verified_rounded,
          iconBg: const Color(0xFFE8F5E9),
          iconColor: const Color(0xFF16A34A),
          tintColor: const Color(0xFF16A34A),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HistoryPage(officerId: widget.officerId)),
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
          tintColor: const Color(0xFFDC2626),
          onTap: () {
            Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => HistoryPage(officerId: widget.officerId)),
            );
          },
        ),
      ],
    );
  }

  Widget _photoStatCard({
    required String title,
    required int count,
    required IconData icon,
    required Color iconBg,
    required Color iconColor,
    required Color tintColor,
    required VoidCallback onTap,
    Color? cardBg,
  }) {
    final bg = tintColor.withOpacity(0.14);
    final borderColor = tintColor.withOpacity(0.22);

    return Expanded(
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: onTap,
        child: Container(
          height: 106,
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: borderColor),
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
                child: Icon(icon, color: iconColor, size: 22),
              ),
              const SizedBox(height: 8),
              Text(
                "$count",
                style: GoogleFonts.poppins(
                  fontSize: 20,
                  fontWeight: FontWeight.w800,
                  color: const Color(0xFF111827),
                ),
              ),
              const SizedBox(height: 2),
              Text(
                title,
                style: GoogleFonts.inter(
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                  color: Colors.grey[700],
                ),
              ),
            ],
          ),
        ),
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
      margin: const EdgeInsets.only(bottom: 10),
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
              MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: loan.loanId)),
            ).then((_) => _loadData());
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFF0F1B2D),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(12),
                    child: FutureBuilder<String?>(
                      future: _snapshotUrlForLoan(loan.loanId),
                      builder: (context, snap) {
                        final url = (snap.data ?? "").trim();
                        if (url.isNotEmpty) {
                          return Image.network(
                            url,
                            fit: BoxFit.cover,
                            errorBuilder: (_, __, ___) => Center(
                              child: Text(
                                loan.applicantName.isNotEmpty ? loan.applicantName[0] : "?",
                                style: GoogleFonts.poppins(
                                  color: const Color(0xFF60A5FA),
                                  fontWeight: FontWeight.bold,
                                  fontSize: 18,
                                ),
                              ),
                            ),
                          );
                        }
                        return Center(
                          child: Text(
                            loan.applicantName.isNotEmpty ? loan.applicantName[0] : "?",
                            style: GoogleFonts.poppins(
                              color: const Color(0xFF60A5FA),
                              fontWeight: FontWeight.bold,
                              fontSize: 18,
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        loan.applicantName,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: GoogleFonts.poppins(
                          fontWeight: FontWeight.w600,
                          fontSize: 15,
                          color: titleColor,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
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
                Icon(Icons.arrow_forward_ios_rounded, size: 16, color: subColor.withOpacity(0.4)),
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
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: border),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.check_circle_outline_rounded, size: 66, color: subColor.withOpacity(0.25)),
          const SizedBox(height: 12),
          Text(
            "All caught up!",
            style: GoogleFonts.poppins(
              fontSize: 18,
              color: subColor,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 6),
          Text(
            "No pending loans to review.",
            style: GoogleFonts.inter(color: subColor, fontWeight: FontWeight.w600),
          ),
        ],
      ),
    );
  }
}
