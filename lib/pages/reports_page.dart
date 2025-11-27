import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api.dart';
import 'loan_detail_page.dart';

class ReportsPage extends StatefulWidget {
  final String officerId;
  const ReportsPage({super.key, required this.officerId});

  @override
  State<ReportsPage> createState() => _ReportsPageState();
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
}

enum _RangePick { today, week, month, all, custom }

class _ReportsPageState extends State<ReportsPage> {
  static const _bg = Color(0xFFF6F7FB);
  static const _accent = Color(0xFFFF9933);

  bool _loading = true;

  final Set<String> _selectedSchemes = {};
  bool _showAccepted = true;
  bool _showRejected = true;
  bool _showPending = true;

  _RangePick _rangePick = _RangePick.week;
  DateTimeRange? _customRange;

  final List<_LoanRow> _all = [];
  static const List<String> _schemeOptions = ["NBCFDC", "NSFDC", "NSKFDC"];

  @override
  void initState() {
    super.initState();
    _loadFromApi();
  }

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
    final s = st.trim().toLowerCase();

    // if none selected => show ALL (as per your requirement)
    if (!_showAccepted && !_showRejected && !_showPending) return true;

    if (_showAccepted && s == "verified") return true;
    if (_showRejected && s == "rejected") return true;
    if (_showPending && (s == "not verified" || s == "pending")) return true;

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
      list.where((l) => l.status.toLowerCase() == status).length;

  double _sumAmount(List<_LoanRow> list, String status) {
    return list
        .where((l) => l.status.toLowerCase() == status)
        .fold<double>(0, (p, e) => p + e.amount);
  }

  String _fmtCompact(num v) {
    if (v >= 10000000) return "${(v / 10000000).toStringAsFixed(1)}Cr";
    if (v >= 100000) return "${(v / 100000).toStringAsFixed(1)}L";
    if (v >= 1000) return "${(v / 1000).toStringAsFixed(1)}K";
    return v.toStringAsFixed(0);
  }

