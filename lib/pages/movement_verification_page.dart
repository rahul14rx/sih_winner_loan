import 'dart:async';
import 'dart:math';
import 'dart:ui'; // For ImageFilter (Blur effect)
import 'package:flutter/material.dart';
import 'package:camera/camera.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:flutter_tts/flutter_tts.dart'; // IMPORT TTS

List<CameraDescription> _cameras = [];

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  try {
    _cameras = await availableCameras();
  } on CameraException catch (e) {
    print('Error initializing camera: $e');
  }
  runApp(const MovementApp());
}

class MovementApp extends StatelessWidget {
  const MovementApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: ThemeData.dark().copyWith(
        scaffoldBackgroundColor: Colors.black,
        colorScheme: const ColorScheme.dark(
          primary: Colors.white,
          secondary: Colors.white,
        ),
      ),
      home: const MovementScreen(),
    );
  }
}

class MovementScreen extends StatefulWidget {
  const MovementScreen({super.key});

  @override
  State<MovementScreen> createState() => _MovementScreenState();
}

class _MovementScreenState extends State<MovementScreen> {
  CameraController? _controller;
  StreamSubscription? _accelSubscription;
  Timer? _gameLoopTimer;
  Timer? _stopMovingTimer;

  // TTS Engine
  late FlutterTts _flutterTts;
  bool _isMuted = false; // Mute State

  // Game State
  bool _isCameraReady = false;
  bool _isTestActive = false;
  bool _isTestComplete = false;

  bool _isUserMoving = false;
  bool _isWrongDirection = false;
  bool _isResting = false;

  // Language State
  String _selectedLanguageCode = 'en'; // Default English

  final List<String> _allInstructions = [
    "Move Left",
    "Move Right",
    "Move Straight",
    "Move Back",
    "Move Around"
  ];

