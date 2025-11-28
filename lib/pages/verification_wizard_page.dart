import 'dart:async';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/services/api.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';

import 'package:loan2/ai/combined_ai_gate.dart';
import 'package:loan2/pages/movement_verification_page.dart';
import 'package:loan2/pages/rear_camera_capture_page.dart';

class VerificationWizardPage extends StatefulWidget {
  final String loanId;
  final String userId;

  const VerificationWizardPage({
    super.key,
    required this.loanId,
    required this.userId,
  });

  @override
  State<VerificationWizardPage> createState() => _VerificationWizardPageState();
}

class _StageGroup {
  final int stageNo;
  final List<ProcessStep> steps;
  _StageGroup(this.stageNo, this.steps);
}

class _VerificationWizardPageState extends State<VerificationWizardPage> {
  static const _saffron = Color(0xFFFF9933);
  static const _deep = Color(0xFFD26C00);

  final _svc = BeneficiaryService();
  final _picker = ImagePicker();

  BeneficiaryLoan? _loan;
  bool _loading = true;

  final Map<String, bool> _localUploads = {};
  final Map<String, String> _localPaths = {};

  File? _mediaFile;
  bool _checkingAi = false;
  bool _uploading = false;
  String? _warn;

  final _utilCtrl = TextEditingController();

  StreamSubscription? _onlineSub;

  int _idx = 0;

  int _stageIdx = 0;
  int _stageStepIdx = 0;
  final Map<int, int> _rememberStepPerStage = {};

