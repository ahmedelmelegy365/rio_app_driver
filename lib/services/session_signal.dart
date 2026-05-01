// lib/services/session_signal.dart
//
// A tiny global signal that fires whenever the driver's session is
// invalidated server-side (HTTP 401). The auth interceptor in api_service.dart
// bumps this notifier; GoRouter listens to it via `refreshListenable`, sees
// the cleared token, and kicks the user to /login.
//
// Kept as a plain ValueNotifier (not a Riverpod provider) because the
// interceptor lives outside the widget tree and shouldn't depend on a Ref.

import 'package:flutter/foundation.dart';

/// Increments whenever the API returns 401 (other than the login endpoint).
/// The exact value is meaningless — only the change is observed.
final ValueNotifier<int> sessionSignal = ValueNotifier<int>(0);

/// Marks the session as expired. Safe to call from any isolate / async
/// context. Idempotent if called multiple times in quick succession; the
/// router redirect debounces naturally because the second tick re-runs the
/// same redirect and ends up on /login again.
void notifySessionExpired() {
  sessionSignal.value++;
}
