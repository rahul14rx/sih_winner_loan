import 'dart:async';
import 'package:flutter/material.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/verification_wizard_page.dart';
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
  bool _isRefreshing = false;

  Map<String, bool> _localUploads = {};
  double _amountUsed = 0;

  StreamSubscription? _syncSub;
  StreamSubscription? _itemSyncSub;
  StreamSubscription? _onlineSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _currentLoan = widget.loan;

    _amountUsed = _currentLoan.amount * 0.45;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLoanData();
    });

    _checkLocalUploads();

    _onlineSub = SyncService.onOnlineStatusChanged.listen((isOnline) {
      if (isOnline) {
        _refreshLoanData();
      }
    });

    _syncSub = SyncService.onSync.listen((_) {
      _refreshLoanData(silent: true);
    });

    _itemSyncSub = SyncService.onItemSynced.listen((event) {
      if (event['loanId'] == _currentLoan.loanId) {
        _refreshLoanData(silent: true);
      }
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
    final queued = await DatabaseHelper.instance.getQueuedForUpload();
    final Map<String, bool> statusMap = {};

    for (var row in queued) {
      final pid = row[DatabaseHelper.colProcessId] as String?;
      final lid = row[DatabaseHelper.colLoanId] as String?;
      if (pid != null && lid == _currentLoan.loanId) {
        statusMap[pid] = true;
      }
    }

    if (mounted) {
      setState(() {
        _localUploads = statusMap;
      });
    }
  }

  Future<void> _refreshLoanData({bool silent = false}) async {
    if (!silent && mounted) setState(() => _isRefreshing = true);

    await _checkLocalUploads();

    try {
      final updatedLoan = await _service.fetchLoanDetails(_currentLoan.loanId);

      if (!mounted) return;
      setState(() {
        _currentLoan = updatedLoan;
        _amountUsed = _currentLoan.amount * 0.45;
        if (!silent) _isRefreshing = false;
      });
    } catch (_) {
      if (mounted && !silent) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  bool _serverDone(ProcessStep s) {
    final t = s.status.toLowerCase().trim();
    return t == 'verified' || t == 'pending_review';
  }

  bool _localDone(ProcessStep s) => _localUploads[s.id] == true;

  bool _allDone() {
    for (final s in _currentLoan.processes) {
      if (!_serverDone(s) && !_localDone(s)) return false;
    }
    return true;
  }

  Future<void> _showStartSheet() async {
    final steps = [..._currentLoan.processes]..sort((a, b) => a.processId.compareTo(b.processId));
    bool agreed = false;

    bool isConstructionLoan() {
      final t = (_currentLoan.loanType).toLowerCase();
      final s = (_currentLoan.scheme).toLowerCase();
      return t.contains('construction') || t.contains('shop') || s.contains('construction') || s.contains('shop');
    }

    int? stageNoFromText(String text) {
      final re = RegExp(r'^\s*Stage\s*(\d+)\s*:', caseSensitive: false);
      final m = re.firstMatch(text.trim());
      if (m == null) return null;
      return int.tryParse(m.group(1) ?? "");
    }

    String stripStagePrefix(String text) {
      final re = RegExp(r'^\s*Stage\s*\d+\s*:\s*', caseSensitive: false);
      return text.replaceFirst(re, "").trim();
    }

    await showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            final cons = isConstructionLoan();

            Widget buildTile({
              required String left,
              required String title,
              required String evidence,
            }) {
              return Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Row(
                  children: [
                    Container(
                      width: 42,
                      height: 34,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(
                        color: Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Text(left, style: const TextStyle(fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(title, style: const TextStyle(fontWeight: FontWeight.w800)),
                          const SizedBox(height: 6),
                          Text(
                            "Evidence: $evidence",
                            style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              );
            }

            Widget stepsView;
            if (!cons) {
              stepsView = ListView.separated(
                shrinkWrap: true,
                itemCount: steps.length,
                separatorBuilder: (_, __) => const SizedBox(height: 10),
                itemBuilder: (_, i) {
                  final s = steps[i];
                  return buildTile(
                    left: "${s.processId}",
                    title: s.whatToDo.isEmpty ? "Step ${s.processId}" : s.whatToDo,
                    evidence: s.dataType,
                  );
                },
              );
            } else {
              final Map<int, List<ProcessStep>> mp = {};
              for (final st in steps) {
                final sn = stageNoFromText(st.whatToDo) ?? 0;
                if (sn <= 0) continue;
                mp.putIfAbsent(sn, () => []).add(st);
              }

              final keys = mp.keys.toList()..sort();

              final items = <Widget>[];
              for (final k in keys) {
                final lst = mp[k]!..sort((a, b) => a.processId.compareTo(b.processId));

                items.add(
                  Padding(
                    padding: const EdgeInsets.only(top: 6, bottom: 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text(
                        "Stage $k",
                        style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14),
                      ),
                    ),
                  ),
                );

                for (int i = 0; i < lst.length; i++) {
                  final s = lst[i];
                  items.add(buildTile(
                    left: "Step ${i + 1}",
                    title: stripStagePrefix(s.whatToDo.isEmpty ? "Step ${s.processId}" : s.whatToDo),
                    evidence: s.dataType,
                  ));
                  items.add(const SizedBox(height: 10));
                }
              }

              stepsView = ListView(
                shrinkWrap: true,
                children: items.isEmpty ? [const Text("No steps found")] : items,
              );
            }

            return SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      "Verification Steps",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                    ),
                    const SizedBox(height: 10),
                    Flexible(child: stepsView),
                    const SizedBox(height: 8),
                    CheckboxListTile(
                      value: agreed,
                      onChanged: (v) => setSheet(() => agreed = v == true),
                      title: const Text(
                        "I have read and understood the steps",
                        style: TextStyle(fontWeight: FontWeight.w700),
                      ),
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
                          _openWizard();
                        },
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF9933),
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
                        ),
                        child: const Text(
                          "Start Verification Process",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
                        ),
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


  Future<void> _openWizard() async {
    final changed = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => VerificationWizardPage(
          loanId: _currentLoan.loanId,
          userId: _currentLoan.userId,
        ),
      ),
    );

    if (changed == true) {
      _refreshLoanData();
    } else {
      _refreshLoanData(silent: true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final sanctionedAmount = _currentLoan.amount;
    final utilizationPercent = sanctionedAmount > 0
        ? (_amountUsed / sanctionedAmount).clamp(0.0, 1.0)
        : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          'Verification Page',
          style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold),
        ),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(
                width: 20,
                height: 20,
                child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black),
              ),
            )
          else
            IconButton(icon: const Icon(Icons.refresh), onPressed: _refreshLoanData),
        ],
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Loan Utilization",
                          style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text(
                        "${(utilizationPercent * 100).toInt()}% · Provisional",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    children: [
                      Container(
                        height: 10,
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(5),
                        ),
                      ),
                      FractionallySizedBox(
                        widthFactor: utilizationPercent,
                        child: Container(
                          height: 10,
                          decoration: BoxDecoration(
                            color: const Color(0xFF435E91),
                            borderRadius: BorderRadius.circular(5),
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        "₹${_amountUsed.toInt()} of ₹${sanctionedAmount.toInt()} used",
                        style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54),
                      ),
                      Text(
                        "${(utilizationPercent * 100).toInt()}% · Provisional",
                        style: TextStyle(color: Colors.grey[600], fontSize: 12),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: const [BoxShadow(color: Color(0x14000000), blurRadius: 10)],
              ),
              child: Column(
                children: [
                  _buildDetailRow("Beneficiary", _currentLoan.applicantName),
                  _buildDetailRow("Loan ID", _currentLoan.loanId),
                  _buildDetailRow("Type", _currentLoan.loanType),
                  _buildDetailRow("Scheme", _currentLoan.scheme),
                  _buildDetailRow("Date Applied", _currentLoan.dateApplied),
                  _buildDetailRow("Sanctioned Amount", "₹${_currentLoan.amount.toInt()}"),
                  _buildDetailRow("Status", _currentLoan.status),
                ],
              ),
            ),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              height: 55,
              child: ElevatedButton(
                onPressed: _allDone() ? null : _showStartSheet,
                style: ElevatedButton.styleFrom(
                  backgroundColor: _allDone() ? Colors.green : const Color(0xFF435E91),
                  disabledBackgroundColor: const Color(0xFF2E7D32),
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                ),
                child: Text(
                  _allDone() ? "All Steps Completed" : "Start Verification Process",
                  style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(
            width: 120,
            child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14)),
          ),
          Expanded(
            child: Text(
              value,
              style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }
}
