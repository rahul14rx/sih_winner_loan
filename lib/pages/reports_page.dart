import 'dart:math';
import 'dart:ui';
import 'dart:convert';
import 'dart:io';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:path_provider/path_provider.dart';
import 'package:path/path.dart' as p;

import '../services/api.dart';
import '../services/sync_service.dart';
import 'loan_detail_page.dart';
import 'package:loan2/widgets/officer_nav_bar.dart';

class ReportsPage extends StatefulWidget {
  final String officerId;
  const ReportsPage({super.key, required this.officerId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
}
String _canonStatus(String st) {
  final s = st.trim().toLowerCase();

  if (s == "verified" || s == "accepted" || s == "approved" || s == "approve") return "verified";
  if (s == "rejected" || s == "declined" || s == "denied" || s == "deny") return "rejected";
  if (s == "pending" || s == "not verified" || s == "not_verified" || s == "not-verified" || s == "unverified") {
    return "pending";
  }
  return s;
}

class _LoanRow {
  final String loanId;
  final String applicantName;
  final double amount;
  final String loanType;
  final String status;
  final String dateApplied;
  String scheme;

  _LoanRow({
    required this.loanId,
    required this.applicantName,
    required this.amount,
    required this.loanType,
    required this.status,
    required this.dateApplied,
    this.scheme = "",
  });

  Map<String, dynamic> toJson() => {
    "loan_id": loanId,
    "applicant_name": applicantName,
    "amount": amount,
    "loan_type": loanType,
    "status": status,
    "date_applied": dateApplied,
    "scheme": scheme,
  };

  static _LoanRow fromJson(Map<String, dynamic> j) => _LoanRow(
    loanId: (j["loan_id"] ?? "").toString(),
    applicantName: (j["applicant_name"] ?? "Beneficiary").toString(),
    amount: (j["amount"] is num) ? (j["amount"] as num).toDouble() : double.tryParse("${j["amount"]}") ?? 0.0,
    loanType: (j["loan_type"] ?? "Loan").toString(),
    status: (j["status"] ?? "not verified").toString(),
    dateApplied: (j["date_applied"] ?? "2000-01-01").toString(),
    scheme: (j["scheme"] ?? "").toString(),
  );
}

enum _RangePick { today, week, month, all, custom }

class _ReportsPageState extends State<ReportsPage> {
  // ====== THEME PALETTE (auto light/dark) ======

  static const _bgDark = Color(0xFF0B1220);
  static const _cardDark = Color(0xFF0F1B2D);
  static const _cardBorderDark = Color(0xFF1E2B44);
  static const _mutedDark = Color(0xFFB8C0D4);
  static const _titleDark = Colors.white;

  static const _bgLight = Color(0xFFF6F8FB);
  static const _cardLight = Colors.white;
  static const _cardBorderLight = Color(0xFFE5E7EB);
  static const _mutedLight = Color(0xFF6B7280);
  static const _titleLight = Color(0xFF111827);

  static const _accent = Color(0xFF1E5AA8);
  static const double _headerRadius = 25;

  bool get _isDarkMode => Theme.of(context).brightness == Brightness.dark;

  Color get _bg => _isDarkMode ? _bgDark : _bgLight;
  Color get _cardFill => _isDarkMode ? _cardDark : _cardLight;
  Color get _cardBorder => _isDarkMode ? _cardBorderDark : _cardBorderLight;
  Color get _muted => _isDarkMode ? _mutedDark : _mutedLight;
  Color get _title => _isDarkMode ? _titleDark : _titleLight;

  Color get _chipBg => _isDarkMode ? Colors.white.withOpacity(0.08) : Colors.black.withOpacity(0.04);
  Color get _chipBorder => _isDarkMode ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.08);
  Color get _chipActiveBg => _isDarkMode ? Colors.white.withOpacity(0.14) : Colors.black.withOpacity(0.07);

  // ====== STATE ======

  bool _loading = true;

  final Set<String> _selectedSchemes = {};
  bool _showAccepted = true;
  bool _showRejected = true;
  bool _showPending = true;

  _RangePick _rangePick = _RangePick.all;

  DateTimeRange? _customRange;

  final List<_LoanRow> _all = [];
  static const List<String> _schemeOptions = ["NBCFDC", "NSFDC", "NSKFDC"];

  String? _cacheUpdatedAt; // optional display/debug

  @override
  void initState() {
    super.initState();
    _load(); // ✅ offline-aware now
  }

  // ====== OFFLINE SNAPSHOT (FILE CACHE) ======

  Future<File> _getCacheFile() async {
    final docs = await getApplicationDocumentsDirectory();
    // per officer cache (so officers don’t overwrite each other)
    return File(p.join(docs.path, 'reports_cache_${widget.officerId}.json'));
  }

  Future<void> _writeCache() async {
    try {
      final f = await _getCacheFile();
      final payload = {
        "updated_at": DateTime.now().toIso8601String(),
        "items": _all.map((e) => e.toJson()).toList(),
      };
      await f.writeAsString(jsonEncode(payload));
      _cacheUpdatedAt = payload["updated_at"]?.toString();
    } catch (e) {
      debugPrint("❌ Reports cache write failed: $e");
    }
  }

  Future<void> _loadFromCache({bool showSnack = true}) async {
    try {
      final f = await _getCacheFile();
      if (!await f.exists()) {
        if (mounted) {
          setState(() {
            _all.clear();
            _loading = false;
          });
          if (showSnack) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text("Offline: No cached reports available yet."), backgroundColor: Colors.orange),
            );
          }
        }
        return;
      }

