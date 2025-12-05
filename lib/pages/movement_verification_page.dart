import 'dart:async';
import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:flutter_vision/flutter_vision.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart';

import 'package:loan2/models/process_step.dart';

class MovementVerificationPage extends StatefulWidget {
  final String loanId;
  final String userId;
  final ProcessStep step;

  const MovementVerificationPage({
    super.key,
    required this.loanId,
    required this.userId,
    required this.step,
  });

  @override
  State<MovementVerificationPage> createState() =>
      _MovementVerificationPageState();
}

class _MovementVerificationPageState extends State<MovementVerificationPage> {
  CameraController? _controller;
  late FlutterVision _vision;
  StreamSubscription? _sensorSubscription;

  // TTS
  late FlutterTts _flutterTts;
  bool _isMuted = false;

  // Camera / model state
  bool _isCameraInitialized = false;
  bool _isDetecting = false;

  // YOLO detections
  List<Map<String, dynamic>> _yoloResults = [];

  // Object lock / AR state
  bool _objectLocked = false;
  String _lockedLabel = "";
  double _lockedObjectArea = 0.0;
  bool _targetVisible = true;
  int _lossCounter = 0;
  bool _wrongDirectionWarning = false;

  // Scan progress state
  double _scanProgress = 0.0; // 0–100
  bool _isPaused = false;
  Timer? _pauseTimer;

  // Recording state
  bool _isRecording = false;
  String? _lastVideoPath;

  // Test/game state
  bool _isTestComplete = false;
  int _currentIndex = 0;

  // Language state
  String _selectedLanguageCode = 'en';

  final List<String> _allInstructions = [
    "Move Left",
    "Move Right",
    "Move Straight",
    "Move Back",
    "Move Around",
  ];
  List<String> _currentSessionInstructions = [];

