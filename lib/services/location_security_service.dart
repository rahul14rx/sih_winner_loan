import 'dart:async';
import 'package:geolocator/geolocator.dart';

class LocationSecurityResult {
  final double confidence; // 0 - 100
  final bool isMocked;
  final String reason;

  const LocationSecurityResult({
    required this.confidence,
    required this.isMocked,
    required this.reason,
  });
}

class LocationSecurityService {
  bool _started = false;

  Future<void> start() async {
    _started = true;
    await _ensurePermission();
  }

  void stop() {
    _started = false;
  }

  Future<LocationSecurityResult> evaluate(Position p) async {
    if (!_started) {
      return const LocationSecurityResult(
        confidence: 0,
        isMocked: false,
        reason: "Location security not started",
      );
    }

    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) {
      return const LocationSecurityResult(
        confidence: 0,
        isMocked: false,
        reason: "Location services OFF",
      );
    }

    final perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied || perm == LocationPermission.deniedForever) {
      return const LocationSecurityResult(
        confidence: 0,
        isMocked: false,
        reason: "Location permission denied",
      );
    }

    // Some geolocator versions/platforms may not expose isMocked everywhere.
    bool mocked = false;
    try {
      mocked = (p as dynamic).isMocked == true;
    } catch (_) {
      mocked = false;
    }

    if (mocked) {
      return const LocationSecurityResult(
        confidence: 0,
        isMocked: true,
        reason: "Mock location detected",
      );
    }

    final acc = p.accuracy; // meters
    double conf;
    if (acc <= 10) conf = 95;
    else if (acc <= 25) conf = 85;
    else if (acc <= 50) conf = 70;
    else conf = 55;

    return LocationSecurityResult(
      confidence: conf,
      isMocked: false,
      reason: "OK (accuracy ${acc.toStringAsFixed(1)}m)",
    );
  }

  Future<void> _ensurePermission() async {
    final enabled = await Geolocator.isLocationServiceEnabled();
    if (!enabled) return;

    var perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
    }
  }
}
