// lib/pages/loan_detail_screen.dart
//
// Safe for both Map-based and model-based steps (no [] on objects)
// Handles offline queue + live refresh, shows static utilization ring,
// and launches the VerificationWizardPage.

import 'dart:async';
import 'dart:math';
import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:loan2/models/beneficiary_loan.dart' show BeneficiaryLoan;
import 'package:loan2/pages/verification_step_page.dart';
import 'package:loan2/models/process_step.dart' as ps;

import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';

class LoanDetailScreen extends StatefulWidget {
  final BeneficiaryLoan loan;

  const LoanDetailScreen({super.key, required this.loan});

  @override
  State<LoanDetailScreen> createState() => _LoanDetailScreenState();
}

class _LoanDetailScreenState extends State<LoanDetailScreen> {
  late BeneficiaryLoan _currentLoan;
  final BeneficiaryService _service = BeneficiaryService();
  ps.ProcessStep _asPs(dynamic s) {
    if (s is ps.ProcessStep) return s;

    if (s is Map<String, dynamic>) return ps.ProcessStep.fromJson(s);
    if (s is Map) return ps.ProcessStep.fromJson(Map<String, dynamic>.from(s));

    // Fallback: build a tolerant json shape from your safe getters.
    final m = <String, dynamic>{
      'id': _sid(s),
      'processId': _pid(s),
      'process_id': _pid(s),
      'whatToDo': _what(s),
      'what_to_do': _what(s),
      'dataType': _dtype(s),
      'data_type': _dtype(s),
      'status': _status(s),
      'fileId': _fileId(s),
      'file_id': _fileId(s),
      'utilizationAmount': _util(s),
      'utilization_amount': _util(s),
    };

    return ps.ProcessStep.fromJson(m);
  }

  bool _isDone(dynamic s) => _serverDone(s) || _localDone(s);

  dynamic _firstIncompleteDynamic(List<dynamic> steps) {
    for (final s in steps) {
      if (!_isDone(s)) return s;
    }
    return steps.isNotEmpty ? steps.first : null;
  }

