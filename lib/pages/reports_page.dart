import 'dart:math';
import 'dart:ui';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:fl_chart/fl_chart.dart';
import '../services/api.dart';
import 'loan_detail_page.dart';
import 'package:loan2/widgets/officer_nav_bar.dart';

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
  static const _accent = Color(0xFF1E5AA8);
  static const double _headerRadius = 25;

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

  // =========================
  // ONLY DATE PICKER CHANGED
  // =========================
  Future<void> _pickCustomRange() async {
    final now = DateTime.now();
    final initial = _customRange ??
        DateTimeRange(
          start: now.subtract(const Duration(days: 7)),
          end: now,
        );

    final picked = await showDialog<DateTimeRange>(
      context: context,
      barrierColor: Colors.black.withOpacity(0.28),
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

  Widget _tintedGlassCard({
    required Color tint,
    required Widget child,
    EdgeInsets padding = const EdgeInsets.all(16),
  }) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(18),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
        child: Container(
          padding: padding,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
              colors: [
                tint.withOpacity(0.34),
                Colors.white.withOpacity(0.20),
              ],
            ),
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
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 9),
              decoration: BoxDecoration(
                color: active ? Colors.black.withOpacity(0.06) : Colors.white.withOpacity(0.32),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: Colors.white.withOpacity(0.40)),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withOpacity(0.05),
                    blurRadius: 14,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Text(
                text,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  fontSize: 12.5,
                  color: Colors.black87,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _statusPill(String label, bool selected, Color activeColor, VoidCallback onTap) {
    final fill = selected ? activeColor.withOpacity(0.18) : Colors.white.withOpacity(0.20);
    final border = selected ? activeColor.withOpacity(0.28) : Colors.white.withOpacity(0.40);
    final txt = selected ? activeColor : Colors.black87;

    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 16, sigmaY: 16),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            onTap: onTap,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    fill,
                    Colors.white.withOpacity(0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(color: border, width: 1.2),
                boxShadow: [
                  BoxShadow(
                    color: activeColor.withOpacity(selected ? 0.10 : 0.04),
                    blurRadius: 18,
                    offset: const Offset(0, 12),
                  ),
                ],
              ),
              child: Text(
                label,
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w900,
                  color: txt,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _kpiGlass(String title, String value, IconData icon, Color tint) {
    return Expanded(
      child: _tintedGlassCard(
        tint: tint,
        child: Row(
          children: [
            Container(
              height: 42,
              width: 42,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                  colors: [
                    tint.withOpacity(0.35),
                    Colors.white.withOpacity(0.10),
                  ],
                ),
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.white.withOpacity(0.35)),
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

  Widget _miniGlassChip(String label, Color base) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(999),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
          decoration: BoxDecoration(
            color: base.withOpacity(0.14),
            borderRadius: BorderRadius.circular(999),
            border: Border.all(color: base.withOpacity(0.28), width: 1.1),
          ),
          child: Text(
            label,
            style: GoogleFonts.inter(fontWeight: FontWeight.w900, color: base),
          ),
        ),
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
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(_headerRadius)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: _loadFromApi,
        backgroundColor: _accent,
        foregroundColor: Colors.white,
        elevation: 2,
        child: const Icon(Icons.refresh_rounded),
      ),
      body: _loading
          ? Center(child: CircularProgressIndicator(color: _accent))
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
              ClipRRect(
                borderRadius: BorderRadius.circular(30),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 14, sigmaY: 14),
                  child: InkWell(
                    borderRadius: BorderRadius.circular(30),
                    onTap: _openSchemeFilter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.32),
                        borderRadius: BorderRadius.circular(30),
                        border: Border.all(color: Colors.white.withOpacity(0.42)),
                      ),
                      child: Row(
                        children: [
                          const Icon(Icons.tune_rounded, size: 18, color: Colors.black87),
                          const SizedBox(width: 8),
                          Text(
                            _selectedSchemes.isEmpty ? "Loan" : "Loan (${_selectedSchemes.length})",
                            style: GoogleFonts.inter(fontWeight: FontWeight.w900),
                          ),
                          const Spacer(),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.black45),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              Align(
                alignment: Alignment.center,
                child: Wrap(
                  alignment: WrapAlignment.center,
                  runAlignment: WrapAlignment.center,
                  spacing: 10,
                  runSpacing: 10,
                  children: [
                    _statusPill("Accepted", _showAccepted, const Color(0xFF1F9D55), () => setState(() => _showAccepted = !_showAccepted)),
                    _statusPill("Rejected", _showRejected, const Color(0xFFE11D48), () => setState(() => _showRejected = !_showRejected)),
                    _statusPill("Pending", _showPending, const Color(0xFFB45309), () => setState(() => _showPending = !_showPending)),
                  ],
                ),
              ),
              const SizedBox(height: 18),
              _sectionTitle("Performance Overview"),
              const SizedBox(height: 12),
              Row(
                children: [
                  _kpiGlass("Total Applications", total.toString(), Icons.folder_copy_outlined, const Color(0xFFFFD7C2)),
                  const SizedBox(width: 12),
                  _kpiGlass("Approval Rate", "${(approvalRate * 100).toStringAsFixed(0)}%", Icons.task_alt, const Color(0xFFE9DDFF)),
                ],
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  _kpiGlass("Pending", pending.toString(), Icons.hourglass_empty_rounded, const Color(0xFFFFF0B8)),
                  const SizedBox(width: 12),
                  _kpiGlass("Verified Amount", "₹${_fmtCompact(verifiedAmount)}", Icons.currency_rupee_rounded, const Color(0xFFD7F5E6)),
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
                                  style: GoogleFonts.inter(fontSize: 11.5, fontWeight: FontWeight.w900, color: Colors.black87),
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
                              GoogleFonts.inter(fontWeight: FontWeight.w900, color: Colors.white, fontSize: 12),
                              children: [
                                TextSpan(
                                  text: "$val applications",
                                  style: GoogleFonts.inter(fontWeight: FontWeight.w800, color: Colors.white.withOpacity(0.9), fontSize: 11.5),
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
                              color: Colors.green.withOpacity(0.78),
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
                Column(children: recent8.map(_activityTile).toList()),
            ],
          ),
        ),
      ),
      bottomNavigationBar: OfficerNavBar(currentIndex: 3, officerId: widget.officerId),
    );
  }

  Widget _activityTile(_LoanRow l) {
    final st = l.status.trim().toLowerCase();
    final isVerified = st == "verified";
    final isRejected = st == "rejected";

    IconData icon;
    String label;
    Color chipColor;

    if (isVerified) {
      icon = Icons.check_circle_rounded;
      label = "accepted";
      chipColor = const Color(0xFF1F9D55);
    } else if (isRejected) {
      icon = Icons.cancel_rounded;
      label = "rejected";
      chipColor = const Color(0xFFE11D48);
    } else {
      icon = Icons.hourglass_bottom_rounded;
      label = "pending";
      chipColor = const Color(0xFFB45309);
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
              _miniGlassChip(label, chipColor),
            ],
          ),
        ),
      ),
    );
  }
}

