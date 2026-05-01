// lib/services/api_service.dart

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import '../models/driver_models.dart';
import 'location_service.dart';
import 'session_signal.dart';

// const _baseUrl = 'http://192.168.141.1:82/rio_club_app_api/api'; // local dev
const _baseUrl = 'http://riosclub.com/rio_club_app_api/api'; // production

class ApiService {
  static final ApiService instance = ApiService._();
  ApiService._();

  final _storage = const FlutterSecureStorage();
  late final Dio _dio = Dio(BaseOptions(
    baseUrl: _baseUrl,
    connectTimeout: const Duration(seconds: 15),
    receiveTimeout: const Duration(seconds: 15),
    headers: {'Accept': 'application/json', 'Content-Type': 'application/json'},
  ))..interceptors.add(_AuthInterceptor(_storage));

  // ── Auth ──────────────────────────────────────────────────

  Future<({String token, DriverModel driver})> login(
      String username, String password) async {
    final res = await _dio.post(
      '/driver/login',
      data: {'username': username, 'password': password},
    );
    final data = res.data;
    if (data['success'] == true) {
      final token  = data['data']['access_token'] as String;
      final driver = DriverModel.fromJson(
          data['data']['driver'] as Map<String, dynamic>);

      // Always write fresh — clear first to avoid any stale token
      await _storage.delete(key: 'driver_token');
      await _storage.write(key: 'driver_token', value: token);

      debugPrint('✅ driver_token stored: ${token.substring(0, 20)}...');
      return (token: token, driver: driver);
    }
    throw Exception(data['message'] ?? 'Login failed');
  }

  Future<void> logout() async {
    await _storage.delete(key: 'driver_token');
    debugPrint('🔑 driver_token cleared');
  }

  Future<bool> isLoggedIn() async {
    final token = await _storage.read(key: 'driver_token');
    debugPrint('🔍 isLoggedIn check: ${token != null ? 'YES' : 'NO'}');
    return token != null && token.isNotEmpty;
  }

  // ── Buses ─────────────────────────────────────────────────