  Future<void> _openStep(ps.ProcessStep step) async {
    final loanId = _currentLoan.loanId ?? '';
    final userId = _currentLoan.userId ?? '';

    if (loanId.isEmpty || userId.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Missing loanId / userId for this loan')),
      );
      return;
    }

    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerificationStepPage(
          loanId: loanId,
          userId: userId,
          step: step,
        ),
      ),
    );

    if (changed == true) {
      _refreshLoanData();
    } else {
      _refreshLoanData(silent: true);
    }
  }

  Future<void> _openFirstIncompleteStep() async {
    final steps = [..._steps()]..sort((a, b) => _pid(a).compareTo(_pid(b)));
    final target = _firstIncompleteDynamic(steps);
    if (target == null) return;
    await _openStep(_asPs(target));
  }

  bool _isRefreshing = false;
  Map<String, bool> _localUploads = {};
  double _amountUsed = 0.0;

  StreamSubscription? _syncSub;
  StreamSubscription? _itemSyncSub;
  StreamSubscription? _onlineSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _currentLoan = widget.loan;
    _amountUsed = _sumUtilization(_steps());

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
        if (event is Map &&
            (event['loanId']?.toString() ?? '') == _currentLoan.loanId) {
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

  // ---------- dynamic-safe helpers (never call [] on objects) ----------

  List<dynamic> _steps() {
    final raw = _currentLoan.processes;
    if (raw is List) return raw;
    return const <dynamic>[];
  }

  String _sid(dynamic s) {
    try {
      if (s is Map) {
        return (s['id']?.toString() ??
            s['processId']?.toString() ??
            s['process_id']?.toString() ??
            '')
            .toString();
      }
      final d = s as dynamic;
      return (d.id ?? d.processId ?? d.process_id ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  int _pid(dynamic s) {
    try {
      if (s is Map) {
        final v = s['processId'] ?? s['process_id'];
        if (v is num) return v.toInt();
        return int.tryParse(v?.toString() ?? '') ?? 0;
      }
      final d = s as dynamic;
      final v = d.processId ?? d.process_id;
      if (v is num) return v.toInt();
      return int.tryParse(v?.toString() ?? '') ?? 0;
    } catch (_) {
      return 0;
    }
  }

  String _what(dynamic s) {
    try {
      if (s is Map) {
        return (s['what_to_do'] ?? s['whatToDo'] ?? 'Step ${_pid(s)}')
            .toString();
      }
      final d = s as dynamic;
      return (d.whatToDo ?? 'Step ${_pid(s)}').toString();
    } catch (_) {
      return 'Step ${_pid(s)}';
    }
  }

  String? _dtype(dynamic s) {
    try {
      if (s is Map) return (s['data_type'] ?? s['dataType'])?.toString();
      final d = s as dynamic;
      return d.dataType?.toString();
    } catch (_) {
      return null;
    }
  }

  String _status(dynamic s) {
    try {
      if (s is Map) return (s['status'] ?? '').toString();
      final d = s as dynamic;
      return (d.status ?? '').toString();
    } catch (_) {
      return '';
    }
  }

  String? _fileId(dynamic s) {
    try {
      if (s is Map) return (s['file_id'] ?? s['fileId'])?.toString();
      final d = s as dynamic;
      return d.fileId?.toString();
    } catch (_) {
      return null;
    }
  }

  dynamic _util(dynamic s) {
    try {
      if (s is Map) {
        return s['utilizationAmount'] ?? s['utilization_amount'];
      }
      final d = s as dynamic;
      return d.utilizationAmount ?? d.utilization_amount;
    } catch (_) {
      return null;
    }
  }

  bool _serverDone(dynamic s) {
    final t = _status(s).toLowerCase().trim();
    return t == 'verified' || t == 'pending_review';
  }

  bool _localDone(dynamic s) => _localUploads[_sid(s)] == true;

  double _sumUtilization(List<dynamic> steps) {
    double sum = 0.0;
    for (final s in steps) {
      final v = _util(s);
      if (v is num) {
        sum += v.toDouble();
      } else if (v is String) {
        sum += double.tryParse(v) ?? 0.0;
      } else if (v != null) {
        sum += double.tryParse(v.toString()) ?? 0.0;
      }
    }
    return sum;
  }

  bool _allDone() {
    for (final s in _steps()) {
      if (!_serverDone(s) && !_localDone(s)) return false;
    }
    return true;
  }

  // ---------- data + sync ----------

  Future<void> _checkLocalUploads() async {
    final queued = await DatabaseHelper.instance.getQueuedForUpload();
    final Map<String, bool> statusMap = {};
    for (var row in queued) {
      final pid = row[DatabaseHelper.colProcessId] as String?;
      final lid = row[DatabaseHelper.colLoanId] as String?;
      if (pid != null && lid == _currentLoan.loanId) {
        statusMap[pid] = true;
      }
    }
    if (mounted) setState(() => _localUploads = statusMap);
  }

  Future<void> _refreshLoanData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isRefreshing = true);
    await _checkLocalUploads();

    try {
      final updated = await _service.fetchLoanDetails(_currentLoan.loanId);
      if (!mounted) return;
      setState(() {
        _currentLoan = updated;
        _amountUsed = _sumUtilization(_steps());
        if (!silent) _isRefreshing = false;
      });
    } catch (_) {
      if (mounted && !silent) setState(() => _isRefreshing = false);
    }
  }

  // ---------- start sheet + wizard ----------

  Future<void> _showStartSheet() async {
    final steps = [..._steps()]..sort((a, b) => _pid(a).compareTo(_pid(b)));
    bool agreed = false;

    bool isConstructionLoan() {
      final t = (_currentLoan.loanType ?? '').toLowerCase();
      final s = (_currentLoan.scheme ?? '').toLowerCase();
      return t.contains('construction') ||
          t.contains('shop') ||
          s.contains('construction') ||
          s.contains('shop');
    }

    int? stageNoFromText(String text) {
      final re = RegExp(r'^\s*Stage\s*(\d+)\s*:', caseSensitive: false);
      final m = re.firstMatch(text.trim());
      return m == null ? null : int.tryParse(m.group(1) ?? '');
    }

    String stripStagePrefix(String text) {
      final re = RegExp(r'^\s*Stage\s*\d+\s*:\s*', caseSensitive: false);
      return text.replaceFirst(re, '').trim();
    }

    await showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final cons = isConstructionLoan();

            Widget tile({
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
                  boxShadow: [
                    BoxShadow(
                        color: Colors.black.withOpacity(0.03),
                        blurRadius: 8,
                        offset: const Offset(0, 6))
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 44,
                      height: 38,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color:
                        done ? Colors.green.shade50 : Colors.grey.shade50,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(left,
                          style: TextStyle(
                              fontWeight: FontWeight.w900,
                              color: done
                                  ? Colors.green[800]
                                  : Colors.black87)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(title,
                                style: const TextStyle(
                                    fontWeight: FontWeight.w800)),
                            const SizedBox(height: 6),
                            Text("Evidence: $evidence",
                                style: TextStyle(
                                    fontSize: 12, color: Colors.grey[700])),
                          ]),
                    ),
                    if (done)
                      const Icon(Icons.check_circle,
                          color: Colors.green, size: 18),
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
                  return tile(
                    left: "${_pid(s)}",
                    title: _what(s),
                    evidence: _dtype(s) ?? 'image',
                    done: done,
                  );
                },
              );
            } else {
              final Map<int, List<dynamic>> mp = {};
              for (final st in steps) {
                final sn = stageNoFromText(_what(st)) ?? 0;
                mp.putIfAbsent(sn, () => []).add(st);
              }
              final keys = mp.keys.toList()..sort();
              final items = <Widget>[];
              for (final k in keys) {
                final lst = mp[k]!..sort((a, b) => _pid(a).compareTo(_pid(b)));
                items.add(Padding(
                  padding: const EdgeInsets.only(top: 6, bottom: 8),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: Text("Stage $k",
                        style: const TextStyle(
                            fontWeight: FontWeight.w900, fontSize: 14)),
                  ),
                ));
                for (int i = 0; i < lst.length; i++) {
                  final s = lst[i];
                  final done = _serverDone(s) || _localDone(s);
                  items.add(tile(
                    left: "Step ${i + 1}",
                    title: stripStagePrefix(_what(s)),
                    evidence: _dtype(s) ?? 'image',
                    done: done,
                  ));
                  items.add(const SizedBox(height: 10));
                }
              }
              stepsView = ListView(shrinkWrap: true, children: items);
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 18),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                        height: 6,
                        width: 60,
                        decoration: BoxDecoration(
                            color: Colors.grey[300],
                            borderRadius: BorderRadius.circular(6))),
                    const SizedBox(height: 12),
                    Text("Verification Steps",
                        style: GoogleFonts.inter(
                            fontSize: 16, fontWeight: FontWeight.w900)),
                    const SizedBox(height: 12),
                    Flexible(child: stepsView),
                    const SizedBox(height: 10),
                    CheckboxListTile(
                      value: agreed,
                      onChanged: (v) => setSheet(() => agreed = v == true),
                      title: Text("I have read and understood the steps",
                          style: GoogleFonts.inter(
                              fontWeight: FontWeight.w700)),
                      controlAffinity: ListTileControlAffinity.leading,
                      contentPadding: EdgeInsets.zero,
                    ),
                    const SizedBox(height: 10),
                    SizedBox(
                      width: double.infinity,
                      height: 54,
                      child: ElevatedButton(
                        onPressed: !agreed
                            ? null
                            : () {
                          Navigator.pop(ctx);
                          _openFirstIncompleteStep();

                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9933),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(14)),
                        ),
                        child: Text("Start Verification Process",
                            style: GoogleFonts.inter(
                                fontSize: 16, fontWeight: FontWeight.w900)),
                      ),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ---------- UI ----------

  PreferredSizeWidget _buildAppBar() {
    return AppBar(
      backgroundColor: Colors.white,
      elevation: 0,
      centerTitle: true,
      title: Text('Verification Page',
          style: GoogleFonts.inter(
              color: Colors.black, fontWeight: FontWeight.bold)),
      iconTheme: const IconThemeData(color: Colors.black),
      actions: [
        if (_isRefreshing)
          const Padding(
            padding: EdgeInsets.all(16.0),
            child: SizedBox(
                width: 20,
                height: 20,
                child:
                CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
          )
        else
          IconButton(
              icon: const Icon(Icons.refresh),
              onPressed: () => _refreshLoanData()),
      ],
    );
  }

  Widget _buildUtilizationCardStatic() {
    final sanctioned = (_currentLoan.amount is num)
        ? (_currentLoan.amount as num).toDouble()
        : double.tryParse('${_currentLoan.amount}') ?? 0.0;

    final used = _amountUsed;
    final percent = sanctioned > 0 ? (used / sanctioned).clamp(0.0, 1.0) : 0.0;
    final percentInt = (percent * 100).clamp(0, 100).toInt();

    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 4),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
              color: Colors.black.withOpacity(0.06),
              blurRadius: 18,
              offset: const Offset(0, 10))
        ],
      ),
      child: Row(
        children: [
          SizedBox(
            width: 86,
            height: 86,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 86,
                  height: 86,
                  decoration: BoxDecoration(
                      shape: BoxShape.circle, color: Colors.grey[50]),
                ),
                SizedBox(
                  width: 68,
                  height: 68,
                  child: CustomPaint(
                    painter: _RingPainter(progress: percent, strokeWidth: 8),
                  ),
                ),
                Column(mainAxisSize: MainAxisSize.min, children: [
                  Text("$percentInt%",
                      style: GoogleFonts.inter(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  Text("Used", style: GoogleFonts.inter(fontSize: 12)),
                ]),
              ],
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text("Utilization",
                      style: GoogleFonts.inter(
                          fontSize: 16, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text(
                      "₹${used.toStringAsFixed(2)} used of ₹${sanctioned.toStringAsFixed(2)}",
                      style: GoogleFonts.inter(color: Colors.grey[700])),
                  const SizedBox(height: 12),
                  ClipRRect(
                    borderRadius: BorderRadius.circular(8),
                    child: LinearProgressIndicator(
                      value: percent,
                      minHeight: 8,
                      backgroundColor: Colors.grey[200],
                      valueColor:
                      const AlwaysStoppedAnimation(Color(0xFF1F6FEB)),
                    ),
                  ),
                ]),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final sanctionedAmount = (_currentLoan.amount is num)
        ? (_currentLoan.amount as num).toDouble()
        : double.tryParse('${_currentLoan.amount}') ?? 0.0;

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
                _buildUtilizationCardStatic(),
                const SizedBox(height: 12),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(18),
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(14),
                    boxShadow: [
                      BoxShadow(
                          color: Colors.black.withOpacity(0.04),
                          blurRadius: 18,
                          offset: const Offset(0, 8))
                    ],
                  ),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Expanded(
                              child: Text(_currentLoan.applicantName ?? "Beneficiary",
                                  style: GoogleFonts.inter(
                                      fontSize: 16, fontWeight: FontWeight.w800))),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 10, vertical: 6),
                            decoration: BoxDecoration(
                                color: Colors.grey[100],
                                borderRadius: BorderRadius.circular(10)),
                            child: Text(_currentLoan.status ?? 'N/A',
                                style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700)),
                          ),
                        ]),
                        const SizedBox(height: 8),
                        _detailRow('Loan ID', _currentLoan.loanId),
                        _detailRow('Type', _currentLoan.loanType),
                        _detailRow('Scheme', _currentLoan.scheme),
                        _detailRow('Date Applied', _currentLoan.dateApplied),
                        _detailRow('Sanctioned Amount',
                            '₹${sanctionedAmount.toStringAsFixed(2)}'),
                      ]),
                ),
                const SizedBox(height: 20),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(14),
                      boxShadow: [
                        BoxShadow(
                            color: Colors.black.withOpacity(0.03),
                            blurRadius: 12)
                      ]),
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [
                          Text("My Requests & Steps",
                              style: GoogleFonts.inter(
                                  fontSize: 15, fontWeight: FontWeight.w800)),
                          const Spacer(),
                          Text("${_steps().length} steps",
                              style: TextStyle(color: Colors.grey[700])),
                        ]),
                        const SizedBox(height: 12),
                        _stepsPreview(),
                      ]),
                ),
                const SizedBox(height: 18),
                SizedBox(
                  width: double.infinity,
                  height: 56,
                  child: ElevatedButton(
                    onPressed: _allDone() ? null : _showStartSheet,
                    style: ElevatedButton.styleFrom(
                      backgroundColor:
                      _allDone() ? Colors.green : const Color(0xFF1F6FEB),
                      shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14)),
                    ),
                    child: Text(
                        _allDone()
                            ? "All Steps Completed"
                            : "Start Verification Process",
                        style: GoogleFonts.inter(
                            fontWeight: FontWeight.w800, fontSize: 16)),
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

  Widget _detailRow(String label, String? value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          SizedBox(
              width: 130,
              child: Text(label,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14))),
          Expanded(
            child: Text(value ?? '',
                style: const TextStyle(
                    fontWeight: FontWeight.w600,
                    fontSize: 14,
                    color: Colors.black87),
                textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _stepsPreview() {
    final steps = _steps();
    if (steps.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 18),
        child: Center(
            child: Text("No steps available",
                style: GoogleFonts.inter(color: Colors.grey[700]))),
      );
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
          final captured =
              (_fileId(s) != null) || _localDone(s) || _serverDone(s);
          final statusText = _status(s).isNotEmpty
              ? _status(s)
              : (captured ? 'Captured' : 'Pending');

          return GestureDetector(
            onTap: () => _openStep(_asPs(s)),

            child: Container(
              width: 220,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: Colors.grey.shade100),
                boxShadow: [
                  BoxShadow(
                      color: Colors.black.withOpacity(0.02),
                      blurRadius: 10,
                      offset: const Offset(0, 6))
                ],
              ),
              child:
              Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Row(children: [
                  CircleAvatar(
                    radius: 16,
                    backgroundColor:
                    captured ? Colors.green.shade50 : Colors.blue.shade50,
                    child: Text('${_pid(s)}',
                        style: TextStyle(
                            color: captured
                                ? Colors.green[800]
                                : Colors.blue[800],
                            fontWeight: FontWeight.w800)),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                      child: Text(_what(s),
                          style:
                          GoogleFonts.inter(fontWeight: FontWeight.w700))),
                ]),
                const Spacer(),
                Row(children: [
                  Text(statusText,
                      style: TextStyle(
                          fontSize: 12,
                          color: captured ? Colors.green : Colors.orange)),
                  const Spacer(),
                  Icon(Icons.chevron_right,
                      size: 18, color: Colors.grey[500]),
                ]),
              ]),
            ),
          );
        },
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
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
      ..shader = const LinearGradient(
          colors: [Color(0xFF1F6FEB), Color(0xFF2757D6)])
          .createShader(Rect.fromCircle(center: center, radius: radius))
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawCircle(center, radius, bgPaint);

    final sweep = 2 * pi * progress;
    final start = -pi / 2;
    canvas.drawArc(
        Rect.fromCircle(center: center, radius: radius),
        start,
        sweep,
        false,
        fgPaint);
  }

  @override
  bool shouldRepaint(covariant _RingPainter oldDelegate) =>
      oldDelegate.progress != progress || oldDelegate.strokeWidth != strokeWidth;
}