  @override
  void initState() {
    super.initState();
    CombinedAiGate.instance.init();
    _load();

    _onlineSub = SyncService.onOnlineStatusChanged.listen((isOnline) {
      if (isOnline) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _utilCtrl.dispose();
    super.dispose();
  }

  String _url(String path) {
    var b = kBaseUrl;
    if (!b.endsWith('/')) b = '$b/';
    if (path.startsWith('/')) path = path.substring(1);
    return '$b$path';
  }

  bool _isConstruction(BeneficiaryLoan loan) {
    final t = (loan.loanType).toLowerCase();
    final s = (loan.scheme).toLowerCase();
    return t.contains('construction') || t.contains('shop') || s.contains('construction') || s.contains('shop');
  }

  int? _stageNoFromText(String text) {
    final re = RegExp(r'^\s*Stage\s*(\d+)\s*:', caseSensitive: false);
    final m = re.firstMatch(text.trim());
    if (m == null) return null;
    return int.tryParse(m.group(1) ?? "");
  }

  String _stripStagePrefix(String text) {
    final re = RegExp(r'^\s*Stage\s*\d+\s*:\s*', caseSensitive: false);
    return text.replaceFirst(re, "").trim();
  }

  List<ProcessStep> _sortedSteps() {
    final loan = _loan;
    if (loan == null) return [];
    final steps = [...loan.processes]..sort((a, b) => a.processId.compareTo(b.processId));
    return steps;
  }

  bool _serverDone(ProcessStep s) {
    final t = s.status.toLowerCase().trim();
    return t == 'verified' || t == 'pending_review';
  }

  bool _done(ProcessStep s) => _serverDone(s) || (_localUploads[s.id] == true);

  bool _allDone(List<ProcessStep> steps) {
    for (final s in steps) {
      if (!_done(s)) return false;
    }
    return true;
  }

  List<_StageGroup> _stageGroups(BeneficiaryLoan loan) {
    final sorted = _sortedSteps();
    final Map<int, List<ProcessStep>> mp = {};
    for (final st in sorted) {
      final sn = _stageNoFromText(st.whatToDo) ?? 0;
      if (sn <= 0) continue;
      mp.putIfAbsent(sn, () => []).add(st);
    }

    final keys = mp.keys.toList()..sort();
    final groups = <_StageGroup>[];
    for (final k in keys) {
      final lst = mp[k] ?? [];
      lst.sort((a, b) => a.processId.compareTo(b.processId));
      groups.add(_StageGroup(k, lst));
    }
    return groups;
  }

  bool _stageComplete(_StageGroup g) {
    for (final s in g.steps) {
      if (!_done(s)) return false;
    }
    return true;
  }

  bool _stageEnabled(int stageIndex, List<_StageGroup> groups) {
    if (stageIndex <= 0) return true;
    for (int i = 0; i < stageIndex; i++) {
      if (!_stageComplete(groups[i])) return false;
    }
    return true;
  }

  String? _serverMediaUrl(ProcessStep s) {
    try {
      final d = s as dynamic;
      final u = d.mediaUrl ?? d.media_url ?? d.mediaURL;
      if (u is String && u.trim().isNotEmpty) return u.trim();
    } catch (_) {}
    return null;
  }

  String _existingUtil(ProcessStep s) {
    try {
      final d = s as dynamic;
      final v = d.utilizationAmount ?? d.utilization_amount;
      if (v == null) return "";
      final out = v.toString();
      return out == "null" ? "" : out;
    } catch (_) {}
    return "";
  }

  bool _needsUtilAmount(BeneficiaryLoan loan, ProcessStep step) {
    if (_isConstruction(loan)) return step.processId == 1;
    return step.processId == 1;
  }

  Future<void> _checkLocalUploads() async {
    final queued = await DatabaseHelper.instance.getQueuedForUpload();
    final Map<String, bool> statusMap = {};
    final Map<String, String> pathMap = {};

    for (var row in queued) {
      final lid = (row[DatabaseHelper.colLoanId] ??
          row['loan_id'] ??
          row['loanId'])
          ?.toString();
      if (lid != widget.loanId) continue;

      final pid = (row[DatabaseHelper.colProcessId] ??
          row['process_id'] ??
          row['processId'])
          ?.toString();
      if (pid == null) continue;

      statusMap[pid] = true;

      final fp = (row[DatabaseHelper.colFilePath] ??
          row['file_path'] ??
          row['filePath'] ??
          row['path'])
          ?.toString();
      if (fp != null && fp.isNotEmpty) {
        pathMap[pid] = fp;
      }
    }

    if (!mounted) return;
    setState(() {
      _localUploads
        ..clear()
        ..addAll(statusMap);
      _localPaths
        ..clear()
        ..addAll(pathMap);
    });
  }

  Future<void> _load({bool silent = false}) async {
    if (!silent) setState(() => _loading = true);
    await _checkLocalUploads();

    try {
      final d = await _svc.fetchLoanDetails(widget.loanId);
      if (!mounted) return;

      setState(() {
        _loan = d;
        _loading = false;
      });

      if (_isConstruction(d)) {
        final groups = _stageGroups(d);
        if (_stageIdx > groups.length) _stageIdx = 0;
        if (_stageIdx < groups.length) {
          final remembered = _rememberStepPerStage[_stageIdx] ?? 0;
          _stageStepIdx = remembered.clamp(0, (groups[_stageIdx].steps.length - 1).clamp(0, 999999));
        } else {
          _stageStepIdx = 0;
        }
      } else {
        final steps = _sortedSteps();
        if (_idx > steps.length) _idx = 0;
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _loading = false);
    }
  }

  void _resetCaptureUiFor(ProcessStep step) {
    final loan = _loan;
    setState(() {
      _mediaFile = null;
      _warn = null;
      _checkingAi = false;
      _uploading = false;
      _utilCtrl.text = (loan != null && _needsUtilAmount(loan, step)) ? _existingUtil(step) : "";
    });
  }

  void _goToGlobalStep(int i) {
    final steps = _sortedSteps();
    final finishIndex = steps.length;
    if (i < 0 || i > finishIndex) return;

    final isFinish = i == finishIndex;
    if (isFinish && !_allDone(steps)) return;

    if (isFinish) {
      setState(() {
        _idx = finishIndex;
        _mediaFile = null;
        _warn = null;
        _checkingAi = false;
        _uploading = false;
        _utilCtrl.text = "";
      });
      return;
    }

    final step = steps[i];
    _idx = i;
    _resetCaptureUiFor(step);
  }

  void _goToStage(int stageTab, List<_StageGroup> groups) {
    final finishIndex = groups.length;
    if (stageTab < 0 || stageTab > finishIndex) return;

    final isFinish = stageTab == finishIndex;
    if (isFinish && !_allDone(_sortedSteps())) return;

    if (!isFinish && !_stageEnabled(stageTab, groups)) return;

    setState(() {
      _stageIdx = stageTab;
      _mediaFile = null;
      _warn = null;
      _checkingAi = false;
      _uploading = false;

      if (!isFinish) {
        final remembered = _rememberStepPerStage[_stageIdx] ?? 0;
        final max = (groups[_stageIdx].steps.length - 1).clamp(0, 999999);
        _stageStepIdx = remembered.clamp(0, max);
      } else {
        _stageStepIdx = 0;
      }

      if (!isFinish && groups[_stageIdx].steps.isNotEmpty) {
        final step = groups[_stageIdx].steps[_stageStepIdx];
        final loan = _loan;
        _utilCtrl.text = (loan != null && _needsUtilAmount(loan, step)) ? _existingUtil(step) : "";
      } else {
        _utilCtrl.text = "";
      }
    });
  }

  void _goToStageStep(int stepIndex, List<_StageGroup> groups) {
    if (_stageIdx >= groups.length) return;
    final steps = groups[_stageIdx].steps;
    if (stepIndex < 0 || stepIndex >= steps.length) return;

    setState(() {
      _stageStepIdx = stepIndex;
      _rememberStepPerStage[_stageIdx] = stepIndex;
    });

    _resetCaptureUiFor(steps[stepIndex]);
  }

  Widget _chip({
    required String text,
    required bool active,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return InkWell(
      onTap: enabled ? onTap : null,
      borderRadius: BorderRadius.circular(999),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: active ? _saffron : Colors.grey.shade100,
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: active ? _deep : Colors.grey.shade300),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: active ? Colors.white : (enabled ? Colors.black87 : Colors.grey),
            fontWeight: FontWeight.w900,
            fontSize: 12,
          ),
        ),
      ),
    );
  }

  Widget _exampleBox() {
    return Container(
      height: 130,
      width: double.infinity,
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: const [
          Icon(Icons.image_outlined, size: 34, color: Colors.grey),
          SizedBox(height: 6),
          Text("Example guide image will be added here", style: TextStyle(color: Colors.grey)),
        ],
      ),
    );
  }

  Future<void> _pickMedia(ProcessStep step) async {
    if (_uploading || _checkingAi) return;

    final dt = step.dataType.trim().toLowerCase();

    setState(() {
      _warn = null;
      _mediaFile = null;
    });

    try {
      if (dt == 'movement') {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(builder: (_) => const MovementScreen()),
        );
        if (result is String && result.isNotEmpty) {
          setState(() => _mediaFile = File(result));
        }
        return;
      }

      if (dt == 'video') {
        final XFile? pickedVideo = await _picker.pickVideo(
          source: ImageSource.camera,
          preferredCameraDevice: CameraDevice.rear,
          maxDuration: const Duration(seconds: 15),
        );
        if (pickedVideo == null) return;
        setState(() => _mediaFile = File(pickedVideo.path));
        return;
      }

      final path = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RearCameraCapturePage()),
      );

      if (path is! String || path.isEmpty) return;

      final file = File(path);

      final shouldRunAi = step.processId == 1;
      if (!shouldRunAi) {
        setState(() => _mediaFile = file);
        return;
      }

      setState(() {
        _checkingAi = true;
        _mediaFile = null;
      });

      final r = await CombinedAiGate.instance.check(file);
      if (!mounted) return;

      setState(() => _checkingAi = false);

      if (r.verdict == AiVerdict.valid) {
        setState(() {
          _mediaFile = file;
          _warn = null;
        });
      } else {
        final msg = (r.verdict == AiVerdict.screenInvalid)
            ? "Invalid image: Screen-captured photo detected. Please retake."
            : "Invalid image: Photo is too blurry. Please retake.";
        setState(() {
          _mediaFile = null;
          _warn = msg;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _checkingAi = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Failed to capture media: $e")),
      );
    }
  }

  Future<void> _submit(ProcessStep step) async {
    final loan = _loan;
    if (loan == null) return;

    if (_mediaFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please capture the required media first.")),
      );
      return;
    }

    if (_needsUtilAmount(loan, step) && _utilCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter utilization amount")),
      );
      return;
    }

    setState(() => _uploading = true);

    int? dbId;
    try {
      final finalPath = _mediaFile!.path;

      dbId = await DatabaseHelper.instance.insertImagePath(
        userId: widget.userId,
        processId: step.id,
        processIntId: step.processId,
        loanId: widget.loanId,
        filePath: finalPath,
      );

      final isOnline = await SyncService.realInternetCheck();

      if (!isOnline) {
        await DatabaseHelper.instance.queueForUpload(dbId);
        if (!mounted) return;

        setState(() {
          _localUploads[step.id] = true;
          _localPaths[step.id] = finalPath;
          _uploading = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Saved offline. Will sync when online."),
            backgroundColor: _saffron,
          ),
        );

        _afterStepDone();
        return;
      }

      final request = http.MultipartRequest('POST', Uri.parse(_url('upload')));
      request.fields['loan_id'] = widget.loanId;
      request.fields['process_id'] = step.id;
      request.fields['user_id'] = widget.userId;

      if (_needsUtilAmount(loan, step)) {
        request.fields['utilization_amount'] = _utilCtrl.text.trim();
      }

      request.files.add(await http.MultipartFile.fromPath('file', finalPath));

      final response = await request.send().timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await DatabaseHelper.instance.deleteImage(dbId, deleteFile: false);

        if (!mounted) return;

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Uploaded successfully!"), backgroundColor: Colors.green),
        );

        await _checkLocalUploads();
        await _load(silent: true);

        _afterStepDone();
      } else {
        throw Exception("Server error ${response.statusCode}");
      }
    } catch (e) {
      if (dbId != null) {
        await DatabaseHelper.instance.queueForUpload(dbId);
      }
      if (!mounted) return;

      setState(() {
        _localUploads[step.id] = true;
        if (_mediaFile != null) _localPaths[step.id] = _mediaFile!.path;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Upload failed (queued): $e"), backgroundColor: Colors.red),
      );

      _afterStepDone();
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  void _afterStepDone() {
    final loan = _loan;
    if (loan == null) return;

    final stepsAll = _sortedSteps();

    if (_allDone(stepsAll)) {
      if (_isConstruction(loan)) {
        final groups = _stageGroups(loan);
        _goToStage(groups.length, groups);
      } else {
        _goToGlobalStep(stepsAll.length);
      }
      return;
    }

    if (_isConstruction(loan)) {
      final groups = _stageGroups(loan);
      if (_stageIdx >= groups.length) return;

      final curGroup = groups[_stageIdx];
      final nextStep = _stageStepIdx + 1;

      if (nextStep < curGroup.steps.length) {
        _goToStageStep(nextStep, groups);
        return;
      }

      final nextStage = _stageIdx + 1;
      if (nextStage < groups.length && _stageEnabled(nextStage, groups)) {
        _goToStage(nextStage, groups);
        return;
      }

      _goToStage(_stageIdx, groups);
      return;
    }

    final next = (_idx < stepsAll.length) ? _idx + 1 : _idx;
    if (next <= stepsAll.length) _goToGlobalStep(next);
  }

  Future<void> _showImageFull({required Widget image}) async {
    await showDialog(
      context: context,
      builder: (_) {
        return Dialog(
          insetPadding: const EdgeInsets.all(14),
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(16),
            child: Stack(
              children: [
                Container(
                  color: Colors.black,
                  child: InteractiveViewer(
                    minScale: 0.8,
                    maxScale: 4.0,
                    child: Center(child: image),
                  ),
                ),
                Positioned(
                  top: 8,
                  right: 8,
                  child: IconButton(
                    onPressed: () => Navigator.pop(context),
                    icon: const Icon(Icons.close, color: Colors.white),
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _mediaBox({
    required ProcessStep step,
    required String dt,
  }) {
    final localQueued = _localPaths[step.id];
    final serverUrl = _serverMediaUrl(step);

    final showLocalQueued = (_mediaFile == null) &&
        (localQueued != null) &&
        (localQueued.isNotEmpty) &&
        File(localQueued).existsSync();

    final showServer = (_mediaFile == null) && !showLocalQueued && (serverUrl != null && serverUrl.isNotEmpty);

    final hasPreview = _mediaFile != null || showLocalQueued || showServer;

    Widget preview;
    if (_mediaFile != null) {
      if (dt == 'video' || dt == 'movement') {
        preview = Container(
          color: Colors.black,
          child: const Center(child: Icon(Icons.play_circle, color: Colors.white, size: 56)),
        );
      } else {
        preview = Image.file(_mediaFile!, fit: BoxFit.cover);
      }
    } else if (showLocalQueued) {
      if (dt == 'video' || dt == 'movement') {
        preview = Container(
          color: Colors.black,
          child: const Center(child: Icon(Icons.play_circle, color: Colors.white, size: 56)),
        );
      } else {
        preview = Image.file(File(localQueued!), fit: BoxFit.cover);
      }
    } else if (showServer) {
      if (dt == 'video' || dt == 'movement') {
        preview = Container(
          color: Colors.black,
          child: const Center(child: Icon(Icons.play_circle, color: Colors.white, size: 56)),
        );
      } else {
        preview = Image.network(serverUrl!, fit: BoxFit.cover);
      }
    } else {
      preview = Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              dt == 'video' || dt == 'movement' ? Icons.videocam_outlined : Icons.camera_alt_outlined,
              size: 44,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 8),
            Text(
              dt == 'video' || dt == 'movement' ? "Tap to record" : "Tap to capture image",
              style: TextStyle(color: Colors.grey[700], fontWeight: FontWeight.w800),
            ),
          ],
        ),
      );
    }

    return Column(
      children: [
        GestureDetector(
          onTap: (_uploading || _checkingAi)
              ? null
              : () async {
            if (!hasPreview) {
              await _pickMedia(step);
              return;
            }

            if (dt == 'video' || dt == 'movement') return;

            if (_mediaFile != null) {
              await _showImageFull(image: Image.file(_mediaFile!, fit: BoxFit.contain));
              return;
            }

            if (showLocalQueued) {
              await _showImageFull(image: Image.file(File(localQueued!), fit: BoxFit.contain));
              return;
            }

            if (showServer) {
              await _showImageFull(image: Image.network(serverUrl!, fit: BoxFit.contain));
              return;
            }
          },
          child: Container(
            height: 190,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Stack(
              children: [
                if (hasPreview)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(14),
                      child: preview,
                    ),
                  )
                else
                  preview,
                if (_checkingAi)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: const Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            CircularProgressIndicator(),
                            SizedBox(height: 10),
                            Text("Checking photo quality..."),
                          ],
                        ),
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ),
        if (hasPreview) ...[
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    (dt == 'video' || dt == 'movement')
                        ? "Preview ready"
                        : "Tap preview to enlarge",
                    style: const TextStyle(fontWeight: FontWeight.w800),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton(
                  onPressed: (_uploading || _checkingAi) ? null : () => _pickMedia(step),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _deep,
                    side: const BorderSide(color: _deep),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                  ),
                  child: const Text("Recapture", style: TextStyle(fontWeight: FontWeight.w900)),
                ),
              ],
            ),
          ),
        ],
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final loan = _loan;

    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (loan == null) {
      return Scaffold(
        appBar: AppBar(title: const Text("Verification")),
        body: Center(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Text("Failed to load loan"),
              const SizedBox(height: 10),
              ElevatedButton(onPressed: _load, child: const Text("Retry")),
            ],
          ),
        ),
      );
    }

    final allSteps = _sortedSteps();
    final isCons = _isConstruction(loan);
    final groups = isCons ? _stageGroups(loan) : <_StageGroup>[];

    final finishIndexGlobal = allSteps.length;
    final isFinishGlobal = !isCons && _idx == finishIndexGlobal;

    final finishIndexStage = groups.length;
    final isFinishStage = isCons && _stageIdx == finishIndexStage;

    ProcessStep? currentStep;
    if (isCons) {
      if (!isFinishStage && _stageIdx >= 0 && _stageIdx < groups.length) {
        final st = groups[_stageIdx].steps;
        if (st.isNotEmpty) {
          final si = _stageStepIdx.clamp(0, st.length - 1);
          currentStep = st[si];
        }
      }
    } else {
      if (!isFinishGlobal && _idx >= 0 && _idx < allSteps.length) currentStep = allSteps[_idx];
    }

    final dt = currentStep?.dataType.toLowerCase().trim() ?? '';

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        title: const Text("Verification Process"),
        centerTitle: true,
      ),
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          child: Column(
            children: [
              if (!isCons) ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < allSteps.length; i++) ...[
                        _chip(
                          text: "Step ${i + 1}",
                          active: _idx == i,
                          enabled: true,
                          onTap: () {
                            _goToGlobalStep(i);
                          },
                        ),
                        const SizedBox(width: 10),
                      ],
                      _chip(
                        text: "Finish",
                        active: isFinishGlobal,
                        enabled: _allDone(allSteps),
                        onTap: () => _goToGlobalStep(finishIndexGlobal),
                      ),
                    ],
                  ),
                ),
              ] else ...[
                SingleChildScrollView(
                  scrollDirection: Axis.horizontal,
                  child: Row(
                    children: [
                      for (int i = 0; i < groups.length; i++) ...[
                        _chip(
                          text: "Stage ${groups[i].stageNo}",
                          active: _stageIdx == i,
                          enabled: _stageEnabled(i, groups),
                          onTap: () => _goToStage(i, groups),
                        ),
                        const SizedBox(width: 10),
                      ],
                      _chip(
                        text: "Finish",
                        active: isFinishStage,
                        enabled: _allDone(allSteps),
                        onTap: () => _goToStage(finishIndexStage, groups),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 10),
                if (!isFinishStage && _stageIdx < groups.length)
                  SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (int i = 0; i < groups[_stageIdx].steps.length; i++) ...[
                          _chip(
                            text: "Step ${i + 1}",
                            active: _stageStepIdx == i,
                            enabled: true,
                            onTap: () => _goToStageStep(i, groups),
                          ),
                          const SizedBox(width: 10),
                        ],
                      ],
                    ),
                  ),
              ],
              const SizedBox(height: 14),
              Expanded(
                child: (isCons ? isFinishStage : isFinishGlobal)
                    ? _finishView(loan, allSteps)
                    : _stepView(loan, currentStep!, dt),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _finishView(BeneficiaryLoan loan, List<ProcessStep> steps) {
    final doneAll = _allDone(steps);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text("Review & Complete", style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900)),
          const SizedBox(height: 8),
          Text(
            "Loan: ${loan.loanId} • ${loan.applicantName}",
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 14),
          ...steps.map((s) {
            final ok = _done(s);
            return Container(
              margin: const EdgeInsets.only(bottom: 10),
              padding: const EdgeInsets.all(14),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: ok ? Colors.green.shade200 : Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  Icon(ok ? Icons.check_circle : Icons.lock_clock, color: ok ? Colors.green : Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      s.whatToDo.isEmpty ? "Step ${s.processId}" : s.whatToDo,
                      style: const TextStyle(fontWeight: FontWeight.w800),
                    ),
                  ),
                  Text(
                    ok ? "done" : "pending",
                    style: TextStyle(color: ok ? Colors.green : Colors.grey[700], fontWeight: FontWeight.w800),
                  )
                ],
              ),
            );
          }),
          const SizedBox(height: 8),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: !doneAll ? null : () => Navigator.pop(context, true),
              style: ElevatedButton.styleFrom(
                backgroundColor: doneAll ? Colors.green : Colors.grey.shade300,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
              ),
              child: const Text(
                "Complete Verification Process",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _stepView(BeneficiaryLoan loan, ProcessStep step, String dt) {
    final needUtil = _needsUtilAmount(loan, step);

    final title = _isConstruction(loan)
        ? _stripStagePrefix(step.whatToDo.isEmpty ? "Step ${step.processId}" : step.whatToDo)
        : (step.whatToDo.isEmpty ? "Step ${step.processId}" : step.whatToDo);

    return SingleChildScrollView(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.w900, fontSize: 18),
          ),
          const SizedBox(height: 6),
          Text(
            "Please capture a ${step.dataType} as instructed.",
            style: TextStyle(color: Colors.grey[700]),
          ),
          const SizedBox(height: 14),
          if (needUtil) ...[
            const Text("Utilization amount (₹)", style: TextStyle(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            TextField(
              controller: _utilCtrl,
              keyboardType: TextInputType.number,
              decoration: InputDecoration(
                hintText: "Enter amount you have used",
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(color: _deep, width: 1.6),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ],
          _exampleBox(),
          const SizedBox(height: 14),
          _mediaBox(step: step, dt: dt),
          if (_warn != null) ...[
            const SizedBox(height: 12),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFFFF3CD),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: const Color(0xFFFFE69C)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.warning_amber_rounded, color: Color(0xFF856404)),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _warn!,
                      style: const TextStyle(
                        fontWeight: FontWeight.w800,
                        color: Color(0xFF856404),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: 16),
          SizedBox(
            width: double.infinity,
            height: 54,
            child: ElevatedButton(
              onPressed: (_uploading || _checkingAi) ? null : () => _submit(step),
              style: ElevatedButton.styleFrom(
                backgroundColor: (_mediaFile == null) ? Colors.grey.shade300 : _saffron,
                foregroundColor: (_mediaFile == null) ? Colors.grey[700] : Colors.white,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
              ),
              child: _uploading
                  ? const SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
              )
                  : const Text(
                "Submit Step",
                style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