  /// GET /api/shuttle/driver/buses
  Future<List<BusModel>> fetchBuses() async {
    final res  = await _dio.get('/shuttle/driver/buses');
    final data = res.data;
    if (data['success'] == true) {
      return (data['data'] as List)
          .map((e) => BusModel.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(data['message'] ?? 'Failed to load buses');
  }

  // ── All trips today ───────────────────────────────────────

  /// GET /api/shuttle/driver/driver-all-trips
  Future<List<AllTripItem>> fetchAllTrips() async {
    final res  = await _dio.get('/shuttle/driver/driver-all-trips');
    final data = res.data;
    if (data['success'] == true) {
      return (data['data'] as List)
          .map((e) => AllTripItem.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(data['message'] ?? 'Failed to load trips');
  }

  // ── My trips ─────────────────────────────────────────────

  /// GET /api/shuttle/driver/driver-my-trips
  Future<List<TripAssignment>> myTrips() async {
    final res  = await _dio.get('/shuttle/driver/driver-my-trips');
    final data = res.data;
    if (data['success'] == true) {
      return (data['data'] as List)
          .map((e) => TripAssignment.fromJson(e as Map<String, dynamic>))
          .toList();
    }
    throw Exception(data['message'] ?? 'Failed to load my trips');
  }

  // ── Self-assign ───────────────────────────────────────────

  /// POST /api/shuttle/driver/driver-trips-assignment
  Future<({int assignmentId, String busPlate})> selfAssign({
    required int tripId,
    required int busId,
  }) async {
    final res = await _dio.post(
      '/shuttle/driver/driver-trips-assignment',
      data: {'trip_id': tripId, 'bus_id': busId},
    );
    final data = res.data;
    if (data['success'] == true) {
      return (
      assignmentId: data['data']['assignment_id'] as int,
      busPlate:     data['data']['bus_plate'] as String,
      );
    }
    throw Exception(data['message'] ?? 'Failed to assign trip');
  }

  Future<({int assignmentId, String firebaseKey, String busPlate})> selfAssignAndStart({
    required int tripId,
    required int busId,
  }) async {
    final res = await _dio.post(
      '/shuttle/driver/driver-trips-assignment-and-start',
      data: {'trip_id': tripId, 'bus_id': busId},
    );
    final data = res.data;
    if (data['success'] == true) {
      return (
      assignmentId: data['data']['assignment_id'] as int,
      firebaseKey:  data['data']['firebase_trip_key'] as String,
      busPlate:     data['data']['bus_plate'] as String,
      );
    }
    throw Exception(data['message'] ?? 'Failed');
  }

  Future<TripAssignment?> fetchActiveAssignment() async {
    final res  = await _dio.get('/shuttle/driver/active-assignment');
    final data = res.data;
    if (data['success'] == true && data['data'] != null) {
      return TripAssignment.fromJson(data['data'] as Map<String, dynamic>);
    }
    return null;
  }
  // ── Start trip ────────────────────────────────────────────

  /// POST /api/shuttle/driver/assignments/{id}/start
  Future<String> startTrip(int assignmentId) async {
    final res  = await _dio.post(
        '/shuttle/driver/assignments/$assignmentId/start');
    final data = res.data;
    if (data['success'] == true) {
      return data['data']['firebase_trip_key'] as String;
    }
    throw Exception(data['message'] ?? 'Failed to start trip');
  }

  // ── End trip ──────────────────────────────────────────────

  /// POST /api/shuttle/driver/assignments/{id}/end
  /// Returns [LinkedTripInfo] when a locked to_club trip is waiting
  /// for the driver (transition screen). Returns null otherwise.
  Future<LinkedTripInfo?> endTrip(int assignmentId) async {
    final res  = await _dio.post('/shuttle/driver/assignments/$assignmentId/end');
    final data = res.data;
    if (data['success'] != true) {
      throw Exception(data['message'] ?? 'Failed to end trip');
    }
    final lt = data['data']?['linked_trip'];
    if (lt != null && lt is Map<String, dynamic> && lt['show_transition'] == true) {
      return LinkedTripInfo.fromJson(lt);
    }
    return null;
  }

  // ── Start linked (to_club) trip ───────────────────────────

  /// POST /api/shuttle/driver/assignments/{id}/start-linked
  /// Called from the transition screen after the driver ends from_club.
  Future<String> startLinkedTrip(int assignmentId) async {
    final res  = await _dio.post('/shuttle/driver/assignments/$assignmentId/start-linked');
    final data = res.data;
    if (data['success'] == true) {
      return data['data']['firebase_trip_key'] as String;
    }
    throw Exception(data['message'] ?? 'Failed to start linked trip');
  }

  // ── Trip stop counts ──────────────────────────────────────

  /// GET /api/shuttle/driver/trips/{tripId}/stop-counts
  Future<List<TripStopCount>> fetchTripStopCounts(int tripId) async {
    try {
      final res  = await _dio.get('/shuttle/driver/trips/$tripId/stop-counts');
      final data = res.data;
      if (data is Map && data['success'] == true) {
        return (data['data'] as List)
            .map((e) => TripStopCount.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ fetchTripStopCounts: $e');
      return [];
    }
  }

  // ── Extension chain (parallel multi-line activation) ──────

  /// GET /api/shuttle/driver/trips/{tripId}/extension-options
  /// Returns same-day trips this driver can extend the active trip into.
  /// Empty list when none are configured or all already activated/taken.
  Future<List<ExtensionOption>> fetchExtensionOptions(int tripId) async {
    try {
      final res  = await _dio.get('/shuttle/driver/trips/$tripId/extension-options');
      final data = res.data;
      if (data is Map && data['success'] == true) {
        return (data['data'] as List)
            .map((e) => ExtensionOption.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ fetchExtensionOptions: $e');
      return [];
    }
  }

  /// POST /api/shuttle/driver/trips/{sourceTripId}/extend
  /// Activates target_trip_id as an extension of an already-active source
  /// trip. Both trips become 'active' simultaneously, sharing the source's
  /// firebase_trip_key — no extra GPS streams to start in this app.
  Future<Map<String, dynamic>> extendTrip({
    required int sourceTripId,
    required int targetTripId,
  }) async {
    final res  = await _dio.post(
      '/shuttle/driver/trips/$sourceTripId/extend',
      data: {'target_trip_id': targetTripId},
    );
    final data = res.data;
    if (data is Map && data['success'] == true) {
      return Map<String, dynamic>.from(data['data'] as Map);
    }
    throw Exception(data is Map ? (data['message'] ?? 'Failed to extend trip') : 'Failed to extend trip');
  }

  /// GET /api/shuttle/driver/trips/{tripId}/extension-chain
  /// Returns the active extension descendants of a chain root. Empty list
  /// when the trip has no extensions or all have already completed.
  /// Used on app resume to seed the linked-extension strip.
  Future<List<ExtensionOption>> fetchExtensionChain(int tripId) async {
    try {
      final res  = await _dio.get('/shuttle/driver/trips/$tripId/extension-chain');
      final data = res.data;
      if (data is Map && data['success'] == true) {
        return (data['data'] as List)
            .map((e) => ExtensionOption.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ fetchExtensionChain: $e');
      return [];
    }
  }

  /// GET /api/shuttle/driver/trips/{tripId}/chain-stop-counts
  /// Per-stop passenger counts AGGREGATED across the chain root + all of
  /// its extension descendants. Returned as a list of line groups with
  /// stops and counts inside each.
  Future<List<ChainLineStops>> fetchChainStopCounts(int tripId) async {
    try {
      final res  = await _dio.get('/shuttle/driver/trips/$tripId/chain-stop-counts');
      final data = res.data;
      if (data is Map && data['success'] == true) {
        return (data['data'] as List)
            .map((e) => ChainLineStops.fromJson(e as Map<String, dynamic>))
            .toList();
      }
      return [];
    } catch (e) {
      debugPrint('⚠️ fetchChainStopCounts: $e');
      return [];
    }
  }
}

// ── Auth interceptor ──────────────────────────────────────────────────────────

class _AuthInterceptor extends Interceptor {
  final FlutterSecureStorage _storage;
  _AuthInterceptor(this._storage);

  @override
  void onRequest(
      RequestOptions options, RequestInterceptorHandler handler) async {
    final token = await _storage.read(key: 'driver_token');
    if (token != null && token.isNotEmpty) {
      options.headers['Authorization'] = 'Bearer $token';
      debugPrint('🔑 --> ${options.method} ${options.path} [token: ${token.substring(0, 15)}...]');
    } else {
      debugPrint('⚠️  --> ${options.method} ${options.path} [NO TOKEN]');
    }
    handler.next(options);
  }

  @override
  void onResponse(Response response, ResponseInterceptorHandler handler) {
    debugPrint('✅ <-- ${response.statusCode} ${response.requestOptions.path}');
    handler.next(response);
  }

  @override
  void onError(DioException err, ErrorInterceptorHandler handler) async {
    debugPrint('❌ ERROR ${err.response?.statusCode} ${err.requestOptions.path}');
    if (err.response?.data != null) {
      debugPrint('   ${err.response?.data}');
    }

    // Session expired — clear the stored token, stop GPS tracking, and
    // notify the router so it redirects to /login. The login endpoint also
    // returns 401 for wrong credentials, so we skip it here to avoid
    // logging out a user who isn't logged in yet.
    final isLoginAttempt = err.requestOptions.path.contains('/driver/login');
    if (err.response?.statusCode == 401 && !isLoginAttempt) {
      try {
        await _storage.delete(key: 'driver_token');
      } catch (_) { /* best-effort cleanup */ }
      try {
        await LocationService.instance.stopTracking();
      } catch (_) { /* GPS may not be running */ }
      debugPrint('🚪 Session expired — redirecting to /login');
      notifySessionExpired();
    }

    handler.next(err);
  }


}