  Future<List<_LoanRow>> _fetchList(String status) async {
    final res = await getJson("bank/loans?officer_id=${widget.officerId}&status=$status");

    final List items = (res["data"] ?? []) as List;

    return items.map((e) {
      return _LoanRow(
        loanId: (e["loan_id"] ?? "").toString(),
        applicantName: (e["applicant_name"] ?? "Beneficiary").toString(),
        amount: (e["amount"] is num) ? (e["amount"] as num).toDouble() : 0.0,
        loanType: (e["loan_type"] ?? "Loan").toString(),
        status: (e["status"] ?? status).toString(),
        dateApplied: (e["date_applied"] ?? "2000-01-01").toString(),
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
    const batchSize = 8;
    for (int i = 0; i < loans.length; i += batchSize) {
      final chunk = loans.sublist(i, min(i + batchSize, loans.length));
      await Future.wait(chunk.map((l) async {
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
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );

    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime(now.year + 1),
      initialDateRange: initial,
    );

    if (picked == null) return;
    setState(() {
      _customRange = picked;
      _rangePick = _RangePick.custom;
    });
  }

  void _openSchemeFilter() {
    final temp = Set<String>.from(_selectedSchemes);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (ctx) {
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
                      color: Colors.black12,
                      borderRadius: BorderRadius.circular(10),
                    ),
                  ),
                  const SizedBox(height: 14),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      "Loan Schemes",
                      style: GoogleFonts.poppins(fontSize: 16, fontWeight: FontWeight.w700),
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
                      title: Text(s, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
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
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: Text("Clear", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                            elevation: 0,
                          ),
                          child: Text("Apply", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
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

  Widget _glassCard({required Widget child, EdgeInsets padding = const EdgeInsets.all(16)}) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            color: Colors.white.withOpacity(0.55),
            borderRadius: BorderRadius.circular(18),
            border: Border.all(color: Colors.white.withOpacity(0.35)),
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.06),
                blurRadius: 18,
                offset: const Offset(0, 10),
              )
            ],
          ),
          child: child,
        ),
      ),
    );
  }

  Widget _pillChip(String text, bool active, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
        decoration: BoxDecoration(
          color: active ? Colors.black.withOpacity(0.08) : Colors.white.withOpacity(0.45),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(color: Colors.black.withOpacity(0.08)),
        ),
        child: Text(
          text,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            fontSize: 12.5,
            color: Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String label, bool selected, Color activeColor, VoidCallback onTap) {
    return InkWell(
      borderRadius: BorderRadius.circular(30),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white.withOpacity(0.45),
          borderRadius: BorderRadius.circular(30),
          border: Border.all(
            color: selected ? activeColor : Colors.black.withOpacity(0.08),
          ),
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _kpiGlass(String title, String value, IconData icon) {
    return Expanded(
      child: _glassCard(
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                color: Colors.black.withOpacity(0.06),
                borderRadius: BorderRadius.circular(14),
              ),
              child: Icon(icon, color: Colors.black87, size: 20),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(value, style: GoogleFonts.poppins(fontSize: 18, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 2),
                  Text(
                    title,
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.black54, fontWeight: FontWeight.w600),
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
        color: Colors.black87,
      ),
    );
  }

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
    final recent8 = recent.take(8).toList();

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
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadFromApi,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 2,
        child: const Icon(Icons.refresh_rounded),
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.white.withOpacity(0.70), _bg],
          ),
        ),
        child: SingleChildScrollView(
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
                    _pillChip("Today", _rangePick == _RangePick.today, () => setState(() => _rangePick = _RangePick.today)),
                    const SizedBox(width: 8),
                    _pillChip("7 Days", _rangePick == _RangePick.week, () => setState(() => _rangePick = _RangePick.week)),
                    const SizedBox(width: 8),
                    _pillChip("30 Days", _rangePick == _RangePick.month, () => setState(() => _rangePick = _RangePick.month)),
                    const SizedBox(width: 8),
                    _pillChip("All", _rangePick == _RangePick.all, () => setState(() => _rangePick = _RangePick.all)),
                    const SizedBox(width: 8),
                    _pillChip("Custom", _rangePick == _RangePick.custom, _pickCustomRange),
                  ],
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                borderRadius: BorderRadius.circular(30),
                onTap: _openSchemeFilter,
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.white.withOpacity(0.50),
                    borderRadius: BorderRadius.circular(30),
                    border: Border.all(color: Colors.black.withOpacity(0.08)),
                  ),
                  child: Row(
                    children: [
                      const Icon(Icons.tune_rounded, size: 18, color: Colors.black87),
                      const SizedBox(width: 8),
                      Text(
                        _selectedSchemes.isEmpty ? "Loan" : "Loan (${_selectedSchemes.length})",
                        style: GoogleFonts.inter(fontWeight: FontWeight.w800),
                      ),
                      const Spacer(),
                      const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black45),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  _statusPill("Accepted", _showAccepted, const Color(0xFF1F9D55), () => setState(() => _showAccepted = !_showAccepted)),
                  _statusPill("Rejected", _showRejected, const Color(0xFFE11D48), () => setState(() => _showRejected = !_showRejected)),
                  _statusPill("Pending", _showPending, const Color(0xFFB45309), () => setState(() => _showPending = !_showPending)),
                ],
              ),

              const SizedBox(height: 18),
              _sectionTitle("Performance Overview"),
              const SizedBox(height: 12),
              Row(
                children: [
                  _kpiGlass("Total Applications", total.toString(), Icons.folder_copy_outlined),
                  const SizedBox(width: 12),
                  _kpiGlass("Approval Rate", "${(approvalRate * 100).toStringAsFixed(0)}%", Icons.task_alt),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _kpiGlass("Pending", pending.toString(), Icons.hourglass_empty_rounded),
                  const SizedBox(width: 12),
                  _kpiGlass("Verified Amount", "₹${_fmtCompact(verifiedAmount)}", Icons.currency_rupee_rounded),
                ],
              ),

              const SizedBox(height: 18),
              _sectionTitle("Scheme Breakdown (Bar Graph)"),
              const SizedBox(height: 12),
              _glassCard(
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
                                style: GoogleFonts.inter(fontSize: 10.5, color: Colors.black54, fontWeight: FontWeight.w600),
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
                                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w800, color: Colors.black87),
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
                          getTooltipItem: (group, groupIndex, rod, rodIndex) {
                            final i = group.x.toInt();
                            final name = (i >= 0 && i < _schemeOptions.length) ? _schemeOptions[i] : "Scheme";
                            final val = rod.toY.toInt();
                            return BarTooltipItem(
                              "$name\n",
                              GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.white, fontSize: 12),
                              children: [
                                TextSpan(
                                  text: "$val applications",
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.white.withOpacity(0.9), fontSize: 11.5),
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
                              color: Colors.green,
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
                _glassCard(
                  child: Center(
                    child: Text(
                      "No activity for this range",
                      style: GoogleFonts.inter(color: Colors.black54, fontWeight: FontWeight.w700),
                    ),
                  ),
                )
              else
                Column(
                  children: recent8.map(_activityTile).toList(),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _activityTile(_LoanRow l) {
    final st = l.status.trim().toLowerCase();
    final isVerified = st == "verified";
    final isRejected = st == "rejected";

    IconData icon;
    String label;
    Color chipBg;

    if (isVerified) {
      icon = Icons.check_circle_rounded;
      label = "Accepted";
      chipBg = const Color(0xFF1F9D55);
    } else if (isRejected) {
      icon = Icons.cancel_rounded;
      label = "Rejected";
      chipBg = const Color(0xFFE11D48);
    } else {
      icon = Icons.hourglass_bottom_rounded;
      label = "Pending";
      chipBg = const Color(0xFFB45309);
    }

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
        child: _glassCard(
          padding: const EdgeInsets.all(14),
          child: Row(
            children: [
              Container(
                height: 44,
                width: 44,
                decoration: BoxDecoration(
                  color: Colors.black.withOpacity(0.06),
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Icon(icon, color: Colors.black87, size: 22),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l.applicantName.isEmpty ? "Beneficiary" : l.applicantName,
                      style: GoogleFonts.poppins(fontWeight: FontWeight.w800, fontSize: 14.5),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 3),
                    Text(
                      "Loan: ${l.loanId}  •  ₹${l.amount.toStringAsFixed(0)}  •  ${l.scheme.isNotEmpty ? l.scheme : l.loanType}",
                      style: GoogleFonts.inter(fontSize: 12.2, color: Colors.black54, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 2),
                    Text(
                      "Applied: ${l.dateApplied}",
                      style: GoogleFonts.inter(fontSize: 12.2, color: Colors.black54, fontWeight: FontWeight.w600),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 10),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
                decoration: BoxDecoration(
                  color: chipBg,
                  borderRadius: BorderRadius.circular(999),
                ),
                child: Text(
                  label,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.white),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