  final Map<String, Map<String, String>> _translations = {
    'en': {
      'name': 'English',
      'Move Left': 'Move Left',
      'Move Right': 'Move Right',
      'Move Straight': 'Move Straight',
      'Move Back': 'Move Back',
      'Move Around': 'Move Around',
      'STAY STILL': 'STAY STILL',
      'Please stay still': 'Please stay still',
      'AR SCANNER': 'AR SCANNER',
      'Hold device steady': 'Hold device steady',
      'Please stop moving...': 'Please stop moving...',
      'Scanning...': 'Scanning...',
      'Good, keep moving...': 'Good, keep moving...',
      'Move your device to start': 'Move your device to start',
      'Scan Complete': 'Scan Complete',
      'Scan Again': 'Scan Again',
      'Video saved to:': 'Video saved to:',
      'WRONG DIRECTION': 'WRONG DIRECTION',
      'Please check the instruction': 'Please check the instruction',
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
      'AR SCANNER': 'एआर स्कैनर',
      'Hold device steady': 'डिवाइस स्थिर रखें',
      'Please stop moving...': 'कृपया रुकें...',
      'Scanning...': 'स्कैनिंग...',
      'Good, keep moving...': 'अच्छा, चलते रहें...',
      'Move your device to start': 'शुरू करने के लिए हिलाएं',
      'Scan Complete': 'स्कैन पूर्ण',
      'Scan Again': 'फिर से स्कैन करें',
      'Video saved to:': 'वीडियो यहाँ सहेजा गया:',
      'WRONG DIRECTION': 'गलत दिशा',
      'Please check the instruction': 'कृपया निर्देश जांचें',
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
      'AR SCANNER': 'ஏஆர் ஸ்கேனர்',
      'Hold device steady': 'சாதனத்தை நிலையாகப் பிடிக்கவும்',
      'Please stop moving...': 'நகர்வதை நிறுத்துங்கள்...',
      'Scanning...': 'ஸ்கேன் செய்கிறது...',
      'Good, keep moving...': 'நன்று, தொடர்ந்து நகரவும்...',
      'Move your device to start': 'தொடங்க சாதனத்தை நகர்த்தவும்',
      'Scan Complete': 'சிறப்பான ஆள் நீ',
      'Scan Again': 'மீண்டும் ஸ்கேன் செய்யவும்',
      'Video saved to:': 'வீடியோ சேமிக்கப்பட்டது:',
      'WRONG DIRECTION': 'தவறான திசை',
      'Please check the instruction': 'வழிமுறையை சரிபார்க்கவும்',
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
      'AR SCANNER': 'എആർ സ്കാനർ',
      'Hold device steady': 'ഉപകരണം സ്ഥിരമായി പിടിക്കുക',
      'Please stop moving...': 'ദയവായി നീങ്ങുന്നത് നിർത്തുക...',
      'Scanning...': 'സ്കാൻ ചെയ്യുന്നു...',
      'Good, keep moving...': 'കൊള്ളാം, നീങ്ങിക്കൊണ്ടിരിക്കൂ...',
      'Move your device to start': 'ആരംഭിക്കാൻ ഉപകരണം നീക്കുക',
      'Scan Complete': 'സ്കാൻ പൂർത്തിയായി',
      'Scan Again': 'വീണ്ടും സ്کാൻ ചെയ്യുക',
      'Video saved to:': 'വീഡിയോ സേവ് ചെയ്തു:',
      'WRONG DIRECTION': 'തെറ്റായ ദിശ',
      'Please check the instruction': 'നിർദ്ദേശം പരിശോധിക്കുക',
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
      'AR SCANNER': 'ఏఆర్ స్కానర్',
      'Hold device steady': 'పరికరాన్ని స్థిరంగా ఉంచండి',
      'Please stop moving...': 'దయచేసి కదలడం ఆపండి...',
      'Scanning...': 'స్కానింగ్...',
      'Good, keep moving...': 'బాగుంది, కదులుతూ ఉండండి...',
      'Move your device to start': 'ప్రారంభించడానికి కదిలించండి',
      'Scan Complete': 'స్కాన్ పూర్తయింది',
      'Scan Again': 'మళ్ళీ స్కాన్ చేయండి',
      'Video saved to:': 'వీడియో సేవ్ చేయబడింది:',
      'WRONG DIRECTION': 'తప్పు దిశ',
      'Please check the instruction': 'సూచనను తనిఖీ చేయండి',
    },
  };

  List<String> _currentSessionInstructions = [];
  int _currentIndex = 0;
  double _currentDuration = 0.0;

  // --- FINAL TUNED THRESHOLDS ---
  final double _requiredDuration = 3.0;
  final double _requiredRestDuration = 2.0;

  // 1. Easy to start moving (Low Threshold)
  final double _validMoveThreshold = 1.0;

  // 2. Hard to trigger error (High Threshold)
  final double _wrongAxisThreshold = 2.5;

  // Confidence Counter
  double _confidence = 0.0;
  final double _confidenceMax = 100.0;
  final double _confidenceToStart = 15.0;

  @override
  void initState() {
    super.initState();
    _initializeCamera();
    _initTts();
  }

