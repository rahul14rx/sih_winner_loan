import 'dart:async';
import 'dart:io';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

// Import your new services
import 'package:loan2/services/api.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:loan2/services/database_helper.dart';

class LoanProcessPage extends StatefulWidget {
  final String userId;

  const LoanProcessPage({super.key, required this.userId});

  @override
  State<LoanProcessPage> createState() => _LoanProcessPageState();
}

class _LoanProcessPageState extends State<LoanProcessPage> {
  final ImagePicker _picker = ImagePicker();

  List<dynamic> loanData = [];
  bool loading = true;
  bool isOnline = false;
  int unsyncedCount = 0;

  Map<String, File?> uploadedFiles = {}; // key = process_id -> file
  Map<String, int?> uploadedDbIds = {}; // key = process_id -> db id
  Map<String, int> uploadStatus = {}; // key = process_id -> 0: captured, 1: queued

  StreamSubscription? _syncSubscription;
  StreamSubscription? _onlineStatusSubscription;

  @override
  void initState() {
    super.initState();
    _initPage();

    // Listen for background syncs to refresh UI
    _syncSubscription = SyncService.onSync.listen((_) {
      debugPrint("🔄 UI Refresh triggered by background sync");
      fetchUserLoanData();
      loadSavedImages();
    });

    // Listen for connectivity changes
    _onlineStatusSubscription = SyncService.onOnlineStatusChanged.listen((online) {
      if (online != isOnline) {
        setState(() {
          isOnline = online;
        });
      }
    });
  }

  @override
  void dispose() {
    _syncSubscription?.cancel();
    _onlineStatusSubscription?.cancel();
    super.dispose();
  }

  Future<void> _initPage() async {
    // Initial check
    isOnline = await SyncService.realInternetCheck();
    await loadSavedImages();
    await fetchUserLoanData();
    if (mounted) setState(() => loading = false);
  }

  Future<void> _updateUnsyncedCount() async {
    final count = await DatabaseHelper.instance.getQueuedForUploadCount();
    if (mounted) {
      setState(() {
        unsyncedCount = count;
      });
    }
  }

