// lib/pages/history_page.dart
//
// Verification History (beneficiary)
// Blue header with back-to-dashboard, search, filters, and list.
// 2025-12-01

import 'dart:async';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:intl/intl.dart';

import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:loan2/models/beneficiary_loan.dart';
// ❌ removed: import 'package:loan2/navigation_utils.dart';

/// Flattened entry used by the UI
class _HistoryEntry {
  final String loanId;
  final String userId;
  final String stepId;
  final int processId;
  final String stepName;
  final String status; // pending / verified / rejected / etc
  final String? timestamp;
  final String? utilizationAmount;
  final String? mediaUrl;

  _HistoryEntry({
    required this.loanId,
    required this.userId,
    required this.stepId,
    required this.processId,
    required this.stepName,
    required this.status,
    this.timestamp,
    this.utilizationAmount,
    this.mediaUrl,
  });
}

class VerificationHistoryPage extends StatefulWidget {
  final String userId;
  final String title;
  const VerificationHistoryPage({
    super.key,
    required this.userId,
    this.title = "Verification History",
  });

  @override
  State<VerificationHistoryPage> createState() => _VerificationHistoryPageState();
}

class _VerificationHistoryPageState extends State<VerificationHistoryPage> {
  final BeneficiaryService _service = BeneficiaryService();

  bool _loading = true;
  bool _refreshing = false;

  List<BeneficiaryLoan> _loans = [];
  List<_HistoryEntry> _allEntries = [];
  List<_HistoryEntry> _visibleEntries = [];

  // search / filters
  final TextEditingController _searchController = TextEditingController();
  String _query = "";
  String _statusFilter = "all"; // all | pending | verified | rejected
  DateTimeRange? _dateRange;

  Timer? _debounce;
  final DateFormat _displayDate = DateFormat('dd MMM yyyy, HH:mm');

  @override
  void initState() {
    super.initState();
    _fetchHistory();

    // keep live with sync/online events
    SyncService.onSync.listen((_) => _fetchHistory(showLoading: false));
    SyncService.onOnlineStatusChanged.listen((_) => _fetchHistory(showLoading: false));
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  // ---------------- navigation helper (replaces missing goToDashboard) ----------------
  void goToDashboard(BuildContext context, String userId) {
    // Prefer pop if we have a back stack; otherwise send to a known route.
    if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    } else {
      Navigator.of(context).pushNamedAndRemoveUntil(
        '/dashboard',
            (route) => false,
        arguments: {'userId': userId},
      );
    }
  }

  // ---------------- data ----------------

