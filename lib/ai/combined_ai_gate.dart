import 'dart:io';
import 'package:image/image.dart' as img;
import 'package:tflite_flutter/tflite_flutter.dart';

const String kBlurModelPath   = 'assets/models/blur_detector_v2.tflite';
const String kScreenModelPath = 'assets/models/screen_detector_efficientb0.tflite';

const double kBlurLowThreshold  = 0.0;
const double kBlurHighThreshold = 0.0;
const double kScreenThreshold = 1.0;


enum AiVerdict { valid, blurInvalid, blurBorderline, screenInvalid, notReady, decodeFail, error }

class AiResult {
  final AiVerdict verdict;
  final String message;
  final double blurScore;
  final double screenScore;

  const AiResult({
    required this.verdict,
    required this.message,
    required this.blurScore,
    required this.screenScore,
  });
}

class CombinedAiGate {
  CombinedAiGate._();
  static final CombinedAiGate instance = CombinedAiGate._();

  Interpreter? _blur;
  Interpreter? _screen;
  Future<void>? _initFuture;

  bool get ready => _blur != null && _screen != null;

  Future<void> init() {
    _initFuture ??= _load();
    return _initFuture!;
  }

  Future<void> _load() async {
    _blur = await Interpreter.fromAsset(kBlurModelPath);
    _screen = await Interpreter.fromAsset(kScreenModelPath);
  }

  List<double> _rgbFromPixel(img.Pixel p) => [p.r.toDouble(), p.g.toDouble(), p.b.toDouble()];

  Future<AiResult> check(File imageFile) async {
    try {
      if (!ready) {
        await init();
      }
      if (!ready) {
        return const AiResult(
          verdict: AiVerdict.notReady,
          message: "AI models not loaded.",
          blurScore: 0.0,
          screenScore: 0.0,
        );
      }

      final bytes = await imageFile.readAsBytes();
      final img.Image? original = img.decodeImage(bytes);
      if (original == null) {
        return const AiResult(
          verdict: AiVerdict.decodeFail,
          message: "Could not decode image. Retake.",
          blurScore: 0.0,
          screenScore: 0.0,
        );
      }

      final blurInputTensor = _blur!.getInputTensor(0);
      final blurShape = blurInputTensor.shape;
      final blurH = blurShape[1];
      final blurW = blurShape[2];

      final img.Image blurImg = img.copyResize(original, width: blurW, height: blurH);

      final blurInput = List.generate(
        1,
            (_) => List.generate(
          blurH,
              (y) => List.generate(
            blurW,
                (x) {
              final pixel = blurImg.getPixel(x, y);
              final rgb = _rgbFromPixel(pixel);
              return [rgb[0], rgb[1], rgb[2]];
            },
          ),
        ),
      );

      final blurOutputTensor = _blur!.getOutputTensor(0);
      final blurOutputShape = blurOutputTensor.shape;

      dynamic blurOutput;
      if (blurOutputShape.length == 2 && blurOutputShape[1] == 1) {
        blurOutput = List.generate(1, (_) => List.filled(1, 0.0));
      } else if (blurOutputShape.length == 2 && blurOutputShape[1] >= 2) {
        blurOutput = List.generate(1, (_) => List.filled(blurOutputShape[1], 0.0));
      } else {
        blurOutput = List.generate(1, (_) => List.filled(1, 0.0));
      }

      _blur!.run(blurInput, blurOutput);

      double blurScore;
      if (blurOutputShape.length == 2 && blurOutputShape[1] == 1) {
        blurScore = (blurOutput[0][0] as num).toDouble();
      } else if (blurOutputShape.length == 2 && blurOutputShape[1] >= 2) {
        final probs = (blurOutput[0] as List).map((e) => (e as num).toDouble()).toList();
        blurScore = probs.length > 1 ? probs[1] : probs[0];
      } else {
        blurScore = 0.0;
      }

      if (blurScore <= kBlurLowThreshold) {
        return AiResult(
          verdict: AiVerdict.blurInvalid,
          message: "Photo is too blurry. Retake.\n(blur=${blurScore.toStringAsFixed(4)})",
          blurScore: blurScore,
          screenScore: 0.0,
        );
      }

      if (blurScore < kBlurHighThreshold) {
        return AiResult(
          verdict: AiVerdict.blurBorderline,
          message: "Photo is borderline blurry. Retake.\n(blur=${blurScore.toStringAsFixed(4)})",
          blurScore: blurScore,
          screenScore: 0.0,
        );
      }

      final screenInputTensor = _screen!.getInputTensor(0);
      final screenShape = screenInputTensor.shape;
      final screenH = screenShape[1];
      final screenW = screenShape[2];

      final img.Image screenImg = img.copyResize(original, width: screenW, height: screenH);

      final screenInput = List.generate(
        1,
            (_) => List.generate(
          screenH,
              (y) => List.generate(
            screenW,
                (x) {
              final px = screenImg.getPixel(x, y);
              final rgb = _rgbFromPixel(px);
              return [rgb[0], rgb[1], rgb[2]];
            },
          ),
        ),
      );

      final screenOutputTensor = _screen!.getOutputTensor(0);
      final screenOutputShape = screenOutputTensor.shape;

      dynamic screenOutput;
      if (screenOutputShape.length == 2 && screenOutputShape[1] == 1) {
        screenOutput = List.generate(1, (_) => List.filled(1, 0.0));
      } else if (screenOutputShape.length == 2 && screenOutputShape[1] >= 2) {
        screenOutput = List.generate(1, (_) => List.filled(screenOutputShape[1], 0.0));
      } else {
        screenOutput = List.generate(1, (_) => List.filled(1, 0.0));
      }

      _screen!.run(screenInput, screenOutput);

      double screenProb;
      if (screenOutputShape.length == 2 && screenOutputShape[1] == 1) {
        final realProb = (screenOutput[0][0] as num).toDouble();
        screenProb = 1.0 - realProb;
      } else if (screenOutputShape.length == 2 && screenOutputShape[1] >= 2) {
        final probs = (screenOutput[0] as List).map((e) => (e as num).toDouble()).toList();
        screenProb = probs.length >= 2 ? probs[1] : 0.0;
      } else {
        screenProb = 0.0;
      }

      if (screenProb >= kScreenThreshold) {
        return AiResult(
          verdict: AiVerdict.screenInvalid,
          message: "Screen-captured photo detected. Retake.\n(screen=${screenProb.toStringAsFixed(4)})",
          blurScore: blurScore,
          screenScore: screenProb,
        );
      }

      return AiResult(
        verdict: AiVerdict.valid,
        message: "VALID",
        blurScore: blurScore,
        screenScore: screenProb,
      );
    } catch (_) {
      return const AiResult(
        verdict: AiVerdict.error,
        message: "AI check failed. Retake.",
        blurScore: 0.0,
        screenScore: 0.0,
      );
    }
  }
}
