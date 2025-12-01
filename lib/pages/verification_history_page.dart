// TODO Implement this library.// lib/pages/history_page.dart
//
// Verification History page
// - Lists all verification step records (flattened from loans -> processes)
// - Search, status filter chips (All / Pending / Verified / Rejected)
// - Date range picker filter
// - Pull-to-refresh which re-fetches from backend (integrated)
// - Matches app's visual style (Google Fonts Inter) and responsive layout
//
// Author: ChatGPT (UI + backend integration)
// Date: 2025-12-01

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/models/process_step.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:intl/intl.dart';

/// Simple flattened model used by this page
class _HistoryEntry {
  final String loanId;
  final String userId;
  final String stepId;
  final int processId;
  final String stepName;
  final String status; // pending / verified / rejected / other
  final String? timestamp; // server-provided or derived
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

/// Page
class VerificationHistoryPage extends StatefulWidget {
  final String userId;
  final String title;
  const VerificationHistoryPage({super.key, required this.userId, this.title = "Verification History"});

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
  String _query = "";
  String _statusFilter = "all"; // all | pending | verified | rejected
  DateTimeRange? _dateRange;

  // UI helpers
  final TextEditingController _searchController = TextEditingController();
  Timer? _debounce;

  // date format
  final DateFormat _displayDate = DateFormat('dd MMM yyyy, HH:mm');