  Future<void> _fetchHistory({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final data = await _service.fetchUserLoans(widget.userId);
      _loans = data.where((l) => (l.userId ?? "").trim() == widget.userId.trim()).toList();
      _allEntries = _flattenLoansToEntries(_loans);
      _applyFilters();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to load history: $e")),
      );
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_HistoryEntry> _flattenLoansToEntries(List<BeneficiaryLoan> loans) {
    final out = <_HistoryEntry>[];
    for (final loan in loans) {
      for (final s in loan.processes) {
        // Try common timestamp fields dynamically (don’t depend on typed fields)
        String? ts;
        try {
          final d = s as dynamic;
          for (final c in [d.updatedAt, d.timestamp, d.createdAt, d.date]) {
            if (c != null) {
              ts = c.toString();
              break;
            }
          }
        } catch (_) {
          ts = null;
        }
        ts ??= loan.dateApplied;

        out.add(_HistoryEntry(
          loanId: loan.loanId ?? '',
          userId: loan.userId ?? widget.userId,
          stepId: s.id,
          processId: s.processId,
          // ✅ ensure non-null String for stepName
          stepName: ((s.whatToDo ?? '').isEmpty) ? 'Step ${s.processId}' : (s.whatToDo ?? ''),
          status: (s.status ?? 'pending').toString().toLowerCase(),
          timestamp: ts,
          utilizationAmount: s.utilizationAmount?.toString(),
          mediaUrl: s.mediaUrl,
        ));
      }
    }

    // Sort newest first
    out.sort((a, b) {
      final da = _parseDate(a.timestamp);
      final db = _parseDate(b.timestamp);
      if (da != null && db != null) return db.compareTo(da);
      if (da != null) return -1;
      if (db != null) return 1;
      final ri = b.loanId.compareTo(a.loanId);
      return ri != 0 ? ri : (b.processId - a.processId);
    });
    return out;
  }

  DateTime? _parseDate(String? s) {
    if (s == null) return null;
    try {
      final d = DateTime.tryParse(s);
      if (d != null) return d;
      final epoch = int.tryParse(s);
      if (epoch != null) {
        return epoch > 9999999999
            ? DateTime.fromMillisecondsSinceEpoch(epoch)
            : DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
      }
    } catch (_) {}
    return null;
  }

  // ---------------- filters/search ----------------

  void _applyFilters() {
    final q = _query.trim().toLowerCase();
    final status = _statusFilter;
    final range = _dateRange;

    final filtered = _allEntries.where((e) {
      // status
      if (status != 'all') {
        if (status == 'pending' &&
            e.status != 'pending' &&
            e.status != 'in_progress' &&
            e.status != 'submitted') return false;
        if (status == 'verified' &&
            e.status != 'verified' &&
            e.status != 'accepted' &&
            e.status != 'completed') return false;
        if (status == 'rejected' &&
            e.status != 'rejected' &&
            e.status != 'failed') return false;
      }

      // search term: loan id, step name, amount
      if (q.isNotEmpty) {
        final inLoan = e.loanId.toLowerCase().contains(q);
        final inStep = e.stepName.toLowerCase().contains(q);
        final inAmt  = (e.utilizationAmount ?? '').toLowerCase().contains(q);
        if (!(inLoan || inStep || inAmt)) return false;
      }

      // date range
      if (range != null) {
        final dt = _parseDate(e.timestamp);
        if (dt == null) return false;
        if (dt.isBefore(range.start) || dt.isAfter(range.end.add(const Duration(days: 1)))) {
          return false;
        }
      }
      return true;
    }).toList();

    if (mounted) setState(() => _visibleEntries = filtered);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 300), () {
      _query = v;
      _applyFilters();
    });
  }

  void _setStatusFilter(String f) {
    setState(() => _statusFilter = f);
    _applyFilters();
  }

  Future<void> _pickDateRange() async {
    final now = DateTime.now();
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 3),
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(textTheme: GoogleFonts.interTextTheme(Theme.of(ctx).textTheme)),
        child: child ?? const SizedBox(),
      ),
    );
    if (picked != null) {
      setState(() => _dateRange = picked);
      _applyFilters();
    }
  }

  void _clearDateRange() {
    setState(() => _dateRange = null);
    _applyFilters();
  }

  Future<void> _onRefresh() async {
    setState(() => _refreshing = true);
    await _fetchHistory(showLoading: false);
    if (mounted) setState(() => _refreshing = false);
  }

  // ---------------- UI ----------------

  Color _statusColor(String s) {
    final k = s.toLowerCase();
    if (k.contains('ver') || k.contains('accept') || k.contains('complete')) return Colors.green;
    if (k.contains('rej') || k.contains('fail')) return Colors.red;
    return Colors.orange;
  }

  Widget _header() {
    return Container(
      padding: EdgeInsets.only(
        top: MediaQuery.of(context).padding.top + 12,
        left: 16,
        right: 8,
        bottom: 16,
      ),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [Color(0xFF1F6FEB), Color(0xFF2757D6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.vertical(bottom: Radius.circular(20)),
      ),
      child: Column(
        children: [
          Row(
            children: [
              IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: () => goToDashboard(context, widget.userId),
              ),
              Expanded(
                child: Text(
                  widget.title,
                  textAlign: TextAlign.center,
                  style: GoogleFonts.inter(color: Colors.white, fontSize: 18, fontWeight: FontWeight.w800),
                ),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Colors.white),
                onPressed: () => _fetchHistory(showLoading: false),
              ),
            ],
          ),
          const SizedBox(height: 12),
          // Search bar inside the blue header
          Container(
            height: 52,
            padding: const EdgeInsets.symmetric(horizontal: 14),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.10), blurRadius: 12, offset: const Offset(0, 6))],
            ),
            child: Row(
              children: [
                const Icon(Icons.search, color: Color(0xFF6B7C9A)),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _searchController,
                    onChanged: _onSearchChanged,
                    decoration: const InputDecoration(
                      hintText: "Search loan id, step or amount",
                      border: InputBorder.none,
                    ),
                  ),
                ),
                if (_searchController.text.isNotEmpty)
                  IconButton(
                    icon: const Icon(Icons.clear, color: Color(0xFF6B7C9A)),
                    onPressed: () {
                      _searchController.clear();
                      _onSearchChanged('');
                    },
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _filtersRow() {
    final chips = const [
      {'k': 'all', 'label': 'All'},
      {'k': 'pending', 'label': 'Pending'},
      {'k': 'verified', 'label': 'Accepted'},
      {'k': 'rejected', 'label': 'Rejected'},
    ];

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      padding: const EdgeInsets.fromLTRB(12, 12, 12, 8),
      child: Row(
        children: [
          ...chips.map((c) {
            final key = c['k']!;
            final active = _statusFilter == key;
            return Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ChoiceChip(
                label: Text(c['label']!, style: GoogleFonts.inter(fontWeight: FontWeight.w600)),
                selected: active,
                onSelected: (_) => _setStatusFilter(key),
                selectedColor: Colors.blue.shade50,
                backgroundColor: Colors.grey.shade100,
                labelPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
              ),
            );
          }),
          const SizedBox(width: 6),
          GestureDetector(
            onTap: _pickDateRange,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)],
              ),
              child: Row(
                children: [
                  const Icon(Icons.date_range_outlined, size: 18, color: Colors.black87),
                  const SizedBox(width: 8),
                  Text(
                    _dateRange == null
                        ? 'Date range'
                        : '${DateFormat('dd MMM').format(_dateRange!.start)} — ${DateFormat('dd MMM').format(_dateRange!.end)}',
                    style: GoogleFonts.inter(fontSize: 13),
                  ),
                  if (_dateRange != null)
                    GestureDetector(
                      onTap: _clearDateRange,
                      child: Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Icon(Icons.close, size: 16, color: Colors.grey[600]),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _entryCard(_HistoryEntry e) {
    final dt = _parseDate(e.timestamp);
    final dtText = dt != null ? _displayDate.format(dt.toLocal()) : (e.timestamp ?? '—');

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 6))],
      ),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Container(width: 6, height: 64, decoration: BoxDecoration(color: _statusColor(e.status), borderRadius: BorderRadius.circular(6))),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text(e.stepName, style: GoogleFonts.inter(fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _statusColor(e.status).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(e.status.toUpperCase(),
                    style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(e.status))),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.receipt_long, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text('Loan: ${e.loanId}', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[800])),
              const SizedBox(width: 12),
              if ((e.utilizationAmount ?? '').isNotEmpty)
                Row(children: [
                  Icon(Icons.currency_rupee, size: 14, color: Colors.grey[600]),
                  const SizedBox(width: 4),
                  Text(e.utilizationAmount!, style: GoogleFonts.inter(fontSize: 13)),
                ]),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(dtText, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
            ]),
            if ((e.mediaUrl ?? '').isNotEmpty) ...[
              const SizedBox(height: 8),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: Image.network(
                    e.mediaUrl!,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) =>
                        Container(color: Colors.grey[100], alignment: Alignment.center, child: const Icon(Icons.broken_image)),
                  ),
                ),
              ),
            ],
          ]),
        ),
      ]),
    );
  }

  Widget _body() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: ListView(
        physics: const AlwaysScrollableScrollPhysics(parent: BouncingScrollPhysics()),
        children: [
          _filtersRow(),
          if (_refreshing) const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: LinearProgressIndicator(),
          ),
          const SizedBox(height: 6),
          if (_visibleEntries.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 40),
              child: Center(child: Text("No records match your filters", style: GoogleFonts.inter(color: Colors.grey[600]))),
            )
          else
            ..._visibleEntries.map(_entryCard),
          const SizedBox(height: 24),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: Theme.of(context).copyWith(textTheme: GoogleFonts.interTextTheme(Theme.of(context).textTheme)),
      child: Scaffold(
        backgroundColor: const Color(0xFFF6F9FC),
        // No AppBar (to avoid duplicate title) — we use the blue header instead
        body: Column(
          children: [
            _header(),
            Expanded(child: _body()),
          ],
        ),
      ),
    );
  }
}
