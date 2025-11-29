import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import '../services/api.dart';
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

  @override
  void initState() {
    super.initState();
    _load();
    _q.addListener(() {
      if (!mounted) return;
      setState(() {});
    });
  }

  @override
  void dispose() {
    _q.dispose();
    super.dispose();
  }

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
    const batchSize = 8;
    for (int i = 0; i < loans.length; i += batchSize) {
      final chunk = loans.sublist(i, min(i + batchSize, loans.length));
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
    }
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    try {
      final results = await Future.wait([
        _fetchList("verified"),
        _fetchList("rejected"),
      ]);
      _all = <_LoanRow>[...results[0], ...results[1]];
      if (!mounted) return;
      setState(() => _loading = false);

      await _attachSchemesAndPurposeInBatches(_all);
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
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
                      activeColor: const Color(0xFFFF9933),
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
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
              ),
            );
          },
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
    return InkWell(
      borderRadius: BorderRadius.circular(14),
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        decoration: BoxDecoration(
          color: selected ? activeColor : Colors.white,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: selected ? activeColor : Colors.grey.shade300),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.03),
              blurRadius: 10,
              offset: const Offset(0, 4),
            )
          ],
        ),
        child: Text(
          label,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w700,
            color: selected ? Colors.white : Colors.black87,
          ),
        ),
      ),
    );
  }

  Widget _loanCard(_LoanRow l) {
    final isVerified = l.status.toLowerCase() == "verified";

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
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 14,
              offset: const Offset(0, 6),
            )
          ],
          border: Border.all(color: Colors.grey.shade200),
        ),
        child: Row(
          children: [
            Container(
              height: 44,
              width: 44,
              decoration: BoxDecoration(
                color: const Color(0xFFFF9933).withValues(alpha: 0.12),
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
                    style: GoogleFonts.poppins(fontWeight: FontWeight.w700, fontSize: 15),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Text(
                    "ID: ${l.loanId}  •  ₹${l.amount.toStringAsFixed(0)}  •  ${l.loanType}",
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[700]),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Text(
                    "Applied: ${l.dateApplied}${l.scheme.isNotEmpty ? "  •  ${l.scheme}" : ""}",
                    style: GoogleFonts.inter(fontSize: 12.5, color: Colors.grey[700]),
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
                color: (isVerified ? Colors.green : Colors.red).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(999),
                border: Border.all(
                  color: (isVerified ? Colors.green : Colors.red).withValues(alpha: 0.25),
                ),
              ),
              child: Text(
                isVerified ? "accepted" : "rejected",
                style: GoogleFonts.inter(
                  fontWeight: FontWeight.w800,
                  color: isVerified ? Colors.green[800] : Colors.red[700],
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
    final list = _filtered;

    return Scaffold(
      backgroundColor: const Color(0xFFF8F9FA),
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
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: Colors.grey.shade200),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.03),
                    blurRadius: 10,
                    offset: const Offset(0, 4),
                  )
                ],
              ),
              child: Row(
                children: [
                  Icon(Icons.search_rounded, color: Colors.grey[600]),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: _q,
                      decoration: InputDecoration(
                        hintText: "Search by name / loan id / type...",
                        hintStyle: GoogleFonts.inter(color: Colors.grey[500]),
                        border: InputBorder.none,
                      ),
                    ),
                  ),
                  if (_q.text.isNotEmpty)
                    IconButton(
                      onPressed: () => _q.clear(),
                      icon: const Icon(Icons.close_rounded),
                      color: Colors.grey[600],
                    ),
                ],
              ),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Expanded(
                  child: InkWell(
                    borderRadius: BorderRadius.circular(14),
                    onTap: _openLoanFilter,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: Colors.grey.shade300),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.03),
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
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700),
                          ),
                          const Spacer(),
                          const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.grey),
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
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : list.isEmpty
                  ? Center(
                child: Text(
                  "No results found",
                  style: GoogleFonts.inter(color: Colors.grey[600], fontWeight: FontWeight.w600),
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