  // 🌐 Translations (merged from your old screen + new strings)
  final Map<String, Map<String, String>> _translations = {
    'en': {
      'name': 'English',

      // Movement
      'Move Left': 'Move Left',
      'Move Right': 'Move Right',
      'Move Straight': 'Move Straight',
      'Move Back': 'Move Back',
      'Move Around': 'Move Around',

      // Status / UI
      'STAY STILL': 'STAY STILL',
      'Please stay still': 'Please stay still',
      'Please check the instruction': 'Please check the instruction',
      'AR SCANNER': 'AR SCANNER',
      'Scanning...': 'Scanning...',
      'Scan Complete': 'Scan Complete',
      'Scan Again': 'Scan Again',
      'WRONG DIRECTION': 'WRONG DIRECTION',
      'Point at an object': 'Point at an object',
      'LOCK ON': 'LOCK ON',
      'SCAN NEW OBJECT': 'SCAN NEW OBJECT',
      'Looking for objects...': 'Looking for objects...',
      'Coverage': 'Coverage',
      'LOST TARGET': 'LOST TARGET',
      'Show object to continue': 'Show object to continue',
      'Target Lost. Show object to continue':
      'Target Lost. Show object to continue',
      'Video Saved': 'Video Saved',
    },
    'hi': {
      'name': 'हिंदी (Hindi)',

      'Move Left': 'बाएं चलें',
      'Move Right': 'दाएं चलें',
      'Move Straight': 'सीधे चलें',
      'Move Back': 'पीछे चलें',
      'Move Around': 'घूमें',

      'STAY STILL': 'स्थिर रहें',
      'Please stay still': 'कृपया स्थिर रहें',
      'Please check the instruction': 'कृपया निर्देश जांचें',
      'AR SCANNER': 'एआर स्कैनर',
      'Scanning...': 'स्कैनिंग...',
      'Scan Complete': 'स्कैन पूर्ण',
      'Scan Again': 'फिर से स्कैन करें',
      'WRONG DIRECTION': 'गलत दिशा',
      'Point at an object': 'वस्तु की ओर देखें',
      'LOCK ON': 'लॉक करें',
      'SCAN NEW OBJECT': 'नई वस्तु स्कैन करें',
      'Looking for objects...': 'वस्तुएं खोज रहा है...',
      'Coverage': 'कवरेज',
      'LOST TARGET': 'लक्ष्य खो गया',
      'Show object to continue': 'जारी रखने के लिए वस्तु दिखाएं',
      'Target Lost. Show object to continue':
      'लक्ष्य खो गया। जारी रखने के लिए वस्तु दिखाएं',
      'Video Saved': 'वीडियो सहेजा गया',
    },
    'ta': {
      'name': 'தமிழ் (Tamil)',
      'Move Left': 'இடதுபுறம் நகர்த்தவும்',
      'Move Right': 'வலதுபுறம் நகர்த்தவும்',
      'Move Straight': 'நேராக நகர்த்தவும்',
      'Move Back': 'பின்னால் நகர்த்தவும்',
      'Move Around': 'சுற்றி நகர்த்தவும்',
      'STAY STILL': 'அசையாமல் இருங்கள்',
      'Please stay still': 'தயவுசெய்து அசையாமல் இருக்கவும்',
      'Please check the instruction': 'வழிமுறையை சரிபார்க்கவும்',
      'AR SCANNER': 'ஏஆர் ஸ்கேனர்',
      'Scanning...': 'ஸ்கேன் செய்கிறது...',
      'Scan Complete': 'ஸ்கேன் முடிந்தது',
      'Scan Again': 'மீண்டும் ஸ்கேன் செய்யவும்',
      'WRONG DIRECTION': 'தவறான திசை',
      'Point at an object': 'ஒரு பொருளை நோக்கி பிடிக்கவும்',
      'LOCK ON': 'பொருளை பூட்டு',
      'SCAN NEW OBJECT': 'புதிய பொருள் ஸ்கேன்',
      'Looking for objects...': 'பொருள்களைத் தேடுகிறது...',
      'Coverage': 'கவரேஜ்',
      'LOST TARGET': 'இலக்கு தொலைந்தது',
      'Show object to continue': 'தொடர பொருளைக் காட்டவும்',
      'Target Lost. Show object to continue':
      'இலக்கு தொலைந்தது, தொடர பொருளைக் காட்டவும்',
      'Video Saved': 'வீடியோ சேமிக்கப்பட்டது',
    },
    'ml': {
      'name': 'മലയാളം (Malayalam)',
      'Move Left': 'ഇടത്തോട്ട് നീക്കുക',
      'Move Right': 'വലത്തോട്ട് നീക്കുക',
      'Move Straight': 'നേരെ നീക്കുക',
      'Move Back': 'പിന്നിലേക്ക് നീക്കുക',
      'Move Around': 'ചുറ്റും നീക്കുക',
      'STAY STILL': 'അനങ്ങാതെ നിൽക്കുക',
      'Please stay still': 'ദയവായി അനങ്ങാതെ നിൽക്കുക',
      'Please check the instruction': 'നിർദ്ദേശം പരിശോധിക്കുക',
      'AR SCANNER': 'എആർ സ്കാനർ',
      'Scanning...': 'സ്കാൻ ചെയ്യുന്നു...',
      'Scan Complete': 'സ്കാൻ പൂർത്തിയായി',
      'Scan Again': 'വീണ്ടും സ്‌കാൻ ചെയ്യുക',
      'WRONG DIRECTION': 'തെറ്റായ ദിശ',
      'Point at an object': 'ഒരു വസ്തുവിലേക്ക് നോക്കുക',
      'LOCK ON': 'ലോക്ക് ചെയ്യുക',
      'SCAN NEW OBJECT': 'പുതിയ വസ്തു സ്കാൻ ചെയ്യുക',
      'Looking for objects...': 'വസ്തുക്കൾ അന്വേഷിക്കുന്നു...',
      'Coverage': 'മൂടൽവിസ്താരം',
      'LOST TARGET': 'ലക്ഷ്യം നഷ്ടമായി',
      'Show object to continue': 'തുടരാൻ വസ്തു കാണിക്കുക',
      'Target Lost. Show object to continue':
      'ലക്ഷ്യം നഷ്ടപ്പെട്ടു. തുടരാൻ വസ്തു കാണിക്കുക',
      'Video Saved': 'വീഡിയോ സേവ് ചെയ്തു',
    },
    'te': {
      'name': 'తెలుగు (Telugu)',
      'Move Left': 'ఎడమ వైపుకు కదలండి',
      'Move Right': 'కుడి వైపుకు కదలండి',
      'Move Straight': 'నేరుగా కదలండి',
      'Move Back': 'వెనక్కి కదలండి',
      'Move Around': 'చుట్టూ కదలండి',
      'STAY STILL': 'కదలకుండా ఉండండి',
      'Please stay still': 'దయచేసి కదలకుండా ఉండండి',
      'Please check the instruction': 'సూచనను తనిఖీ చేయండి',
      'AR SCANNER': 'ఏఆర్ స్కానర్',
      'Scanning...': 'స్కానింగ్...',
      'Scan Complete': 'స్కాన్ పూర్తయింది',
      'Scan Again': 'మళ్ళీ స్కాన్ చేయండి',
      'WRONG DIRECTION': 'తప్పు దిశ',
      'Point at an object': 'వస్తువు వైపు చూపించండి',
      'LOCK ON': 'లాక్ చేయండి',
      'SCAN NEW OBJECT': 'కొత్త వస్తువు స్కాన్ చేయండి',
      'Looking for objects...': 'వస్తువులను వెతుకుతోంది...',
      'Coverage': 'కవరేజ్',
      'LOST TARGET': 'లక్ష్యం కోల్పోయారు',
      'Show object to continue': 'కొనసాగడానికి వస్తువును చూపించండి',
      'Target Lost. Show object to continue':
      'లక్ష్యం కోల్పోయారు. కొనసాగడానికి వస్తువును చూపించండి',
      'Video Saved': 'వీడియో సేవ్ చేయబడింది',
    },
  };

