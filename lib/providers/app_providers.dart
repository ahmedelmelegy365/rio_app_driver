// lib/providers/app_providers.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../models/driver_models.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../services/location_service.dart';

// ── Auth ──────────────────────────────────────────────────────────────────────

final isLoggedInProvider = FutureProvider<bool>((ref) {
  return ApiService.instance.isLoggedIn();
});

final currentDriverProvider = StateProvider<DriverModel?>((ref) => null);

// ── All trips today (for self-assign tab) ─────────────────────────────────────

final allTripsProvider = FutureProvider<List<AllTripItem>>((ref) {
  return ApiService.instance.fetchAllTrips();
});

// ── My assigned trips (active + completed tab) ────────────────────────────────

final tripsProvider = FutureProvider<List<TripAssignment>>((ref) {
  return ApiService.instance.myTrips();
});

// ── Buses ─────────────────────────────────────────────────────────────────────

final busesProvider = FutureProvider<List<BusModel>>((ref) {
  return ApiService.instance.fetchBuses();
});

// ── Active trip ───────────────────────────────────────────────────────────────

class ActiveTripState {
  final TripAssignment? assignment;
  final String? firebaseKey;
  final bool isLoading;
  final String? error;

  const ActiveTripState({
    this.assignment,
    this.firebaseKey,
    this.isLoading = false,
    this.error,
  });

  bool get hasActiveTrip => assignment != null && firebaseKey != null;

  ActiveTripState copyWith({
    TripAssignment? assignment,
    String? firebaseKey,
    bool? isLoading,
    String? error,
    bool clearError = false,
    bool clearTrip  = false,
  }) =>
      ActiveTripState(
        assignment:  clearTrip   ? null : assignment  ?? this.assignment,
        firebaseKey: clearTrip   ? null : firebaseKey ?? this.firebaseKey,
        isLoading:   isLoading   ?? this.isLoading,
        error:       clearError  ? null : error ?? this.error,
      );
}

class ActiveTripNotifier extends StateNotifier<ActiveTripState> {
  final Ref _ref;
  ActiveTripNotifier(this._ref) : super(const ActiveTripState());

  Future<bool> startTrip(TripAssignment assignment) async {
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final driver = _ref.read(currentDriverProvider);
      final key = await ApiService.instance.startTrip(assignment.assignmentId);

      await LocationService.instance.startTracking(
        firebaseKey: key,
        driverId:    driver?.id ?? 0,
        tripId:      assignment.tripId,
      );

      state = state.copyWith(
        isLoading:   false,
        assignment:  assignment,
        firebaseKey: key,
      );

      // Refresh both lists
      _ref.invalidate(allTripsProvider);
      _ref.invalidate(tripsProvider);
      return true;
    } catch (e) {
      state = state.copyWith(isLoading: false, error: formatApiError(e));
      return false;
    }
  }

  /// Ends the active trip.
  /// Returns [LinkedTripInfo] when a locked to_club trip is waiting
  /// (transition screen should be shown). Returns null on normal end.
  /// Returns null (with error set) on failure.
  Future<LinkedTripInfo?> endTrip() async {
    if (state.assignment == null) return null;
    final endedTripId = state.assignment!.tripId;
    state = state.copyWith(isLoading: true, clearError: true);
    try {
      final linked = await ApiService.instance.endTrip(state.assignment!.assignmentId);
      await LocationService.instance.stopTracking();
      state = const ActiveTripState();

      // Reset extension chain state — the backend has already completed the
      // descendants in lock-step inside end(), so any UI cache must clear.
      _ref.read(activeExtendedChildrenProvider.notifier).state = [];
      _ref.invalidate(extensionOptionsProvider(endedTripId));

      // Refresh both lists
      _ref.invalidate(allTripsProvider);
      _ref.invalidate(tripsProvider);
      return linked; // null = normal end, non-null = show transition screen
    } catch (e) {
      state = state.copyWith(isLoading: false, error: formatApiError(e));
      return null;
    }
  }

  void setActiveTrip({
    required TripAssignment assignment,
    required String firebaseKey,
  }) {
    state = ActiveTripState(
      assignment:  assignment,
      firebaseKey: firebaseKey,
      isLoading:   false,
    );
    _ref.invalidate(allTripsProvider);
    _ref.invalidate(tripsProvider);
  }


}


final activeTripProvider =
StateNotifierProvider<ActiveTripNotifier, ActiveTripState>(
      (ref) => ActiveTripNotifier(ref),
);

/// Per-stop passenger counts for the active trip.
/// Auto-refreshed every 30s by ActiveTripScreen via ref.invalidate().
final tripStopCountsProvider =
    FutureProvider.family<List<TripStopCount>, int>((ref, tripId) async {
  return ApiService.instance.fetchTripStopCounts(tripId);
});

/// Trips this driver may extend the active trip into. Empty list when
/// none configured / all activated. Invalidate after a successful extend.
final extensionOptionsProvider =
    FutureProvider.family<List<ExtensionOption>, int>((ref, tripId) async {
  return ApiService.instance.fetchExtensionOptions(tripId);
});

/// Trips the driver has activated as extensions of the current active trip
/// (chain children). Used by the active trip screen to render linked-line
/// summaries beneath the source trip.
///
/// Seeded on app resume by [extensionChainProvider] (below) so the strip
/// repopulates after a cold start mid-chain.
final activeExtendedChildrenProvider =
    StateProvider<List<ExtensionOption>>((ref) => []);

/// One-shot fetch of the active extension descendants for a chain root.
/// Used by the active trip screen on mount to seed the children list when
/// the driver reopens the app while a chain is still running.
final extensionChainProvider =
    FutureProvider.family<List<ExtensionOption>, int>((ref, tripId) async {
  return ApiService.instance.fetchExtensionChain(tripId);
});

/// Per-line stop counts for the whole extension chain. Used by the active
/// trip screen to render grouped stop list across all lines.
final chainStopCountsProvider =
    FutureProvider.family<List<ChainLineStops>, int>((ref, tripId) async {
  return ApiService.instance.fetchChainStopCounts(tripId);
});