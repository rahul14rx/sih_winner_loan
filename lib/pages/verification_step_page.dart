// lib/pages/verification_step_page.dart
//
// Verification Step — One-step-at-a-time wizard UI
// - Utilization entry inline (editable) for step.processId == 1
// - Utilization saved locally immediately but applied to backend only after wizard completion (Option A)
// - Removes "More" option & removes extra Start button near utilization
// - Single Do's & Don'ts placeholder, constrained
// - Fixes scroll/pixel overflow by wrapping step main card in SingleChildScrollView
//
// Author: ChatGPT (updated per user request)
// Date: 2025-12-01 (patched)

import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'package:exif/exif.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:loan2/models/beneficiary_loan.dart';
import 'package:loan2/pages/movement_verification_page.dart';
import 'package:loan2/pages/rear_camera_capture_page.dart';
import 'package:loan2/services/beneficiary_service.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/sync_service.dart';
import 'package:loan2/ai/combined_ai_gate.dart';
import 'package:loan2/services/location_security_service.dart';
import 'package:geolocator/geolocator.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:loan2/models/process_step.dart';

class VerificationStepPage extends StatefulWidget {
  final String loanId;
  final String userId;

  /// optional: provide a pre-built list of steps (wizard mode)
  final List<ProcessStep>? steps;

  /// optional: open a single step (e.g. when the user taps a step tile)
  final ProcessStep? step;

  const VerificationStepPage({
    super.key,
    required this.loanId,
    required this.userId,
    this.steps,
    this.step,
  });

  @override
  State<VerificationStepPage> createState() => _VerificationStepPageState();
}

class _VerificationStepPageState extends State<VerificationStepPage> with TickerProviderStateMixin {
  final BeneficiaryService _service = BeneficiaryService();
  final ImagePicker _picker = ImagePicker();
  final LocationSecurityService _locationSecurity = LocationSecurityService();

  BeneficiaryLoan? _loan;
  List<ProcessStep> _steps = [];
  int _currentIndex = 0;

  late PageController _pageController;
  late AnimationController _cardAnimController;
  late AnimationController _btnAnim;
  late Animation<double> _btnScale;

  File? _mediaFile;
  bool _isCheckingAi = false;
  bool _isProcessing = false;
  AiResult? _lastAi;

  Position? _position;
  LocationSecurityResult? _locationSecurityResult;
  String _locationStatus = "Initializing location...";
  double _locationConfidence = 0.0;

  String? _warnText;
  bool _debug = false;

  // store editing state & controllers per step id
  final Map<String, bool> _isEditingUtil = {};
  final Map<String, TextEditingController> _utilCtrls = {};

  // pending local util values (kept until wizard complete)
  final Map<String, double> _pendingUtilizations = {}; // key: step.id -> amount

