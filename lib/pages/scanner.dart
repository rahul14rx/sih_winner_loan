// lib/pages/scanner.dart

import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:path_provider/path_provider.dart';

// Removed the global dependency that was causing the issue
// late List<CameraDescription> availableCamerasGlobal;

class ScannerPage extends StatefulWidget {
  final String loanId;
  final String processId;
  final String userId;
  final String title;

  const ScannerPage({
    super.key,
    required this.loanId,
    required this.processId,
    required this.userId,
    this.title = "Document Scanner",
  });

  @override
  State<ScannerPage> createState() => _ScannerPageState();
}

class _ScannerPageState extends State<ScannerPage> with WidgetsBindingObserver {
  CameraController? _controller;
  bool _initialized = false;
  bool _processing = false;
  bool _saving = false;

  Uint8List? _displayBytes;
  final double overlayAspectRatio = 8.5 / 11.0; // Letter size paper aspect

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _initCamera();
  }

  Future<void> _initCamera() async {
    try {
      // Fetch cameras directly here instead of relying on an uninitialized global
      final cameras = await availableCameras();
      
      if (cameras.isEmpty) {
        debugPrint("No cameras found");
        if (mounted) setState(() => _initialized = false);
        return;
      }

      final cam = cameras.firstWhere(
            (c) => c.lensDirection == CameraLensDirection.back,
        orElse: () => cameras.first,
      );

      _controller = CameraController(
        cam,
        ResolutionPreset.max,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await _controller!.initialize();
      await _controller!.setFlashMode(FlashMode.off);
      
      if (!mounted) return;
      setState(() => _initialized = true);
    } catch (e) {
      debugPrint("Camera init error: $e");
      if (mounted) setState(() => _initialized = false);
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller?.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    final CameraController? cameraController = _controller;
    if (cameraController == null || !cameraController.value.isInitialized) {
      return;
    }
    if (state == AppLifecycleState.inactive) {
      cameraController.dispose();
    } else if (state == AppLifecycleState.resumed) {
      _initCamera();
    }
  }

  Future<void> _captureAndScan() async {
    if (_controller == null || !_controller!.value.isInitialized) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("Camera not ready. Please restart app or check permissions.")));
      return;
    }

    setState(() {
      _processing = true;
    });

    try {
      final XFile photo = await _controller!.takePicture();
      final bytes = await photo.readAsBytes();

      final ui.Image captured = await _decodeUiImage(bytes);
      final cropRect = _computeCropRect(captured.width, captured.height);

      // Crop and Grayscale
      final ui.Image cropped = await _cropUiImage(
        captured,
        cropRect,
        applyGrayscale: true,
      );

      final ByteData? pngBytes =
      await cropped.toByteData(format: ui.ImageByteFormat.png);

      if (pngBytes == null) throw Exception("Failed to encode PNG");

      setState(() {
        _displayBytes = pngBytes.buffer.asUint8List();
      });
    } catch (e, st) {
      debugPrint("Scan error: $e\n$st");
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text("Scan failed: $e")));
    } finally {
      if (mounted) setState(() => _processing = false);
    }
  }

  Future<void> _saveScan() async {
    if (_displayBytes == null) return;

    setState(() => _saving = true);

    try {
      // Save bytes to a temp file and return path
      final tempDir = await getTemporaryDirectory();
      final filename = 'scan_${widget.loanId}_${widget.processId}_${DateTime.now().millisecondsSinceEpoch}.png';
      final file = File('${tempDir.path}/$filename');
      await file.writeAsBytes(_displayBytes!);

      if (!mounted) return;
      Navigator.pop(context, file.path); // Return path to parent
    } catch (e) {
      ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error saving: $e"), backgroundColor: Colors.red)
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<ui.Image> _decodeUiImage(Uint8List bytes) {
    final completer = Completer<ui.Image>();
    ui.decodeImageFromList(bytes, (ui.Image img) {
      completer.complete(img);
    });
    return completer.future;
  }

  Rect _computeCropRect(int w, int h) {
    final wf = w.toDouble(), hf = h.toDouble();
    final imageAspect = wf / hf;

    double cropW, cropH;

    if (imageAspect > overlayAspectRatio) {
      cropH = hf * 0.88;
      cropW = cropH * overlayAspectRatio;
    } else {
      cropW = wf * 0.92;
      cropH = cropW / overlayAspectRatio;
    }

    final left = (wf - cropW) / 2;
    final top = (hf - cropH) / 2;

    return Rect.fromLTWH(left, top, cropW, cropH);
  }

  Future<ui.Image> _cropUiImage(
      ui.Image src,
      Rect rect, {
        bool applyGrayscale = false,
      }) async {
    final dstW = rect.width.round();
    final dstH = rect.height.round();
    final recorder = ui.PictureRecorder();
    final canvas =
    Canvas(recorder, Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()));

    final paint = Paint();

    if (applyGrayscale) {
      const grayMatrix = <double>[
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0.2126, 0.7152, 0.0722, 0, 0,
        0, 0, 0, 1, 0,
      ];
      paint.colorFilter = ui.ColorFilter.matrix(grayMatrix);
    }

    canvas.drawImageRect(
      src,
      rect,
      Rect.fromLTWH(0, 0, dstW.toDouble(), dstH.toDouble()),
      paint,
    );

    final picture = recorder.endRecording();
    return picture.toImage(dstW, dstH);
  }

  @override
  Widget build(BuildContext context) {
    // If we have a scan, show Preview Mode
    if (_displayBytes != null) {
      return Scaffold(
        appBar: AppBar(
          title: const Text("Review Scan"),
          leading: IconButton(
            icon: const Icon(Icons.close),
            onPressed: () {
              setState(() => _displayBytes = null);
            },
          ),
        ),
        body: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                child: Center(
                  child: Image.memory(_displayBytes!),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      icon: const Icon(Icons.refresh),
                      label: const Text("Retake"),
                      onPressed: _saving ? null : () {
                        setState(() => _displayBytes = null);
                      },
                      style: OutlinedButton.styleFrom(padding: const EdgeInsets.all(16)),
                    ),
                  ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: ElevatedButton.icon(
                      icon: _saving
                          ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2))
                          : const Icon(Icons.check),
                      label: Text(_saving ? "Saving..." : "Done"),
                      onPressed: _saving ? null : _saveScan,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF138808),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.all(16)
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    // Otherwise, show Camera Scanner Mode
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: Column(
        children: [
          Expanded(
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (_initialized && _controller != null)
                  CameraPreview(_controller!)
                else
                  const Center(child: CircularProgressIndicator()),

                _buildOverlay(),
                
                if (_processing)
                  Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: const Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        CircularProgressIndicator(color: Colors.white),
                        SizedBox(height: 16),
                        Text("Processing...", style: TextStyle(color: Colors.white))
                      ],
                    ),
                  ),
              ],
            ),
          ),
          Container(
            color: Colors.black,
            padding: const EdgeInsets.symmetric(vertical: 24, horizontal: 32),
            child: SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  FloatingActionButton.large(
                    onPressed: _processing ? null : _captureAndScan,
                    backgroundColor: Colors.white,
                    child: const Icon(Icons.camera, color: Colors.black, size: 48),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildOverlay() {
    return LayoutBuilder(builder: (context, c) {
      final w = c.maxWidth;
      final h = c.maxHeight;

      double ow, oh;

      if (w / h > overlayAspectRatio) {
        oh = h * 0.84;
        ow = oh * overlayAspectRatio;
      } else {
        ow = w * 0.9;
        oh = ow / overlayAspectRatio;
      }

      final left = (w - ow) / 2;
      final top = (h - oh) / 2;

      return IgnorePointer(
        child: Stack(
          children: [
            Positioned.fill(
              child: ColorFiltered(
                colorFilter: ColorFilter.mode(
                  Colors.black.withOpacity(0.5),
                  BlendMode.srcOut,
                ),
                child: Stack(
                  children: [
                    Container(
                      decoration: const BoxDecoration(
                        color: Colors.black,
                        backgroundBlendMode: BlendMode.dstOut,
                      ),
                    ),
                    Positioned(
                      left: left,
                      top: top,
                      width: ow,
                      height: oh,
                      child: Container(
                        decoration: BoxDecoration(
                          color: Colors.white,
                          borderRadius: BorderRadius.circular(8),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned(
              left: left,
              top: top,
              width: ow,
              height: oh,
              child: Container(
                decoration: BoxDecoration(
                  border: Border.all(color: Colors.greenAccent, width: 2),
                  borderRadius: BorderRadius.circular(8),
                ),
              ),
            ),
            Positioned(
              top: top - 40,
              left: 0,
              right: 0,
              child: const Text(
                "Align document within frame",
                textAlign: TextAlign.center,
                style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.w500, shadows: [Shadow(blurRadius: 2, color: Colors.black)]),
              ),
            )
          ],
        ),
      );
    });
  }
}