  Future<void> _initializeCamera() async {
    var status = await Permission.camera.request();
    if (status.isGranted && _cameras.isNotEmpty) {
      _controller = CameraController(_cameras[0], ResolutionPreset.medium);
      await _controller!.initialize();
      if (mounted) {
        setState(() {
          _isCameraReady = true;
        });
      }
    }
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

  void _repeatCurrentInstruction() {
    if (!_isTestActive || _isTestComplete) return;

    if (_isResting) {
      _speak("Please stay still");
    } else {
      _speak(_currentSessionInstructions[_currentIndex]);
    }
  }

  String _t(String key) {
    Map<String, String> langMap = _translations[_selectedLanguageCode] ?? _translations['en']!;
    if (langMap.containsKey(key)) return langMap[key]!;
    if (key.startsWith("Video saved to:")) {
      String prefix = langMap["Video saved to:"] ?? "Video saved to:";
      return key.replaceFirst("Video saved to:", prefix);
    }
    return key;
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
                  width: 40, height: 4,
                  margin: const EdgeInsets.only(bottom: 20),
                  decoration: BoxDecoration(color: Colors.white38, borderRadius: BorderRadius.circular(2)),
                ),
                const Text(
                  "SELECT LANGUAGE",
                  style: TextStyle(color: Colors.white, fontSize: 14, letterSpacing: 1.5, fontWeight: FontWeight.bold),
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
                        : const Icon(Icons.circle_outlined, color: Colors.white38),
                    title: Text(
                      _translations[code]!['name']!,
                      style: TextStyle(
                          color: isSelected ? Colors.white : Colors.white70,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          fontSize: 18
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

  Future<void> _startTest() async {
    if (_controller == null || !_controller!.value.isInitialized) return;

    try {
      if (_controller!.value.isRecordingVideo) {
        await _controller!.stopVideoRecording();
      }
      await _controller!.startVideoRecording(onAvailable: null);
    } catch (e) {
      print("Error starting video recording: $e");
      return;
    }

    setState(() {
      _isTestActive = true;
      _isTestComplete = false;
      _isResting = false;
      _currentIndex = 0;
      _currentDuration = 0.0;
      _isUserMoving = false;
      _isWrongDirection = false;
      _confidence = 0.0;

      var list = List<String>.from(_allInstructions)..shuffle();
      _currentSessionInstructions = list.take(4).toList();
    });

    _speak(_currentSessionInstructions[0]);

    _accelSubscription = userAccelerometerEventStream().listen((UserAccelerometerEvent event) {
      if (!_isTestActive || _isTestComplete) return;

      bool validSignal = false;
      bool strongWrongSignal = false;

      if (!_isResting) {
        String instruction = _currentSessionInstructions[_currentIndex];

        if (instruction == "Move Left") {
          if (event.x < -_validMoveThreshold) validSignal = true;
          if (event.z.abs() > _wrongAxisThreshold && event.z.abs() > event.x.abs()) strongWrongSignal = true;
        } else if (instruction == "Move Right") {
          if (event.x > _validMoveThreshold) validSignal = true;
          if (event.z.abs() > _wrongAxisThreshold && event.z.abs() > event.x.abs()) strongWrongSignal = true;
        } else if (instruction == "Move Straight") {
          if (event.z < -_validMoveThreshold || event.y.abs() > _validMoveThreshold) validSignal = true;
          if (event.x.abs() > _wrongAxisThreshold && event.x.abs() > event.z.abs()) strongWrongSignal = true;
        } else if (instruction == "Move Back") {
          if (event.z > _validMoveThreshold) validSignal = true;
          if (event.x.abs() > _wrongAxisThreshold && event.x.abs() > event.z.abs()) strongWrongSignal = true;
        } else if (instruction == "Move Around") {
          double mag = sqrt(event.x*event.x + event.y*event.y + event.z*event.z);
          if (mag > _validMoveThreshold) validSignal = true;
        }
      } else {
        double mag = sqrt(event.x*event.x + event.y*event.y + event.z*event.z);
        if (mag > _validMoveThreshold) strongWrongSignal = true;
      }

      if (strongWrongSignal) {
        _confidence -= 5.0;
      } else if (validSignal) {
        _confidence += 2.0;
      } else {
        _confidence -= 1.0;
      }

      if (_confidence > _confidenceMax) _confidence = _confidenceMax;
      if (_confidence < 0) _confidence = 0;

      bool limitReached = _confidence >= _confidenceToStart;

      if (limitReached) {
        if (_stopMovingTimer?.isActive ?? false) _stopMovingTimer!.cancel();

        if (!_isUserMoving || _isWrongDirection) {
          setState(() {
            _isUserMoving = true;
            _isWrongDirection = false;
          });
        }
      } else {
        if (strongWrongSignal && _confidence < 5) {
          if (!_isWrongDirection) {
            setState(() {
              _isUserMoving = false;
              _isWrongDirection = true;
            });
            _speak("WRONG DIRECTION");
          }
        } else {
          if (_isUserMoving || _isWrongDirection) {
            if (_stopMovingTimer == null || !_stopMovingTimer!.isActive) {
              _stopMovingTimer = Timer(const Duration(milliseconds: 200), () {
                if (mounted && _isTestActive) {
                  setState(() {
                    _isUserMoving = false;
                    _isWrongDirection = false;
                  });
                }
              });
            }
          }
        }
      }
    });

    _gameLoopTimer = Timer.periodic(const Duration(milliseconds: 100), (timer) {
      if (!_isTestActive || _isTestComplete) return;

      if (_isResting) {
        if (!_isUserMoving && !_isWrongDirection) {
          setState(() {
            _currentDuration += 0.1;
          });
          if (_currentDuration >= _requiredRestDuration) {
            _nextInstruction();
          }
        } else {
          setState(() {
            _currentDuration = 0.0;
          });
        }
      } else {
        if (_isUserMoving && !_isWrongDirection) {
          setState(() {
            _currentDuration += 0.1;
          });

          if (_currentDuration >= _requiredDuration) {
            if (_currentIndex < 3) {
              setState(() {
                _isResting = true;
                _currentDuration = 0.0;
                _isWrongDirection = false;
                _confidence = 0.0;
              });
              _speak("Please stay still");
            } else {
              _endTest();
            }
          }
        }
      }
    });
  }

  void _nextInstruction() {
    setState(() {
      _currentIndex++;
      _isResting = false;
      _currentDuration = 0.0;
      _isWrongDirection = false;
      _confidence = 0.0;
    });
    _speak(_currentSessionInstructions[_currentIndex]);
  }

  Future<void> _endTest() async {
    _accelSubscription?.cancel();
    _gameLoopTimer?.cancel();
    _stopMovingTimer?.cancel();

    _speak("Scan Complete");

    XFile? videoFile;
    try {
      if (_controller!.value.isRecordingVideo) {
        videoFile = await _controller!.stopVideoRecording();
      }
    } catch (e) {
      print("Error stopping video recording: $e");
    }

    setState(() {
      _isTestActive = false;
      _isTestComplete = true;
    });

    if (mounted && videoFile != null) {
      Navigator.pop(context, videoFile.path);
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    _accelSubscription?.cancel();
    _gameLoopTimer?.cancel();
    _stopMovingTimer?.cancel();
    _flutterTts.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_isCameraReady || _controller == null || !_controller!.value.isInitialized) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    String currentLangName = _translations[_selectedLanguageCode]?['name']?.split('(').first.trim() ?? "English";

    // Calculate Scale to Cover Screen (FIXED STRETCHING)
    final size = MediaQuery.of(context).size;
    var scale = size.aspectRatio * _controller!.value.aspectRatio;
    if (scale < 1) scale = 1 / scale;

    return Scaffold(
      body: Stack(
        children: [
          // 1. Camera Preview Layer (SCALED TO COVER)
          Transform.scale(
            scale: scale,
            child: Center(
              child: CameraPreview(_controller!),
            ),
          ),

          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.all(16.0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      GestureDetector(
                        onTap: _showLanguageSelector,
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                          decoration: BoxDecoration(
                              color: Colors.black45,
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: Colors.white24),
                              boxShadow: const [BoxShadow(color: Colors.black26, blurRadius: 8)]
                          ),
                          child: Row(
                            children: [
                              const Icon(Icons.language, color: Colors.white, size: 16),
                              const SizedBox(width: 8),
                              Text(
                                currentLangName,
                                style: const TextStyle(color: Colors.white, fontSize: 14, fontWeight: FontWeight.bold),
                              ),
                              const SizedBox(width: 4),
                              const Icon(Icons.keyboard_arrow_down, color: Colors.white70, size: 16),
                            ],
                          ),
                        ),
                      ),

                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                        decoration: BoxDecoration(
                          color: Colors.black26,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          _t("AR SCANNER"),
                          style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                        ),
                      ),

                      IconButton(
                        onPressed: () {
                          setState(() {
                            _isMuted = !_isMuted;
                          });
                          if (!_isMuted) _speak(_isResting ? "Please stay still" : _currentSessionInstructions[_currentIndex]);
                        },
                        icon: Icon(
                            _isMuted ? Icons.volume_off : Icons.volume_up,
                            color: Colors.white,
                            size: 28
                        ),
                      ),
                    ],
                  ),
                ),

                const Spacer(),

                if (_isTestActive) ...[
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        SizedBox(
                          height: 200,
                          width: 300,
                          child: ARPhoneAnimation(
                            instruction: _isResting ? "STAY STILL" : _currentSessionInstructions[_currentIndex],
                          ),
                        ),

                        const SizedBox(height: 40),

                        Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              _isWrongDirection
                                  ? _t("WRONG DIRECTION")
                                  : _t(_isResting ? "Hold device steady" : _currentSessionInstructions[_currentIndex]),
                              style: TextStyle(
                                color: _isWrongDirection ? Colors.redAccent : Colors.white,
                                fontSize: 22,
                                fontWeight: FontWeight.w600,
                                shadows: const [Shadow(color: Colors.black45, blurRadius: 4)],
                              ),
                            ),
                            const SizedBox(width: 10),
                            IconButton(
                              icon: const Icon(Icons.replay, color: Colors.white70),
                              onPressed: _repeatCurrentInstruction,
                              tooltip: "Repeat Instruction",
                            ),
                          ],
                        ),

                        const SizedBox(height: 8),

                        Text(
                          _isWrongDirection
                              ? _t("Please check the instruction")
                              : _t(_isResting
                              ? (_isUserMoving ? "Please stop moving..." : "Scanning...")
                              : (_isUserMoving ? "Good, keep moving..." : "Move your device to start")),
                          style: const TextStyle(color: Colors.white70, fontSize: 14),
                        ),

                        const SizedBox(height: 30),

                        Padding(
                          padding: const EdgeInsets.symmetric(horizontal: 60),
                          child: ClipRRect(
                            borderRadius: BorderRadius.circular(2),
                            child: LinearProgressIndicator(
                              value: _currentDuration / (_isResting ? _requiredRestDuration : _requiredDuration),
                              backgroundColor: Colors.white24,
                              color: _isWrongDirection ? Colors.redAccent : Colors.white,
                              minHeight: 4,
                            ),
                          ),
                        ),

                        const SizedBox(height: 60),
                      ],
                    ),
                  ),
                ],

                if (_isTestComplete)
                  Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.check_circle_outline, color: Colors.white, size: 80),
                        const SizedBox(height: 20),
                        Text(
                          _t("Scan Complete"),
                          style: const TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w300),
                        ),
                        const SizedBox(height: 40),
                        ElevatedButton(
                          onPressed: _startTest,
                          style: ElevatedButton.styleFrom(
                            backgroundColor: Colors.white,
                            foregroundColor: Colors.black,
                            padding: const EdgeInsets.symmetric(horizontal: 40, vertical: 15),
                            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(30)),
                          ),
                          child: Text(_t("Scan Again")),
                        )
                      ],
                    ),
                  ),

                if (!_isTestActive && !_isTestComplete)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 80.0),
                    child: ElevatedButton(
                      onPressed: _startTest,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.white.withOpacity(0.2),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(horizontal: 30, vertical: 20),
                        shape: const CircleBorder(),
                        side: const BorderSide(color: Colors.white, width: 2),
                      ),
                      child: const Icon(Icons.play_arrow, size: 40),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// AR Animation Widget
