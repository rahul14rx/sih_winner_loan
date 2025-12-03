import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../services/api.dart';
import '../services/sync_service.dart';
import 'loan_detail_page.dart';
import 'package:loan2/widgets/officer_nav_bar.dart';

class HistoryPage extends StatefulWidget {
  final String officerId;
  const HistoryPage({super.key, required this.officerId});

  @override
  State<HistoryPage> createState() => _HistoryPageState();
}

class _LoanRow {
  final String loanId;
  final String applicantName;
  final double amount;
  final String loanType;
  final String status;
  final String dateApplied;
  final String userId;

  String scheme;
  String loanPurpose;

  _LoanRow({
    required this.loanId,
    required this.applicantName,
    required this.amount,
    required this.loanType,
    required this.status,
    required this.dateApplied,
    required this.userId,
    this.scheme = "",
    this.loanPurpose = "",
  });

  Map<String, dynamic> toJson() => {
    "loan_id": loanId,
    "applicant_name": applicantName,
    "amount": amount,
    "loan_type": loanType,
    "status": status,
    "date_applied": dateApplied,
    "user_id": userId,
    "scheme": scheme,
    "loan_purpose": loanPurpose,
  };

  static _LoanRow fromJson(Map<String, dynamic> e) {
    return _LoanRow(
      loanId: (e["loan_id"] ?? "").toString(),
      applicantName: (e["applicant_name"] ?? "Beneficiary").toString(),
      amount: (e["amount"] is num)
          ? (e["amount"] as num).toDouble()
          : double.tryParse("${e["amount"] ?? 0}") ?? 0.0,
      loanType: (e["loan_type"] ?? "Loan").toString(),
      status: (e["status"] ?? "").toString(),
      dateApplied: (e["date_applied"] ?? "N/A").toString(),
      userId: (e["user_id"] ?? "").toString(),
      scheme: (e["scheme"] ?? "").toString(),
      loanPurpose: (e["loan_purpose"] ?? "").toString(),
    );
  }
}

class _HistoryPageState extends State<HistoryPage> {
  static const _accent = Color(0xFF1E5AA8);
  static const double _headerRadius = 25;

  final _q = TextEditingController();
  bool _loading = true;

  final Set<String> _selectedSchemes = {};
  bool _showAccepted = true;
  bool _showRejected = true;

  List<_LoanRow> _all = [];

  static const List<String> _schemeOptions = ["NSKFDC", "NBCFDC", "NSFDC"];

  StreamSubscription<bool>? _syncSub;
  StreamSubscription<bool>? _onlineSub;

  @override
  void initState() {
    super.initState();

    _q.addListener(() {
      if (!mounted) return;
      setState(() {});
    });

    _syncSub = SyncService.onSync.listen((_) {
      if (!mounted) return;
      _load();
    });

    _onlineSub = SyncService.onOnlineStatusChanged.listen((online) {
      if (!mounted) return;
      if (online) _load();
    });

    _load();
  }

  @override
  void dispose() {
    _q.dispose();
    _syncSub?.cancel();
    _onlineSub?.cancel();
    super.dispose();
  }

  String _safeOfficerKey() {
    final raw = widget.officerId.trim();
    return raw.replaceAll(RegExp(r'[^a-zA-Z0-9_\-]'), "_");
  }

