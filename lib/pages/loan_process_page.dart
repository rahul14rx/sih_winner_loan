import 'package:flutter/material.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/pages/verification_wizard_page.dart';

class LoanProcessPage extends StatefulWidget {
  final String loanId;
  final String userId;

  const LoanProcessPage({
    super.key,
    required this.loanId,
    required this.userId,
  });

  @override
  State<LoanProcessPage> createState() => _LoanProcessPageState();
}

class _LoanProcessPageState extends State<LoanProcessPage> {
  static const _saffron = Color(0xFFFF9933);
  static const _deep = Color(0xFFD26C00);
  static const _navy = Color(0xFF435E91);

  final _svc = BeneficiaryService();

  BeneficiaryLoan? _loan;
  bool _loading = true;
  bool _agree = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    try {
      final d = await _svc.fetchLoanDetails(widget.loanId);
      if (!mounted) return;
      setState(() {
        _loan = d;
        _loading = false;
      });
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  bool _isConstruction(BeneficiaryLoan loan) {
    final t = loan.loanType.toLowerCase();
    final s = loan.scheme.toLowerCase();
    return t.contains('construction') || t.contains('shop') || s.contains('construction') || s.contains('shop');
  }

  int? _stageNoFromText(String text) {
    final re = RegExp(r'^\s*Stage\s*(\d+)\s*:', caseSensitive: false);
    final m = re.firstMatch(text.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? "");
  }

  List<ProcessStep> _sortedSteps(BeneficiaryLoan loan) {
    final steps = [...loan.processes]..sort((a, b) => a.processId.compareTo(b.processId));
    return steps;
  }

  Map<int, List<ProcessStep>> _groupByStage(BeneficiaryLoan loan) {
    final sorted = _sortedSteps(loan);
    final mp = <int, List<ProcessStep>>{};
    for (final st in sorted) {
      final sn = _stageNoFromText(st.whatToDo) ?? 0;
      mp.putIfAbsent(sn, () => []).add(st);
    }
    return mp;
  }

  String _fmtMoney(double v) => "₹${v.toStringAsFixed(0)}";

  Color _statusColor(String s) {
    final t = s.toLowerCase().trim();
    if (t == 'verified') return const Color(0xFF138808);
    if (t == 'rejected') return Colors.red;
    if (t == 'pending_review') return Colors.blue;
    return Colors.grey[700]!;
  }

  String _prettyStatus(String s) {
    final t = s.toLowerCase().trim();
    if (t == 'not verified') return 'not verified';
    if (t == 'pending_review') return 'in review';
    return t.isEmpty ? 'pending' : t;
  }

  Widget _row(String k, String v, {Color? valueColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: Row(
        children: [
          SizedBox(
            width: 120,
            child: Text(k, style: TextStyle(color: Colors.grey[600], fontSize: 12)),
          ),
          Expanded(
            child: Text(
              v,
              textAlign: TextAlign.right,
              style: TextStyle(fontWeight: FontWeight.w700, color: valueColor ?? Colors.black87),
            ),
          ),
        ],
      ),
    );
  }

  void _openStepsSheet(BeneficiaryLoan loan) {
    setState(() => _agree = false);

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      backgroundColor: const Color(0xFFF7F8FB),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) {
        final isConst = _isConstruction(loan);
        final steps = _sortedSteps(loan);
        final groups = _groupByStage(loan);
        final stageKeys = groups.keys.toList()..sort();

        Widget stepTile(ProcessStep st) {
          return Container(
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade200),
            ),
            child: Row(
              children: [
                Container(
                  width: 34,
                  height: 34,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFFF1E6),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFFFD7B5)),
                  ),
                  child: Text(
                    "${st.processId}",
                    style: const TextStyle(fontWeight: FontWeight.w900, color: Color(0xFF7A3E00)),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        st.whatToDo.isEmpty ? "Step ${st.processId}" : st.whatToDo,
                        style: const TextStyle(fontWeight: FontWeight.w800),
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade100,
                              borderRadius: BorderRadius.circular(999),
                            ),
                            child: Text(
                              st.dataType,
                              style: TextStyle(fontSize: 12, color: Colors.grey[700]),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Text(
                            _prettyStatus(st.status),
                            style: TextStyle(fontSize: 12, color: _statusColor(st.status), fontWeight: FontWeight.w800),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        }

        final content = <Widget>[];

        content.add(const SizedBox(height: 6));
        content.add(const Padding(
          padding: EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            "Verification Steps",
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900),
          ),
        ));
        content.add(const SizedBox(height: 10));

