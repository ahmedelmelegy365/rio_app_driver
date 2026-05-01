// lib/services/location_service.dart

import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';

class LocationService {
  static final LocationService instance = LocationService._();
  LocationService._();

  final _db = FirebaseFirestore.instance;
  StreamSubscription<Position>? _positionSub;
  Timer?  _mockTimer;
  Timer?  _fallbackTimer;
  String? _currentFirebaseKey;
  int     _currentDriverId = 0;
  bool    _receivedRealGps  = false;

  // ── Alexandria bounding box ───────────────────────────────
  // The bus only operates in Alexandria. Any position outside
  // this box (e.g. Cairo from the emulator default) is rejected.
  static bool _isValidPosition(double lat, double lng) {
    return lat >= 30.8 && lat <= 31.6 &&
           lng >= 29.4 && lng <= 30.6;
  }

  // ── Start broadcasting ────────────────────────────────────

  Future<void> startTracking({
    required String firebaseKey,
    required int driverId,
    required int tripId,
  }) async {
    await stopTracking();

    _currentFirebaseKey = firebaseKey;
    _currentDriverId    = driverId;
    _receivedRealGps    = false;

    debugPrint('📍 startTracking: key=$firebaseKey driverId=$driverId tripId=$tripId');

    // Request permission
    LocationPermission perm = await Geolocator.checkPermission();
    if (perm == LocationPermission.denied) {
      perm = await Geolocator.requestPermission();
      if (perm == LocationPermission.denied) {
        throw Exception('Location permission denied');
      }
    }
    if (perm == LocationPermission.deniedForever) {
      throw Exception('Location permission permanently denied');
    }

    String _extractDriverId(String key) {
      final match = RegExp(r'driver_(\d+)').firstMatch(key);
      return match?.group(1) ?? '0';
    }

    // Write initial Firestore document
    await _db.collection('trips').doc(firebaseKey).set({
      'trip_id':    tripId.toString(),
      'driver_id':  _extractDriverId(firebaseKey),
      'status':     'active',
      'start_time': FieldValue.serverTimestamp(),
      'end_time':   null,
      'lat':        0.0,
      'lng':        0.0,
      'heading':    0.0,
    });

    debugPrint('✅ Firestore doc created: trips/$firebaseKey');

    final serviceEnabled = await Geolocator.isLocationServiceEnabled();

    if (serviceEnabled) {
      _positionSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy:       LocationAccuracy.high,
          distanceFilter: 15, // update every 15 metres — smooth enough, battery-friendly
        ),
      ).listen(
        (pos) {
          final lat = pos.latitude;
          final lng = pos.longitude;

          // Reject positions outside Alexandria (emulator emits Cairo by default)
          if (!_isValidPosition(lat, lng)) {
            debugPrint('⚠️ GPS outside Alexandria ($lat, $lng) — ignored');
            return;
          }

          _receivedRealGps = true;

          // Stop mock if it somehow started
          if (_mockTimer != null) {
            debugPrint('✅ Valid GPS received — stopping mock');
            _mockTimer?.cancel();
            _mockTimer = null;
          }

          debugPrint('📍 GPS valid: lat=$lat lng=$lng');
          _db.collection('trips').doc(firebaseKey).update({
            'lat':        lat,
            'lng':        lng,
            'heading':    pos.heading,
            'updated_at': FieldValue.serverTimestamp(),
          });
        },
        onError: (e) {
          debugPrint('❌ GPS stream error: $e');
          if (!_receivedRealGps) _startMockTracking(firebaseKey);
        },
      );

      // Only fall back to mock if NO real GPS arrives within 8 seconds
      _fallbackTimer = Timer(const Duration(seconds: 8), () {
        _fallbackTimer = null;
        if (!_receivedRealGps && _mockTimer == null) {
          debugPrint('⚠️ No GPS after 8s — falling back to mock');
          _startMockTracking(firebaseKey);
        } else if (_receivedRealGps) {
          debugPrint('✅ Real GPS confirmed — no mock needed');
        }
      });
    } else {
      debugPrint('⚠️ Location service disabled — using mock');
      _startMockTracking(firebaseKey);
    }
  }

  // ── Mock tracking (emulator with no adb geo fix running) ─────────────────
  // Uses Rio Club area as starting point (not Cairo)

  void _startMockTracking(String firebaseKey) {
    if (_mockTimer != null) return;
    debugPrint('🤖 Mock tracking started (Alexandria/Rio Club area)');

    // Start near Rio Club — moves slowly south-west toward Stop 16
    double lat = 31.2050;
    double lng = 30.0980;

    _mockTimer = Timer.periodic(const Duration(seconds: 3), (_) {
      if (_currentFirebaseKey == null) return;
      lat -= 0.0003;  // heading south-west toward stop 16
      lng -= 0.0005;
      debugPrint('🤖 Mock GPS: lat=$lat lng=$lng');
      _db.collection('trips').doc(firebaseKey).update({
        'lat':        lat,
        'lng':        lng,
        'heading':    225.0,  // south-west
        'updated_at': FieldValue.serverTimestamp(),
      });
    });
  }

  // ── Stop broadcasting ─────────────────────────────────────

  Future<void> stopTracking() async {
    _fallbackTimer?.cancel();
    _fallbackTimer = null;

    await _positionSub?.cancel();
    _positionSub = null;

    _mockTimer?.cancel();
    _mockTimer = null;

    _receivedRealGps = false;

    if (_currentFirebaseKey != null) {
      debugPrint('🛑 stopTracking: $_currentFirebaseKey');
      await _db.collection('trips').doc(_currentFirebaseKey).update({
        'status':   'completed',
        'end_time': FieldValue.serverTimestamp(),
        'lat':      0.0,
        'lng':      0.0,
      });
      _currentFirebaseKey = null;
      _currentDriverId    = 0;
    }
  }

  bool    get isTracking         => _positionSub != null || _mockTimer != null;
  String? get currentFirebaseKey => _currentFirebaseKey;
  int     get currentDriverId    => _currentDriverId;
}