// =========================
// Fancy month-only range picker (square, arrows, no pencil)
// =========================
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

  String _monthTitle(DateTime m) => "${_months[m.month - 1]} ${m.year}";

  DateTime _addMonths(DateTime m, int delta) {
    final y = m.year + ((m.month - 1 + delta) ~/ 12);
    final mm = ((m.month - 1 + delta) % 12) + 1;
    return DateTime(y, mm, 1);
  }

  bool _canGoPrev() {
    final prev = _addMonths(_month, -1);
    final prevEnd = DateTime(prev.year, prev.month, DateUtils.getDaysInMonth(prev.year, prev.month));
    return !_dateOnly(prevEnd).isBefore(_dateOnly(widget.firstDate));
  }

  bool _canGoNext() {
    final next = _addMonths(_month, 1);
    final nextStart = DateTime(next.year, next.month, 1);
    return !_dateOnly(nextStart).isAfter(_dateOnly(widget.lastDate));
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
    final daysInMonth = DateUtils.getDaysInMonth(_month.year, _month.month);

    // Sunday-first grid
    final offset = first.weekday % 7; // Sun=0, Mon=1...Sat=6
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
                colors: [
                  Colors.white.withOpacity(0.82),
                  Colors.white.withOpacity(0.62),
                ],
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
                  // Top row: title + actions
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          "Select Range",
                          style: GoogleFonts.poppins(fontSize: 14.5, fontWeight: FontWeight.w800, color: Colors.black87),
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

                  // Month header with arrows
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.white.withOpacity(0.55),
                      border: Border.all(color: Colors.black.withOpacity(0.06)),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        IconButton(
                          onPressed: _canGoPrev()
                              ? () => setState(() => _month = _addMonths(_month, -1))
                              : null,
                          icon: const Icon(Icons.chevron_left_rounded),
                        ),
                        Expanded(
                          child: Center(
                            child: Text(
                              _monthTitle(_month),
                              style: GoogleFonts.poppins(fontSize: 15.5, fontWeight: FontWeight.w900, color: Colors.black87),
                            ),
                          ),
                        ),
                        IconButton(
                          onPressed: _canGoNext()
                              ? () => setState(() => _month = _addMonths(_month, 1))
                              : null,
                          icon: const Icon(Icons.chevron_right_rounded),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 10),

                  // Weekday labels
                  Row(
                    children: const [
                      _W("Su"), _W("Mo"), _W("Tu"), _W("We"), _W("Th"), _W("Fr"), _W("Sa")
                    ],
                  ),
                  const SizedBox(height: 8),

                  // Grid
                  AspectRatio(
                    aspectRatio: 7 / 6,
                    child: GridView.builder(
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: 42,
                      gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                        crossAxisCount: 7,
                        mainAxisSpacing: 6,
                        crossAxisSpacing: 6,
                      ),
                      itemBuilder: (ctx, i) {
                        final d = cells[i];
                        final inMonth = d.month == _month.month;
                        final selectable = _isSelectable(d);
                        final inRange = _inRange(d);
                        final isStart = _isStart(d);
                        final isEnd = _isEnd(d);

                        Color? bg;
                        Border? border;
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
                          border = null;
                        }


                        return InkWell(
                          borderRadius: BorderRadius.circular(10),
                          onTap: selectable ? () => _onTapDay(d) : null,
                          child: Container(
                            decoration: BoxDecoration(
                              color: bg,
                              border: border,
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

                  // Range readout (small)
                  Row(
                    children: [
                      Expanded(
                        child: _RangePill(
                          label: "Start",
                          value: _start == null ? "--" : _fmt(_start!),
                          accent: accent,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: _RangePill(
                          label: "End",
                          value: (_end ?? _start) == null ? "--" : _fmt((_end ?? _start)!),
                          accent: accent,
                        ),
                      ),
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
    const m = [
      "Jan","Feb","Mar","Apr","May","Jun",
      "Jul","Aug","Sep","Oct","Nov","Dec"
    ];
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
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            color: Colors.black54,
            fontSize: 12,
          ),
        ),
      ),
    );
  }
}

class _RangePill extends StatelessWidget {
  final String label;
  final String value;
  final Color accent;

  const _RangePill({
    required this.label,
    required this.value,
    required this.accent,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white.withOpacity(0.55),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.black.withOpacity(0.06)),
      ),
      child: Row(
        children: [
          Container(
            height: 10,
            width: 10,
            decoration: BoxDecoration(
              color: accent.withOpacity(0.85),
              borderRadius: BorderRadius.circular(3),
            ),
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