        if (!isConst) {
          content.addAll(steps.map((s) => Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
            child: stepTile(s),
          )));
        } else {
          for (final k in stageKeys) {
            if (k == 0) continue;
            content.add(Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                "Stage $k",
                style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ));
            final stList = groups[k] ?? [];
            for (final s in stList) {
              content.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: stepTile(s),
              ));
            }
          }

          if (groups.containsKey(0) && (groups[0]?.isNotEmpty ?? false)) {
            content.add(const Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 8),
              child: Text(
                "Other",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 13),
              ),
            ));
            for (final s in groups[0]!) {
              content.add(Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 10),
                child: stepTile(s),
              ));
            }
          }
        }

        content.add(const SizedBox(height: 8));
        content.add(Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 0),
          child: Row(
            children: [
              Checkbox(
                value: _agree,
                activeColor: _saffron,
                onChanged: (v) => setState(() => _agree = v == true),
              ),
              const Expanded(
                child: Text(
                  "I have read and understood the steps",
                  style: TextStyle(fontWeight: FontWeight.w700),
                ),
              ),
            ],
          ),
        ));

        content.add(Padding(
          padding: EdgeInsets.fromLTRB(16, 6, 16, MediaQuery.of(context).padding.bottom + 16),
          child: SizedBox(
            width: double.infinity,
            height: 52,
            child: ElevatedButton(
              onPressed: _agree
                  ? () {
                Navigator.pop(context);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => VerificationWizardPage(
                      loanId: loan.loanId,
                      userId: loan.userId.isNotEmpty ? loan.userId : widget.userId,
                    ),
                  ),
                ).then((_) => _load(silent: true));
              }
                  : null,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade600,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                "Start Verification Process",
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w900),
              ),
            ),
          ),
        ));

        return SafeArea(
          child: SizedBox(
            height: MediaQuery.of(context).size.height * 0.82,
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: content,
              ),
            ),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;

    return Scaffold(
      backgroundColor: const Color(0xFFF6F7FB),
      appBar: AppBar(
        title: const Text("Verification Page"),
        centerTitle: true,
        actions: [
          IconButton(
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : (loan == null)
          ? Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text("Failed to load loan details"),
            const SizedBox(height: 10),
            ElevatedButton(onPressed: _load, child: const Text("Retry")),
          ],
        ),
      )
          : SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
          child: Column(
            children: [
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        const Text("Loan Utilization", style: TextStyle(fontWeight: FontWeight.w900)),
                        const Spacer(),
                        Text("Provisional", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                      ],
                    ),
                    const SizedBox(height: 10),
                    ClipRRect(
                      borderRadius: BorderRadius.circular(999),
                      child: LinearProgressIndicator(
                        value: 0.0,
                        minHeight: 10,
                      ),
                    ),
                    const SizedBox(height: 10),
                    Text(
                      "${_fmtMoney(0)} of ${_fmtMoney(loan.amount)} used",
                      style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w800),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 14),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: Colors.grey.shade200),
                ),
                child: Column(
                  children: [
                    _row("Beneficiary", loan.applicantName),
                    _row("Loan ID", loan.loanId),
                    _row("Type", loan.loanType),
                    _row("Scheme", loan.scheme),
                    _row("Date Applied", loan.dateApplied),
                    _row("Sanctioned Amount", _fmtMoney(loan.amount)),
                    _row("Status", loan.status, valueColor: _statusColor(loan.status)),
                  ],
                ),
              ),
              const Spacer(),
              SizedBox(
                width: double.infinity,
                height: 54,
                child: ElevatedButton(
                  onPressed: () => _openStepsSheet(loan),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _saffron,
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
      ),
    );
  }
}
