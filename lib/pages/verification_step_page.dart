// lib/pages/verification_step_page.dart
//
// Wizard-like Verification Step (Single Step)
// - Backend logic identical to previous working version
// - UI inspired by multi-step wizard screen
//   * White app bar with online/offline + queued badge
//   * GPS bar at top
//   * Rich step card with capture box, Do's & Don'ts banner
//   * Inline utilization for processId == 1
//   * Primary Submit button at bottom of card
//

import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:image_picker/image_picker.dart';
import 'package:http/http.dart' as http;

import 'package:loan2/ai/combined_ai_gate.dart';
import 'package:loan2/models/process_step.dart' as ps;
import 'package:loan2/pages/movement_verification_page.dart';
import 'package:loan2/pages/rear_camera_capture_page.dart';
import 'package:loan2/pages/scanner.dart'; // Imported ScannerPage
import 'package:loan2/services/api.dart';
import 'package:loan2/services/database_helper.dart';
import 'package:loan2/services/location_security_service.dart';
import 'package:loan2/services/sync_service.dart';

import 'package:geolocator/geolocator.dart';

class VerificationStepPage extends StatefulWidget {
  final String loanId;
  final String userId;
  final ps.ProcessStep step;

  const VerificationStepPage({
    super.key,
    required this.loanId,
    required this.userId,
    required this.step,
  });

  @override
  State<VerificationStepPage> createState() => _VerificationStepPageState();
}

class _VerificationStepPageState extends State<VerificationStepPage> {
  static const _navy = Color(0xFF1F6FEB);
  static const _accent = Color(0xFFFF9933);

  final ImagePicker _picker = ImagePicker();
  final LocationSecurityService _locationSecurity = LocationSecurityService();

  final TextEditingController _amountController = TextEditingController();

  File? _mediaFile;
  bool _uploading = false;
  bool _checkingAi = false;
  String? _warn;

  // location UI
  String _locationStatus = "Initializing…";
  double _locationConfidence = 0.0;
  Position? _position;
  LocationSecurityResult? _sec;

  // local queued preview (for THIS step)
  String? _queuedLocalPath;

  StreamSubscription? _onlineSub;

  bool get _needsUtil => widget.step.processId == 1;

  @override
  void initState() {
    super.initState();
    CombinedAiGate.instance.init();

    // preload existing utilization (if any)
    final existingUtil = _existingUtil(widget.step);
    if (existingUtil.isNotEmpty) _amountController.text = existingUtil;

    _locationSecurity.start().then((_) {
      if (mounted) setState(() => _locationStatus = "Location service ready");
      _refreshLocation(); // best-effort
    });

    _loadQueuedPreview();

    // optional: refresh queued preview when coming online
    _onlineSub = SyncService.onOnlineStatusChanged.listen((isOnline) {
      if (isOnline) _loadQueuedPreview();
    });
  }

  @override
  void dispose() {
    _onlineSub?.cancel();
    _amountController.dispose();
    _locationSecurity.stop();
    super.dispose();
  }

  // ---------- small helpers ----------

  String _url(String path) {
    var b = kBaseUrl;
    if (!b.endsWith('/')) b = '$b/';
    if (path.startsWith('/')) path = path.substring(1);
    return '$b$path';
  }

  String _existingUtil(ps.ProcessStep s) {
    try {
      final d = s as dynamic;
      final v = d.utilizationAmount ?? d.utilization_amount;
      if (v == null) return "";
      final out = v.toString();
      return out == "null" ? "" : out;
    } catch (_) {
      return "";
    }
  }

  String? _serverMediaUrl(ps.ProcessStep s) {
    try {
      if ((s.mediaUrl ?? '').trim().isNotEmpty) return s.mediaUrl!.trim();
      final d = s as dynamic;
      final u = d.media_url ?? d.mediaURL ?? d.mediaUrl;
      final out = (u ?? '').toString().trim();
      return out.isEmpty ? null : out;
    } catch (_) {
      return (s.mediaUrl ?? '').trim().isEmpty ? null : s.mediaUrl!.trim();
    }
  }

  bool _serverDone(ps.ProcessStep s) {
    final t = (s.status ?? '').toLowerCase().trim();
    return t == 'verified' || t == 'pending_review';
  }

  Color _statusColor() {
    final t = (widget.step.status ?? '').toLowerCase().trim();
    if (t == 'verified') return Colors.green;
    if (t == 'rejected') return Colors.red;
    if (t == 'pending_review' || t == 'in_review') return Colors.blue;
    return Colors.orange;
  }