      final text = await f.readAsString();
      final decoded = jsonDecode(text);

      if (decoded is Map<String, dynamic>) {
        final items = decoded["items"];
        final ts = decoded["updated_at"]?.toString();
        final list = <_LoanRow>[];

        if (items is List) {
          for (final it in items) {
            if (it is Map) {
              list.add(_LoanRow.fromJson(Map<String, dynamic>.from(it)));
            }
          }
        }

        if (mounted) {
          setState(() {
            _all
              ..clear()
              ..addAll(list);
            _cacheUpdatedAt = ts;
            _loading = false;
          });

          if (showSnack) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text("Offline: Showing last saved report snapshot${ts != null ? " ($ts)" : ""}."),
                backgroundColor: Colors.orange,
              ),
            );
          }
        }
      }
    } catch (e) {
      debugPrint("❌ Reports cache read failed: $e");
      if (mounted) {
        setState(() => _loading = false);
      }
    }
  }

  // ====== FILTER SHEET ======

  void _openSchemeFilter() {
    final temp = Set<String>.from(_selectedSchemes);

    showModalBottomSheet(
      context: context,
      backgroundColor: _cardFill,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        final isDark = Theme.of(ctx).brightness == Brightness.dark;
        final titleC = isDark ? Colors.white : const Color(0xFF111827);
        final subC = isDark ? Colors.white70 : const Color(0xFF6B7280);

        return StatefulBuilder(
          builder: (ctx, setSheet) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 5,
                    width: 42,
                    decoration: BoxDecoration(
                      color: isDark ? Colors.white24 : Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Loan Schemes",
                      style: GoogleFonts.poppins(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: titleC,
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  ..._schemeOptions.map((s) {
                    final checked = temp.contains(s);
                    return CheckboxListTile(
                      value: checked,
                      onChanged: (v) {
                        setSheet(() {
                          if (v == true) {
                            temp.add(s);
                          } else {
                            temp.remove(s);
                          }
                        });
                      },
                      activeColor: _accent,
                      checkColor: Colors.white,
                      title: Text(
                        s,
                        style: GoogleFonts.inter(
                          fontWeight: FontWeight.w600,
                          color: titleC,
                        ),
                      ),
                      subtitle: isDark
                          ? null
                          : Text(
                        "Filter by scheme",
                        style: GoogleFonts.inter(
                          color: subC,
                          fontSize: 12,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    );
                  }),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton(
                          onPressed: () => setSheet(() => temp.clear()),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: titleC,
                            side: BorderSide(
                              color: isDark ? Colors.white30 : Colors.black12,
                            ),
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                          ),
                          child: Text(
                            "Clear",
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: ElevatedButton(
                          onPressed: () {
                            setState(() {
                              _selectedSchemes
                                ..clear()
                                ..addAll(temp);
                            });
                            Navigator.pop(ctx);
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: _accent,
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(30),
                            ),
                            elevation: 0,
                          ),
                          child: Text(
                            "Apply",
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ====== LOGIC (unchanged) ======

  DateTime _parseDate(String s) {
    try {
      final t = DateTime.tryParse(s.trim());
      if (t != null) return t;
    } catch (_) {}
    return DateTime.now();
  }

  DateTimeRange _effectiveRange() {
    final now = DateTime.now();
    DateTime start;
    DateTime end = now;

    if (_rangePick == _RangePick.custom && _customRange != null) {
      return _customRange!;
    }

    switch (_rangePick) {
      case _RangePick.today:
        start = DateTime(now.year, now.month, now.day);
        break;
      case _RangePick.week:
        start = now.subtract(const Duration(days: 7));
        break;
      case _RangePick.month:
        start = now.subtract(const Duration(days: 30));
        break;
      case _RangePick.all:
        start = DateTime(2000);
        break;
      case _RangePick.custom:
        start = now.subtract(const Duration(days: 7));
        break;
    }

    return DateTimeRange(start: start, end: end);
  }

  bool _statusAllowed(String st) {
    final s = _canonStatus(st);
    if (!_showAccepted && !_showRejected && !_showPending) return true;

    if (_showAccepted && s == "verified") return true;
    if (_showRejected && s == "rejected") return true;
    if (_showPending && s == "pending") return true;

    return false;
  }


  List<_LoanRow> get _filtered {
    final r = _effectiveRange();
    return _all.where((l) {
      final d = _parseDate(l.dateApplied);
      if (d.isBefore(r.start) || d.isAfter(r.end)) return false;

      if (_selectedSchemes.isNotEmpty) {
        final sc = l.scheme.trim();
        if (sc.isEmpty || !_selectedSchemes.contains(sc)) return false;
      }

      if (!_statusAllowed(l.status)) return false;
      return true;
    }).toList();
  }

  int _countStatus(List<_LoanRow> list, String status) =>
      list.where((l) => _canonStatus(l.status) == status).length;

  double _sumAmount(List<_LoanRow> list, String status) {
    return list
        .where((l) => _canonStatus(l.status) == status)
        .fold<double>(0, (p, e) => p + e.amount);
  }


  String _fmtCompact(num v) {
    if (v >= 10000000) return "${(v / 10000000).toStringAsFixed(1)}Cr";
    if (v >= 100000) return "${(v / 100000).toStringAsFixed(1)}L";
    if (v >= 1000) return "${(v / 1000).toStringAsFixed(1)}K";
    return v.toStringAsFixed(0);
  }

  Future<List<_LoanRow>> _fetchList(String status) async {
    final oid = Uri.encodeComponent(widget.officerId.trim());
    final st = Uri.encodeComponent(status.trim());
    final res = await getJson("bank/loans?officer_id=$oid&status=$st");

    final List items = (res["data"] ?? []) as List;

    return items.map((e) {
      return _LoanRow(
        loanId: (e["loan_id"] ?? "").toString(),
        applicantName: (e["applicant_name"] ?? "Beneficiary").toString(),
        amount: (e["amount"] is num) ? (e["amount"] as num).toDouble() : 0.0,
        loanType: (e["loan_type"] ?? "Loan").toString(),
        status: status, // force classification based on the list we requested

        dateApplied: (e["date_applied"] ?? "2000-01-01").toString(),
        scheme: (e["scheme"] ?? "").toString(), // ✅ server already sends this
      );
    }).toList();
  }

  Future<List<_LoanRow>> _safeFetchList(String status) async {
    try {
      return await _fetchList(status);
    } catch (_) {
      return [];
    }
  }

  Future<void> _attachSchemesInBatches(List<_LoanRow> loans) async {
    // ✅ Only fetch details if scheme missing (keeps your old logic, but avoids spam calls)
    const batchSize = 8;
    for (int i = 0; i < loans.length; i += batchSize) {
      final chunk = loans.sublist(i, min(i + batchSize, loans.length));
      await Future.wait(chunk.map((l) async {
        if (l.scheme.trim().isNotEmpty) return;
        try {
          final d = await getJson("bank/loan/${l.loanId}");
          final s = (d["scheme"] ?? "").toString().trim();
          if (s.isNotEmpty) l.scheme = s;
        } catch (_) {}
      }));
      if (!mounted) return;
      setState(() {});
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);

    // ✅ DO NOT call getJson when offline (your api.dart blocks waiting for internet)
    final online = await SyncService.realInternetCheck();
    if (!online) {
      await _loadFromCache(showSnack: true);
      return;
    }

    await _loadFromApi();
  }

  Future<void> _loadFromApi() async {
    setState(() => _loading = true);

    try {
      final lists = await Future.wait([
        _safeFetchList("verified"),
        _safeFetchList("rejected"),
        _safeFetchList("pending"),
        _safeFetchList("not verified"),
      ]);

      final map = <String, _LoanRow>{};
      var c = 0;
      for (final li in lists) {
        for (final row in li) {
          final k = row.loanId.isNotEmpty ? row.loanId : "x_${c++}";
          map.putIfAbsent(k, () => row);
        }
      }

      _all
        ..clear()
        ..addAll(map.values);

      if (!mounted) return;
      setState(() => _loading = false);

      await _attachSchemesInBatches(_all);

      // ✅ after we have best data, snapshot it for offline viewing
      await _writeCache();
    } catch (e) {
      debugPrint("❌ Reports API load failed: $e");
      if (!mounted) return;
      // fallback to cache if API fails
      await _loadFromCache(showSnack: true);
    }
  }

  // ===== Custom range picker =====
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now);

    final picked = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.5),
      builder: (dctx) {
        return _FancyRangePickerDialog(
          firstDate: DateTime(2020),
          lastDate: DateTime(now.year + 1, 12, 31),
          initialRange: initial,
          accent: _accent,
        );
      },
    );

    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _rangePick = _RangePick.custom;
    });
  }

  // ====== UI helpers ======

  Widget _card({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: _cardFill,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: _cardBorder),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isDarkMode ? 0.35 : 0.08),
                blurRadius: 16,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _blueCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    final grad = _isDarkMode
        ? const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFF183B7A), Color(0xFF0F2A57)],
    )
        : const LinearGradient(
      begin: Alignment.topLeft,
      end: Alignment.bottomRight,
      colors: [Color(0xFFEAF2FF), Color(0xFFDDEAFF)],
    );

    final border = _isDarkMode ? const Color(0xFF22406D) : const Color(0xFFCFE0FF);

    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 6, sigmaY: 6),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: grad,
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: border),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(_isDarkMode ? 0.45 : 0.10),
                blurRadius: 18,
                offset: const Offset(0, 12),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _pillChip(String text, bool active, VoidCallback onTap) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 8, sigmaY: 8),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: active ? _chipActiveBg : _chipBg,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: _chipBorder),
              ),
              child: Text(
                text,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: _title,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String label, bool selected, Color activeColor, VoidCallback onTap) {
    final fill = selected
        ? activeColor.withOpacity(_isDarkMode ? 0.18 : 0.14)
        : (_isDarkMode ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04));
    final border = selected
        ? activeColor.withOpacity(_isDarkMode ? 0.35 : 0.28)
        : (_isDarkMode ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.08));
    final txt = selected ? (_isDarkMode ? Colors.white : const Color(0xFF111827)) : _muted;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                color: fill,
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: border, width: 1.1),
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: txt),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpi(String title, String value, IconData icon) {
    final iconBg = _isDarkMode ? Colors.white.withOpacity(0.12) : Colors.black.withOpacity(0.04);
    final iconBorder = _isDarkMode ? Colors.white.withOpacity(0.18) : Colors.black.withOpacity(0.08);
    final iconColor = _isDarkMode ? Colors.white : _accent;
    final valueColor = _isDarkMode ? Colors.white : const Color(0xFF111827);

    return Expanded(
      child: _blueCard(
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: iconBg,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: iconBorder),
              ),
              child: Icon(icon, color: iconColor, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    value,
                    style: GoogleFonts.poppins(
                      fontSize: 18,
                      fontWeight: FontWeight.w800,
                      color: valueColor,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: GoogleFonts.inter(
                      fontSize: 12.5,
                      color: _muted,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _sectionTitle(String t) {
    return Text(
      t,
      style: GoogleFonts.poppins(
        fontSize: 16.5,
        fontWeight: FontWeight.w800,
        color: _title,
      ),
    );
  }

  Widget _miniChip(String label, Color base) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: base.withOpacity(_isDarkMode ? 0.16 : 0.12),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: base.withOpacity(_isDarkMode ? 0.35 : 0.25), width: 1.0),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(
              fontWeight: FontWeight.w900,
              color: _isDarkMode ? Colors.white : const Color(0xFF111827),
            ),
          ),
        ),
      ),
    );
  }

  // ====== BUILD ======

  @override
  Widget build(BuildContext context) {
    final list = _filtered;

    final accepted = _countStatus(list, "verified");
    final rejected = _countStatus(list, "rejected");
    final pending = list.where((l) {
      final s = l.status.toLowerCase();
      return s == "not verified" || s == "pending";
    }).length;

    final total = accepted + rejected + pending;
    final approvalRate = (accepted + rejected) == 0 ? 0.0 : accepted / (accepted + rejected);
    final verifiedAmount = _sumAmount(list, "verified");

    final schemeCounts = <String, int>{};
    for (final s in _schemeOptions) {
      schemeCounts[s] = list.where((l) => l.scheme == s).length;
    }
    final maxVal = schemeCounts.values.fold<int>(0, (p, e) => max(p, e));
    final maxY = max(1, maxVal + 1).toDouble();

    final recent = [...list]..sort((a, b) => _parseDate(b.dateApplied).compareTo(_parseDate(a.dateApplied)));
    final recent8 = recent.take(50).toList(); // or just: final recent8 = recent;
// or just: final recent8 = recent;


    return Scaffold(
      backgroundColor: _bg,
      appBar: AppBar(
        title: Text(
          "Analytics & Reports",
          style: GoogleFonts.poppins(color: Colors.white, fontWeight: FontWeight.w700),
        ),
        backgroundColor: _accent,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.white),
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(_headerRadius)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load, // ✅ offline aware refresh
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 2,
        child: const Icon(Icons.refresh_rounded),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _accent))
          : SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _sectionTitle("Filters"),
            const SizedBox(height: 10),
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _pillChip("Today", _rangePick == _RangePick.today,
                          () => setState(() => _rangePick = _RangePick.today)),
                  const SizedBox(width: 8),
                  _pillChip("7 Days", _rangePick == _RangePick.week,
                          () => setState(() => _rangePick = _RangePick.week)),
                  const SizedBox(width: 8),
                  _pillChip("30 Days", _rangePick == _RangePick.month,
                          () => setState(() => _rangePick = _RangePick.month)),
                  const SizedBox(width: 8),
                  _pillChip("All", _rangePick == _RangePick.all,
                          () => setState(() => _rangePick = _RangePick.all)),
                  const SizedBox(width: 8),
                  _pillChip("Custom", _rangePick == _RangePick.custom, _pickCustomRange),
                ],
              ),
            ),
            const SizedBox(height: 12),
            _card(
              child: InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: _openSchemeFilter,
                child: Row(
                  children: [
                    Icon(Icons.tune_rounded, size: 18, color: _title),
                    const SizedBox(width: 8),
                    Text(
                      _selectedSchemes.isEmpty ? "Loan" : "Loan (${_selectedSchemes.length})",
                      style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: _title),
                    ),
                    const Spacer(),
                    Icon(Icons.keyboard_arrow_down_rounded,
                        color: _isDarkMode ? Colors.white70 : Colors.black54),
                  ],
                ),
              ),
            ),

            // (optional) small hint that cache exists
            if (_cacheUpdatedAt != null) ...[
              const SizedBox(height: 8),
              Text(
                "Last snapshot: $_cacheUpdatedAt",
                style: GoogleFonts.inter(fontSize: 11.5, color: _muted, fontWeight: FontWeight.w600),
              ),
            ],

            const SizedBox(height: 10),
            Align(
              alignment: Alignment.center,
              child: Wrap(
                alignment: WrapAlignment.center,
                runAlignment: WrapAlignment.center,
                spacing: 10,
                runSpacing: 10,
                children: [
                  _statusPill("Accepted", _showAccepted, const Color(0xFF22C55E),
                          () => setState(() => _showAccepted = !_showAccepted)),
                  _statusPill("Rejected", _showRejected, const Color(0xFFEF4444),
                          () => setState(() => _showRejected = !_showRejected)),
                  _statusPill("Pending", _showPending, const Color(0xFFF59E0B),
                          () => setState(() => _showPending = !_showPending)),
                ],
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle("Performance Overview"),
            const SizedBox(height: 12),
            Row(
              children: [
                _kpi("Total Applications", total.toString(), Icons.folder_copy_outlined),
                const SizedBox(width: 12),
                _kpi("Approval Rate", "${(approvalRate * 100).toStringAsFixed(0)}%", Icons.task_alt),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _kpi("Pending", pending.toString(), Icons.hourglass_empty_rounded),
                const SizedBox(width: 12),
                _kpi("Verified Amount", "₹${_fmtCompact(verifiedAmount)}", Icons.currency_rupee_rounded),
              ],
            ),
            const SizedBox(height: 18),
            _sectionTitle("Scheme Breakdown (Bar Graph)"),
            const SizedBox(height: 12),
            _blueCard(
              child: SizedBox(
                height: 240,
                child: BarChart(
                  BarChartData(
                    alignment: BarChartAlignment.spaceEvenly,
                    maxY: maxY,
                    gridData: FlGridData(show: false),
                    borderData: FlBorderData(show: false),
                    titlesData: FlTitlesData(
                      topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                      leftTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          reservedSize: 28,
                          interval: 1,
                          getTitlesWidget: (v, meta) => Padding(
                            padding: const EdgeInsets.only(right: 6),
                            child: Text(
                              v.toInt().toString(),
                              style: GoogleFonts.inter(
                                fontSize: 10.5,
                                color: _isDarkMode ? Colors.white70 : Colors.black54,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        ),
                      ),
                      bottomTitles: AxisTitles(
                        sideTitles: SideTitles(
                          showTitles: true,
                          getTitlesWidget: (v, meta) {
                            final i = v.toInt();
                            if (i < 0 || i >= _schemeOptions.length) return const SizedBox.shrink();
                            return Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: Text(
                                _schemeOptions[i],
                                style: GoogleFonts.inter(
                                  fontSize: 11.5,
                                  fontWeight: FontWeight.w900,
                                  color: _isDarkMode ? Colors.white : const Color(0xFF111827),
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ),
                    barTouchData: BarTouchData(
                      enabled: true,
                      touchTooltipData: BarTouchTooltipData(
                        tooltipPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        tooltipMargin: 10,
                        tooltipRoundedRadius: 10,
                        getTooltipItem: (group, groupIndex, rod, rodIndex) {
                          final i = group.x.toInt();
                          final name =
                          (i >= 0 && i < _schemeOptions.length) ? _schemeOptions[i] : "Scheme";
                          final val = rod.toY.toInt();
                          return BarTooltipItem(
                            "$name\n",
                            GoogleFonts.inter(
                              fontWeight: FontWeight.w900,
                              color: Colors.white,
                              fontSize: 12,
                            ),
                            children: [
                              TextSpan(
                                text: "$val applications",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  color: Colors.white.withOpacity(0.9),
                                  fontSize: 11.5,
                                ),
                              ),
                            ],
                          );
                        },
                      ),
                    ),
                    barGroups: List.generate(_schemeOptions.length, (i) {
                      final y = (schemeCounts[_schemeOptions[i]] ?? 0).toDouble();
                      return BarChartGroupData(
                        x: i,
                        barRods: [
                          BarChartRodData(
                            toY: y,
                            width: 24,
                            borderRadius: BorderRadius.circular(8),
                            color: _isDarkMode ? const Color(0xFF60A5FA) : _accent,
                          ),
                        ],
                      );
                    }),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 18),
            _sectionTitle("Recent Activity"),
            const SizedBox(height: 12),
            if (recent8.isEmpty)
              _card(
                child: Center(
                  child: Text(
                    "No activity for this range",
                    style: GoogleFonts.inter(color: _muted, fontWeight: FontWeight.w700),
                  ),
                ),
              )
            else
              Column(children: recent8.map(_activityTile).toList()),
          ],
        ),
      ),
      bottomNavigationBar: OfficerNavBar(currentIndex: 3, officerId: widget.officerId),
    );
  }

  Widget _activityTile(_LoanRow l) {
    final st = _canonStatus(l.status);
    final isVerified = st == "verified";
    final isRejected = st == "rejected";


    IconData icon;
    String label;
    Color chipColor;

    if (isVerified) {
      icon = Icons.check_circle_rounded;
      label = "accepted";
      chipColor = const Color(0xFF22C55E);
    } else if (isRejected) {
      icon = Icons.cancel_rounded;
      label = "rejected";
      chipColor = const Color(0xFFEF4444);
    } else {
      icon = Icons.hourglass_bottom_rounded;
      label = "pending";
      chipColor = const Color(0xFFF59E0B);
    }

    final iconBg = _isDarkMode ? Colors.white.withOpacity(0.06) : Colors.black.withOpacity(0.04);
    final iconC = _isDarkMode ? Colors.white : _accent;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          if (l.loanId.trim().isEmpty) return;
          Navigator.push(
            context,
            MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: l.loanId)),
          );
        },
        child: _card(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: iconBg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: iconC, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.applicantName.isEmpty ? "Beneficiary" : l.applicantName,
                      style: GoogleFonts.poppins(
                        fontWeight: FontWeight.w800,
                        fontSize: 14.5,
                        color: _title,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "Loan: ${l.loanId}  •  ₹${l.amount.toStringAsFixed(0)}  •  ${l.scheme.isNotEmpty ? l.scheme : l.loanType}",
                      style: GoogleFonts.inter(
                        fontSize: 12.2,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Applied: ${l.dateApplied}",
                      style: GoogleFonts.inter(
                        fontSize: 12.2,
                        color: _muted,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              _miniChip(label, chipColor),
            ],
          ),
        ),
      ),
    );
  }
}

