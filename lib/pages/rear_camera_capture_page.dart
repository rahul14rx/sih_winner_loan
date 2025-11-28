import 'package:camera/camera.dart';
import 'package:flutter/material.dart';

class RearCameraCapturePage extends StatefulWidget {
  const RearCameraCapturePage({super.key});

  @override
  State<RearCameraCapturePage> createState() => _RearCameraCapturePageState();
}

class _RearCameraCapturePageState extends State<RearCameraCapturePage> {
  CameraController? _c;
  bool _busy = true;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      final cams = await availableCameras();
      final back = cams.firstWhere(
            (e) => e.lensDirection == CameraLensDirection.back,
        orElse: () => cams.first,
      );

      final c = CameraController(
        back,
        ResolutionPreset.high,
        enableAudio: false,
        imageFormatGroup: ImageFormatGroup.jpeg,
      );

      await c.initialize();
      if (!mounted) return;
      setState(() {
        _c = c;
        _busy = false;
      });
    } catch (_) {
      if (!mounted) return;
      Navigator.pop(context, null);
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  Future<void> _shot() async {
    if (_c == null || !_c!.value.isInitialized) return;
    if (_c!.value.isTakingPicture) return;

    try {
      final x = await _c!.takePicture();
      if (!mounted) return;
      Navigator.pop(context, x.path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: SafeArea(
        child: _busy || _c == null
            ? const Center(child: CircularProgressIndicator())
            : Stack(
          children: [
            Positioned.fill(child: CameraPreview(_c!)),
            Positioned(
              top: 12,
              left: 12,
              child: IconButton(
                onPressed: () => Navigator.pop(context, null),
                icon: const Icon(Icons.close, color: Colors.white),
              ),
            ),
            Positioned(
              bottom: 28,
              left: 0,
              right: 0,
              child: Center(
                child: GestureDetector(
                  onTap: _shot,
                  child: Container(
                    width: 72,
                    height: 72,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(color: Colors.white, width: 5),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