  @override
  void initState() {
    super.initState();
    _fetchHistory();
    // re-fetch on sync events so backend-integrated updates reflect quickly
    SyncService.onSync.listen((_) => _fetchHistory());
    SyncService.onOnlineStatusChanged.listen((_) => _fetchHistory());
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _fetchHistory({bool showLoading = true}) async {
    if (showLoading && mounted) setState(() => _loading = true);
    try {
      final data = await _service.fetchUserLoans(widget.userId);
      // filter exact user id (defensive)
      final filtered = data.where((l) => (l.userId ?? "").trim() == widget.userId.trim()).toList();

      _loans = filtered;
      _allEntries = _flattenLoansToEntries(_loans);
      _applyFilters();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to load history: $e")));
      }
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  List<_HistoryEntry> _flattenLoansToEntries(List<BeneficiaryLoan> loans) {
    final out = <_HistoryEntry>[];
    for (final loan in loans) {
      final steps = loan.processes ?? [];
      for (final s in steps) {
        // try to extract a timestamp from step fields (common keys)
        String? ts;
        try {
          final dyn = s as dynamic;
          ts = (dyn.updatedAt ?? dyn.timestamp ?? dyn.createdAt ?? dyn.date ?? s.officerComment ?? null)?.toString();
        } catch (_) {
          ts = null;
        }

        // fallback: use loan.dateApplied as last resort
        ts ??= loan.dateApplied;

        out.add(_HistoryEntry(
          loanId: loan.loanId ?? '',
          userId: loan.userId ?? widget.userId,
          stepId: s.id,
          processId: s.processId,
          stepName: s.whatToDo ?? 'Step ${s.processId}',
          status: (s.status ?? 'pending').toString().toLowerCase(),
          timestamp: ts,
          utilizationAmount: s.utilizationAmount?.toString(),
          mediaUrl: s.mediaUrl,
        ));
      }
    }

    // sort descending by timestamp if possible, else by loan/process id
    out.sort((a, b) {
      final da = _parseDate(a.timestamp);
      final db = _parseDate(b.timestamp);
      if (da != null && db != null) return db.compareTo(da);
      if (da != null && db == null) return -1;
      if (da == null && db != null) return 1;
      // fallback to loanId + processId
      final ri = b.loanId.compareTo(a.loanId);
      if (ri != 0) return ri;
      return b.processId - a.processId;
    });

    return out;
  }

  DateTime? _parseDate(String? s) {
    if (s == null) return null;
    try {
      // try common formats: ISO or epoch string
      final d = DateTime.tryParse(s);
      if (d != null) return d;
      final epoch = int.tryParse(s);
      if (epoch != null) {
        // detect milliseconds vs seconds
        if (epoch > 9999999999) {
          return DateTime.fromMillisecondsSinceEpoch(epoch);
        } else {
          return DateTime.fromMillisecondsSinceEpoch(epoch * 1000);
        }
      }
    } catch (_) {}
    return null;
  }

  void _applyFilters() {
    final q = _query.trim().toLowerCase();
    final status = _statusFilter;
    final range = _dateRange;
    final List<_HistoryEntry> filtered = _allEntries.where((e) {
      // status
      if (status != 'all') {
        if (status == 'pending' && e.status != 'pending' && e.status != 'in_progress' && e.status != 'submitted') return false;
        if (status == 'verified' && e.status != 'verified' && e.status != 'accepted' && e.status != 'completed') return false;
        if (status == 'rejected' && e.status != 'rejected' && e.status != 'failed') return false;
      }

      // query (loan id, step name)
      if (q.isNotEmpty) {
        final inLoan = e.loanId.toLowerCase().contains(q);
        final inStep = e.stepName.toLowerCase().contains(q);
        final inAmount = (e.utilizationAmount ?? '').toLowerCase().contains(q);
        if (!(inLoan || inStep || inAmount)) return false;
      }

      // date range
      if (range != null) {
        final dt = _parseDate(e.timestamp);
        if (dt == null) return false;
        if (dt.isBefore(range.start) || dt.isAfter(range.end.add(const Duration(days: 1)))) return false;
      }

      return true;
    }).toList();

    if (mounted) setState(() => _visibleEntries = filtered);
  }

  void _onSearchChanged(String v) {
    _debounce?.cancel();
    _debounce = Timer(const Duration(milliseconds: 350), () {
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
    final first = DateTime(now.year - 3);
    final picked = await showDateRangePicker(
      context: context,
      firstDate: first,
      lastDate: DateTime(now.year + 1),
      initialDateRange: _dateRange ?? DateTimeRange(start: now.subtract(const Duration(days: 30)), end: now),
      builder: (ctx, child) {
        return Theme(data: Theme.of(ctx).copyWith(textTheme: GoogleFonts.interTextTheme(Theme.of(ctx).textTheme)), child: child ?? const SizedBox());
      },
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
    setState(() {
      _refreshing = true;
    });
    await _fetchHistory(showLoading: false);
    if (mounted) setState(() => _refreshing = false);
  }

  Color _statusColor(String s) {
    final key = s.toLowerCase();
    if (key.contains('ver') || key.contains('accept') || key.contains('complete')) return Colors.green;
    if (key.contains('rej') || key.contains('fail')) return Colors.red;
    return Colors.orange;
  }

  Widget _buildFiltersRow() {
    final chips = [
      {'k': 'all', 'label': 'All'},
      {'k': 'pending', 'label': 'Pending'},
      {'k': 'verified', 'label': 'Accepted'},
      {'k': 'rejected', 'label': 'Rejected'},
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(children: [
        const SizedBox(width: 8),
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
        }).toList(),
        const SizedBox(width: 6),
        // date range button
        GestureDetector(
          onTap: _pickDateRange,
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(10), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8)]),
            child: Row(children: [
              const Icon(Icons.date_range_outlined, size: 18, color: Colors.black87),
              const SizedBox(width: 8),
              Text(_dateRange == null ? 'Date range' : '${DateFormat('dd MMM').format(_dateRange!.start)} — ${DateFormat('dd MMM').format(_dateRange!.end)}', style: GoogleFonts.inter(fontSize: 13)),
              if (_dateRange != null)
                GestureDetector(
                  onTap: _clearDateRange,
                  child: Padding(
                    padding: const EdgeInsets.only(left: 8),
                    child: Icon(Icons.close, size: 16, color: Colors.grey[600]),
                  ),
                ),
            ]),
          ),
        ),
        const SizedBox(width: 12),
      ]),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 10)]),
      child: Row(children: [
        const Icon(Icons.search, color: Colors.grey),
        const SizedBox(width: 8),
        Expanded(
          child: TextField(
            controller: _searchController,
            onChanged: _onSearchChanged,
            decoration: InputDecoration(hintText: 'Search loan id, step or amount', border: InputBorder.none, isDense: true),
          ),
        ),
        IconButton(
          onPressed: () {
            _searchController.clear();
            _onSearchChanged('');
          },
          icon: const Icon(Icons.clear, color: Colors.grey),
        )
      ]),
    );
  }

  Widget _buildEntryCard(_HistoryEntry e) {
    final dt = _parseDate(e.timestamp);
    final dtText = dt != null ? _displayDate.format(dt.toLocal()) : (e.timestamp ?? '—');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8),
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0, 6))]),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        // left marker
        Container(
          width: 6,
          height: 64,
          decoration: BoxDecoration(color: _statusColor(e.status), borderRadius: BorderRadius.circular(6)),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            // top row
            Row(children: [
              Expanded(child: Text('${e.stepName}', style: GoogleFonts.inter(fontWeight: FontWeight.w800))),
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                decoration: BoxDecoration(color: _statusColor(e.status).withOpacity(0.12), borderRadius: BorderRadius.circular(8)),
                child: Text(
                  e.status.toUpperCase(),
                  style: GoogleFonts.inter(fontSize: 12, fontWeight: FontWeight.w700, color: _statusColor(e.status)),
                ),
              ),
            ]),
            const SizedBox(height: 6),
            Row(children: [
              Icon(Icons.receipt_long, size: 14, color: Colors.grey[600]),
              const SizedBox(width: 6),
              Text('Loan: ${e.loanId}', style: GoogleFonts.inter(fontSize: 13, color: Colors.grey[800])),
              const SizedBox(width: 12),
              if (e.utilizationAmount != null && e.utilizationAmount!.isNotEmpty)
                Row(children: [Icon(Icons.currency_rupee, size: 14, color: Colors.grey[600]), const SizedBox(width: 4), Text('${e.utilizationAmount}', style: GoogleFonts.inter(fontSize: 13))]),
            ]),
            const SizedBox(height: 8),
            Row(children: [
              Icon(Icons.access_time, size: 14, color: Colors.grey[500]),
              const SizedBox(width: 6),
              Text(dtText, style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600])),
            ]),
            const SizedBox(height: 8),
            if (e.mediaUrl != null && e.mediaUrl!.isNotEmpty)
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: double.infinity,
                  height: 120,
                  child: Image.network(e.mediaUrl!, fit: BoxFit.cover, errorBuilder: (_, __, ___) => Container(color: Colors.grey[100], alignment: Alignment.center, child: const Icon(Icons.broken_image))),
                ),
              ),
          ]),
        ),
      ]),
    );
  }

  Widget _buildBody() {
    if (_loading) {
      return const Center(child: CircularProgressIndicator());
    }

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: CustomScrollView(
        physics: const BouncingScrollPhysics(parent: AlwaysScrollableScrollPhysics()),
        slivers: [
          SliverToBoxAdapter(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(widget.title, style: GoogleFonts.inter(fontSize: 20, fontWeight: FontWeight.w800)),
                const SizedBox(height: 8),
                Text('All verification activity for this account', style: GoogleFonts.inter(color: Colors.grey[700])),
                const SizedBox(height: 12),
                _buildSearchBar(),
                const SizedBox(height: 12),
                _buildFiltersRow(),
                const SizedBox(height: 10),
                if (_refreshing) LinearProgressIndicator(),
              ]),
            ),
          ),

          // list
          SliverPadding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
            sliver: _visibleEntries.isEmpty
                ? SliverToBoxAdapter(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 40),
                child: Center(child: Text("No records match your filters", style: GoogleFonts.inter(color: Colors.grey[600]))),
              ),
            )
                : SliverList(
              delegate: SliverChildBuilderDelegate((context, index) {
                final e = _visibleEntries[index];
                return _buildEntryCard(e);
              }, childCount: _visibleEntries.length),
            ),
          ),

          SliverToBoxAdapter(child: const SizedBox(height: 28)),
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
        appBar: AppBar(
          title: Text(widget.title, style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
          elevation: 0,
          backgroundColor: Colors.white,
          actions: [
            IconButton(onPressed: () => _fetchHistory(), icon: const Icon(Icons.refresh)),
          ],
        ),
        body: _buildBody(),
      ),
    );
  }
}