  String _statusText() {
    final t = (widget.step.status ?? '').trim();
    return t.isEmpty ? "Pending" : t;
  }

  Future<int> _queuedCount() async {
    try {
      final c = await DatabaseHelper.instance.getQueuedForUploadCount();
      return c ?? 0;
    } catch (_) {
      return 0;
    }
  }

  // ---------- location ----------

  Future<void> _refreshLocation() async {
    try {
      final enabled = await Geolocator.isLocationServiceEnabled();
      if (!enabled) {
        if (mounted) setState(() => _locationStatus = "Location service disabled");
        return;
      }

      var perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied) perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
        if (mounted) setState(() => _locationStatus = "Location permission denied");
        return;
      }

      final pos = await Geolocator.getCurrentPosition(desiredAccuracy: LocationAccuracy.best);
      _position = pos;

      final sec = await _locationSecurity.evaluate(pos);
      _sec = sec;

      if (mounted) {
        setState(() {
          _locationConfidence = sec.confidence;
          _locationStatus = "Location OK (${sec.confidence.toStringAsFixed(1)}%)";
        });
      }
    } catch (_) {
      if (mounted) setState(() => _locationStatus = "Location unavailable");
    }
  }

  // ---------- queued preview ----------

  Future<void> _loadQueuedPreview() async {
    try {
      final queued = await DatabaseHelper.instance.getQueuedForUpload();
      String? found;

      for (final row in queued) {
        final lid = (row[DatabaseHelper.colLoanId] ?? row['loan_id'] ?? row['loanId'])?.toString();
        if (lid != widget.loanId) continue;

        final pid = (row[DatabaseHelper.colProcessId] ?? row['process_id'] ?? row['processId'])?.toString();
        // IMPORTANT: in your submit, you save step.id into processId column
        if (pid != widget.step.id) continue;

        final fp = (row[DatabaseHelper.colFilePath] ??
            row['file_path'] ??
            row['filePath'] ??
            row['path'])
            ?.toString();
        if (fp != null && fp.isNotEmpty && File(fp).existsSync()) {
          found = fp;
          break;
        }
      }

      if (!mounted) return;
      setState(() => _queuedLocalPath = found);
    } catch (_) {
      if (!mounted) return;
      setState(() => _queuedLocalPath = null);
    }
  }

  // ---------- UI widgets ----------

  Widget _gpsBar() {
    final conf = _locationConfidence.clamp(0.0, 100.0);
    final p = conf / 100.0;

    Color c;
    if (conf >= 75) {
      c = Colors.green;
    } else if (conf >= 40) {
      c = Colors.orange;
    } else {
      c = Colors.red;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      color: Colors.white,
      child: Row(
        children: [
          const Icon(Icons.gps_fixed, size: 22),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _locationStatus,
                  style: GoogleFonts.inter(fontWeight: FontWeight.w700, fontSize: 14),
                ),
                const SizedBox(height: 6),
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: LinearProgressIndicator(
                    value: p.isNaN ? 0 : p,
                    minHeight: 8,
                    backgroundColor: Colors.grey[200],
                    valueColor: AlwaysStoppedAnimation(c),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(width: 10),
          Text(
            "${conf.toStringAsFixed(0)}%",
            style: GoogleFonts.inter(fontWeight: FontWeight.w800),
          ),
        ],
      ),
    );
  }

  Widget _dosDontsBanner() {
    return Container(
      height: 140,
      width: double.infinity,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: Colors.grey.shade300),
        color: Colors.grey.shade100,
      ),
      clipBehavior: Clip.antiAlias,
      child: Image.asset(
        "assets/dos/dos_donts_sample.png",
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) => Center(
          child: Text(
            "Do's & Don'ts Banner",
            style: GoogleFonts.inter(
              color: Colors.grey[600],
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
      ),
    );
  }

  Widget _warnBox(String t) {
    return Container(
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
              t,
              style: const TextStyle(
                color: Color(0xFF856404),
                fontWeight: FontWeight.w800,
              ),
            ),
          ),
        ],
      ),
    );
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

  Widget _mediaBox() {
    final dt = (widget.step.dataType ?? 'image').trim().toLowerCase();

    final serverUrl = _serverMediaUrl(widget.step);
    final localQueued = _queuedLocalPath;

    final showLocalQueued = (_mediaFile == null) &&
        (localQueued != null) &&
        localQueued.isNotEmpty &&
        File(localQueued).existsSync();

    final showServer =
        (_mediaFile == null) && !showLocalQueued && (serverUrl != null && serverUrl.isNotEmpty);

    final hasPreview = _mediaFile != null || showLocalQueued || showServer;

    Widget preview;
    if (_mediaFile != null) {
      if (dt == 'video' || dt == 'movement') {
        preview = Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.play_circle, color: Colors.white, size: 60),
          ),
        );
      } else {
        preview = Image.file(_mediaFile!, fit: BoxFit.cover);
      }
    } else if (showLocalQueued) {
      if (dt == 'video' || dt == 'movement') {
        preview = Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.play_circle, color: Colors.white, size: 60),
          ),
        );
      } else {
        preview = Image.file(File(localQueued!), fit: BoxFit.cover);
      }
    } else if (showServer) {
      if (dt == 'video' || dt == 'movement') {
        preview = Container(
          color: Colors.black,
          child: const Center(
            child: Icon(Icons.play_circle, color: Colors.white, size: 60),
          ),
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
              dt == 'video' || dt == 'movement'
                  ? Icons.videocam_outlined
                  : dt == 'scanner'
                  ? Icons.document_scanner_outlined // Scanner icon
                  : Icons.camera_alt_outlined,
              size: 44,
              color: Colors.grey[700],
            ),
            const SizedBox(height: 8),
            Text(
              dt == 'video' || dt == 'movement'
                  ? "Tap to record"
                  : dt == 'scanner'
                  ? "Tap to scan"
                  : "Tap to capture",
              style: GoogleFonts.inter(
                color: Colors.grey[700],
                fontWeight: FontWeight.w900,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              "Follow on-screen instructions",
              style: GoogleFonts.inter(
                color: Colors.grey[600],
                fontSize: 12,
              ),
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
              await _pickMedia();
              return;
            }

            // only enlarge images
            if (dt == 'video' || dt == 'movement') return;

            if (_mediaFile != null) {
              await _showImageFull(
                image: Image.file(
                  _mediaFile!,
                  fit: BoxFit.contain,
                ),
              );
              return;
            }
            if (showLocalQueued) {
              await _showImageFull(
                image: Image.file(
                  File(localQueued!),
                  fit: BoxFit.contain,
                ),
              );
              return;
            }
            if (showServer) {
              await _showImageFull(
                image: Image.network(
                  serverUrl!,
                  fit: BoxFit.contain,
                ),
              );
              return;
            }
          },
          child: Container(
            height: 220,
            width: double.infinity,
            decoration: BoxDecoration(
              color: Colors.grey.shade50,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Stack(
              children: [
                if (hasPreview)
                  Positioned.fill(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: preview,
                    ),
                  )
                else
                  preview,

                // top-right status chip (Captured/Queued/Server)
                Positioned(
                  top: 12,
                  right: 12,
                  child: Container(
                    padding:
                    const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                    decoration: BoxDecoration(
                      color: Colors.black.withOpacity(0.06),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          _mediaFile != null
                              ? Icons.check_circle
                              : (showLocalQueued
                              ? Icons.wifi_off
                              : (showServer
                              ? Icons.cloud_done
                              : Icons.error_outline)),
                          size: 16,
                          color: _mediaFile != null
                              ? Colors.green
                              : (showLocalQueued
                              ? Colors.orange
                              : (showServer ? Colors.blue : Colors.orange)),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          _mediaFile != null
                              ? "Captured"
                              : (showLocalQueued
                              ? "Queued"
                              : (showServer
                              ? "Server"
                              : "Not captured")),
                          style: GoogleFonts.inter(
                            fontWeight: FontWeight.w700,
                            fontSize: 12,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),

                if (_checkingAi)
                  Positioned.fill(
                    child: Container(
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.88),
                        borderRadius: BorderRadius.circular(16),
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
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
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
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
                OutlinedButton(
                  onPressed:
                  (_uploading || _checkingAi) ? null : _pickMedia,
                  style: OutlinedButton.styleFrom(
                    foregroundColor: _accent,
                    side: const BorderSide(color: _accent),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 10,
                    ),
                  ),
                  child: Text(
                    "Recapture",
                    style: GoogleFonts.inter(
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                ),
              ],
            ),
          )
        ],
      ],
    );
  }

  // ---------- capture (BACKEND LOGIC UNTOUCHED) ----------

  Future<void> _pickMedia() async {
    if (_uploading || _checkingAi) return;

    final dt = (widget.step.dataType ?? 'image').trim().toLowerCase();

    setState(() {
      _warn = null;
      _mediaFile = null;
    });

    try {
      if (dt == 'movement') {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => MovementVerificationPage(
              loanId: widget.loanId,
              userId: widget.userId,
              step: widget.step,
            ),
          ),
        );

        if (result is String && result.isNotEmpty) {
          setState(() => _mediaFile = File(result));
        }
        return;
      }

      if (dt == 'scanner') {
        final result = await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => ScannerPage(
              loanId: widget.loanId,
              processId: widget.step.id,
              userId: widget.userId,
              title: widget.step.whatToDo ?? "Scan Document",
            ),
          ),
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

      // photo
      final path = await Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => const RearCameraCapturePage()),
      );
      if (path is! String || path.isEmpty) return;

      final file = File(path);

      final shouldRunAi = widget.step.processId == 1;
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

  // ---------- submit (BACKEND LOGIC UNTOUCHED) ----------

  Future<void> _submitStep() async {
    if (_mediaFile == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please capture the required media first.")),
      );
      return;
    }

    if (_needsUtil && _amountController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please enter utilization amount")),
      );
      return;
    }

    setState(() => _uploading = true);

    int? dbId;

    try {
      if (_position == null || _sec == null) {
        await _refreshLocation();
      }

      final finalPath = _mediaFile!.path;

      dbId = await DatabaseHelper.instance.insertImagePath(
        userId: widget.userId,
        processId: widget.step.id,
        processIntId: widget.step.processId,
        loanId: widget.loanId,
        filePath: finalPath,
      );

      final isOnline = await SyncService.realInternetCheck();

      if (!isOnline) {
        await DatabaseHelper.instance.queueForUpload(dbId);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Saved offline. Will sync when online."),
            backgroundColor: Colors.orange,
          ),
        );
        Navigator.pop(context, true);
        return;
      }

      final request =
      http.MultipartRequest('POST', Uri.parse(_url('upload')))
        ..fields['loan_id'] = widget.loanId
        ..fields['process_id'] = widget.step.id
        ..fields['user_id'] = widget.userId
        ..fields['latitude'] = (_position?.latitude ?? 0).toString()
        ..fields['longitude'] = (_position?.longitude ?? 0).toString()
        ..fields['location_confidence'] =
        (_sec?.confidence ?? 0).toString();

      if (_needsUtil) {
        request.fields['utilization_amount'] =
            _amountController.text.trim();
      }

      request.files.add(
        await http.MultipartFile.fromPath('file', finalPath),
      );
      final response =
      await request.send().timeout(const Duration(seconds: 30));

      if (response.statusCode == 200) {
        await DatabaseHelper.instance.deleteImage(dbId, deleteFile: false);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Uploaded successfully!"),
            backgroundColor: Colors.green,
          ),
        );
        Navigator.pop(context, true);
      } else {
        throw Exception("Server error ${response.statusCode}");
      }
    } catch (e) {
      if (dbId != null) {
        try {
          await DatabaseHelper.instance.queueForUpload(dbId);
        } catch (_) {}
      }
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text("Upload failed (queued): $e"),
          backgroundColor: Colors.red,
        ),
      );
      Navigator.pop(context, true);
    } finally {
      if (mounted) setState(() => _uploading = false);
    }
  }

  // ---------- build (UI reshaped to wizard style) ----------

  @override
  Widget build(BuildContext context) {
    final dt = (widget.step.dataType ?? 'image').trim().toLowerCase();

    return Scaffold(
      backgroundColor: Colors.grey.shade100,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 1,
        foregroundColor: Colors.black87,
        iconTheme: const IconThemeData(color: Colors.black87),
        title: Text(
          "Verification Wizard",
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: GoogleFonts.inter(
            fontWeight: FontWeight.w900,
            fontSize: 18,
            color: Colors.black87,
          ),
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 10),
            child: Row(
              children: [
                FutureBuilder<bool>(
                  future: SyncService.realInternetCheck(),
                  builder: (_, snap) {
                    final online = snap.data ?? false;
                    return Row(
                      children: [
                        Icon(
                          online ? Icons.wifi : Icons.wifi_off,
                          color: online ? Colors.green : Colors.grey,
                        ),
                        const SizedBox(width: 6),
                        FutureBuilder<int>(
                          future: _queuedCount(),
                          builder: (_, s) {
                            final c = s.data ?? 0;
                            if (c <= 0) {
                              return Text(
                                online ? "Online" : "Offline",
                                style: GoogleFonts.inter(
                                  color:
                                  online ? Colors.green : Colors.grey[600],
                                  fontSize: 12,
                                  fontWeight: FontWeight.w600,
                                ),
                              );
                            }
                            return Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: Colors.orange.shade100,
                                borderRadius: BorderRadius.circular(12),
                              ),
                              child: Text(
                                "$c offline",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w800,
                                  fontSize: 12,
                                  color: Colors.orange.shade800,
                                ),
                              ),
                            );
                          },
                        ),
                      ],
                    );
                  },
                ),
              ],
            ),
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            // GPS bar at the very top
            _gpsBar(),
            const SizedBox(height: 8),

            Expanded(
              child: SingleChildScrollView(
                physics: const BouncingScrollPhysics(),
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                child: Column(
                  children: [
                    // Step header card (wizard-ish)
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.all(14),
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withOpacity(0.06),
                            blurRadius: 18,
                            offset: const Offset(0, 10),
                          ),
                        ],
                      ),
                      child: Row(
                        children: [
                          CircleAvatar(
                            radius: 18,
                            backgroundColor: _navy.withOpacity(0.08),
                            child: Text(
                              "${widget.step.processId}",
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                color: _navy,
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment:
                              CrossAxisAlignment.start,
                              children: [
                                Text(
                                  "Loan: ${widget.loanId}",
                                  style: GoogleFonts.inter(
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  "Capture: $dt",
                                  style: GoogleFonts.inter(
                                    color: Colors.grey[700],
                                    fontSize: 12,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 10,
                              vertical: 6,
                            ),
                            decoration: BoxDecoration(
                              color: _statusColor().withOpacity(0.12),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              _statusText(),
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w800,
                                color: _statusColor(),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 14),

                    // Main wizard-style step card
                    Container(
                      width: double.infinity,
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(18),
                        border: Border.all(color: Colors.grey.shade200),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment:
                          CrossAxisAlignment.start,
                          children: [
                            // Step title + subtitle
                            Text(
                              widget.step.whatToDo ??
                                  "Capture evidence",
                              style: GoogleFonts.inter(
                                fontSize: 18,
                                fontWeight: FontWeight.w900,
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              "Follow the instructions carefully and capture a clear $dt of the asset.",
                              style: GoogleFonts.inter(
                                color: Colors.grey[700],
                              ),
                            ),

                            const SizedBox(height: 16),

                            if (_needsUtil) ...[
                              Text(
                                "Utilization amount (₹)",
                                style: GoogleFonts.inter(
                                  fontWeight: FontWeight.w900,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _amountController,
                                keyboardType: TextInputType.number,
                                decoration: InputDecoration(
                                  hintText:
                                  "Enter amount you have used",
                                  border: OutlineInputBorder(
                                    borderRadius:
                                    BorderRadius.circular(12),
                                  ),
                                  focusedBorder: OutlineInputBorder(
                                    borderRadius:
                                    BorderRadius.circular(12),
                                    borderSide: const BorderSide(
                                      color: _accent,
                                      width: 1.6,
                                    ),
                                  ),
                                ),
                              ),
                              const SizedBox(height: 16),
                            ],

                            Text(
                              "Do's & Don'ts",
                              style: GoogleFonts.inter(
                                fontWeight: FontWeight.w900,
                                fontSize: 16,
                              ),
                            ),
                            const SizedBox(height: 10),
                            _dosDontsBanner(),

                            const SizedBox(height: 16),

                            _mediaBox(),

                            if (_warn != null) ...[
                              const SizedBox(height: 12),
                              _warnBox(_warn!),
                            ],

                            const SizedBox(height: 20),

                            SizedBox(
                              width: double.infinity,
                              height: 54,
                              child: AnimatedOpacity(
                                opacity: _uploading ? 0.8 : 1.0,
                                duration:
                                const Duration(milliseconds: 180),
                                child: ElevatedButton(
                                  onPressed: (_uploading || _checkingAi)
                                      ? null
                                      : _submitStep,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: (_mediaFile == null)
                                        ? Colors.grey.shade300
                                        : _accent,
                                    foregroundColor: (_mediaFile == null)
                                        ? Colors.grey[700]
                                        : Colors.white,
                                    shape: RoundedRectangleBorder(
                                      borderRadius:
                                      BorderRadius.circular(16),
                                    ),
                                  ),
                                  child: _uploading
                                      ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2,
                                    ),
                                  )
                                      : Text(
                                    "Submit Step ${widget.step.processId}",
                                    style: GoogleFonts.inter(
                                      fontWeight:
                                      FontWeight.w900,
                                      fontSize: 16,
                                    ),
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 22),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}