  @override
  void initState() {
    super.initState();
    _pageController = PageController(initialPage: 0);
    _cardAnimController = AnimationController(vsync: this, duration: const Duration(milliseconds: 420));
    _btnAnim = AnimationController(vsync: this, duration: const Duration(milliseconds: 220));
    _btnScale = Tween(begin: 1.0, end: 0.96).animate(CurvedAnimation(parent: _btnAnim, curve: Curves.easeOut));

    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadLoan();
    });

    _initLocationSecurity();
  }

  @override
  void dispose() {
    _pageController.dispose();
    _cardAnimController.dispose();
    _btnAnim.dispose();
    _locationSecurity.stop();
    for (var c in _utilCtrls.values) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _loadLoan() async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    try {
      // load loan details from service
      final loan = await _service.getLoanDetails(widget.loanId);
      _loan = loan;

      // Priority for populating steps:
      // 1) widget.step (single step) -> we open a single-step wizard
      // 2) widget.steps (list provided)
      // 3) loan's processes / supportive fields
      if (widget.step != null) {
        _steps = [widget.step!];
      } else if (widget.steps != null && widget.steps!.isNotEmpty) {
        _steps = List<ProcessStep>.from(widget.steps!);
      } else {
        final rawSteps = <ProcessStep>[];
        try {
          final dyn = loan as dynamic;
          if (dyn.processes != null) {
            final p = dyn.processes;
            if (p is List<ProcessStep>) rawSteps.addAll(p);
            else if (p is List) rawSteps.addAll(p.map((e) => _toProcessStep(e)));
          } else if (dyn.process != null) {
            final p = dyn.process;
            if (p is List<ProcessStep>) rawSteps.addAll(p);
            else if (p is List) rawSteps.addAll(p.map((e) => _toProcessStep(e)));
          } else if (dyn.steps != null) {
            final p = dyn.steps;
            if (p is List<ProcessStep>) rawSteps.addAll(p);
            else if (p is List) rawSteps.addAll(p.map((e) => _toProcessStep(e)));
          } else if (loan is BeneficiaryLoan) {
            rawSteps.addAll(loan.processes);
          }
        } catch (_) {}
        _steps = rawSteps;
      }

      _steps.sort((a, b) => a.processId.compareTo(b.processId));
      _currentIndex = 0;
      _pageController = PageController(initialPage: _currentIndex);

      // prepare controllers + editing flags for steps
      for (final s in _steps) {
        final id = s.id ?? s.processId.toString();
        _isEditingUtil[id] = false;
        final initial = (s.utilizationAmount != null) ? s.utilizationAmount.toString() : '';
        _utilCtrls[id] = TextEditingController(text: initial);
        if (s.utilizationAmount != null) {
          _pendingUtilizations[id] = double.tryParse(s.utilizationAmount.toString()) ?? 0.0;
        }
      }

      if (mounted) {
        setState(() {});
        _cardAnimController.forward();
      }
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('Failed to load loan: $e')));
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  ProcessStep _toProcessStep(dynamic raw) {
    try {
      if (raw is ProcessStep) return raw;
      if (raw is Map<String, dynamic>) return ProcessStep.fromJson(raw);
    } catch (_) {}
    return ProcessStep(id: raw?['id']?.toString() ?? '', processId: int.tryParse(raw?['process_id']?.toString() ?? '0') ?? 0);
  }

  Future<void> _initLocationSecurity() async {
    try {
      await _locationSecurity.start();
      setState(() => _locationStatus = "Acquiring location…");
      await _attemptGetPosition();
    } catch (e) {
      if (_debug) debugPrint("Location init failed: $e");
      setState(() => _locationStatus = "Location unavailable");
    }
  }

  Future<void> _attemptGetPosition() async {
    try {
      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        setState(() => _locationStatus = "Location service disabled");
        return;
      }

      LocationPermission p = await Geolocator.checkPermission();
      if (p == LocationPermission.denied) {
        p = await Geolocator.requestPermission();
        if (p == LocationPermission.denied || p == LocationPermission.deniedForever) {
          setState(() => _locationStatus = "Location permission denied");
          return;
        }
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _position = pos;

      try {
        _locationSecurityResult = await _locationSecurity.evaluate(pos);
        _locationConfidence = (_locationSecurityResult?.confidence ?? 0.0);
        setState(() => _locationStatus = "Location OK (${_locationConfidence.toStringAsFixed(1)}%)");
      } catch (_) {
        setState(() => _locationStatus = "Location acquired");
      }
    } catch (e) {
      if (_debug) debugPrint("Position error: $e");
      setState(() => _locationStatus = "Failed to obtain location");
    }
  }

  // ---------- Capture logic ----------
  void _startStepCapture(ProcessStep step) async {
    if (_isProcessing) return;
    final dt = (step.dataType ?? 'image').toLowerCase();
    if (dt == 'movement' || dt == 'video') {
      await _pickMovement(step);
    } else {
      await _pickImageForStep(step);
    }
  }

  Future<void> _pickMovement(ProcessStep step) async {
    final res = await Navigator.push(
      context,
      MaterialPageRoute(builder: (_) => MovementVerificationPage(loanId: widget.loanId, step: step, userId: widget.userId)),
    );

    if (res is Map && res['success'] == true && res['file_path'] != null) {
      final path = res['file_path'] as String;
      await _handleCapturedFile(step: step, filePath: path, autoAdvance: true);
    } else if (res is String && res.isNotEmpty) {
      await _handleCapturedFile(step: step, filePath: res, autoAdvance: true);
    } else {
      if (_debug) debugPrint('Movement pick cancelled: $res');
    }
  }

  Future<void> _pickImageForStep(ProcessStep step) async {
    if (_isCheckingAi || _isProcessing) return;
    try {
      final dt = (step.dataType ?? 'image').toLowerCase();
      if (dt == 'video') {
        final XFile? pickedVideo = await _picker.pickVideo(source: ImageSource.camera, preferredCameraDevice: CameraDevice.rear, maxDuration: const Duration(seconds: 18));
        if (pickedVideo == null) return;
        _mediaFile = File(pickedVideo.path);
        await _handleCapturedFile(step: step, filePath: _mediaFile!.path, autoAdvance: true);
        return;
      }

      final path = await Navigator.push(context, MaterialPageRoute(builder: (_) => const RearCameraCapturePage()));
      if (path is! String || path.isEmpty) return;
      final file = File(path);

      final shouldRunAi = step.processId == 1;
      if (!shouldRunAi) {
        _mediaFile = file;
        _warnText = null;
        await _handleCapturedFile(step: step, filePath: file.path, autoAdvance: true);
        return;
      }

      setState(() {
        _isCheckingAi = true;
        _warnText = null;
        _mediaFile = null;
      });

      final r = await _runAiChecks(file);
      setState(() => _isCheckingAi = false);

      if (r == null) {
        _mediaFile = file;
        _warnText = "AI check unavailable — please ensure clear photo.";
        await _handleCapturedFile(step: step, filePath: file.path, autoAdvance: true);
      } else if (r.verdict == AiVerdict.valid) {
        _mediaFile = file;
        _warnText = null;
        await _handleCapturedFile(step: step, filePath: file.path, autoAdvance: true);
      } else {
        final msg = (r.verdict == AiVerdict.screenInvalid)
            ? "Invalid image: screen-capture detected. Please retake."
            : "Invalid image: too blurry or low quality. Please retake.";
        _warnText = msg;
        await _showRetakeDialog(msg);
      }
    } catch (e) {
      debugPrint('pickImage error: $e');
      if (!mounted) return;
      setState(() => _isCheckingAi = false);
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text("Failed to capture media: $e")));
    }
  }

  Future<AiResult?> _runAiChecks(File file) async {
    try {
      final isFront = await _isFrontCameraImage(file);
      if (isFront) {
        final proceed = await _showFrontCameraWarning();
        if (proceed != true) return null;
      }
      final r = await CombinedAiGate.instance.check(file);
      _lastAi = r;
      return r;
    } catch (e) {
      debugPrint('AI check error: $e');
      return null;
    }
  }

  Future<void> _showRetakeDialog(String msg) async {
    if (!mounted) return;
    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Retake required"),
        content: Text(msg),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text("Cancel")),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              if (mounted) _startStepCapture(_steps[_currentIndex]);
            },
            child: const Text("Retake"),
          ),
        ],
      ),
    );
  }

  Future<bool?> _showFrontCameraWarning() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text("Front camera detected"),
        content: const Text("Image appears to be taken with the front camera. For verification, please use rear camera for better quality and EXIF trust."),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text("Cancel")),
          ElevatedButton(onPressed: () => Navigator.pop(context, true), child: const Text("Proceed anyway")),
        ],
      ),
    );
  }

  Future<bool> _isFrontCameraImage(File f) async {
    try {
      final bytes = await f.readAsBytes();
      final tags = await readExifFromBytes(bytes);

      final v1 = (tags["EXIF LensModel"]?.printable ?? "").toString().toLowerCase();
      final v2 = (tags["Image Model"]?.printable ?? "").toString().toLowerCase();
      final v3 = (tags["EXIF BodySerialNumber"]?.printable ?? "").toString().toLowerCase();
      final v4 = (tags["EXIF CameraOwnerName"]?.printable ?? "").toString().toLowerCase();

      final s = "$v1 $v2 $v3 $v4";
      if (s.contains("front")) return true;
      return false;
    } catch (_) {
      return false;
    }
  }

  // ------------------ Handle captured file ------------------
  Future<void> _handleCapturedFile({required ProcessStep step, required String filePath, bool autoAdvance = false}) async {
    if (!mounted) return;
    setState(() => _isProcessing = true);
    int? dbId;
    try {
      await _attemptGetPosition();

      // dynamic invocation so compile-time doesn't fail if signature changed.
      final helper = DatabaseHelper.instance as dynamic;
      dbId = await helper.insertImagePath(
        userId: widget.userId,
        processId: step.id,
        processIntId: step.processId,
        loanId: widget.loanId,
        filePath: filePath,
        latitude: _position?.latitude?.toString(),
        longitude: _position?.longitude?.toString(),
        locationConfidence: _locationSecurityResult?.confidence?.toString(),
      );

      final isOnline = await SyncService.realInternetCheck();

      if (!isOnline) {
        await helper.queueForUpload(dbId);
        if (mounted) {
          _toast('Saved offline; will sync when online.', bg: Colors.orange);
          await _refreshLoanAndSteps();
        }
        if (autoAdvance) _advanceAfterDelay();
        return;
      }

      bool uploaded = false;
      try {
        if (helper.uploadQueuedItem != null) {
          uploaded = await helper.uploadQueuedItem(dbId);
        }
      } catch (e) {
        if (_debug) debugPrint('uploadQueuedItem failed: $e');
        uploaded = false;
      }

      if (uploaded) {
        _toast('Uploaded successfully!', bg: Colors.green);
      } else {
        await helper.queueForUpload(dbId);
        _toast('Upload queued (server helper missing).', bg: Colors.orange);
      }

      await _refreshLoanAndSteps();

      if (autoAdvance) _advanceAfterDelay();
    } catch (e) {
      if (_debug) debugPrint('handleCapturedFile error: $e');
      if (dbId != null) {
        try {
          final helper = DatabaseHelper.instance as dynamic;
          await helper.queueForUpload(dbId);
        } catch (_) {}
      }
      _toast('Failed to save capture: $e', bg: Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  Future<void> _refreshLoanAndSteps() async {
    try {
      final updated = await _service.getLoanDetails(widget.loanId);
      if (!mounted) return;
      _loan = updated;
      if (widget.steps == null && widget.step == null) {
        final raw = <ProcessStep>[];
        try {
          final dyn = _loan as dynamic;
          if (dyn.processes != null) {
            final p = dyn.processes;
            if (p is List<ProcessStep>) raw.addAll(p);
            else if (p is List) raw.addAll(p.map((e) => _toProcessStep(e)));
          } else if (dyn.process != null) {
            final p = dyn.process;
            if (p is List<ProcessStep>) raw.addAll(p);
            else if (p is List) raw.addAll(p.map((e) => _toProcessStep(e)));
          } else if (dyn.steps != null) {
            final p = dyn.steps;
            if (p is List<ProcessStep>) raw.addAll(p);
            else if (p is List) raw.addAll(p.map((e) => _toProcessStep(e)));
          } else if (_loan is BeneficiaryLoan) {
            raw.addAll(_loan!.processes);
          }
        } catch (_) {}
        _steps = raw;
        _steps.sort((a,b) => a.processId.compareTo(b.processId));
      }
      // refresh controllers for new/updated steps
      for (final s in _steps) {
        final id = s.id ?? s.processId.toString();
        if (!_utilCtrls.containsKey(id)) {
          _utilCtrls[id] = TextEditingController(text: (s.utilizationAmount != null) ? s.utilizationAmount.toString() : '');
          _isEditingUtil[id] = false;
        } else {
          // keep existing controller but update text if backend changed it
          final cur = _utilCtrls[id]!;
          final backendText = (s.utilizationAmount != null) ? s.utilizationAmount.toString() : '';
          if (backendText != cur.text) cur.text = backendText;
        }
        if (s.utilizationAmount != null) {
          _pendingUtilizations[id] = double.tryParse(s.utilizationAmount.toString()) ?? 0.0;
        }
      }
      setState(() {});
    } catch (e) {
      if (_debug) debugPrint('refreshLoanAndSteps failed: $e');
    }
  }

  void _advanceAfterDelay() {
    Future.delayed(const Duration(milliseconds: 700), () {
      if (!mounted) return;
      if (_currentIndex < _steps.length - 1) {
        _pageController.nextPage(duration: const Duration(milliseconds: 360), curve: Curves.easeInOut);
        setState(() => _currentIndex = min(_steps.length - 1, _currentIndex + 1));
      } else {
        _completeWizard();
      }
    });
  }

  Future<void> _completeWizard() async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    try {
      // finalize verification (server helper if exists)
      try {
        final svc = _service as dynamic;
        if (svc.finalizeVerification != null) {
          final ok = await svc.finalizeVerification(widget.loanId);
          if (ok == true) _toast('Verification submitted for review', bg: Colors.green);
          else _toast('Server rejected finalize', bg: Colors.orange);
        } else {
          _toast('All steps complete (local). Sync will upload queued items.', bg: Colors.blue);
        }
      } catch (_) {
        _toast('All steps complete (local). Sync will upload queued items.', bg: Colors.blue);
      }

      // --- APPLY pending utilization entries to backend now (Option A) ---
      try {
        for (final entry in Map<String,double>.from(_pendingUtilizations).entries) {
          // find step by id
          final step = _steps.firstWhere((s) => (s.id ?? s.processId.toString()) == entry.key, orElse: () => ProcessStep(id: entry.key, processId: 0));
          final amount = entry.value;
          if (amount <= 0) continue;

          try {
            final svc = _service as dynamic;
            if (svc.saveStageUtilization != null && step.processId != 0) {
              await svc.saveStageUtilization(widget.loanId, widget.userId, step.processId, amount);
            } else {
              final helper = DatabaseHelper.instance as dynamic;
              if (helper.updateStepUtilization != null) {
                await helper.updateStepUtilization(loanId: widget.loanId, processId: step.id, utilizationAmount: amount);
              }
            }
            _pendingUtilizations.remove(entry.key);
          } catch (e) {
            if (_debug) debugPrint('apply util failed for ${entry.key}: $e');
            // keep pending for next try
          }
        }
      } catch (e) {
        if (_debug) debugPrint('applying pending utils failed: $e');
      }

      await _refreshLoanAndSteps();
    } catch (e) {
      _toast('Complete failed: $e', bg: Colors.red);
    } finally {
      if (mounted) setState(() => _isProcessing = false);
    }
  }

  // ---------- Helpers ----------
  void _toast(String s, {Color bg = Colors.black87}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(s), backgroundColor: bg));
  }

  Future<int> _safeQueuedCount() async {
    try {
      final c = await DatabaseHelper.instance.getQueuedForUploadCount();
      return c ?? 0;
    } catch (_) {
      return 0;
    }
  }

  bool _allDone() {
    for (final s in _steps) {
      final t = ((s.status ?? '')).toString().toLowerCase();
      final serverDone = t == 'verified' || t == 'pending_review';
      final local = _hasLocalQueuedForStep(s);
      if (!serverDone && !local) return false;
    }
    return true;
  }

  Future<bool> _hasQueuedForStep(ProcessStep s) async {
    try {
      final queued = await DatabaseHelper.instance.getQueuedForUpload();
      for (var row in queued) {
        final pid = row[DatabaseHelper.colProcessId] as String?;
        final lid = row[DatabaseHelper.colLoanId] as String?;
        if (pid != null && pid == s.id && (lid ?? "") == (widget.loanId)) return true;
      }
      return false;
    } catch (_) {
      return false;
    }
  }

  bool _hasLocalQueuedForStep(ProcessStep s) {
    try {
      return (s.fileId == null) && ((s.status ?? '').toLowerCase() != 'verified');
    } catch (_) {
      return false;
    }
  }

  // ---------- Top GPS bar widget (Simple GPS Bar) ----------
  Widget _buildGpsBar() {
    final confidence = _locationConfidence.clamp(0.0, 100.0) / 100.0;
    Color barColor;
    if (_locationConfidence >= 75) barColor = Colors.green;
    else if (_locationConfidence >= 40) barColor = Colors.orange;
    else barColor = Colors.red;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(children: [
        const Icon(Icons.gps_fixed, size: 22),
        const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(_locationStatus, style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14)),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(8),
              child: LinearProgressIndicator(value: confidence, minHeight: 8, backgroundColor: Colors.grey[200], valueColor: AlwaysStoppedAnimation(barColor)),
            ),
          ]),
        ),
        const SizedBox(width: 12),
        Text('${_locationConfidence.toStringAsFixed(0)}%', style: GoogleFonts.inter(fontWeight: FontWeight.w800)),
      ]),
    );
  }

  Widget _docsWidgetForStep(ProcessStep step) {
    final docsAsset = (step as dynamic).docsAsset ?? (step as dynamic).docsImage ?? null;
    final placeholder = Container(
      height: 120,
      decoration: BoxDecoration(
        color: Colors.grey[100],
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Center(child: Text('Do\'s & Don\'ts (placeholder)', style: GoogleFonts.inter(color: Colors.grey[600]))),
    );

    if (docsAsset == null) return placeholder;

    if (docsAsset is String && docsAsset.startsWith('http')) {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.network(docsAsset, height: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder));
    }

    try {
      return ClipRRect(borderRadius: BorderRadius.circular(12), child: Image.asset(docsAsset, height: 120, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder));
    } catch (_) {
      return placeholder;
    }
  }

  // ---------- Build step card ----------
  Widget _buildStepCard(ProcessStep step, bool active, int idx) {
    final status = ((step.status ?? '') as String).toLowerCase();
    final isVerified = status == 'verified';
    final isRejected = status == 'rejected';

    final stepIdKey = (step.id ?? step.processId.toString());

    return AnimatedBuilder(
      animation: _cardAnimController,
      builder: (context, child) {
        return Transform.scale(scale: active ? 1.0 : 0.996, child: child);
      },
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        child: Column(
          children: [
            // header
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black12, blurRadius: 12, offset: Offset(0,6))]),
              child: Row(children: [
                Expanded(child: Text('Step ${step.processId} • ${_currentIndex + 1}/${_steps.length}', style: GoogleFonts.inter(fontWeight: FontWeight.w700))),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(color: isVerified ? Colors.green.withOpacity(0.12) : Colors.orange.withOpacity(0.08), borderRadius: BorderRadius.circular(12)),
                  child: Text(isVerified ? 'Verified' : (isRejected ? 'Rejected' : 'Pending'), style: GoogleFonts.inter(color: isVerified ? Colors.green : Colors.orange, fontWeight: FontWeight.w700)),
                ),
              ]),
            ),

            // main card (flexible with scroll)
            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                child: Container(
                  width: double.infinity,
                  decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(18), border: Border.all(color: Colors.grey.shade200)),
                  child: Column(children: [
                    // instruction header + actions
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(step.whatToDo ?? 'Capture evidence', style: GoogleFonts.inter(fontSize: 18, fontWeight: FontWeight.w800)),
                              const SizedBox(height: 8),
                              Text('Follow instructions and capture clearly', style: GoogleFonts.inter(color: Colors.grey[700])),
                            ]),
                          ),
                          const SizedBox(width: 8),
                          Column(children: [
                            IconButton(onPressed: () => _previewMedia(step), icon: Icon(Icons.visibility_outlined, color: Colors.grey[700])),
                          ]),
                        ],
                      ),
                    ),

                    // capture placeholder / media preview
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: GestureDetector(
                        onTap: () => _startStepCapture(step),
                        child: Container(
                          constraints: const BoxConstraints(minHeight: 180, maxHeight: 320),
                          decoration: BoxDecoration(borderRadius: BorderRadius.circular(14), color: Colors.grey[50], border: Border.all(color: Colors.grey.shade300)),
                          child: Stack(children: [
                            if (step.fileId != null)
                              Positioned.fill(
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(14),
                                  child: step.dataType == 'movement' || step.dataType == 'video'
                                      ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.videocam, size: 64), SizedBox(height: 8), Text('Video/Movement captured')]))
                                      : Image.network(step.mediaUrl ?? '', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image))),
                                ),
                              )
                            else
                              Center(child: Column(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.camera_alt, size: 40, color: Colors.grey[500]), const SizedBox(height: 8), Text('Tap to capture', style: GoogleFonts.inter(fontWeight: FontWeight.w700, color: Colors.grey[700])), const SizedBox(height: 6), Text('Follow on-screen instructions', style: GoogleFonts.inter(fontSize: 12, color: Colors.grey[600]))])),

                            Positioned(
                              right: 12,
                              top: 12,
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                decoration: BoxDecoration(color: Colors.black.withOpacity(0.06), borderRadius: BorderRadius.circular(8)),
                                child: Row(children: [
                                  Icon(step.fileId != null ? Icons.check_circle : Icons.error_outline, color: step.fileId != null ? Colors.green : Colors.orange, size: 16),
                                  const SizedBox(width: 6),
                                  Text(step.fileId != null ? 'Captured' : 'Not captured', style: GoogleFonts.inter(color: Colors.black87, fontSize: 12)),
                                ]),
                              ),
                            ),

                            if (_lastAi != null && step.fileId != null)
                              Positioned(left: 12, bottom: 12, child: Container(padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6), decoration: BoxDecoration(color: Colors.black.withOpacity(0.06), borderRadius: BorderRadius.circular(8)), child: Text('AI: ${_lastAi!.verdict.name} • blur:${_lastAi!.blurScore.toStringAsFixed(2)}', style: GoogleFonts.inter(color: Colors.black87, fontSize: 12)))),
                          ]),
                        ),
                      ),
                    ),

                    const SizedBox(height: 12),

                    // Do's & Don'ts + single banner placeholder
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            "Do's & Don'ts",
                            style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16),
                          ),
                          const SizedBox(height: 8),
                          _docsWidgetForStep(step),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),


                    // Utilization inline (for step.processId == 1) & capture control (no extra Start button)
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      child: Column(
                        children: [
                          if (step.processId == 1) _buildInlineUtilization(step),
                          const SizedBox(height: 12),
                          // only keep capture action as tap on capture box above; provide Retake quick button if media exists
                          Row(children: [
                            Expanded(
                              child: ElevatedButton.icon(
                                onPressed: step.fileId != null ? () => _startStepCapture(step) : null,
                                icon: const Icon(Icons.camera_alt_outlined),
                                label: Text(step.fileId != null ? 'Retake' : 'Capture above'),
                                style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
                              ),
                            ),
                          ]),
                        ],
                      ),
                    ),

                    const SizedBox(height: 16),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInlineUtilization(ProcessStep step) {
    final id = (step.id ?? step.processId.toString());
    final ctrl = _utilCtrls[id] ?? TextEditingController(text: (step.utilizationAmount != null) ? step.utilizationAmount.toString() : '');
    final editing = _isEditingUtil[id] ?? false;
    final displayed = (step.utilizationAmount != null && (step.utilizationAmount.toString()).isNotEmpty) || (_pendingUtilizations.containsKey(id) && _pendingUtilizations[id]! > 0);

    final displayValue = _pendingUtilizations.containsKey(id)
        ? _pendingUtilizations[id]!.toStringAsFixed(2)
        : ((step.utilizationAmount != null) ? double.tryParse(step.utilizationAmount.toString())?.toStringAsFixed(2) ?? '' : '');

    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), color: Colors.grey[100], border: Border.all(color: Colors.grey.shade200)),
      child: Row(children: [
        Expanded(
          child: editing
              ? TextField(
            controller: ctrl,
            keyboardType: TextInputType.numberWithOptions(decimal: true),
            inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d+\.?\d{0,2}'))],
            decoration: InputDecoration(border: InputBorder.none, hintText: 'Enter utilization amount (₹)', hintStyle: TextStyle(color: Colors.grey[600])),
          )
              : (displayed
              ? Row(children: [
            Text('₹$displayValue', style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 16)),
            const SizedBox(width: 8),
            Text('applied after submission', style: GoogleFonts.inter(color: Colors.grey[600], fontSize: 12)),
          ])
              : Text('No utilization amount entered', style: TextStyle(color: Colors.grey[600]))),
        ),

        // inline edit/save button (single control)
        const SizedBox(width: 8),
        editing
            ? Row(children: [
          IconButton(
            onPressed: () {
              // cancel editing: restore controller to previous
              ctrl.text = (step.utilizationAmount != null) ? step.utilizationAmount.toString() : (_pendingUtilizations.containsKey(id) ? _pendingUtilizations[id]!.toString() : '');
              setState(() => _isEditingUtil[id] = false);
            },
            icon: const Icon(Icons.close),
          ),
          ElevatedButton(
            onPressed: () async {
              final txt = ctrl.text.trim();
              final val = double.tryParse(txt) ?? 0.0;
              if (val <= 0) {
                _toast('Enter a valid amount', bg: Colors.orange);
                return;
              }

              // Save locally immediately (so UI shows it). But per Option A, we don't apply to backend until wizard completion.
              try {
                // try DB helper if available to persist locally
                final helper = DatabaseHelper.instance as dynamic;
                if (helper.updateStepUtilization != null) {
                  await helper.updateStepUtilization(loanId: widget.loanId, processId: step.id, utilizationAmount: val);
                }
              } catch (_) {}
              // reflect locally in step & pending map
              step.utilizationAmount = val;
              _pendingUtilizations[id] = val;
              setState(() => _isEditingUtil[id] = false);
              _toast('Utilization saved locally — will apply after submission', bg: Colors.green);
            },
            child: const Text('Save'),
          ),
        ])
            : IconButton(
          onPressed: () {
            setState(() => _isEditingUtil[id] = true);
            // ensure controller text has latest
            final current = (step.utilizationAmount != null) ? step.utilizationAmount.toString() : (_pendingUtilizations.containsKey(id) ? _pendingUtilizations[id]!.toString() : '');
            ctrl.text = current;
          },
          icon: const Icon(Icons.edit),
        ),
      ]),
    );
  }

  void _previewMedia(ProcessStep step) {
    showDialog(
      context: context,
      builder: (_) => Dialog(
        child: SizedBox(
          width: double.infinity,
          height: 520,
          child: Column(children: [
            Expanded(
              child: (step.fileId != null)
                  ? (step.dataType == 'movement' || step.dataType == 'video')
                  ? Center(child: Column(mainAxisSize: MainAxisSize.min, children: const [Icon(Icons.videocam_outlined, size: 80), Text('Video preview not embedded here')]))
                  : Image.network(step.mediaUrl ?? '', fit: BoxFit.cover, errorBuilder: (_, __, ___) => const Center(child: Icon(Icons.broken_image, size: 64)))
                  : const Center(child: Text('No media available')),
            ),
            Padding(
              padding: const EdgeInsets.all(12),
              child: Row(children: [
                Expanded(child: Text('Step ${step.processId} · ${step.whatToDo ?? ""}', style: GoogleFonts.inter(fontWeight: FontWeight.bold))),
                TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
              ]),
            )
          ]),
        ),
      ),
    );
  }

  Widget _buildMiniIndicator() {
    return SizedBox(
      height: 28,
      child: Row(mainAxisAlignment: MainAxisAlignment.center, children: List.generate(_steps.length, (i) {
        final active = i == _currentIndex;
        return AnimatedContainer(duration: const Duration(milliseconds: 250), margin: const EdgeInsets.symmetric(horizontal: 6), width: active ? 26 : 8, height: 8, decoration: BoxDecoration(color: active ? const Color(0xFF1F6FEB) : Colors.grey.shade300, borderRadius: BorderRadius.circular(8)));
      })),
    );
  }

  Widget _buildBottomNav() {
    final last = _currentIndex == (_steps.length - 1);
    final disabled = _isProcessing;
    return SafeArea(
      child: Container(
        color: Colors.transparent,
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(children: [
          ElevatedButton.icon(
            onPressed: _currentIndex == 0 ? null : () { _pageController.previousPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut); setState(() => _currentIndex = max(0, _currentIndex - 1)); },
            icon: const Icon(Icons.chevron_left),
            label: const Text('Back'),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.white, foregroundColor: Colors.black),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: ElevatedButton(
              onPressed: disabled ? null : () {
                if (last) {
                  _completeWizard();
                } else {
                  _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
                  setState(() => _currentIndex = min(_steps.length - 1, _currentIndex + 1));
                }
              },
              child: Text(last ? 'Complete' : 'Next', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
              style: ElevatedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 14), backgroundColor: const Color(0xFF1F6FEB)),
            ),
          ),
        ]),
      ),
    );
  }

  Widget _buildHeader() {
    // Defensive dynamic access for totalUtilized/amount to avoid model mismatch compile errors
    final totalUsed = double.tryParse(((_loan as dynamic)?.totalUtilized ?? (_loan?.totalUtilized ?? '')).toString()) ?? 0.0;
    final total = double.tryParse(((_loan as dynamic)?.amount ?? (_loan?.amount ?? '')).toString()) ?? 0.0;
    final percent = total > 0 ? ((totalUsed / total) * 100).clamp(0, 100) : 0.0;
    return Container(
      width: double.infinity,
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        GestureDetector(
          onTap: () => _showUtilizationDetails(),
          child: Container(
            decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.06), blurRadius: 18, offset: const Offset(0, 10))]),
            padding: const EdgeInsets.all(14),
            child: Row(children: [
              SizedBox(width: 72, height: 72, child: Stack(alignment: Alignment.center, children: [
                CircularProgressIndicator(value: total == 0 ? 0.0 : (totalUsed / total).clamp(0.0, 1.0), strokeWidth: 8, color: const Color(0xFF1F6FEB), backgroundColor: Colors.grey[200]),
                Column(mainAxisSize: MainAxisSize.min, children: [Text('${percent.toStringAsFixed(0)}%', style: GoogleFonts.inter(fontWeight: FontWeight.bold)), Text('Used', style: GoogleFonts.inter(fontSize: 12))]),
              ])),
              const SizedBox(width: 12),
              Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text('Utilization', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                const SizedBox(height: 6),
                Text('₹${totalUsed.toStringAsFixed(2)} used of ₹${total.toStringAsFixed(2)}', style: GoogleFonts.inter(color: Colors.grey[400])),
              ])),
              IconButton(onPressed: () => _showUtilizationDetails(), icon: Icon(Icons.chevron_right, color: Colors.grey[400])),
            ]),
          ),
        ),
        const SizedBox(height: 12),
        _buildMiniIndicator(),
      ]),
    );
  }

  void _showUtilizationDetails() {
    final used = double.tryParse(((_loan as dynamic)?.totalUtilized ?? (_loan?.totalUtilized ?? '0')).toString()) ?? 0.0;
    final total = double.tryParse(((_loan as dynamic)?.amount ?? (_loan?.amount ?? '0')).toString()) ?? 0.0;
    showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(14))),
        builder: (_) => SafeArea(
          child: Padding(
              padding: const EdgeInsets.all(18.0),
              child: SizedBox(height: 420, child: Column(children: [
                Row(children: [Text('Utilization Details', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18)), const Spacer(), IconButton(onPressed: () => Navigator.pop(context), icon: const Icon(Icons.close))]),
                const SizedBox(height: 12),
                Container(width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(12), boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.03), blurRadius: 12)]), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                  Text('Total Utilized', style: GoogleFonts.inter(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 8),
                  Text('₹${used.toStringAsFixed(2)}', style: GoogleFonts.inter(fontSize: 26, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 12),
                  Text('Loan Amount: ₹${total.toStringAsFixed(2)}', style: GoogleFonts.inter(color: Colors.grey[700])),
                  const SizedBox(height: 16),
                  Expanded(child: ListView.builder(itemCount: _steps.length, itemBuilder: (ctx, i) {
                    final s = _steps[i];
                    final utilVal = double.tryParse(s.utilizationAmount?.toString() ?? "") ?? 0.0;
                    return ListTile(leading: CircleAvatar(child: Text('${s.processId}')), title: Text(s.whatToDo ?? 'Step ${s.processId}'), subtitle: Text('₹${utilVal.toStringAsFixed(2)}'), trailing: Text((s.status ?? '').toString()));
                  })),
                ])),
              ]))),
        ));
  }

  @override
  Widget build(BuildContext context) {
    if (_steps.isEmpty && _isProcessing) return const Scaffold(body: Center(child: CircularProgressIndicator()));

    return Scaffold(
      backgroundColor: Colors.grey[100],
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        title: Text('Verification Wizard', style: GoogleFonts.inter(fontWeight: FontWeight.w800, fontSize: 18, color: Colors.black87)),
        iconTheme: const IconThemeData(color: Colors.black87),
        actions: [
          FutureBuilder<int>(
            future: _safeQueuedCount(),
            builder: (context, snap) {
              final count = snap.data ?? 0;
              return Padding(
                padding: const EdgeInsets.only(right: 14.0),
                child: Row(children: [
                  FutureBuilder<bool>(
                    future: SyncService.realInternetCheck(),
                    builder: (c, s) {
                      final online = s.data ?? false;
                      return Row(children: [
                        Icon(online ? Icons.wifi : Icons.wifi_off, color: online ? Colors.green : Colors.grey),
                        const SizedBox(width: 8),
                        if (count > 0)
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            decoration: BoxDecoration(color: Colors.orange.shade100, borderRadius: BorderRadius.circular(12)),
                            child: Text('$count offline', style: GoogleFonts.inter(color: Colors.orange.shade800, fontWeight: FontWeight.w700)),
                          )
                        else
                          Text(online ? 'Online' : 'Offline', style: GoogleFonts.inter(color: online ? Colors.green : Colors.grey)),
                      ]);
                    },
                  ),
                ]),
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: _steps.isEmpty
            ? Center(child: Text('No steps available', style: GoogleFonts.inter(color: Colors.grey[700])))
            : Column(children: [
          // GPS bar at top (replaces utilization card in wizard)
          _buildGpsBar(),
          const SizedBox(height: 8),
          Expanded(
            child: PageView.builder(
              controller: _pageController,
              itemCount: _steps.length,
              onPageChanged: (i) {
                setState(() {
                  _currentIndex = i;
                  _cardAnimController.forward(from: 0.0);
                  _mediaFile = null;
                  _warnText = null;
                });
              },
              itemBuilder: (context, idx) {
                final step = _steps[idx];
                final active = idx == _currentIndex;
                return _buildStepCard(step, active, idx);
              },
            ),
          ),
          _buildBottomNav(),
        ]),
      ),
    );
  }
}