  @override
  void initState() {
    super.initState();
    _initCameraAndYolo();
    _initTts();
  }

  Future<void> _initCameraAndYolo() async {
    await Permission.camera.request();
    await Permission.microphone.request(); // for video audio

    _vision = FlutterVision();
    await _vision.loadYoloModel(
      modelPath: 'assets/yolov8n.tflite',
      labels: 'assets/labels.txt',
      modelVersion: "yolov8",
      quantization: true,
      numThreads: 2,
      useGpu: false,
    );

    // Pick back camera if available
    final cameras = await availableCameras();
    CameraDescription camera = cameras.first;
    for (final c in cameras) {
      if (c.lensDirection == CameraLensDirection.back) {
        camera = c;
        break;
      }
    }

    _controller = CameraController(
      camera,
      ResolutionPreset.high,
      enableAudio: true,
    );

    await _controller!.initialize();

    // Start image stream for YOLO
    await _controller!.startImageStream((image) {
      if (!_isDetecting) {
        _isDetecting = true;
        _runInference(image);
      }
    });

    // Gyroscope based movement tracking
    _sensorSubscription = gyroscopeEventStream().listen((GyroscopeEvent event) {
      if (_isPaused || !_objectLocked || _isTestComplete) return;
      if (_scanProgress >= 100 || !_targetVisible) return;

      String currentInstr = _currentSessionInstructions[_currentIndex];

      double validMovement = 0.0;
      bool isWrongDirection = false;
      double xAbs = event.x.abs();
      double yAbs = event.y.abs();

      // Horizontal left/right vs up/down style
      if (currentInstr.contains("Left") || currentInstr.contains("Right")) {
        if (xAbs > yAbs && xAbs > 0.3) {
          isWrongDirection = true;
        } else {
          validMovement = yAbs;
        }
      } else {
        validMovement = xAbs + yAbs;
      }

      if (isWrongDirection) {
        if (!_wrongDirectionWarning) {
          setState(() => _wrongDirectionWarning = true);
        }
        return;
      } else {
        if (_wrongDirectionWarning) {
          setState(() => _wrongDirectionWarning = false);
        }
      }

      if (validMovement > 0.2) {
        double baseIncrement = 0.15;
        double sizeMultiplier = 1.0;

        if (_lockedObjectArea < 0.15) {
          sizeMultiplier = 1.5;
        } else if (_lockedObjectArea > 0.5) {
          sizeMultiplier = 0.8;
        } else {
          sizeMultiplier = 1.5 + ((_lockedObjectArea - 0.15) * -2.0);
        }

        double increment = validMovement * baseIncrement * sizeMultiplier;
        double nextProgress = _scanProgress + increment;

        int currentStep = (_scanProgress / 25).floor();
        int nextStep = (nextProgress / 25).floor();

        if (nextStep > currentStep && nextStep < 4) {
          _triggerPauseSequence(nextStep);
        } else {
          setState(() {
            _scanProgress = nextProgress;
            if (_scanProgress >= 100) {
              _finishScan(); // ✅ This will pop with video.path
            }
          });
        }
      }
    });

    if (mounted) {
      setState(() {
        _isCameraInitialized = true;
      });
    }
  }