  Future<File> _getCacheFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'history_snapshot_${_safeOfficerKey()}.json'));
  }

  Future<void> _writeSnapshot(List<_LoanRow> rows) async {
    try {
      final f = await _getCacheFile();
      final payload = {
        "cached_at": DateTime.now().toIso8601String(),
        "officer_id": widget.officerId.trim(),
        "data": rows.map((e) => e.toJson()).toList(),
      };
      await f.writeAsString(jsonEncode(payload));
    } catch (e) {
      debugPrint("History snapshot write failed: $e");
    }
  }

  Future<void> _loadFromSnapshot({bool showSnack = true}) async {
    try {
      final f = await _getCacheFile();
      if (!await f.exists()) {
        if (!mounted) return;
        setState(() {
          _all = [];
          _loading = false;
        });
        if (showSnack) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Offline: No history snapshot available yet."),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return;
      }

      final raw = await f.readAsString();
      final decoded = jsonDecode(raw);
      final List list = (decoded is Map ? (decoded["data"] ?? []) : []) as List;

      final rows = list
          .whereType<Map>()
          .map((m) => _LoanRow.fromJson(Map<String, dynamic>.from(m)))
          .toList();

      if (!mounted) return;
      setState(() {
        _all = rows;
        _loading = false;
      });

      if (showSnack) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Offline: Showing saved history snapshot."),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } catch (e) {
      debugPrint("History snapshot load failed: $e");
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  // ✅ FIX: use /bank/loans like your old history behaviour
  Future<List<_LoanRow>> _fetchList(String status) async {
    final oid = Uri.encodeComponent(widget.officerId.trim());
    final res = await getJson("bank/loans?officer_id=$oid&status=$status");
    final List items = (res["data"] ?? []) as List;

    return items.map((e) {
      return _LoanRow(
        loanId: (e["loan_id"] ?? "").toString(),
        applicantName: (e["applicant_name"] ?? "Beneficiary").toString(),
        amount: (e["amount"] is num) ? (e["amount"] as num).toDouble() : 0.0,
        loanType: (e["loan_type"] ?? "Loan").toString(),
        status: (e["status"] ?? status).toString(),
        dateApplied: (e["date_applied"] ?? "N/A").toString(),
        userId: (e["user_id"] ?? "").toString(),
        scheme: (e["scheme"] ?? "").toString(),
        loanPurpose: (e["loan_purpose"] ?? e["loanPurpose"] ?? e["purpose"] ?? "").toString(),
      );
    }).toList();
  }

  Future<void> _attachSchemesAndPurposeInBatches(List<_LoanRow> loans) async {
    final needFix = loans.where((l) => l.scheme.trim().isEmpty || l.loanPurpose.trim().isEmpty).toList();
    if (needFix.isEmpty) return;

    const batchSize = 8;
    for (int i = 0; i < needFix.length; i += batchSize) {
      final chunk = needFix.sublist(i, min(i + batchSize, needFix.length));
      await Future.wait(chunk.map((l) async {
        try {
          final d = await getJson("bank/loan/${l.loanId}");

          final s = (d["scheme"] ?? "").toString().trim();
          if (s.isNotEmpty) l.scheme = s;

          final p1 = (d["loan_purpose"] ?? "").toString().trim();
          final p2 = (d["loanPurpose"] ?? "").toString().trim();
          final p3 = (d["purpose"] ?? "").toString().trim();
          final lp = p1.isNotEmpty ? p1 : (p2.isNotEmpty ? p2 : p3);
          if (lp.isNotEmpty) l.loanPurpose = lp;
        } catch (_) {}
      }));

      if (!mounted) return;
      setState(() {});
      await _writeSnapshot(_all);
    }
  }

  Future<void> _load() async {
    if (!mounted) return;
    setState(() => _loading = true);

    final online = await SyncService.realInternetCheck();
    if (!online) {
      await _loadFromSnapshot(showSnack: true);
      return;
    }

    try {
      final results = await Future.wait([
        _fetchList("verified"),
        _fetchList("rejected"),
      ]);

      _all = <_LoanRow>[...results[0], ...results[1]];
      if (!mounted) return;
      setState(() => _loading = false);

      await _writeSnapshot(_all);
      await _attachSchemesAndPurposeInBatches(_all);
    } catch (e) {
      if (!mounted) return;
      setState(() => _loading = false);
      await _loadFromSnapshot(showSnack: true);
    }
  }

  List<_LoanRow> get _filtered {
    final query = _q.text.trim().toLowerCase();

    return _all.where((l) {
      final st = l.status.trim().toLowerCase();

      final noStatusFilter = !_showAccepted && !_showRejected;

      final okStatus = noStatusFilter ||
          (_showAccepted && st == "verified") ||
          (_showRejected && st == "rejected");

      if (!okStatus) return false;

      if (_selectedSchemes.isNotEmpty) {
        final sc = l.scheme.trim();
        if (sc.isEmpty || !_selectedSchemes.contains(sc)) return false;
      }

      if (query.isEmpty) return true;

      final hay = [
        l.applicantName,
        l.loanId,
        l.loanType,
        l.loanPurpose,
        l.scheme,
        l.status,
      ].join(" ").toLowerCase();

      return hay.contains(query);
    }).toList();
  }

  void _openLoanFilter() {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF0F1B2D) : Colors.white;
    final border = isDark ? const Color(0xFF1F2A44) : Colors.grey.shade300;
    final textC = isDark ? Colors.white : Colors.black87;

    final temp = Set<String>.from(_selectedSchemes);

    showModalBottomSheet(
      context: context,
      backgroundColor: card,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
        return Theme(
          data: Theme.of(ctx).copyWith(
            checkboxTheme: CheckboxThemeData(
              fillColor: WidgetStatePropertyAll(const Color(0xFFFF9933)),
              side: BorderSide(color: border),
            ),
            textTheme: GoogleFonts.interTextTheme(Theme.of(ctx).textTheme).apply(
              bodyColor: textC,
              displayColor: textC,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
            child: StatefulBuilder(
              builder: (ctx2, setSheet) {
                return Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      height: 5,
                      width: 42,
                      decoration: BoxDecoration(
                        color: isDark ? Colors.white10 : Colors.black12,
                        borderRadius: BorderRadius.circular(10),
                      ),
                    ),
                    const SizedBox(height: 14),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Loan Schemes",
                        style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700, color: textC),
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
                        activeColor: const Color(0xFFFF9933),
                        title: Text(s, style: GoogleFonts.inter(fontWeight: FontWeight.w600, color: textC)),
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
                              side: BorderSide(color: border),
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                            ),
                            child: Text("Clear", style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: textC)),
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
                              backgroundColor: const Color(0xFFFF9933),
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 12),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                              elevation: 0,
                            ),
                            child: Text("Apply", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  Widget _statusPill({
    required String label,
    required bool selected,
    required Color activeColor,
    required VoidCallback onTap,
  }) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF0F1B2D) : Colors.white;
    final border = isDark ? const Color(0xFF253454) : Colors.grey.shade300;
    final textC = isDark ? Colors.white : Colors.black87;

    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? activeColor : card,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? activeColor : border),
          boxShadow: isDark
              ? []
              : [
            BoxShadow(
              color: Colors.black.withOpacity(0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : textC,
          ),
        ),
      ),
    );
  }

  Widget _loanCard(_LoanRow l) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final card = isDark ? const Color(0xFF0F1B2D) : Colors.white;
    final border = isDark ? const Color(0xFF1F2A44) : Colors.grey.shade200;
    final textPri = isDark ? Colors.white : Colors.black87;
    final textSec = isDark ? Colors.white70 : Colors.grey[700];

    final isVerified = l.status.toLowerCase() == "verified";
    final badgeColor = isVerified ? Colors.green : Colors.red;

    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => LoanDetailPage(loanId: l.loanId)),
        ).then((_) => _load());
      },
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: card,
          borderRadius: BorderRadius.circular(16),
          boxShadow: isDark
              ? []
              : [
            BoxShadow(
              color: Colors.black.withOpacity(0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            )
          ],
          border: Border.all(color: border),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: const BoxDecoration(
                color: Color(0xFFFFF1E6),
                shape: BoxShape.circle,
              ),
              child: const Icon(Icons.receipt_long_rounded, color: Color(0xFFFF9933)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l.applicantName,
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15, color: textPri),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "ID: ${l.loanId}  •  ₹${l.amount.toStringAsFixed(0)}  •  ${l.loanType}",
                    style: GoogleFonts.inter(fontSize: 12.5, color: textSec),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Applied: ${l.dateApplied}${l.scheme.isNotEmpty ? "  •  ${l.scheme}" : ""}",
                    style: GoogleFonts.inter(fontSize: 12.5, color: textSec),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: badgeColor.withOpacity(0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: badgeColor.withOpacity(0.25)),
              ),
              child: Text(
                isVerified ? "accepted" : "rejected",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  color: isVerified ? Colors.green[300] : Colors.red[300],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    final bg = Theme.of(context).scaffoldBackgroundColor;
    final card = isDark ? const Color(0xFF0F1B2D) : Colors.white;
    final border = isDark ? const Color(0xFF1F2A44) : Colors.grey.shade200;
    final textPri = isDark ? Colors.white : Colors.black87;
    final textSec = isDark ? Colors.white70 : Colors.grey[600];

    final list = _filtered;

    return Scaffold(
      backgroundColor: bg,
      appBar: AppBar(
        title: Text(
          "History",
          style: GoogleFonts.poppins(fontWeight: FontWeight.w700, color: Colors.white),
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
      bottomNavigationBar: OfficerNavBar(
        officerId: widget.officerId,
        currentIndex: 2,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _load,
        backgroundColor: const Color(0xFFFF9933),
        foregroundColor: Colors.white,
        elevation: 2,
        child: const Icon(Icons.refresh_rounded),
      ),
      body: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 0),
        child: Column(
          children: [
            // Search
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: card,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: border),
                boxShadow: isDark
                    ? []
                    : [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: textSec),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _q,
                      style: GoogleFonts.inter(color: textPri),
                      decoration: InputDecoration(
                        hintText: "Search by name / loan id / type...",
                        hintStyle: GoogleFonts.inter(color: textSec),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_q.text.isNotEmpty)
                    IconButton(
                      onPressed: () => _q.clear(),
                      icon: Icon(Icons.close_rounded, color: textSec),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            // Filters row
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _openLoanFilter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: card,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: border),
                        boxShadow: isDark
                            ? []
                            : [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 10,
                            offset: const Offset(0, 4),
                          )
                        ],
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded, size: 18, color: Color(0xFFFF9933)),
                          const SizedBox(width: 8),
                          Text(
                            _selectedSchemes.isEmpty ? "Loan" : "Loan (${_selectedSchemes.length})",
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: textPri),
                          ),
                          const Spacer(),
                          Icon(Icons.keyboard_arrow_down_rounded, color: textSec),
                        ],
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                _statusPill(
                  label: "Accepted",
                  selected: _showAccepted,
                  activeColor: Colors.green,
                  onTap: () => setState(() => _showAccepted = !_showAccepted),
                ),
                const SizedBox(width: 8),
                _statusPill(
                  label: "Rejected",
                  selected: _showRejected,
                  activeColor: Colors.red,
                  onTap: () => setState(() => _showRejected = !_showRejected),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // List
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                  ? Center(
                child: Text(
                  "No results found",
                  style: GoogleFonts.inter(color: textSec, fontWeight: FontWeight.w600),
                ),
              )
                  : ListView.builder(
                itemCount: list.length,
                itemBuilder: (_, i) => _loanCard(list[i]),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
