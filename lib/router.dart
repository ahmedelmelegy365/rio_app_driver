// lib/router.dart

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'models/driver_models.dart';
import 'screens/login_screen.dart';
import 'screens/trips_screen.dart';
import 'screens/trip_detail_screen.dart';
import 'screens/active_trip_screen.dart';
import 'screens/transition_screen.dart';
import 'services/api_service.dart';
import 'services/session_signal.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/trips',
    debugLogDiagnostics: false,
    // When the auth interceptor sees a 401 it bumps `sessionSignal`, which
    // re-runs this redirect. By that point the token has been cleared, so
    // `isLoggedIn()` returns false and the driver is sent to /login.
    refreshListenable: sessionSignal,
    redirect: (context, state) async {
      final loggedIn = await ApiService.instance.isLoggedIn();
      final onLogin  = state.matchedLocation == '/login';
      if (!loggedIn && !onLogin) return '/login';
      if (loggedIn  &&  onLogin) return '/trips';
      return null;
    },
    routes: [
      GoRoute(
        path: '/login',
        builder: (_, __) => const LoginScreen(),
      ),
      GoRoute(
        path: '/trips',
        builder: (_, __) => const TripsScreen(),
      ),
      GoRoute(
        path: '/trip-detail',
        builder: (_, state) => TripDetailScreen(
          trip: state.extra as TripAssignment,
        ),
      ),
      GoRoute(
        path: '/active-trip',
        builder: (_, __) => const ActiveTripScreen(),
      ),
      GoRoute(
        path: '/transition-trip',
        builder: (_, state) => TransitionScreen(
          linkedTrip: state.extra as LinkedTripInfo,
        ),
      ),
    ],
  );
});