  void _triggerPauseSequence(int nextStepIndex) {
    setState(() {
      _isPaused = true;
      _wrongDirectionWarning = false;
      _scanProgress = (nextStepIndex * 25).toDouble();
    });

    _speak("Please stay still");

    _pauseTimer?.cancel();
    _pauseTimer = Timer(const Duration(seconds: 2), () {
      if (!mounted) return;
      setState(() {
        _isPaused = false;
        _currentIndex = nextStepIndex;
      });
      _speak(_currentSessionInstructions[_currentIndex]);
    });
  }

  Future<void> _initTts() async {
    _flutterTts = FlutterTts();
    await _flutterTts.setLanguage("en-US");
    await _flutterTts.setPitch(1.0);
    await _flutterTts.setSpeechRate(0.5);
    await _flutterTts.awaitSpeakCompletion(true);
  }

  Future<void> _speak(String text) async {
    if (_isMuted) return;

    String ttsLang = 'en-US';
    if (_selectedLanguageCode == 'hi') ttsLang = 'hi-IN';
    if (_selectedLanguageCode == 'ta') ttsLang = 'ta-IN';
    if (_selectedLanguageCode == 'ml') ttsLang = 'ml-IN';
    if (_selectedLanguageCode == 'te') ttsLang = 'te-IN';

    await _flutterTts.setLanguage(ttsLang);
    await _flutterTts.stop();
    await _flutterTts.speak(_t(text));
  }

  void _repeatInstruction() {
    if (_objectLocked && _scanProgress < 100) {
      if (_isPaused) {
        _speak("Please stay still");
      } else {
        _speak(_currentSessionInstructions[_currentIndex]);
      }
    } else if (_objectLocked && _scanProgress >= 100) {
      _speak("Scan Complete");
    }
  }

  String _t(String key) {
    Map<String, String> langMap =
        _translations[_selectedLanguageCode] ?? _translations['en']!;
    return langMap[key] ?? key;
  }

  Future<void> _runInference(CameraImage image) async {
    final result = await _vision.yoloOnFrame(
      bytesList: image.planes.map((plane) => plane.bytes).toList(),
      imageHeight: image.height,
      imageWidth: image.width,
      iouThreshold: 0.4,
      confThreshold: 0.2,
      classThreshold: 0.5,
    );

    if (!mounted) return;

    setState(() {
      _yoloResults = result;
      _isDetecting = false;

      if (_objectLocked) {
        // keep tracking locked label
        var match = result.firstWhere(
              (r) => r['tag'] == _lockedLabel,
          orElse: () => <String, dynamic>{},
        );

        if (match.isNotEmpty) {
          _lossCounter = 0;
          if (!_targetVisible) {
            _targetVisible = true;
          }
          final box = match["box"];
          double w = box[2] - box[0];
          double h = box[3] - box[1];
          _lockedObjectArea = (w * h).abs();
        } else {
          _lossCounter++;
          if (_lossCounter > 5) {
            if (_targetVisible) {
              _targetVisible = false;
              _speak("Target Lost. Show object to continue");
            }
          }
        }
      }
    });
  }