class ARPhoneAnimation extends StatefulWidget {
  final String instruction;
  const ARPhoneAnimation({super.key, required this.instruction});

  @override
  State<ARPhoneAnimation> createState() => _ARPhoneAnimationState();
}

class _ARPhoneAnimationState extends State<ARPhoneAnimation> with SingleTickerProviderStateMixin {
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

    final Paint arrowPaint = Paint()
      ..color = Colors.white.withOpacity(0.8)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
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

    switch (instruction) {
      case "Move Left":
        dx = -50.0 * t;
        rotation = -0.1 * t;
        _drawArrow(canvas, cx - 50, cy, isLeft: true, opacity: t, paint: arrowPaint);
        break;
      case "Move Right":
        dx = 50.0 * t;
        rotation = 0.1 * t;
        _drawArrow(canvas, cx + 50, cy, isLeft: false, opacity: t, paint: arrowPaint);
        break;
      case "Move Straight":
        dy = -30.0 * t;
        scale = 1.0 + (0.4 * t);
        break;
      case "Move Back":
        dy = 30.0 * t;
        scale = 1.0 - (0.3 * t);
        break;
      case "Move Around":
        dx = 40.0 * cos(progress * 2 * pi);
        dy = 15.0 * sin(progress * 2 * pi);
        rotation = 0.2 * sin(progress * 2 * pi);
        break;
      case "STAY STILL":
        scale = 1.0 + (0.02 * t);
        paint.color = Colors.white.withOpacity(0.8 + (0.2 * t));
        _drawLockCorners(canvas, cx, cy, 70, 110, paint);
        break;
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

    final Paint screenPaint = Paint()
      ..color = Colors.white.withOpacity(0.3)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;

    final RRect screen = RRect.fromRectAndRadius(
      Rect.fromCenter(center: Offset.zero, width: phoneW - 8, height: phoneH - 16),
      const Radius.circular(4),
    );
    canvas.drawRRect(screen, screenPaint);

    canvas.drawCircle(const Offset(0, 38), 3, screenPaint);

    canvas.restore();
  }

