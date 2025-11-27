import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/verification_step_page.dart';
import 'package:loan2/pages/movement_verification_page.dart';
import 'package:loan2/services/api.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';
// EncryptionService import removed as we don't encrypt movement anymore

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

  // Tracks which steps are saved locally (offline) but not yet synced
  Map<String, bool> _localUploads = {};

  // Mock utilization amount calculation
  double _amountUsed = 0;

  // Subscriptions for real-time updates
  StreamSubscription? _syncSub;
  StreamSubscription? _itemSyncSub;
  StreamSubscription? _onlineSub;
  Timer? _pollTimer;

  @override
  void initState() {
    super.initState();
    _currentLoan = widget.loan;

    // Calculate initial used amount (mock)
    _amountUsed = _currentLoan.amount * 0.45;

    // Initial Fetch to get dynamic details
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _refreshLoanData();
    });

    _checkLocalUploads();

    // 1. Listen for Internet connection coming back
    _onlineSub = SyncService.onOnlineStatusChanged.listen((isOnline) {
      if (isOnline) {
        debugPrint("🌐 Online detected: Refreshing data...");
        _refreshLoanData();
      }
    });

    // 2. Listen for Background Sync completions
    _syncSub = SyncService.onSync.listen((_) {
      debugPrint("🔄 Sync completed: Updating UI...");
      _refreshLoanData(silent: true);
    });

    // 3. Listen for Specific Item Sync
    _itemSyncSub = SyncService.onItemSynced.listen((event) {
      if (event['loanId'] == _currentLoan.loanId) {
        final pid = event['processId'];
        if (pid != null) {
          print("⚡ Item Synced for this loan: $pid. Updating status locally.");
          _markStepAsPendingReview(pid);
          _refreshLoanData(silent: true);
        }
      }
    });

    // 4. Periodic Polling
    _pollTimer = Timer.periodic(const Duration(seconds: 10), (timer) {
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

  // Check local DB to see if we have pending uploads for this loan
  Future<void> _checkLocalUploads() async {
    final queued = await DatabaseHelper.instance.getQueuedForUpload();
    final Map<String, bool> statusMap = {};

    for (var row in queued) {
      final pid = row[DatabaseHelper.colProcessId] as String?;
      final lid = row[DatabaseHelper.colLoanId] as String?;

      // If the local DB has an entry for this Loan ID & Process ID, mark it as locally done
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

    // 1. Re-check local DB status (Critical for offline updates)
    await _checkLocalUploads();

    // 2. Fetch latest server status using loan_details (Dynamic Update)
    try {
      // Calling fetchLoanDetails
      final updatedLoan = await _service.fetchLoanDetails(_currentLoan.loanId);

      if (mounted) {
        setState(() {
          // UPDATE: Only update loan details, keep the existing process list
          _currentLoan = BeneficiaryLoan(
            loanId: updatedLoan.loanId,
            userId: updatedLoan.userId,
            applicantName: updatedLoan.applicantName,
            amount: updatedLoan.amount,
            loanType: updatedLoan.loanType,
            scheme: updatedLoan.scheme,
            dateApplied: updatedLoan.dateApplied,
            status: updatedLoan.status,
            processes: _currentLoan.processes, // PRESERVE LOCAL PROCESS LIST
          );

          _amountUsed = _currentLoan.amount * 0.45; // Update mock logic based on new amount
          if (!silent) _isRefreshing = false;
        });
      }
    } catch (e) {
      print("Error fetching details: $e");
      // If offline, we still stop the spinner
      if (mounted && !silent) {
        setState(() => _isRefreshing = false);
      }
    }
  }

  // Helper to manually update a step's status locally after successful upload
  void _markStepAsPendingReview(String stepId) {
    List<ProcessStep> updatedProcesses = _currentLoan.processes.map((step) {
      if (step.id == stepId) {
        return ProcessStep(
          id: step.id,
          processId: step.processId,
          whatToDo: step.whatToDo,
          dataType: step.dataType,
          status: 'pending_review', // Manually set status
        );
      }
      return step;
    }).toList();

    setState(() {
      _currentLoan = BeneficiaryLoan(
        loanId: _currentLoan.loanId,
        userId: _currentLoan.userId,
        applicantName: _currentLoan.applicantName,
        amount: _currentLoan.amount,
        loanType: _currentLoan.loanType,
        scheme: _currentLoan.scheme,
        dateApplied: _currentLoan.dateApplied,
        status: _currentLoan.status,
        processes: updatedProcesses,
      );
    });
  }

  Future<void> _handleMovementResult(String filePath, ProcessStep step) async {
    if (filePath.isEmpty) return;

    setState(() => _isRefreshing = true);

    try {
      // 1. NO Encryption for Movement (Video)
      File originalFile = File(filePath);

      // 2. Save Local (Raw Path)
      int dbId = await DatabaseHelper.instance.insertImagePath(
        userId: _currentLoan.userId,
        processId: step.id,
        processIntId: step.processId,
        loanId: _currentLoan.loanId,
        filePath: originalFile.path,
      );

      // 3. Check Online
      bool isOnline = await SyncService.realInternetCheck();

      if (!isOnline) {
        await DatabaseHelper.instance.queueForUpload(dbId);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text("Movement saved offline. Will sync when online."),
                backgroundColor: Colors.orange,
              )
          );
          _refreshLoanData();
        }
        return;
      }

      // 4. Upload Online (Raw File)
      var request = http.MultipartRequest('POST', Uri.parse('${kBaseUrl}upload'));
      request.fields['loan_id'] = _currentLoan.loanId;
      request.fields['process_id'] = step.id;
      request.fields['user_id'] = _currentLoan.userId;

      request.files.add(await http.MultipartFile.fromPath('file', originalFile.path));

      var response = await request.send();
      if (response.statusCode == 200) {
        await DatabaseHelper.instance.deleteImage(dbId, deleteFile: false);
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Movement verified successfully!"), backgroundColor: Colors.green));
          _markStepAsPendingReview(step.id);
          _refreshLoanData();
        }
      } else {
        throw Exception("Server error ${response.statusCode}");
      }

    } catch (e) {
      print("Movement upload failed: $e");
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Upload failed. Check connection."), backgroundColor: Colors.red));
    } finally {
      if (mounted) setState(() => _isRefreshing = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    double sanctionedAmount = _currentLoan.amount;
    double utilizationPercent = sanctionedAmount > 0 ? (_amountUsed / sanctionedAmount).clamp(0.0, 1.0) : 0.0;

    return Scaffold(
      backgroundColor: const Color(0xFFF5F7FA),
      appBar: AppBar(
        title: const Text('Verification Page', style: TextStyle(color: Colors.black, fontWeight: FontWeight.bold)),
        backgroundColor: Colors.white,
        elevation: 0,
        centerTitle: true,
        iconTheme: const IconThemeData(color: Colors.black),
        actions: [
          if (_isRefreshing)
            const Padding(
              padding: EdgeInsets.all(16.0),
              child: SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.black)),
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
            // 1. Utilization Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Loan Utilization", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                      Text("${(utilizationPercent * 100).toInt()}% · Provisional", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Stack(
                    children: [
                      Container(
                        height: 10,
                        width: double.infinity,
                        decoration: BoxDecoration(color: Colors.grey[200], borderRadius: BorderRadius.circular(5)),
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
                      Text("₹${_amountUsed.toInt()} of ₹${sanctionedAmount.toInt()} used", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.black54)),
                      Text("${(utilizationPercent * 100).toInt()}% · Provisional", style: TextStyle(color: Colors.grey[600], fontSize: 12)),
                    ],
                  ),
                ],
              ),
            ),

            const SizedBox(height: 20),

            // 2. Loan Details Card
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(16),
                boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10)],
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

            // 3. Start Verification Button
            Builder(
                builder: (context) {
                  ProcessStep? nextStep;
                  bool allDone = true;

                  for (var step in _currentLoan.processes) {
                    bool isLocallyDone = _localUploads[step.id] == true;
                    bool isServerDone = step.status == 'verified' || step.status == 'pending_review';

                    if (!isLocallyDone && !isServerDone) {
                      nextStep = step;
                      allDone = false;
                      break;
                    }
                  }

                  if (allDone) {
                    return SizedBox(
                      width: double.infinity,
                      height: 55,
                      child: ElevatedButton(
                        onPressed: null, // Disabled
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          disabledBackgroundColor: Colors.green.withOpacity(0.6),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                        child: const Text("All Steps Completed", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.white)),
                      ),
                    );
                  }

                  return SizedBox(
                    width: double.infinity,
                    height: 55,
                    child: ElevatedButton(
                      onPressed: () {
                        if (nextStep != null) {
                          _startVerification(nextStep);
                        }
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF435E91),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                        elevation: 5,
                      ),
                      child: Text("Start ${nextStep!.whatToDo}", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)),
                    ),
                  );
                }
            ),

            const SizedBox(height: 30),

            // 4. Steps List
            const Text("Steps Checklist", style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.grey)),
            const SizedBox(height: 10),
            ..._currentLoan.processes.map((step) => _buildStepTile(step)),
          ],
        ),
      ),
    );
  }

  void _startVerification(dynamic step) {
    if (step.dataType == 'movement') {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => const MovementScreen(),
        ),
      ).then((result) {
        if (result != null && result is String) {
          _handleMovementResult(result, step);
        }
      });
    } else {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => VerificationStepPage(
            loanId: _currentLoan.loanId,
            step: step,
            userId: _currentLoan.userId,
          ),
        ),
      ).then((result) {
        if (result == true) {
          _markStepAsPendingReview(step.id);
          _refreshLoanData();
        }
      });
    }
  }

  Widget _buildDetailRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SizedBox(width: 120, child: Text(label, style: TextStyle(color: Colors.grey[600], fontSize: 14))),
          Expanded(child: Text(value, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14, color: Colors.black87), textAlign: TextAlign.right)),
        ],
      ),
    );
  }

  Widget _buildStepTile(dynamic step) {
    bool isLocallyDone = _localUploads[step.id] == true;
    bool isServerDone = step.status == 'verified' || step.status == 'pending_review';
    bool isDone = isServerDone || isLocallyDone;

    String statusText = "Pending";
    Color statusColor = Colors.grey;
    IconData statusIcon = Icons.radio_button_unchecked;

    if (isLocallyDone) {
      statusText = "Queued (Offline)";
      statusColor = Colors.orange;
      statusIcon = Icons.cloud_upload;
    } else if (step.status == 'verified') {
      statusText = "Verified";
      statusColor = Colors.green;
      statusIcon = Icons.check_circle;
    } else if (step.status == 'pending_review') {
      statusText = "In Review";
      statusColor = Colors.blue;
      statusIcon = Icons.access_time_filled;
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: isDone ? statusColor.withOpacity(0.3) : Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Icon(statusIcon, color: statusColor, size: 22),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(step.whatToDo, style: TextStyle(color: isDone ? Colors.black87 : Colors.grey[600], fontWeight: isDone ? FontWeight.w600 : FontWeight.normal)),
                if (isDone)
                  Text(statusText, style: TextStyle(fontSize: 10, color: statusColor, fontWeight: FontWeight.bold)),
              ],
            ),
          ),
          if (!isDone)
            ElevatedButton(
              onPressed: () => _startVerification(step),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF138808),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                minimumSize: const Size(60, 30),
                elevation: 0,
              ),
              child: const Text("Start", style: TextStyle(fontSize: 12, color: Colors.white)),
            ),
        ],
      ),
    );
  }
}