  // --- Caching Logic for Offline Support ---
  Future<File> _getCacheFile() async {
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'loan_data_cache_${widget.userId}.json'));
  }

  Future<void> _writeToCache(String content) async {
    try {
      final file = await _getCacheFile();
      await file.writeAsString(content);
    } catch (e) {
      debugPrint("Failed to write to cache: $e");
    }
  }

  Future<void> _loadFromCache() async {
    try {
      final file = await _getCacheFile();
      if (await file.exists()) {
        final content = await file.readAsString();
        final body = jsonDecode(content) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            loanData = body["data"] as List<dynamic>? ?? [];
          });
        }
      }
    } catch (e) {
      debugPrint("Failed to load from cache: $e");
    }
  }

  // --- Fetching Data ---
  Future<void> fetchUserLoanData() async {
    try {
      final url = Uri.parse("${kBaseUrl}user?id=${widget.userId}");
      final resp = await http.get(url).timeout(const Duration(seconds: 10));

      if (resp.statusCode == 200) {
        final body = jsonDecode(resp.body) as Map<String, dynamic>;
        if (mounted) {
          setState(() {
            loanData = body["data"] as List<dynamic>? ?? [];
          });
        }
        await _writeToCache(resp.body);
      } else {
        // Server error, try cache
        await _loadFromCache();
      }
    } catch (e) {
      // Network error, try cache
      debugPrint("API fetch error: $e. Loading from cache.");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("You're offline. Displaying cached data.")),
        );
      }
      await _loadFromCache();
    }
  }

  Future<void> loadSavedImages() async {
    try {
      final rows = await DatabaseHelper.instance.getImagesForUser(widget.userId);

      final Map<String, File?> newFiles = {};
      final Map<String, int?> newDbIds = {};
      final Map<String, int> newStatus = {};

      for (final r in rows) {
        final pid = r[DatabaseHelper.colProcessId] as String?;
        final path = r[DatabaseHelper.colFilePath] as String?;
        final id = r[DatabaseHelper.colId] as int?;
        final status = r[DatabaseHelper.colSubmitted] as int? ?? 0;

        if (pid != null && path != null) {
          newFiles[pid] = File(path);
          newDbIds[pid] = id;
          newStatus[pid] = status;
        }
      }

      if (mounted) {
        setState(() {
          uploadedFiles = newFiles;
          uploadedDbIds = newDbIds;
          uploadStatus = newStatus;
        });
      }
      await _updateUnsyncedCount();
    } catch (e) {
      debugPrint("loadSavedImages error: $e");
    }
  }

  // --- Image/Video Capture ---
  Future<String> _saveFileToAppDir(File srcFile, String userId, String processId) async {
    final docs = await getApplicationDocumentsDirectory();
    final dir = Directory(p.join(docs.path, 'uploads', userId));
    if (!await dir.exists()) await dir.create(recursive: true);

    final fileName = '${processId}_${DateTime.now().millisecondsSinceEpoch}${p.extension(srcFile.path)}';
    final destPath = p.join(dir.path, fileName);
    final newFile = await srcFile.copy(destPath);
    return newFile.path;
  }

  Future<void> pickImage(String processId, int processIntId, String loanId) async {
    try {
      final XFile? xfile = await _picker.pickImage(source: ImageSource.camera);
      if (xfile == null) return;

      final file = File(xfile.path);
      final savedPath = await _saveFileToAppDir(file, widget.userId, processId);

      final id = await DatabaseHelper.instance.insertImagePath(
        userId: widget.userId,
        processId: processId,
        processIntId: processIntId,
        loanId: loanId,
        filePath: savedPath,
      );

      setState(() {
        uploadedFiles[processId] = File(savedPath);
        uploadedDbIds[processId] = id;
        uploadStatus[processId] = 0; // Captured
      });

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Image saved locally")));
      await _updateUnsyncedCount();
    } catch (e) {
      debugPrint("pickImage error: $e");
    }
  }

  Future<void> pickVideo(String processId, int processIntId, String loanId) async {
    try {
      final XFile? xfile = await _picker.pickVideo(source: ImageSource.camera);
      if (xfile == null) return;

      final file = File(xfile.path);
      final savedPath = await _saveFileToAppDir(file, widget.userId, processId);

      final id = await DatabaseHelper.instance.insertImagePath(
        userId: widget.userId,
        processId: processId,
        processIntId: processIntId,
        loanId: loanId,
        filePath: savedPath,
      );

      setState(() {
        uploadedFiles[processId] = File(savedPath);
        uploadedDbIds[processId] = id;
        uploadStatus[processId] = 0; // Captured
      });

      if(mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Video saved locally")));
      await _updateUnsyncedCount();
    } catch (e) {
      debugPrint("pickVideo error: $e");
    }
  }

  Future<void> submitProcess(String processId) async {
    final dbId = uploadedDbIds[processId];
    if (dbId == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Please capture media first")));
      return;
    }

    await DatabaseHelper.instance.queueForUpload(dbId);
    setState(() {
      uploadStatus[processId] = 1; // Queued
    });
    await _updateUnsyncedCount();

    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Queued for upload. Will sync automatically.")));
  }

  // --- Helpers ---
  String getOverallLoanStatus(List<dynamic> processes) {
    if (processes.any((p) => p['status'] == 'rejected')) return 'Rejected';
    if (processes.every((p) => p['status'] == 'verified')) return 'Verified';
    return 'Pending';
  }

  Color getStatusColor(String status) {
    if (status == 'verified') return Colors.green;
    if (status == 'rejected') return Colors.red;
    return Colors.orange;
  }

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // If cache is empty and no network
    if (loanData.isEmpty) {
      return Scaffold(
        appBar: AppBar(title: const Text("Loan Process")),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.cloud_off, size: 64, color: Colors.grey),
              const SizedBox(height: 16),
              const Text("No data found locally."),
              const SizedBox(height: 8),
              Text("User ID: ${widget.userId}", style: const TextStyle(fontWeight: FontWeight.bold)),
              const SizedBox(height: 16),
              ElevatedButton(
                onPressed: _initPage,
                child: const Text("Retry"),
              )
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: const Text("Complete Loan Processes"),
        actions: [
          // Unsynced Count Indicator
          if (unsyncedCount > 0)
            Container(
              margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                children: [
                  const Icon(Icons.sync_problem, color: Colors.orange, size: 18),
                  const SizedBox(width: 4),
                  Text(
                    "$unsyncedCount",
                    style: const TextStyle(color: Colors.orange, fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ),
          // Online/Offline Indicator
          Padding(
            padding: const EdgeInsets.only(right: 16.0),
            child: Row(
              children: [
                Icon(isOnline ? Icons.wifi : Icons.wifi_off, color: isOnline ? Colors.green[100] : Colors.red[100]),
                const SizedBox(width: 8),
                Text(
                  isOnline ? "Online" : "Offline",
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),
        ],
      ),
      body: RefreshIndicator(
        onRefresh: fetchUserLoanData,
        child: SingleChildScrollView(
          child: ListView.builder(
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            padding: const EdgeInsets.all(16),
            itemCount: loanData.length,
            itemBuilder: (context, loanIndex) {
              final loan = loanData[loanIndex] as Map<String, dynamic>;
              final processes = (loan['process'] as List<dynamic>? ?? []);
              final loanId = loan['loan_id']?.toString() ?? '';
              final overallStatus = getOverallLoanStatus(processes);

              return Card(
                elevation: 4,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                margin: const EdgeInsets.only(bottom: 20),
                child: Padding(
                  padding: const EdgeInsets.all(16),
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text("Loan ID: $loanId", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                          decoration: BoxDecoration(
                            color: getStatusColor(overallStatus).withOpacity(0.1),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                              overallStatus,
                              style: TextStyle(fontSize: 14, color: getStatusColor(overallStatus), fontWeight: FontWeight.bold)
                          ),
                        ),
                      ],
                    ),
                    const Divider(height: 20),
                    ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: processes.length,
                      itemBuilder: (context, processIndex) {
                        final process = processes[processIndex] as Map<String, dynamic>;
                        final processId = process['id']?.toString() ?? 'proc_$processIndex';
                        final processIntId = process['process_id'] as int? ?? 0;
                        final type = process['data_type']?.toString() ?? 'image';
                        final serverStatus = process['status']?.toString() ?? 'pending';

                        final localStatus = uploadStatus[processId];
                        String submittedHint = "";
                        if (localStatus == 0) submittedHint = " (Saved locally)";
                        if (localStatus == 1) submittedHint = " (Queued for sync)";

                        bool isCompleted = serverStatus == 'verified';

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          padding: const EdgeInsets.all(12),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(10),
                            color: Colors.grey.shade50,
                          ),
                          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            Text(process['what_to_do']?.toString() ?? '', style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600)),
                            const SizedBox(height: 4),
                            Text("Type: ${type.toUpperCase()}$submittedHint", style: TextStyle(color: Colors.grey[700], fontSize: 12)),
                            const SizedBox(height: 10),

                            if (isCompleted)
                              const Row(
                                children: [
                                  Icon(Icons.check_circle, color: Colors.green),
                                  SizedBox(width: 8),
                                  Text("Verified", style: TextStyle(color: Colors.green, fontWeight: FontWeight.bold)),
                                ],
                              )
                            else
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  if (uploadedFiles[processId] != null) ...[
                                    // Preview Logic
                                    ClipRRect(
                                      borderRadius: BorderRadius.circular(8),
                                      child: uploadedFiles[processId]!.path.toLowerCase().endsWith('.mov') || uploadedFiles[processId]!.path.toLowerCase().endsWith('.mp4')
                                          ? Container(
                                        height: 150,
                                        color: Colors.black12,
                                        child: const Center(child: Icon(Icons.videocam, size: 50, color: Colors.grey)),
                                      )
                                          : Image.file(uploadedFiles[processId]!, height: 180, fit: BoxFit.cover),
                                    ),
                                    const SizedBox(height: 8),
                                    Text("Captured: ${p.basename(uploadedFiles[processId]!.path)}", style: const TextStyle(fontSize: 12, color: Colors.grey)),
                                    const SizedBox(height: 8),
                                  ],

                                  Row(
                                    children: [
                                      Expanded(
                                        child: OutlinedButton.icon(
                                          onPressed: () {
                                            if (type == 'video') {
                                              pickVideo(processId, processIntId, loanId);
                                            } else {
                                              pickImage(processId, processIntId, loanId);
                                            }
                                          },
                                          icon: Icon(type == 'video' ? Icons.videocam : Icons.camera_alt),
                                          label: Text(uploadedFiles[processId] == null ? "Capture" : "Retake"),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: Theme.of(context).primaryColor,
                                            side: BorderSide(color: Theme.of(context).primaryColor),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 10),
                                      Expanded(
                                        child: ElevatedButton.icon(
                                          onPressed: uploadedFiles[processId] == null || localStatus == 1
                                              ? null
                                              : () => submitProcess(processId),
                                          icon: const Icon(Icons.cloud_upload),
                                          label: const Text("Submit"),
                                          style: ElevatedButton.styleFrom(
                                            backgroundColor: const Color(0xFF138808), // Green
                                            foregroundColor: Colors.white,
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                          ]),
                        );
                      },
                    ),
                  ]),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}