  void _drawArrow(Canvas canvas, double x, double y, {required bool isLeft, required double opacity, required Paint paint}) {
    paint.color = Colors.white.withOpacity(opacity);

    final Path path = Path();
    if (isLeft) {
      path.moveTo(x + 10, y - 10);
      path.lineTo(x - 5, y);
      path.lineTo(x + 10, y + 10);
    } else {
      path.moveTo(x - 10, y - 10);
      path.lineTo(x + 5, y);
      path.lineTo(x - 10, y + 10);
    }
    canvas.drawPath(path, paint);
  }

  void _drawLockCorners(Canvas canvas, double cx, double cy, double w, double h, Paint paint) {
    double length = 15;
    double hw = w / 2;
    double hh = h / 2;

    canvas.drawLine(Offset(cx - hw, cy - hh), Offset(cx - hw + length, cy - hh), paint);
    canvas.drawLine(Offset(cx - hw, cy - hh), Offset(cx - hw, cy - hh + length), paint);

    canvas.drawLine(Offset(cx + hw, cy - hh), Offset(cx + hw - length, cy - hh), paint);
    canvas.drawLine(Offset(cx + hw, cy - hh), Offset(cx + hw, cy - hh + length), paint);

    canvas.drawLine(Offset(cx - hw, cy + hh), Offset(cx - hw + length, cy + hh), paint);
    canvas.drawLine(Offset(cx - hw, cy + hh), Offset(cx - hw, cy + hh - length), paint);

    canvas.drawLine(Offset(cx + hw, cy + hh), Offset(cx + hw - length, cy + hh), paint);
    canvas.drawLine(Offset(cx + hw, cy + hh), Offset(cx + hw, cy + hh - length), paint);
  }

  @override
  bool shouldRepaint(covariant PhonePainter oldDelegate) {
    return oldDelegate.progress != progress || oldDelegate.instruction != instruction;
  }
}