  Future<void> _lockOnTarget() async {
    if (_yoloResults.isEmpty || _controller == null) return;

    var list = List<String>.from(_allInstructions)..shuffle();
    final box = _yoloResults.first["box"];
    double w = box[2] - box[0];
    double h = box[3] - box[1];
    double initialArea = (w * h).abs();

    setState(() {
      _objectLocked = true;
      _lockedLabel = _yoloResults.first['tag'];
      _lockedObjectArea = initialArea;
      _scanProgress = 0;
      _currentIndex = 0;
      _currentSessionInstructions = list.take(4).toList();
      _isTestComplete = false;
      _targetVisible = true;
      _lossCounter = 0;
      _isPaused = false;
      _wrongDirectionWarning = false;
      _isRecording = true;
    });

    // Start recording video
    try {
      if (!_controller!.value.isRecordingVideo) {
        await _controller!.startVideoRecording();
      }
      _speak(_currentSessionInstructions[0]);
    } catch (e) {
      debugPrint("Error starting recording: $e");
    }
  }

  Future<void> _finishScan() async {
    if (_isTestComplete) return;

    XFile? video;
    try {
      if (_controller != null && _controller!.value.isRecordingVideo) {
        video = await _controller!.stopVideoRecording();
      }
    } catch (e) {
      debugPrint("Error stopping recording: $e");
    }

    setState(() {
      _isTestComplete = true;
      _wrongDirectionWarning = false;
      _isRecording = false;
      _lastVideoPath = video?.path;
    });

    _speak("Scan Complete");

    // ✅ For your flow: return to previous screen with video path
    if (mounted && video != null) {
      Navigator.pop(context, video.path);
    }
  }

  void _resetForNewObject() {
    _pauseTimer?.cancel();
    setState(() {
      _objectLocked = false;
      _scanProgress = 0;
      _isTestComplete = false;
      _isPaused = false;
      _wrongDirectionWarning = false;
      _isRecording = false;
      _lastVideoPath = null;
    });
  }

