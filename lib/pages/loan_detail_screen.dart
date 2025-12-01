// lib/pages/loan_detail_screen.dart
//
// Upgraded LoanDetailScreen — Static utilization card (no breathing/tilt), premium UI.
// Keeps existing business logic (sync listeners, polling, local uploads check, start sheet, wizard launch).
//
// Author: ChatGPT (UI small tweaks)
// Date: 2025-12-01

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:loan2/models/process_step.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/verification_step_page.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';

class LoanDetailScreen extends StatefulWidget {
  final BeneficiaryLoan loan;

  const LoanDetailScreen({super.key, required this.loan});

  @override
  State<LoanDetailScreen> createState() => LoanDetailScreenState();
}

class LoanDetailScreenState extends State<LoanDetailScreen> with TickerProviderStateMixin {
  late BeneficiaryLoan _currentLoan;
  final BeneficiaryService _service = BeneficiaryService();

  bool _isRefreshing = false;
  Map<String, bool> _localUploads = {};
  double _amountUsed = 0.0;

  StreamSubscription? _syncSub;
  StreamSubscription? _itemSyncSub;
  StreamSubscription? _onlineSub;
  Timer? _pollTimer;

  // small debug flag
  final bool _debug = false;

  @override
  void initState() {
    super.initState();
    _currentLoan = widget.loan;
    _amountUsed = double.tryParse(_currentLoan.totalUtilized?.toString() ?? "") ?? _deriveTotalUtilizationFromSteps();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLoanData();
      _checkLocalUploads();
    });

    _onlineSub = SyncService.onOnlineStatusChanged.listen((isOnline) {
      if (isOnline) _refreshLoanData();
    });
    _syncSub = SyncService.onSync.listen((_) {
      _refreshLoanData(silent: true);
    });
    _itemSyncSub = SyncService.onItemSynced.listen((event) {
      try {
        if (event is Map && (event['loanId']?.toString() ?? "") == (_currentLoan.loanId ?? "")) {
          _refreshLoanData(silent: true);
        }
      } catch (_) {}
    });

    _pollTimer = Timer.periodic(const Duration(seconds: 10), (_) {
      _refreshLoanData(silent: true);
    });
  }

  @override
  void dispose() {
    _pollTimer?.cancel();
    _onlineSub?.cancel();
    _syncSub?.cancel();
    _itemSyncSub?.cancel();
    super.dispose();
  }

  Future<void> _checkLocalUploads() async {
    try {
      final queued = await DatabaseHelper.instance.getQueuedForUpload();
      final Map<String, bool> statusMap = {};
      for (var row in queued) {
        final pid = row[DatabaseHelper.colProcessId] as String?;
        final lid = row[DatabaseHelper.colLoanId] as String?;
        if (pid != null && (lid ?? "") == (_currentLoan.loanId ?? "")) {
          statusMap[pid] = true;
        }
      }
      if (mounted) setState(() => _localUploads = statusMap);
    } catch (e) {
      if (_debug) debugPrint("checkLocalUploads err: $e");
    }
  }

  Future<void> _refreshLoanData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isRefreshing = true);
    await _checkLocalUploads();
    try {
      final updatedLoan = await _service.fetchLoanDetails(_currentLoan.loanId ?? "");
      if (!mounted) return;
      setState(() {
        _currentLoan = updatedLoan;
        _amountUsed = double.tryParse(_currentLoan.totalUtilized?.toString() ?? "") ?? _deriveTotalUtilizationFromSteps();
        if (!silent) _isRefreshing = false;
      });
    } catch (e) {
      if (mounted && !silent) setState(() => _isRefreshing = false);
      if (_debug) debugPrint("refreshLoanData failed: $e");
    }
  }

  double _deriveTotalUtilizationFromSteps() {
    try {
      if (_currentLoan.processes == null || _currentLoan.processes!.isEmpty) return 0.0;
      double sum = 0.0;
      for (final s in _currentLoan.processes ?? []) {
        final raw = s.utilizationAmount;
        double val = 0.0;
        if (raw is num) {
          val = raw.toDouble();
        } else if (raw is String) {
          val = double.tryParse(raw) ?? 0.0;
        } else if (raw != null) {
          val = double.tryParse(raw.toString()) ?? 0.0;
        }
        sum += val;
      }
      return sum;
    } catch (_) {
      return 0.0;
    }
  }

  bool _serverDone(ProcessStep s) {
    final t = (s.status ?? '').toString().toLowerCase().trim();
    return t == 'verified' || t == 'pending_review';
  }

  bool _localDone(ProcessStep s) => _localUploads[s.id] == true;

  bool _allDone() {
    for (final s in _currentLoan.processes ?? []) {
      if (!_serverDone(s) && !_localDone(s)) return false;
    }
    return true;
  }

  // ---------- Start sheet (unchanged behaviour) ----------
  Future<void> _showStartSheet() async {
    final steps = List<ProcessStep>.from(_currentLoan.processes ?? []);
    steps.sort((a, b) => a.processId.compareTo(b.processId));
    bool agreed = false;

    bool isConstructionLoan() {
      final t = (_currentLoan.loanType ?? '').toLowerCase();
      final s = (_currentLoan.scheme ?? '').toLowerCase();
      return t.contains('construction') || t.contains('shop') || s.contains('construction') || s.contains('shop');
    }

    int? stageNoFromText(String text) {
      final txt = (text ?? '').trim();
      final re = RegExp(r'^\s*Stage\s*(\d+)\s*:', caseSensitive: false);
      final m = re.firstMatch(txt);
      if (m == null) return null;
      return int.tryParse(m.group(1) ?? "");
    }

    String stripStagePrefix(String text) {
      final txt = (text ?? '').trim();
      final re = RegExp(r'^\s*Stage\s*\d+\s*:\s*', caseSensitive: false);
      return txt.replaceFirst(re, "").trim();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(18))),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final cons = isConstructionLoan();

            Widget buildTile({
              required String left,
              required String title,
              required String evidence,
              bool done = false,
            }) {
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.grey.shade100),
                  boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 8, offset: const Offset(0,6))],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: done ? Colors.green.shade50 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(left, style: TextStyle(fontWeight: FontWeight.w900, color: done ? Colors.green[800] : Colors.black87)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                        Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                        const SizedBox(height: 6),
                        Text("Evidence: $evidence", style: TextStyle(fontSize: 12, color: Colors.grey[700])),
                      ]),
                    ),
                    if (done) Icon(Icons.check_circle, color: Colors.green, size: 18),
                  ],
                ),
              );
            }

            Widget stepsView;
            if (!cons) {
              stepsView = ListView.separated(
                shrinkWrap: true,
                physics: const BouncingScrollPhysics(),
                itemCount: steps.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final s = steps[i];
                  final done = _serverDone(s) || _localDone(s);
                  return buildTile(
                    left: "${s.processId}",
                    title: (s.whatToDo == null || s.whatToDo!.isEmpty) ? "Step ${s.processId}" : s.whatToDo!,
                    evidence: s.dataType ?? 'image',
                    done: done,
                  );
                },
              );
            } else {
              final Map<int, List<ProcessStep>> mp = {};
              for (final st in steps) {
                final sn = stageNoFromText(st.whatToDo ?? '') ?? 0;
                mp.putIfAbsent(sn, () => []).add(st);
              }

              final keys = mp.keys.toList()..sort();

              final items = <Widget>[];
              for (final k in keys) {
                final lst = mp[k]!..sort((a, b) => a.processId.compareTo(b.processId));
                items.add(Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Stage $k", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                  ),
                ));
                for (int i = 0; i < lst.length; i++) {
                  final s = lst[i];
                  final done = _serverDone(s) || _localDone(s);
                  items.add(buildTile(
                    left: "Step ${i + 1}",
                    title: stripStagePrefix(s.whatToDo ?? "Step ${s.processId}"),
                    evidence: s.dataType ?? 'image',
                    done: done,
                  ));
                  items.add(const SizedBox(height: 10));
                }
              }
              stepsView = ListView(shrinkWrap: true, children: items);
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Container(height: 6, width: 60, decoration: BoxDecoration(color: Colors.grey[300], borderRadius: BorderRadius.circular(6))),
                      const SizedBox(height: 12),
                      Text("Verification Steps", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900)),
                      const SizedBox(height: 12),
                      Flexible(child: stepsView),
                      const SizedBox(height: 10),
                      CheckboxListTile(
                        value: agreed,
                        onChanged: (v) => setSheet(() => agreed = v == true),
                        title: Text("I have read and understood the steps", style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                        controlAffinity: ListTileControlAffinity.leading,
                        contentPadding: EdgeInsets.zero,
                      ),
                      const SizedBox(height: 10),
                      SizedBox(
                        width: double.infinity,
                        height: 54,
                        child: ElevatedButton(
                          onPressed: !agreed ? null : () {
                            Navigator.pop(ctx);
                            // Open wizard full-screen (hides bottom nav because new route)
                            Navigator.push(context, MaterialPageRoute(builder: (_) => VerificationStepPage(loanId: _currentLoan.loanId ?? "", userId: _currentLoan.userId ?? "")));
                          },
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF9933),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                          ),
                          child: Text("Start Verification Process", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w900)),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- Utilization card (STATIC: removed breathing + removed buttons) ----------
  Widget _buildUtilizationCardStatic() {
    final sanctioned = double.tryParse(_currentLoan.amount?.toString() ?? "") ?? 0.0;
    final used = double.tryParse(_currentLoan.totalUtilized?.toString() ?? "") ?? _amountUsed;
    final percent = sanctioned > 0 ? (used / sanctioned).clamp(0.0, 1.0) : 0.0;
    final percentInt = (percent * 100).clamp(0, 100).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))],
      ),
      child: Row(
        children: [
          // circular progress display (static)
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: Colors.grey[50]),
                ),
                SizedBox(
                  width: 68,
                  height: 68,
                  child: CustomPaint(
                    painter: _RingPainter(progress: percent, strokeWidth: 8),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("$percentInt%", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800)),
                  Text("Used", style: GoogleFonts.inter(fontSize: 12)),
                ]),
              ],
            ),
          ),

          const SizedBox(width: 12),

          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text("Utilization", style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800)),
              const SizedBox(height: 6),
              Text("₹${used.toStringAsFixed(2)} used of ₹${sanctioned.toStringAsFixed(2)}", style: GoogleFonts.inter(color: Colors.grey[700])),
              const SizedBox(height: 12),
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: LinearProgressIndicator(
                  value: percent,
                  minHeight: 8,
                  backgroundColor: Colors.grey[200],
                  valueColor: AlwaysStoppedAnimation(const Color(0xFF1F6FEB)),
                ),
              ),
            ]),
          ),

          // removed Start / Details buttons as requested
        ],
      ),
    );
  }

  // ---------- Utilization details modal ----------
  void _showUtilizationDetails() {
    final used = double.tryParse(_currentLoan.totalUtilized?.toString() ?? "") ?? _amountUsed;
    final total = double.tryParse(_currentLoan.amount?.toString() ?? "") ?? 0.0;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
      builder: (_) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(18.0),
          child: SizedBox(
            height: min(MediaQuery.of(context).size.height * 0.78, 520),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(children: [Text('Utilization Details', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)), const Spacer(), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12)]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Total Utilized', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 8),
                    Text('₹${used.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 12),
                    Text('Loan Amount: ₹${total.toStringAsFixed(2)}', style: GoogleFonts.inter(color: Colors.grey[700])),
                    const SizedBox(height: 16),
                    const Divider(),
                    const SizedBox(height: 8),
                    Expanded(
                      child: ListView.builder(
                        itemCount: _currentLoan.processes?.length ?? 0,
                        itemBuilder: (ctx, i) {
                          final s = (_currentLoan.processes ?? [])[i];
                          final utilVal = double.tryParse(s.utilizationAmount?.toString() ?? "") ?? 0.0;
                          return ListTile(
                            leading: CircleAvatar(child: Text('${s.processId}')),
                            title: Text(s.whatToDo ?? 'Step ${s.processId}'),
                            subtitle: Text('₹${utilVal.toStringAsFixed(2)}'),
                            trailing: Text((s.status ?? '').toString()),
                          );
                        },
                      ),
                    ),
                  ]),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Small detail row widget ----------
  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(width: 130, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  // ---------- AppBar ----------
  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: Text('Verification Page', style: GoogleFonts.inter(color: Colors.black, fontWeight: FontWeight.bold)),
      iconTheme: const IconThemeData(color: Colors.black),
      actions: [
        if (_isRefreshing)
          const Padding(padding: EdgeInsets.all(16.0), child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)))
        else
          IconButton(icon: const Icon(Icons.refresh), onPressed: () => _refreshLoanData()),
      ],
    );
  }

  // ---------- Build ----------
  @override
  Widget build(BuildContext context) {
    final sanctionedAmount = double.tryParse(_currentLoan.amount?.toString() ?? "") ?? 0.0;
    final utilizationPercent = sanctionedAmount > 0 ? ((double.tryParse(_currentLoan.totalUtilized?.toString() ?? "") ?? _amountUsed) / sanctionedAmount).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F8FB),
      appBar: _buildAppBar(),
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: () => _refreshLoanData(),
          child: SingleChildScrollView(
            physics: const BouncingScrollPhysics(),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // UTILIZATION: static (no breathing)
                _buildUtilizationCardStatic(),
                const SizedBox(height: 12),

                // Loan details card
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 18, offset: const Offset(0,8))],
                  ),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Expanded(child: Text('${_currentLoan.applicantName ?? "Beneficiary"}', style: GoogleFonts.inter(fontSize: 16, fontWeight: FontWeight.w800))),
                      const SizedBox(width: 8),
                      Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.grey[100], borderRadius: BorderRadius.circular(10)), child: Text(_currentLoan.status ?? 'N/A', style: GoogleFonts.inter(fontWeight: FontWeight.w700))),
                    ]),
                    const SizedBox(height: 8),
                    _buildDetailRow('Loan ID', _currentLoan.loanId ?? ''),
                    _buildDetailRow('Type', _currentLoan.loanType ?? ''),
                    _buildDetailRow('Scheme', _currentLoan.scheme ?? ''),
                    _buildDetailRow('Date Applied', _currentLoan.dateApplied ?? ''),
                    _buildDetailRow('Sanctioned Amount', '₹${(double.tryParse(_currentLoan.amount?.toString() ?? "") ?? 0.0).toStringAsFixed(2)}'),
                  ]),
                ),

                const SizedBox(height: 20),

                // Steps preview
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12)]),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(children: [
                      Text("My Requests & Steps", style: GoogleFonts.inter(fontSize: 15, fontWeight: FontWeight.w800)),
                      const Spacer(),
                      Text("${(_currentLoan.processes ?? []).length} steps", style: TextStyle(color: Colors.grey[700])),
                    ]),
                    const SizedBox(height: 12),
                    _buildStepsPreview(),
                  ]),
                ),

                const SizedBox(height: 18),

                // action button (keeps start verification to open wizard)
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _allDone() ? null : _showStartSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: _allDone() ? Colors.green : const Color(0xFF1F6FEB),
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(_allDone() ? "All Steps Completed" : "Start Verification Process", style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 16)),
                  ),
                ),

                const SizedBox(height: 26),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ---------- Steps preview ----------
  Widget _buildStepsPreview() {
    final steps = _currentLoan.processes ?? [];
    if (steps.isEmpty) {
      return Padding(padding: const EdgeInsets.symmetric(vertical: 18), child: Center(child: Text("No steps available", style: GoogleFonts.inter(color: Colors.grey[700]))));
    }

    return SizedBox(
      height: 110,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        physics: const BouncingScrollPhysics(),
        itemCount: steps.length,
        separatorBuilder: (_, __) => const SizedBox(width: 12),
        itemBuilder: (context, index) {
          final s = steps[index];
          final captured = s.fileId != null || _localUploads[s.id] == true || _serverDone(s);
          final statusText = s.status ?? (captured ? 'Captured' : 'Pending');
          return GestureDetector(
            onTap: () => _openStepDetail(s),
            child: Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade100),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.02), blurRadius: 10, offset: const Offset(0,6))],
              ),
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(radius: 16, backgroundColor: captured ? Colors.green.shade50 : Colors.blue.shade50, child: Text('${s.processId}', style: TextStyle(color: captured ? Colors.green[800] : Colors.blue[800], fontWeight: FontWeight.w800))),
                  const SizedBox(width: 10),
                  Expanded(child: Text(s.whatToDo ?? 'Step ${s.processId}', style: GoogleFonts.inter(fontWeight: FontWeight.w700))),
                ]),
                const Spacer(),
                Row(children: [
                  Text(statusText, style: TextStyle(fontSize: 12, color: captured ? Colors.green : Colors.orange)),
                  const Spacer(),
                  Icon(Icons.chevron_right, size: 18, color: Colors.grey[500]),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }

  // ---------- Open step detail (navigate to step page) ----------
  void _openStepDetail(ProcessStep step) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerificationStepPage(loanId: _currentLoan.loanId ?? "", userId: _currentLoan.userId ?? "", steps: _currentLoan.processes),
      ),
    ).then((_) => _refreshLoanData(silent: true));
  }
}

// ---------- Custom painter for ring ----------
class _RingPainter extends CustomPainter {
  final double progress; // 0.0 -> 1.0
  final double strokeWidth;
  const _RingPainter({required this.progress, this.strokeWidth = 8});

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (min(size.width, size.height) / 2) - strokeWidth / 2;

    final bgPaint = Paint()
      ..color = Colors.grey.shade200
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    final fgPaint = Paint()
      ..shader = const LinearGradient(colors: [Color(0xFF1F6FEB), Color(0xFF2757D6)]).createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final sweep = 2 * pi * progress;
    final start = -pi / 2;

    canvas.drawArc(Rect.fromCircle(center: center, radius: radius), start, sweep, false, fgPaint);

    final glossPaint = Paint()
      ..color = Colors.white.withOpacity(0.22)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4
      ..strokeCap = StrokeCap.round;

    final glossSweep = min(sweep, pi / 3);
    canvas.drawArc(Rect.fromCircle(center: center, radius: radius - strokeWidth / 2 + 2), start, glossSweep, false, glossPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.strokeWidth != strokeWidth;
  }
}
