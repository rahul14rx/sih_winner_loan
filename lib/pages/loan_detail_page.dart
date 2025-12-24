import 'dart:convert';
import 'dart:io';

import 'package:loan2/services/bank_service.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';

class LoanDetailPage extends StatefulWidget {
  final String loanId;
  final String? officerId;

  const LoanDetailPage({super.key, required this.loanId, this.officerId});

  @override
  State<LoanDetailPage> createState() => _LoanDetailPageState();
}

class _LoanDetailPageState extends State<LoanDetailPage> {
  String _two(int n) => n.toString().padLeft(2, '0');
  DateTime? _parseDateTimeAny(dynamic v) {
    if (v == null) return null;
    if (v is DateTime) return v.toLocal();

    final s = v.toString().trim();
    if (s.isEmpty) return null;

    // "YYYY-MM-DD" (date only)
    if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(s)) {
      final dt = DateTime.tryParse(s);
      return dt?.toLocal();
    }

    // ISO datetime or anything DateTime can parse
    final dt = DateTime.tryParse(s);
    return dt?.toLocal();
  }

  bool get _isLoanDueExpired {
    final dueAt = _parseDateTimeAny(_details?['time_period']);
    if (dueAt == null) return false;
    return DateTime.now().isAfter(dueAt);
  }

  Map<String, dynamic> get _noticeMap {
    final n = _details?['notice'];
    if (n is Map) return Map<String, dynamic>.from(n);
    return {};
  }

  String get _noticeStatus {
    final s = (_noticeMap['status'] ?? 'none').toString().toLowerCase().trim();
    return s.isEmpty ? 'none' : s;
  }

  Future<void> _sendNoticeQuick() async {
    final online = await SyncService.realInternetCheck();
    if (!online) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Offline: cannot send notice right now."), backgroundColor: Colors.orange),
      );
      return;
    }

    final officerId = _resolveOfficerId();
    if (officerId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Officer id missing"), backgroundColor: Colors.red),
      );
      return;
    }

    // ✅ simple default notice payload (no UI)
    final dueAt = DateTime.now().add(const Duration(hours: 24));
    final ok = await _bank.sendOfficerNotice(
      officerId: officerId,
      loanId: widget.loanId,
      title: "Notice",
      message: "Please respond regarding the loan verification for Loan ID: ${widget.loanId}.",
      dueAt: dueAt,
      noticeType: "info",
    );

    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(ok ? "Notice sent ✅" : "Failed to send notice ❌"),
        backgroundColor: ok ? Colors.green : Colors.red,
      ),
    );

    if (ok) {
      await _fetchDetails(); // refresh state from backend
    }
  }

  Widget _buildNoticeCardBetween() {
    final expired = _isLoanDueExpired;
    final nStatus = _noticeStatus;

    // ✅ Before due time: show NOTHING (as you asked)
    final hasActiveNotice = nStatus != 'none';
    if (!expired && !hasActiveNotice) return const SizedBox.shrink();

    final canSend = expired && (nStatus == 'none' || nStatus == 'expired' || nStatus == 'resolved');

    String title;
    String subtitle;

    if (nStatus == 'responded') {
      title = "Received a response ✅";
      subtitle = "Tap to view beneficiary reply.";
    } else if (nStatus == 'sent') {
      title = "Notice sent";
      subtitle = "Waiting for beneficiary response.";
    } else if (canSend) {
      title = "Time due. Send Notice";
      subtitle = "Due time is over. Send a notice to beneficiary.";
    } else {
      title = "Notice";
      subtitle = "Tap to view details.";
    }

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: InkWell(
        borderRadius: BorderRadius.circular(18),
        onTap: () {
          // OPTIONAL: open notice details page later
          // Navigator.push(context, MaterialPageRoute(builder: (_) => NoticeListPage(officerId: _resolveOfficerId())));
        },
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: _brandBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: const Icon(Icons.campaign_outlined, color: _brandBlue),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: const TextStyle(fontWeight: FontWeight.w900)),
                    const SizedBox(height: 2),
                    Text(subtitle, style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 12)),
                  ],
                ),
              ),
              if (canSend)
                ElevatedButton(
                  onPressed: _sendNoticeQuick,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                  ),
                  child: const Text("Send", style: TextStyle(fontWeight: FontWeight.w900)),
                )
              else
                TextButton(
                  onPressed: () {
                    // OPTIONAL: open notice details page
                    // Navigator.push(context, MaterialPageRoute(builder: (_) => NoticeListPage(officerId: _resolveOfficerId())));
                  },
                  child: const Text("View"),
                ),
            ],
          ),
        ),
      ),
    );
  }

  String _resolveOfficerId() {
    final a = (widget.officerId ?? '').trim();
    if (a.isNotEmpty) return a;
    final v = _details?['loan_officer_id'] ?? _details?['officer_id'];
    return (v ?? '').toString().trim();
  }

  String _formatDateDdMmYyyy(dynamic input) {
    if (input == null) return "N/A";
    final s = input.toString().trim();
    if (s.isEmpty) return "N/A";

    final dt = DateTime.tryParse(s);
    if (dt != null) {
      return "${_two(dt.day)} - ${_two(dt.month)} - ${dt.year}";
    }

    final m = RegExp(r'^(\d{1,2})\D+(\d{1,2})\D+(\d{4})$').firstMatch(s);
    if (m != null) {
      final d = int.parse(m.group(1)!);
      final mo = int.parse(m.group(2)!);
      final y = m.group(3)!;
      return "${_two(d)} - ${_two(mo)} - $y";
    }

    return s;
  }

  Map<String, dynamic>? _details;
  bool _loading = true;
  String _error = '';
  bool _isOnline = true;
  final BankService _bank = BankService();

  bool _verificationTriggered = false;

  bool _bulkUpdating = false;
  final Map<String, int> _carouselIndexByProcess = {};

  static const _brandBlue = Color(0xFF1E5AA8);

  @override
  void initState() {
    super.initState();
    _checkOnline();
    _fetchDetails();
  }

  Future<void> _openSendNoticeSheet() async {
    final titleCtrl = TextEditingController(text: "Notice");
    final msgCtrl = TextEditingController();
    int hours = 24; // default due time

    String officerId = (widget.officerId ?? '').trim();
    if (officerId.isEmpty) {
      final v = _details?['loan_officer_id'] ?? _details?['officer_id'];
      officerId = (v ?? '').toString().trim();
    }

    if (officerId.isEmpty) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Officer id missing. Can't send notice."),
          backgroundColor: Colors.red,
        ),
      );
      return;
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
            final bottom = MediaQuery.of(ctx).viewInsets.bottom;

            return Padding(
              padding: EdgeInsets.fromLTRB(16, 14, 16, 16 + bottom),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    height: 6,
                    width: 60,
                    decoration: BoxDecoration(
                      color: Colors.grey[300],
                      borderRadius: BorderRadius.circular(6),
                    ),
                  ),
                  const SizedBox(height: 12),
                  const Text("Send Notice",
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900)),
                  const SizedBox(height: 12),
                  TextField(
                    controller: titleCtrl,
                    decoration: const InputDecoration(labelText: "Title"),
                  ),
                  const SizedBox(height: 10),
                  TextField(
                    controller: msgCtrl,
                    maxLines: 3,
                    decoration: const InputDecoration(labelText: "Message"),
                  ),
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      const Text("Due in:", style: TextStyle(fontWeight: FontWeight.w800)),
                      const SizedBox(width: 10),
                      ChoiceChip(
                        label: const Text("24h"),
                        selected: hours == 24,
                        onSelected: (_) => setSheet(() => hours = 24),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("48h"),
                        selected: hours == 48,
                        onSelected: (_) => setSheet(() => hours = 48),
                      ),
                      const SizedBox(width: 8),
                      ChoiceChip(
                        label: const Text("7d"),
                        selected: hours == 168,
                        onSelected: (_) => setSheet(() => hours = 168),
                      ),
                    ],
                  ),
                  const SizedBox(height: 14),
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: ElevatedButton.icon(
                      onPressed: () async {
                        final msg = msgCtrl.text.trim();
                        final title = titleCtrl.text.trim();

                        if (msg.isEmpty) {
                          ScaffoldMessenger.of(context).showSnackBar(
                            const SnackBar(
                              content: Text("Message required"),
                              backgroundColor: Colors.red,
                            ),
                          );
                          return;
                        }

                        final dueAt = DateTime.now().add(Duration(hours: hours));

                        final ok = await _bank.sendOfficerNotice(
                          officerId: officerId,
                          loanId: widget.loanId,
                          title: title,
                          message: msg,
                          dueAt: dueAt,
                          noticeType: "info",
                        );

                        if (!mounted) return;
                        Navigator.pop(ctx);

                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text(ok ? "Notice sent ✅" : "Failed to send notice ❌"),
                            backgroundColor: ok ? Colors.green : Colors.red,
                          ),
                        );
                      },
                      icon: const Icon(Icons.send_rounded),
                      label: const Text("Send"),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );

    titleCtrl.dispose();
    msgCtrl.dispose();
  }

  Future<void> _checkOnline() async {
    _isOnline = await SyncService.realInternetCheck();
    if (mounted) setState(() {});
  }

  Future<File> _getCacheFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'loan_detail_cache_${widget.loanId}.json'));
  }

  Future<void> _writeToCache(Map<String, dynamic> data) async {
    try {
      final file = await _getCacheFile();
      await file.writeAsString(jsonEncode(data));
    } catch (e) {
      debugPrint("Failed to write cache: $e");
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final data = jsonDecode(content) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            _details = data;
            _loading = false;
            _error = '';
          });
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("You are offline. Viewing cached data."),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) setState(() => _error = "No offline data available.");
      }
    } catch (e) {
      debugPrint("Failed to load cache: $e");
      if (mounted) setState(() => _error = "Failed to load offline data.");
    }
  }

  Future<void> _fetchDetails() async {
    if (!mounted) return;
    setState(() {
      _loading = true;
      _error = '';
    });

    try {
      final isOnline = await SyncService.realInternetCheck();
      if (!isOnline) {
        setState(() => _loading = false);
        await _loadFromCache();
        return;
      }

      final data = await getJson('loan_details?loan_id=${widget.loanId}');
      if (!mounted) return;

      final details = data['loan_details'] as Map<String, dynamic>?;

      setState(() {
        _details = details;
        _loading = false;
      });

      if (details != null) {
        await _writeToCache(details);

        final status = (details['status'] ?? '').toString().toLowerCase();
        if (_verificationTriggered && status == 'verified') {
          _verificationTriggered = false;
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("All steps verified. Moved to History."),
              backgroundColor: Colors.green,
            ),
          );
          Navigator.pop(context, true);
        }
      }
    } catch (e) {
      debugPrint("Error fetching details: $e");
      if (mounted) {
        setState(() => _loading = false);
        await _loadFromCache();
      }
    }
  }

  Future<void> _verifyProcess(String processId, String status) async {
    _verificationTriggered = true;

    bool isOnline = await SyncService.realInternetCheck();

    if (!isOnline) {
      try {
        await DatabaseHelper.instance.insertOfficerAction(
          loanId: widget.loanId,
          processId: processId,
          actionType: status,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text("Offline: Action queued ($status). Will sync when online."),
              backgroundColor: Colors.orange,
            ),
          );
          _optimisticUpdate(processId, status);
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Failed to save action: $e")),
          );
        }
      }
      return;
    }

    try {
      final response = await http.post(
        Uri.parse('${kBaseUrl}bank/verify'),
        headers: {'Content-Type': 'application/json'},
        body: jsonEncode({
          'loan_id': widget.loanId,
          'process_id': processId,
          'status': status,
        }),
      );

      if (response.statusCode == 200) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text("Marked as $status"), backgroundColor: Colors.green),
          );
        }
        _fetchDetails();
      } else {
        throw Exception("Server error: ${response.statusCode}");
      }
    } catch (e) {
      debugPrint("Error updating status: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to update: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _verifyAllProcesses(String status) async {
    if (_bulkUpdating) return;

    final processes = _processes();
    final processIds = processes
        .map((p) => (p['id'] ?? '').toString().trim())
        .where((id) => id.isNotEmpty)
        .toList();

    if (processIds.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("No steps to verify.")),
      );
      return;
    }

    setState(() => _bulkUpdating = true);
    _verificationTriggered = true;

    final online = await SyncService.realInternetCheck();

    if (!online) {
      try {
        for (final pid in processIds) {
          await DatabaseHelper.instance.insertOfficerAction(
            loanId: widget.loanId,
            processId: pid,
            actionType: status,
          );
          _optimisticUpdate(pid, status);
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Offline: queued '$status' for ${processIds.length} steps."),
            backgroundColor: Colors.orange,
          ),
        );
      } catch (e) {
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Failed to queue actions: $e"), backgroundColor: Colors.red),
        );
      } finally {
        if (mounted) setState(() => _bulkUpdating = false);
      }
      return;
    }

    try {
      int okCount = 0;
      for (final pid in processIds) {
        final resp = await http.post(
          Uri.parse('${kBaseUrl}bank/verify'),
          headers: {'Content-Type': 'application/json'},
          body: jsonEncode({
            'loan_id': widget.loanId,
            'process_id': pid,
            'status': status,
          }),
        );
        if (resp.statusCode == 200) okCount++;
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Marked $okCount/${processIds.length} steps as $status"),
          backgroundColor: okCount == processIds.length ? Colors.green : Colors.orange,
        ),
      );

      await _fetchDetails();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Bulk update failed: $e"), backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _bulkUpdating = false);
    }
  }

  void _optimisticUpdate(String processId, String status) {
    if (_details == null) return;

    final processes = List<Map<String, dynamic>>.from(_details!['process'] ?? []);
    final index = processes.indexWhere((p) => (p['id'] ?? '').toString() == processId);

    if (index != -1) {
      processes[index]['status'] = status;
      setState(() {
        _details!['process'] = processes;
      });
      _writeToCache(_details!);
    }
  }

  Map<String, dynamic> _extraMap() {
    final raw = _details?['beneficiary_extra'];
    if (raw is Map) return Map<String, dynamic>.from(raw);
    return {};
  }

  String _prettyLabel(String key) {
    const labels = {
      'brand_model': 'Brand & Model',
      'brand': 'Brand',
      'model': 'Model',
      'no_of_cows': 'Number of Cows',
      'institution_name': 'Institution Name',
      'course_name': 'Course Name',
      'course_provider_name': 'Course Provider',
      'course_mode': 'Course Mode',
      'floors': 'Number of Floors',
      'stages': 'Stages',
      'shop_floors': 'Shop Floors',
      'loan_category': 'Loan Category',
      'loan_purpose': 'Loan Purpose',
    };

    if (labels.containsKey(key)) return labels[key]!;
    return key
        .replaceAll('_', ' ')
        .split(' ')
        .where((w) => w.trim().isNotEmpty)
        .map((w) => w[0].toUpperCase() + w.substring(1))
        .join(' ');
  }

  List<Widget> _buildDynamicExtraRows() {
    final extra = _extraMap();
    extra.removeWhere((k, v) => v == null || v.toString().trim().isEmpty);

    const alreadyShown = {
      'loan_id',
      'user_id',
      'loan_officer_id',
      'applicant_name',
      'amount',
      'scheme',
      'loan_type',
      'loan_category',
      'loan_purpose',
      'date_applied',
      'status',
      'process',
      'stage_utilization',
      'beneficiary_address',
      'asset_purchased',
      'beneficiary_extra',
    };

    extra.removeWhere((k, _) => alreadyShown.contains(k));
    if (extra.isEmpty) return const [];

    const preferred = [
      'brand_model',
      'no_of_cows',
      'institution_name',
      'course_mode',
      'course_name',
      'course_provider_name',
      'floors',
      'stages',
      'shop_floors',
    ];

    final orderedKeys = <String>[];
    for (final k in preferred) {
      if (extra.containsKey(k)) orderedKeys.add(k);
    }
    final remaining = extra.keys.where((k) => !orderedKeys.contains(k)).toList()..sort();
    orderedKeys.addAll(remaining);

    return orderedKeys.map((k) {
      final v = extra[k].toString();
      return _buildDetailRow(_prettyLabel(k), v, wrapValue: true);
    }).toList();
  }

  double _num(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    final s = v.toString().replaceAll(',', '').trim();
    return double.tryParse(s) ?? 0.0;
  }

  List<Map<String, dynamic>> _processes() {
    final raw = _details?['process'];
    if (raw is List) {
      return raw.whereType<Map>().map((e) => Map<String, dynamic>.from(e)).toList();
    }
    return const [];
  }

  double _loanAmount() => _num(_details?['amount']);

  double _utilizedAmountFromBackendFlexible() {
    if (_details == null) return 0.0;

    for (final k in const [
      'utilized_amount',
      'amount_utilized',
      'utilization_amount',
      'utilized',
      'used_amount',
      'total_utilized',
    ]) {
      if (_details!.containsKey(k)) {
        final v = _num(_details![k]);
        if (v > 0) return v;
      }
    }

    final su = _details!['stage_utilization'];
    if (su is List) {
      double sum = 0;
      for (final item in su) {
        if (item is Map) {
          final m = Map<String, dynamic>.from(item);
          sum += _num(m['utilization_amount'] ?? m['utilized_amount'] ?? m['amount'] ?? m['utilized']);
        }
      }
      if (sum > 0) return sum;
    }

    double sum = 0;
    for (final p in _processes()) {
      sum += _num(p['utilization_amount']);
    }
    return sum;
  }

  String _processTitle(Map<String, dynamic> p) {
    final t =
    (p['label'] ?? p['title'] ?? p['what_to_do'] ?? p['name'] ?? 'Step')
        .toString()
        .trim();
    return t.isEmpty ? 'Step' : t;
  }

  String _statusRaw(Map<String, dynamic> p) {
    return (p['status'] ?? p['process_status'] ?? '').toString().toLowerCase().trim();
  }

  List<String> _extractMediaUrls(Map<String, dynamic> p) {
    final urls = <String>[];

    final mediaUrl = (p['media_url'] ?? p['mediaUrl'] ?? '').toString().trim();
    if (mediaUrl.isNotEmpty) urls.add(mediaUrl);

    final mediaUrls = p['media_urls'] ?? p['mediaUrls'] ?? p['media'];
    if (mediaUrls is List) {
      for (final x in mediaUrls) {
        final s = x.toString().trim();
        if (s.isNotEmpty) urls.add(s);
      }
    }

    final fileId = p['file_id'] ?? p['fileId'];
    if (fileId is List) {
      for (final id in fileId) {
        final s = id.toString().trim();
        if (s.isNotEmpty) urls.add("${kBaseUrl}media/$s");
      }
    } else if (fileId != null) {
      final s = fileId.toString().trim();
      if (s.isNotEmpty) urls.add("${kBaseUrl}media/$s");
    }

    final seen = <String>{};
    return urls.where((u) => seen.add(u)).toList();
  }

  bool _looksLikeVideo(String url) {
    final u = url.toLowerCase();
    return u.endsWith('.mp4') ||
        u.endsWith('.mov') ||
        u.endsWith('.mkv') ||
        u.endsWith('.webm') ||
        u.contains('video');
  }

  Future<void> _openExternal(String url) async {
    try {
      final uri = Uri.parse(url);
      final ok = await launchUrl(uri, mode: LaunchMode.externalApplication);
      if (!ok && mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Couldn't open media.")),
        );
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Invalid media URL.")),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final processes = _details == null ? const <Map<String, dynamic>>[] : _processes();

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text(
          "Verification Page",
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w900,
            fontSize: 18,
          ),
        ),
        backgroundColor: _brandBlue,
        foregroundColor: Colors.white,
        elevation: 0,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(bottom: Radius.circular(25)),
        ),
        actions: [
          IconButton(
            onPressed: _fetchDetails,
            icon: const Icon(Icons.refresh_rounded),
            tooltip: "Refresh",
          ),
          FutureBuilder<bool>(
            future: SyncService.realInternetCheck(),
            builder: (context, snapshot) {
              final online = snapshot.data ?? false;
              return Padding(
                padding: const EdgeInsets.only(right: 14),
                child: Icon(
                  online ? Icons.cloud_done : Icons.cloud_off,
                  color: online ? Colors.lightGreenAccent : Colors.white70,
                ),
              );
            },
          ),
        ],
      ),

      body: _buildBody(),
      bottomNavigationBar: (_loading || _error.isNotEmpty || _details == null || processes.isEmpty)
          ? null
          : SafeArea(
        child: Container(
          decoration: BoxDecoration(
            color: Colors.white,
            boxShadow: [
              BoxShadow(
                color: Colors.black.withOpacity(0.08),
                blurRadius: 14,
                offset: const Offset(0, -6),
              )
            ],
          ),
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
          child: Row(
            children: [
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _bulkUpdating ? null : () => _verifyAllProcesses('verified'),
                  icon: _bulkUpdating
                      ? const SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                  )
                      : const Icon(Icons.check_circle_outline, size: 18),
                  label: const Text("Approve"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.green[600],
                    disabledBackgroundColor: Colors.green[200],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _bulkUpdating ? null : () => _verifyAllProcesses('rejected'),
                  icon: const Icon(Icons.highlight_off, size: 18),
                  label: const Text("Reject"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.red[600],
                    disabledBackgroundColor: Colors.red[200],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ElevatedButton.icon(
                  onPressed: _bulkUpdating ? null : () => _verifyAllProcesses('retake'),
                  icon: const Icon(Icons.replay_rounded, size: 18),
                  label: const Text("Retake"),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Colors.amber[700],
                    disabledBackgroundColor: Colors.amber[200],
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    if (_loading) return const Center(child: CircularProgressIndicator());

    if (_error.isNotEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            const Icon(Icons.error_outline, size: 48, color: Colors.redAccent),
            const SizedBox(height: 16),
            Text(_error, style: const TextStyle(color: Colors.black54), textAlign: TextAlign.center),
            const SizedBox(height: 16),
            ElevatedButton(onPressed: _fetchDetails, child: const Text("Retry")),
          ]),
        ),
      );
    }

    if (_details == null) return const Center(child: Text("No details found."));

    final processes = _processes();

    if (processes.isEmpty) {
      return RefreshIndicator(
        onRefresh: _fetchDetails,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.all(16),
          children: [
            _buildUtilizationCard(),
            const SizedBox(height: 12),
            _buildDetailsCard(),
            const SizedBox(height: 16),
            const Text("No verification steps for this loan."),
            _buildDetailsCard(),
            const SizedBox(height: 10),
            _buildNoticeCardBetween(),
            const SizedBox(height: 16),

          ],
        ),
      );
    }

    return DefaultTabController(
      key: ValueKey("loan_${widget.loanId}_tabs_${processes.length}"),
      length: processes.length,
      child: Builder(
        builder: (context) {
          final controller = DefaultTabController.of(context);

          return RefreshIndicator(
            onRefresh: _fetchDetails,
            child: NestedScrollView(
              physics: const AlwaysScrollableScrollPhysics(),
              headerSliverBuilder: (context, innerScrolled) {
                return [
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 14),
                      child: Column(
                        children: [
                          _buildUtilizationCard(),
                          const SizedBox(height: 12),
                          _buildDetailsCard(),
                          const SizedBox(height: 10),
                          _buildNoticeCardBetween(), // ✅ NOTICE HERE (between loan card and steps)
                          const SizedBox(height: 14),
                          AnimatedBuilder(
                            animation: controller,
                            builder: (context, _) {
                              return _buildRequestsAndStepsStrip(
                                controller: controller,
                                processes: processes,
                              );
                            },
                          ),

                        ],
                      ),
                    ),
                  ),
                ];
              },
              body: TabBarView(
                children: [
                  for (final p in processes) _buildProcessTab(p),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildRequestsAndStepsStrip({
    required TabController controller,
    required List<Map<String, dynamic>> processes,
  }) {
    return Column(
      children: [
        Row(
          children: [
            const Text(
              "My Requests & Steps",
              style: TextStyle(fontSize: 16, fontWeight: FontWeight.w900, color: Colors.black87),
            ),
            const Spacer(),
            Text(
              "${processes.length} steps",
              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700),
            ),
          ],
        ),
        const SizedBox(height: 10),
        Builder(
          builder: (context) {
            final ts = MediaQuery.textScaleFactorOf(context).clamp(1.0, 1.25);
            final stripH = (220.0 * ts).clamp(220.0, 260.0);

            return SizedBox(
              height: stripH,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                itemCount: processes.length,
                padding: const EdgeInsets.only(right: 4),
                separatorBuilder: (_, __) => const SizedBox(width: 12),
                itemBuilder: (context, i) {
                  final p = processes[i];
                  final selected = controller.index == i;

                  final title = _processTitle(p);
                  final status = _statusRaw(p);
                  final urls = _extractMediaUrls(p);
                  final thumb = urls.isNotEmpty ? urls.first : '';

                  const location = "Chennai Institute of Technology";

                  final dynamic rawScore = p['score'];
                  String aiScore;

                  if (rawScore == null) {
                    aiScore = "1";
                  } else if (rawScore is num) {
                    aiScore = rawScore.toStringAsFixed(rawScore % 1 == 0 ? 0 : 1);
                  } else {
                    aiScore = rawScore.toString();
                  }

                  return _StepCard(
                    index: i,
                    title: title,
                    status: status,
                    selected: selected,
                    thumbUrl: thumb,
                    isVideo: thumb.isNotEmpty && _looksLikeVideo(thumb),
                    locationText: "Location: $location",
                    aiScoreText: "AI Score: $aiScore",
                    onTap: () => controller.animateTo(i),
                  );
                },
              ),
            );
          },
        ),
        const SizedBox(height: 6),
      ],
    );
  }

  Widget _buildUtilizationCard() {
    final loan = _loanAmount();
    final used = _utilizedAmountFromBackendFlexible();
    final pct = (loan <= 0) ? 0.0 : (used / loan).clamp(0.0, 1.0);
    final pctInt = (pct * 100).round();

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
        child: Stack(
          children: [
            Positioned(
              top: 0,
              right: 0,
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                decoration: BoxDecoration(
                  color: _brandBlue.withOpacity(0.10),
                  borderRadius: BorderRadius.circular(999),
                  border: Border.all(color: _brandBlue.withOpacity(0.18)),
                ),
                child: Text(
                  "$pctInt% used",
                  style: const TextStyle(fontWeight: FontWeight.w900, color: _brandBlue, fontSize: 12),
                ),
              ),
            ),
            Row(
              children: [
                SizedBox(
                  width: 70,
                  height: 70,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      CircularProgressIndicator(
                        value: pct,
                        strokeWidth: 7,
                        backgroundColor: Colors.grey.shade200,
                        color: _brandBlue,
                      ),
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text("$pctInt%", style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 14)),
                          Text("Used",
                              style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 11)),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 14),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.only(right: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text("Utilization", style: TextStyle(fontSize: 14, fontWeight: FontWeight.w900)),
                        const SizedBox(height: 6),
                        Text(
                          "₹${used.toStringAsFixed(2)} used of ₹${loan.toStringAsFixed(2)}",
                          style: TextStyle(color: Colors.grey.shade700, fontWeight: FontWeight.w700, fontSize: 12),
                        ),
                        const SizedBox(height: 10),
                        ClipRRect(
                          borderRadius: BorderRadius.circular(999),
                          child: LinearProgressIndicator(
                            value: pct,
                            minHeight: 8,
                            backgroundColor: Colors.grey.shade200,
                            color: _brandBlue,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDetailsCard() {
    final rawDateApplied = _details?['date_applied'];
    final rawDueDate = _details?['time_period'];

    final dateApplied = _formatDateDdMmYyyy(rawDateApplied);
    final dueDate = _formatDateDdMmYyyy(rawDueDate);
    final showDue = (rawDueDate?.toString().trim() ?? '').isNotEmpty;

    final loanCategory = (_details?['loan_category'] ?? '').toString().trim();
    final loanPurpose = (_details?['loan_purpose'] ?? 'N/A').toString();
    final beneficiaryAddress = (_details?['beneficiary_address'] ?? '').toString().trim();
    final assetPurchased = (_details?['asset_purchased'] ?? '').toString().trim();

    final extraRows = _buildDynamicExtraRows();
    final overallStatus = (_details?['status'] ?? 'N/A').toString();
    final applicantName = (_details?['applicant_name'] ?? 'N/A').toString();

    return Card(
      elevation: 2,
      shadowColor: Colors.black.withOpacity(0.06),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    applicantName,
                    style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: Colors.black87),
                  ),
                ),
                _StatusPill(status: overallStatus.toLowerCase().trim()),
              ],
            ),
            const SizedBox(height: 8),
            _buildDetailRow("Loan ID", (_details?['loan_id'] ?? 'N/A').toString()),
            _buildDetailRow("Type", (_details?['loan_type'] ?? 'N/A').toString(), wrapValue: true),
            _buildDetailRow("Scheme", (_details?['scheme'] ?? 'N/A').toString()),
            _buildDetailRow("Date Applied", dateApplied),
            if (showDue) _buildDetailRow("Due Date", dueDate),
            _buildDetailRow("Sanctioned Amount", "₹${_details?['amount']?.toString() ?? '0'}"),
            if (loanCategory.isNotEmpty) _buildDetailRow("Loan Category", loanCategory, wrapValue: true),
            _buildDetailRow("Loan Purpose", loanPurpose, wrapValue: true),
            if (beneficiaryAddress.isNotEmpty) _buildDetailRow("Beneficiary Address", beneficiaryAddress, wrapValue: true),
            if (assetPurchased.isNotEmpty) _buildDetailRow("Asset Purchased", assetPurchased, wrapValue: true),
            if (extraRows.isNotEmpty) ...[
              const SizedBox(height: 4),
              ...extraRows,
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildDetailRow(String label, String value, {bool wrapValue = false}) {
    final labelStyle = TextStyle(color: Colors.grey[600], fontSize: 13, fontWeight: FontWeight.w600);
    final valueStyle = const TextStyle(color: Colors.black87, fontSize: 13, fontWeight: FontWeight.w800);

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3.0),
      child: Row(
        crossAxisAlignment: wrapValue ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(flex: 4, child: Text(label, style: labelStyle)),
          const SizedBox(width: 10),
          Expanded(
            flex: 6,
            child: Align(
              alignment: Alignment.centerRight,
              child: Text(
                value,
                textAlign: TextAlign.right,
                style: valueStyle,
                maxLines: wrapValue ? 3 : 1,
                overflow: TextOverflow.ellipsis,
                softWrap: wrapValue,
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProcessTab(Map<String, dynamic> p) {
    return const SizedBox.shrink();
  }
}

// ------------------- CARDS / PILLS / PREVIEW -------------------

class _StepCard extends StatelessWidget {
  final int index;
  final String title;
  final String status;
  final bool selected;
  final String thumbUrl;
  final bool isVideo;
  final String locationText;
  final String aiScoreText;
  final VoidCallback onTap;

  static const _brandBlue = Color(0xFF1E5AA8);

  const _StepCard({
    required this.index,
    required this.title,
    required this.status,
    required this.selected,
    required this.thumbUrl,
    required this.isVideo,
    required this.locationText,
    required this.aiScoreText,
    required this.onTap,
  });

  Color _statusColor() {
    switch (status) {
      case 'verified':
        return Colors.green;
      case 'rejected':
        return Colors.red;
      case 'retake':
        return Colors.amber;
      default:
        return Colors.grey;
    }
  }

  String _statusLabel() {
    final s = status.trim();
    if (s.isEmpty || s == 'pending') return 'not verified';
    return s;
  }

  Widget _thumb(BuildContext context) {
    void openPreview() {
      if (thumbUrl.trim().isEmpty) return;

      showDialog(
        context: context,
        barrierDismissible: true,
        builder: (_) => _MediaPreviewDialog(url: thumbUrl, isVideo: isVideo),
      );
    }

    const double h = 86;

    if (thumbUrl.trim().isEmpty) {
      return Container(
        height: h,
        decoration: BoxDecoration(color: Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
        child: const Center(child: Icon(Icons.image_not_supported_outlined, color: Colors.grey)),
      );
    }

    if (isVideo) {
      return InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: openPreview,
        child: Container(
          height: h,
          decoration: BoxDecoration(color: Colors.black, borderRadius: BorderRadius.circular(12)),
          child: const Center(child: Icon(Icons.play_circle_fill_rounded, color: Colors.white, size: 46)),
        ),
      );
    }

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: openPreview,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: Image.network(
          thumbUrl,
          height: h,
          width: double.infinity,
          fit: BoxFit.cover,
          loadingBuilder: (ctx, child, progress) => progress == null
              ? child
              : Container(height: h, color: Colors.grey[200], child: const Center(child: CircularProgressIndicator())),
          errorBuilder: (_, __, ___) => Container(
            height: h,
            color: Colors.grey.shade200,
            child: const Center(child: Icon(Icons.broken_image_outlined, color: Colors.grey)),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final border = selected ? _brandBlue.withOpacity(0.55) : Colors.grey.withOpacity(0.18);
    final statusColor = _statusColor();

    return SizedBox(
      width: 270,
      child: Material(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Container(
            padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: border, width: selected ? 1.2 : 1),
              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.04), blurRadius: 10, offset: const Offset(0, 6))],
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Container(
                      width: 32,
                      height: 32,
                      alignment: Alignment.center,
                      decoration: BoxDecoration(color: _brandBlue.withOpacity(0.10), shape: BoxShape.circle),
                      child: Text("${index + 1}", style: const TextStyle(color: _brandBlue, fontWeight: FontWeight.w900)),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w900, color: Colors.black87),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                _thumb(context),
                const SizedBox(height: 6),
                Text(
                  locationText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: Colors.grey.shade800, fontWeight: FontWeight.w700, fontSize: 12),
                ),
                const SizedBox(height: 3),
                Text(
                  aiScoreText,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(color: Colors.indigo, fontWeight: FontWeight.w900, fontSize: 12),
                ),
                const SizedBox(height: 6),
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                      decoration: BoxDecoration(
                        color: statusColor.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(999),
                        border: Border.all(color: statusColor.withOpacity(0.25)),
                      ),
                      child: Text(
                        _statusLabel(),
                        style: TextStyle(color: statusColor, fontWeight: FontWeight.w900, fontSize: 11),
                      ),
                    ),
                    const Spacer(),
                    Icon(Icons.chevron_right_rounded, color: Colors.grey.shade400, size: 22),
                  ],
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _StatusPill extends StatelessWidget {
  final String status;
  const _StatusPill({required this.status});

  Color _bg() {
    switch (status) {
      case 'verified':
        return Colors.green.withOpacity(0.12);
      case 'rejected':
        return Colors.red.withOpacity(0.12);
      case 'retake':
        return Colors.amber.withOpacity(0.18);
      default:
        return Colors.grey.withOpacity(0.14);
    }
  }

  Color _fg() {
    switch (status) {
      case 'verified':
        return Colors.green.shade800;
      case 'rejected':
        return Colors.red.shade800;
      case 'retake':
        return Colors.amber.shade900;
      default:
        return Colors.grey.shade800;
    }
  }

  String _label() {
    final s = status.trim();
    if (s.isEmpty || s == 'pending') return "not verified";
    return s;
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: _bg(),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: _fg().withOpacity(0.22)),
      ),
      child: Text(_label(), style: TextStyle(fontWeight: FontWeight.w900, color: _fg(), fontSize: 12)),
    );
  }
}

class _MediaPreviewDialog extends StatelessWidget {
  final String url;
  final bool isVideo;

  const _MediaPreviewDialog({
    required this.url,
    required this.isVideo,
  });

  @override
  Widget build(BuildContext context) {
    return Dialog(
      insetPadding: const EdgeInsets.all(14),
      backgroundColor: Colors.black,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Stack(
        children: [
          Positioned.fill(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(16),
              child: isVideo
                  ? Center(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.play_circle_fill_rounded, size: 80, color: Colors.white),
                    const SizedBox(height: 10),
                    const Text("Video preview",
                        style: TextStyle(color: Colors.white, fontWeight: FontWeight.w800)),
                    const SizedBox(height: 14),
                    ElevatedButton.icon(
                      onPressed: () async {
                        final uri = Uri.parse(url);
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      },
                      icon: const Icon(Icons.open_in_new_rounded),
                      label: const Text("Open"),
                    ),
                  ],
                ),
              )
                  : InteractiveViewer(
                minScale: 1,
                maxScale: 5,
                child: Image.network(
                  url,
                  fit: BoxFit.contain,
                  errorBuilder: (_, __, ___) => const Center(
                    child: Icon(Icons.broken_image_outlined, color: Colors.white70, size: 48),
                  ),
                ),
              ),
            ),
          ),
          Positioned(
            top: 10,
            right: 10,
            child: IconButton(
              onPressed: () => Navigator.pop(context),
              icon: const Icon(Icons.close_rounded, color: Colors.white),
              tooltip: "Close",
            ),
          ),
        ],
      ),
    );
  }
}