  void _showLanguageSelector() {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (context) {
        return BackdropFilter(
          filter: ImageFilter.blur(sigmaX: 10, sigmaY: 10),
          child: Container(
            decoration: BoxDecoration(
              color: Colors.black.withOpacity(0.85),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
              border: Border.all(color: Colors.white24),
            ),
            padding: const EdgeInsets.symmetric(vertical: 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(
                    color: Colors.white38,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
                const Text(
                  "SELECT LANGUAGE",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 14,
                    letterSpacing: 1.5,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 20),
                ..._translations.keys.map((code) {
                  bool isSelected = _selectedLanguageCode == code;
                  return ListTile(
                    onTap: () {
                      setState(() {
                        _selectedLanguageCode = code;
                      });
                      Navigator.pop(context);
                    },
                    leading: isSelected
                        ? const Icon(Icons.check_circle, color: Colors.white)
                        : const Icon(Icons.circle_outlined,
                        color: Colors.white38),
                    title: Text(
                      _translations[code]!['name']!,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.white70,
                        fontWeight:
                        isSelected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 18,
                      ),
                    ),
                  );
                }),
                const SizedBox(height: 20),
              ],
            ),
          ),
        );
      },
    );
  }

  @override
  void dispose() {
    _sensorSubscription?.cancel();
    _pauseTimer?.cancel();
    _flutterTts.stop();
    _vision.closeYoloModel();
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraInitialized ||
        _controller == null ||
        !_controller!.value.isInitialized) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _controller!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    String currentLangName = _translations[_selectedLanguageCode]?['name']
        ?.split('(')
        .first
        .trim() ??
        "English";

    String currentInstruction;
    Color statusColor = Colors.white;

    if (_objectLocked) {
      if (_isTestComplete) {
        currentInstruction = "Scan Complete";
        statusColor = Colors.greenAccent;
      } else if (!_targetVisible) {
        currentInstruction = "LOST TARGET";
        statusColor = Colors.redAccent;
      } else if (_isPaused) {
        currentInstruction = "STAY STILL";
        statusColor = Colors.amber;
      } else if (_wrongDirectionWarning) {
        currentInstruction = "WRONG DIRECTION";
        statusColor = Colors.deepOrange;
      } else {
        currentInstruction = _currentSessionInstructions[_currentIndex];
        statusColor = Colors.white;
      }
    } else {
      currentInstruction = "Point at an object";
    }

    return Scaffold(
      body: Stack(
        fit: StackFit.expand,
        children: [
          // Camera preview
          Transform.scale(
            scale: scale,
            child: Center(
              child: CameraPreview(_controller!),
            ),
          ),

          // Object boxes (hidden while recording)
          if (!_isRecording) ..._displayBoundingBoxes(_yoloResults),

          SafeArea(
            child: Column(
              children: [
                // Top bar
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _showLanguageSelector,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                            color: Colors.black45,
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(color: Colors.white24),
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.language,
                                  color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                currentLangName,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 14,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down,
                                  color: Colors.white70, size: 16),
                            ],
                          ),
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Row(
                          children: [
                            if (_isRecording)
                              const Padding(
                                padding: EdgeInsets.only(right: 6.0),
                                child: Icon(Icons.circle,
                                    color: Colors.redAccent, size: 12),
                              ),
                            Text(
                              _t("AR SCANNER"),
                              style: const TextStyle(
                                color: Colors.white,
                                fontSize: 12,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        onPressed: () {
                          setState(() => _isMuted = !_isMuted);
                          if (!_isMuted && _objectLocked && !_isTestComplete) {
                            _repeatInstruction();
                          }
                        },
                        icon: Icon(
                          _isMuted ? Icons.volume_off : Icons.volume_up,
                          color: Colors.white,
                          size: 28,
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                // Bottom AR card
                Container(
                  width: double.infinity,
                  margin: const EdgeInsets.all(20),
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: Colors.black.withOpacity(0.85),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor, width: 2),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      SizedBox(
                        height: 150,
                        width: 300,
                        child: ARPhoneAnimation(
                          instruction:
                          _objectLocked ? currentInstruction : "STAY STILL",
                        ),
                      ),
                      const SizedBox(height: 20),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Flexible(
                            child: Text(
                              _t(currentInstruction),
                              textAlign: TextAlign.center,
                              style: TextStyle(
                                color: statusColor,
                                fontSize: 22,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          if (_objectLocked &&
                              !_isTestComplete &&
                              _targetVisible)
                            IconButton(
                              icon: const Icon(Icons.replay,
                                  color: Colors.cyanAccent),
                              onPressed: _repeatInstruction,
                            ),
                        ],
                      ),

                      if (_wrongDirectionWarning)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _t("Please check the instruction"),
                            style: const TextStyle(
                              color: Colors.orangeAccent,
                              fontSize: 12,
                            ),
                          ),
                        ),

                      if (_objectLocked && !_targetVisible)
                        Padding(
                          padding: const EdgeInsets.only(top: 8.0),
                          child: Text(
                            _t("Show object to continue"),
                            style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                            ),
                          ),
                        ),

                      const SizedBox(height: 20),

                      if (_objectLocked) ...[
                        LinearProgressIndicator(
                          value: _scanProgress / 100,
                          backgroundColor: Colors.white10,
                          color: statusColor == Colors.white
                              ? Colors.cyanAccent
                              : statusColor,
                          minHeight: 8,
                        ),
                        const SizedBox(height: 10),
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              "${_scanProgress.toStringAsFixed(0)}% ${_t('Coverage')}",
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                            ),
                          ],
                        ),

                        if (_scanProgress >= 100)
                          Padding(
                            padding: const EdgeInsets.only(top: 15.0),
                            child: ElevatedButton(
                              onPressed: _resetForNewObject,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: Colors.white,
                              ),
                              child: Text(
                                _t("SCAN NEW OBJECT"),
                                style: const TextStyle(color: Colors.black),
                              ),
                            ),
                          ),
                      ] else ...[
                        if (_yoloResults.isNotEmpty)
                          ElevatedButton(
                            onPressed: _lockOnTarget,
                            style: ElevatedButton.styleFrom(
                              backgroundColor: Colors.cyanAccent,
                              padding: const EdgeInsets.symmetric(
                                  horizontal: 40, vertical: 15),
                            ),
                            child: Text(
                              "${_t('LOCK ON')} ${_yoloResults.first['tag'].toUpperCase()}",
                              style: const TextStyle(
                                color: Colors.black,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          )
                        else
                          Text(
                            _t("Looking for objects..."),
                            style: const TextStyle(
                              color: Colors.white54,
                              fontSize: 14,
                            ),
                          ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _displayBoundingBoxes(List<Map<String, dynamic>> results) {
    if (results.isEmpty) return [];

    final Size screenSize = MediaQuery.of(context).size;
    double factorX = screenSize.width;
    double factorY = screenSize.height;

    return results.map((result) {
      final box = result["box"];
      double left = box[0] * factorX;
      double top = box[1] * factorY;
      double width = (box[2] - box[0]) * factorX;
      double height = (box[3] - box[1]) * factorY;

      if (_objectLocked && result['tag'] != _lockedLabel) {
        return const SizedBox.shrink();
      }

      Color boxColor = _objectLocked
          ? (_targetVisible
          ? (_wrongDirectionWarning
          ? Colors.deepOrange
          : (_isPaused ? Colors.amber : Colors.greenAccent))
          : Colors.redAccent)
          : Colors.cyanAccent;

      return Positioned(
        left: left,
        top: top,
        width: width,
        height: height,
        child: Container(
          decoration: BoxDecoration(
            border: Border.all(color: boxColor, width: 3),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Align(
            alignment: Alignment.topCenter,
            child: Container(
              color: boxColor,
              padding:
              const EdgeInsets.symmetric(horizontal: 4, vertical: 2),
              child: Text(
                "${result['tag']} ${(result['box'][4] * 100).toStringAsFixed(0)}%",
                style: const TextStyle(
                  color: Colors.black,
                  fontSize: 10,
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ),
        ),
      );
    }).toList();
  }
}

// === AR Phone Animation (from YOLO version, adapted) ===

class ARPhoneAnimation extends StatefulWidget {
  final String instruction;
  const ARPhoneAnimation({super.key, required this.instruction});

  @override
  State<ARPhoneAnimation> createState() => _ARPhoneAnimationState();
}

class _ARPhoneAnimationState extends State<ARPhoneAnimation>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      duration: const Duration(milliseconds: 2000),
      vsync: this,
    )..repeat(reverse: true);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return CustomPaint(
          painter: PhonePainter(
            progress: _controller.value,
            instruction: widget.instruction,
          ),
          size: const Size(300, 200),
        );
      },
    );
  }
}

class PhonePainter extends CustomPainter {
  final double progress;
  final String instruction;

  PhonePainter({required this.progress, required this.instruction});

  @override
  void paint(Canvas canvas, Size size) {
    final Paint paint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 3.0
      ..strokeCap = StrokeCap.round;

    final double cx = size.width / 2;
    final double cy = size.height / 2;
    const double phoneW = 50.0;
    const double phoneH = 90.0;

    double dx = 0;
    double dy = 0;
    double scale = 1.0;
    double rotation = 0.0;
    final double t = sin(progress * pi);

    if (instruction.contains("Left")) {
      dx = -50.0 * t;
      rotation = -0.1 * t;
    } else if (instruction.contains("Right")) {
      dx = 50.0 * t;
      rotation = 0.1 * t;
    } else if (instruction.contains("Straight") ||
        instruction.contains("Front")) {
      dy = -30.0 * t;
      scale = 1.0 + (0.4 * t);
    } else if (instruction.contains("Back")) {
      dy = 30.0 * t;
      scale = 1.0 - (0.3 * t);
    } else if (instruction.contains("Around")) {
      dx = 40.0 * cos(progress * 2 * pi);
      dy = 15.0 * sin(progress * 2 * pi);
    } else if (instruction.contains("LOST")) {
      dx = 10.0 * sin(progress * 4 * pi);
      paint.color = Colors.redAccent;
    } else if (instruction.contains("WRONG")) {
      dx = 15.0 * sin(progress * 8 * pi);
      paint.color = Colors.deepOrange;
    } else if (instruction.contains("STAY")) {
      scale = 1.0;
      paint.color = Colors.amber;
    } else {
      scale = 1.0 + (0.05 * t);
    }

    canvas.save();
    canvas.translate(cx + dx, cy + dy);
    canvas.rotate(rotation);
    canvas.scale(scale);

    final RRect phoneBody = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: phoneW, height: phoneH),
      const Radius.circular(8),
    );
    canvas.drawRRect(phoneBody, paint);

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant PhonePainter oldDelegate) {
    return oldDelegate.progress != progress ||
        oldDelegate.instruction != instruction;
  }
}
