
// lib/location_security_service.dart
import 'dart:async';
import 'dart:math';
import 'package:flutter/services.dart';
import 'package:geolocator/geolocator.dart';
import 'package:sensors_plus/sensors_plus.dart';
import 'package:permission_handler/permission_handler.dart';

class LocationSecurityResult {
final double confidence; // 0..100
final bool isMocked;
final bool developerMode;
final int satelliteCount;
final double avgSnr;
final String reason; // short explanation

LocationSecurityResult({
required this.confidence,
required this.isMocked,
required this.developerMode,
required this.satelliteCount,
required this.avgSnr,
required this.reason,
});
}

class LocationSecurityService {
// platform channel name must match MainActivity
static const MethodChannel _channel =
MethodChannel('com.example.geosec/gnss');

// sensor streams
StreamSubscription<AccelerometerEvent>? _accelSub;
StreamSubscription<GyroscopeEvent>? _gyroSub;
StreamSubscription<MagnetometerEvent>? _magSub;

// history buffers
final List<double> _accelMagHistory = [];
final List<double> _gpsAccuracyHistory = [];
final List<Position> _gpsHistory = [];

// config
final int accelWindow = 20; // last N samples
final int gpsWindow = 8; // last N gps samples for drift & jumps
final double maxAccelNoiseWhenStill = 0.5; // m/s^2 threshold for "still"
final double suspiciousJumpSpeed = 50.0; // m/s -> extremely high
final double minSatCountRecommended = 4.0;
final double minAvgSnrRecommended = 20.0;

LocationSecurityService();

// start sensors
Future<void> start() async {
// request sensors permission if needed (not always required)
await _ensurePermissions();

_accelSub ??= accelerometerEvents.listen((AccelerometerEvent e) {
final mag = sqrt(e.x * e.x + e.y * e.y + e.z * e.z);
_accelMagHistory.add(mag);
if (_accelMagHistory.length > accelWindow) _accelMagHistory.removeAt(0);
});

_gyroSub ??= gyroscopeEvents.listen((GyroscopeEvent e) {
// could be used for rotation checks — not used directly in this simple version
});

_magSub ??= magnetometerEvents.listen((MagnetometerEvent e) {
// could be used for compass verifications
});
}

Future<void> stop() async {
await _accelSub?.cancel();
await _gyroSub?.cancel();
await _magSub?.cancel();
_accelSub = null;
_gyroSub = null;
_magSub = null;
}

Future<void> _ensurePermissions() async {
// location permission handled when calling fetch; sensors usually don't need permission
if (!await Permission.location.isGranted) {
await Permission.location.request();
}
}

// call this whenever you fetch a new GPS Position (so engine can check history)
void registerGps(Position pos) {
_gpsHistory.add(pos);
_gpsAccuracyHistory.add(pos.accuracy);
if (_gpsHistory.length > gpsWindow) _gpsHistory.removeAt(0);
if (_gpsAccuracyHistory.length > gpsWindow) _gpsAccuracyHistory.removeAt(0);
}

// helper distance calc (meters)
double _haversine(Position a, Position b) {
const R = 6371000.0;
final lat1 = a.latitude * pi / 180;
final lat2 = b.latitude * pi / 180;
final dLat = lat2 - lat1;
final dLon = (b.longitude - a.longitude) * pi / 180;
final hav = sin(dLat / 2) * sin(dLat / 2) +
cos(lat1) * cos(lat2) * sin(dLon / 2) * sin(dLon / 2);
final c = 2 * atan2(sqrt(hav), sqrt(1 - hav));
return R * c;
}

// compute average accel magnitude variance
double _accelStabilityScore() {
if (_accelMagHistory.isEmpty) return 1.0;
// compute standard deviation of accel magnitude
final mean = _accelMagHistory.reduce((a, b) => a + b) / _accelMagHistory.length;
double sumSq = 0;
for (final v in _accelMagHistory) {
sumSq += (v - mean) * (v - mean);
}
final variance = sumSq / _accelMagHistory.length;
final std = sqrt(variance);
// lower std means very still device. we want to detect if GPS shows movement while accel shows stillness.
return std; // raw metric in m/s^2
}

// compute gps movement vs accel movement discrepancy
double _movementDiscrepancyScore() {
if (_gpsHistory.length < 2) return 0.0; // not enough data
// compute gps distance over last two points and compare to accel stability
final a = _gpsHistory[_gpsHistory.length - 2];
final b = _gpsHistory[_gpsHistory.length - 1];
final dt = b.timestamp.millisecondsSinceEpoch - a.timestamp.millisecondsSinceEpoch;
if (dt <= 0) return 0.0;
final distance = _haversine(a, b); // meters
final speed = distance / (dt / 1000.0); // m/s according to GPS
// if speed > 0.5 m/s but accel std is very low -> discrepancy
final accelStd = _accelStabilityScore();
// normalize: bigger discrepancy -> higher score
final desired = speed <= 0.3 ? 0.0 : (speed / 5.0); // scale typical walking speeds
final accelIndicator = (accelStd < maxAccelNoiseWhenStill) ? 1.0 : 0.0;
final score = (desired * accelIndicator).clamp(0.0, 1.0);
return score;
}

// accuracy stability: too-perfect accuracy is suspicious
double _accuracySuspicionScore() {
if (_gpsAccuracyHistory.isEmpty) return 0.0;
// compute variance of accuracy numbers: legit gps has variance
final mean = _gpsAccuracyHistory.reduce((a, b) => a + b) / _gpsAccuracyHistory.length;
double sumSq = 0;
for (final v in _gpsAccuracyHistory) {
sumSq += (v - mean) * (v - mean);
}
final variance = sumSq / _gpsAccuracyHistory.length;
final std = sqrt(variance);
// if std is extremely low and mean is very low -> suspicious (too perfect)
if (std < 0.5 && mean < 5.0) {
return 1.0; // suspicious
}
// small suspicion otherwise
return (0.5 - (std / 10.0)).clamp(0.0, 1.0) * (mean < 5.0 ? 0.8 : 0.0);
}

// check for sudden huge jump (teleport)
double _suddenJumpScore() {
if (_gpsHistory.length < 2) return 0.0;
double maxScore = 0.0;
for (int i = 1; i < _gpsHistory.length; i++) {
final a = _gpsHistory[i - 1];
final b = _gpsHistory[i];
final dt = b.timestamp.millisecondsSinceEpoch - a.timestamp.millisecondsSinceEpoch;
if (dt <= 0) continue;
final dist = _haversine(a, b);
final speed = dist / (dt / 1000.0); // m/s
if (speed > suspiciousJumpSpeed) {
maxScore = 1.0;
} else if (speed > 30.0) {
maxScore = max(maxScore, (speed - 30.0) / 50.0); // scale 30..80 -> 0..1
}
}
return maxScore.clamp(0.0, 1.0);
}

// call platform channel to get satellite & developer mode info
Future<Map<String, dynamic>> _fetchNativeGnss() async {
try {
final res = await _channel.invokeMethod('getSatelliteSummary');
final dev = await _channel.invokeMethod('isDeveloperModeEnabled');
return {
'satCount': res['satCount'] ?? 0,
'avgSnr': res['avgSnr'] ?? 0.0,
'developerMode': dev ?? false,
};
} catch (e) {
// channel not implemented or error -> return defaults
return {'satCount': 0, 'avgSnr': 0.0, 'developerMode': false};
}
}

// final stitched confidence score
Future<LocationSecurityResult> evaluate(Position pos) async {
// 1) basic mock flag if available on Position (Geolocator supports isMocked on Android)
final bool isMocked = pos.isMocked ?? false; // fallback if null

// 2) register to internal history
registerGps(pos);

// 3) compute scores
final accelStd = _accelStabilityScore();
final movementDiscrepancy = _movementDiscrepancyScore();
final accuracySuspicion = _accuracySuspicionScore();
final jumpScore = _suddenJumpScore();

// 4) native GNSS
final gnss = await _fetchNativeGnss();
final int satCount = (gnss['satCount'] ?? 0) as int;
final double avgSnr = (gnss['avgSnr'] ?? 0.0) as double;
final bool devMode = (gnss['developerMode'] ?? false) as bool;

// 5) heuristics combine
double trust = 100.0;

if (isMocked) {
trust -= 80;
}

if (devMode) {
trust -= 30;
}

// movement discrepancy: if significant, reduce trust
trust -= (movementDiscrepancy * 40); // up to -40

// accuracy suspicion
trust -= (accuracySuspicion * 30);

// sudden jump
trust -= (jumpScore * 60);

// satellite checks: fewer satellites + low SNR reduce trust
if (satCount > 0) {
if (satCount < minSatCountRecommended) {
trust -= ((minSatCountRecommended - satCount) / minSatCountRecommended) * 20;
}
if (avgSnr < minAvgSnrRecommended) {
double deficit = (minAvgSnrRecommended - avgSnr) / minAvgSnrRecommended;
trust -= (deficit * 15);
}
} else {
// cannot check satellites -> small penalty (unknown)
trust -= 6;
}

// clamp
if (trust < 0) trust = 0;
if (trust > 100) trust = 100;

// build a readable reason summary
String reason = "";
if (isMocked) reason += "Device reports mock location. ";
if (devMode) reason += "Developer mode enabled. ";
if (movementDiscrepancy > 0.2) reason += "Movement doesn't match sensors. ";
if (accuracySuspicion > 0.5) reason += "Accuracy too perfect (suspicious). ";
if (jumpScore > 0.5) reason += "Sudden teleport-like jump detected. ";
if (satCount > 0 && (satCount < minSatCountRecommended || avgSnr < minAvgSnrRecommended)) {
reason += "Weak/low satellite quality. ";
}
if (reason.isEmpty) reason = "Looks normal";

return LocationSecurityResult(
confidence: trust,
isMocked: isMocked,
developerMode: devMode,
satelliteCount: satCount,
avgSnr: avgSnr,
reason: reason,
);
}
}