// ===== Fancy range picker (unchanged) =====
class _FancyRangePickerDialog extends StatefulWidget {
  final DateTime firstDate;
  final DateTime lastDate;
  final DateTimeRange initialRange;
  final Color accent;

  const _FancyRangePickerDialog({
    required this.firstDate,
    required this.lastDate,
    required this.initialRange,
    required this.accent,
  });

  @override
  State<_FancyRangePickerDialog> createState() => _FancyRangePickerDialogState();
}

class _FancyRangePickerDialogState extends State<_FancyRangePickerDialog> {
  static const double r = 12.0;

  late DateTime _month;
  DateTime? _start;
  DateTime? _end;

  static const _months = [
    "January","February","March","April","May","June",
    "July","August","September","October","November","December"
  ];

  @override
  void initState() {
    super.initState();
    _start = DateTime(widget.initialRange.start.year, widget.initialRange.start.month, widget.initialRange.start.day);
    _end = DateTime(widget.initialRange.end.year, widget.initialRange.end.month, widget.initialRange.end.day);
    _month = DateTime(_start!.year, _start!.month, 1);
  }

  bool _isSelectable(DateTime d) {
    final dd = DateTime(d.year, d.month, d.day);
    final a = DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day);
    final b = DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day);
    return !dd.isBefore(a) && !dd.isAfter(b);
  }

  DateTime _addMonths(DateTime m, int delta) {
    final y = m.year + ((m.month - 1 + delta) ~/ 12);
    final mm = ((m.month - 1 + delta) % 12) + 1;
    return DateTime(y, mm, 1);
  }

  bool _canGoPrev() {
    final prev = _addMonths(_month, -1);
    final prevEnd = DateTime(prev.year, prev.month, DateUtils.getDaysInMonth(prev.year, prev.month));
    return !DateTime(prevEnd.year, prevEnd.month, prevEnd.day)
        .isBefore(DateTime(widget.firstDate.year, widget.firstDate.month, widget.firstDate.day));
  }

  bool _canGoNext() {
    final next = _addMonths(_month, 1);
    final nextStart = DateTime(next.year, next.month, 1);
    return !DateTime(nextStart.year, nextStart.month, nextStart.day)
        .isAfter(DateTime(widget.lastDate.year, widget.lastDate.month, widget.lastDate.day));
  }

  DateTime _dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  void _onTapDay(DateTime d) {
    if (!_isSelectable(d)) return;
    final day = _dateOnly(d);

    if (_start == null || (_start != null && _end != null)) {
      setState(() {
        _start = day;
        _end = null;
      });
      return;
    }

    if (_start != null && _end == null) {
      if (day.isBefore(_start!)) {
        setState(() {
          _end = _start;
          _start = day;
        });
      } else {
        setState(() {
          _end = day;
        });
      }
    }
  }

  bool _inRange(DateTime d) {
    if (_start == null) return false;
    final day = _dateOnly(d);
    if (_end == null) return DateUtils.isSameDay(day, _start);
    return !day.isBefore(_start!) && !day.isAfter(_end!);
  }

  bool _isStart(DateTime d) => _start != null && DateUtils.isSameDay(d, _start);
  bool _isEnd(DateTime d) => _end != null && DateUtils.isSameDay(d, _end);

  @override
  Widget build(BuildContext context) {
    final accent = widget.accent;

    final first = DateTime(_month.year, _month.month, 1);
    final offset = first.weekday % 7;
    final gridStart = first.subtract(Duration(days: offset));
    final cells = List<DateTime>.generate(42, (i) => gridStart.add(Duration(days: i)));

    return Dialog(
      backgroundColor: Colors.transparent,
      elevation: 0,
      insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 22),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(r),
        child: BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
          child: Container(
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(r),
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Colors.white.withOpacity(0.90), Colors.white.withOpacity(0.78)],
              ),
              border: Border.all(color: Colors.white.withOpacity(0.55), width: 1.2),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withOpacity(0.18),
                  blurRadius: 28,
                  offset: const Offset(0, 16),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 12),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Select Range",
                          style: GoogleFonts.poppins(
                            fontSize: 14.5,
                            fontWeight: FontWeight.w800,
                            color: Colors.black87,
                          ),
                        ),
                      ),
                      TextButton(
                        onPressed: () => Navigator.pop(context),
                        child: Text("Cancel", style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
                      ),
                      const SizedBox(width: 6),
                      TextButton(
                        onPressed: _start == null
                            ? null
                            : () {
                          final s = _start!;
                          final e = _end ?? _start!;
                          Navigator.pop(context, DateTimeRange(start: s, end: e));
                        },
                        child: Text("Apply", style: GoogleFonts.inter(fontWeight: FontWeight.w900)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.85),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _canGoPrev() ? () => setState(() => _month = _addMonths(_month, -1)) : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              "${_months[_month.month - 1]} ${_month.year}",
                              style: GoogleFonts.poppins(
                                fontSize: 15.5,
                                fontWeight: FontWeight.w900,
                                color: Colors.black87,
                              ),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _canGoNext() ? () => setState(() => _month = _addMonths(_month, 1)) : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: const [_W("Su"), _W("Mo"), _W("Tu"), _W("We"), _W("Th"), _W("Fr"), _W("Sa")],
                  ),
                  const SizedBox(height: 8),
                  AspectRatio(
                    aspectRatio: 7 / 6,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 42,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7, mainAxisSpacing: 6, crossAxisSpacing: 6,
                      ),
                      itemBuilder: (ctx, i) {
                        final d = cells[i];
                        final inMonth = d.month == _month.month;
                        final selectable = _isSelectable(d);
                        final inRange = _inRange(d);
                        final isStart = _isStart(d);
                        final isEnd = _isEnd(d);

                        Color? bg;
                        Color txt = Colors.black87;

                        if (!inMonth) txt = Colors.black38;
                        if (!selectable) txt = Colors.black26;

                        if (inRange) {
                          if (isStart || isEnd) {
                            bg = accent.withOpacity(0.92);
                            txt = Colors.white;
                          } else {
                            bg = accent.withOpacity(0.14);
                          }
                        } else {
                          bg = Colors.transparent;
                        }

                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: selectable ? () => _onTapDay(d) : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: bg,
                              borderRadius: BorderRadius.circular(10),
                              boxShadow: inRange
                                  ? [
                                BoxShadow(
                                  color: accent.withOpacity((isStart || isEnd) ? 0.20 : 0.08),
                                  blurRadius: 14,
                                  offset: const Offset(0, 8),
                                )
                              ]
                                  : const [],
                            ),
                            child: Center(
                              child: Text(
                                "${d.day}",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                  color: txt,
                                  fontSize: 12.5,
                                ),
                              ),
                            ),
                          ),
                        );
                      },
                    ),
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(child: _RangePill(label: "Start", value: _start == null ? "--" : _fmt(_start!), accent: accent)),
                      const SizedBox(width: 10),
                      Expanded(child: _RangePill(label: "End", value: (_end ?? _start) == null ? "--" : _fmt((_end ?? _start)!), accent: accent)),
                    ],
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static String _fmt(DateTime d) {
    const m = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"];
    return "${m[d.month - 1]} ${d.day}, ${d.year}";
  }
}

class _W extends StatelessWidget {
  final String t;
  const _W(this.t);
  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: Center(
        child: Text(
          t,
          style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: Colors.black54, fontSize: 12),
        ),
      ),
    );
  }
}

class _RangePill extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;
  const _RangePill({required this.label, required this.value, required this.accent});

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.85),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            height: 10,
            width: 10,
            decoration: BoxDecoration(color: accent.withOpacity(0.85), borderRadius: BorderRadius.circular(3)),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(label, style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: Colors.black54, fontSize: 11)),
                const SizedBox(height: 2),
                Text(value, style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: Colors.black87, fontSize: 12.5)),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
