// lib/screens/transition_screen.dart
//
// Shown after the driver ends a from_club trip that has a linked to_club trip.
// The driver must press "ابدأ رحلة العودة" to start the to_club GPS broadcast.

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_colors.dart';
import '../models/driver_models.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../services/location_service.dart';

class TransitionScreen extends ConsumerStatefulWidget {
  final LinkedTripInfo linkedTrip;

  const TransitionScreen({super.key, required this.linkedTrip});

  @override
  ConsumerState<TransitionScreen> createState() => _TransitionScreenState();
}

class _TransitionScreenState extends ConsumerState<TransitionScreen> {
  bool _loading = false;
  String? _error;

  LinkedTripInfo get trip => widget.linkedTrip;

  Future<void> _startLinked() async {
    if (trip.assignmentId == null) {
      setState(() => _error = 'لا يوجد تعيين لرحلة العودة. تواصل مع الإدارة.');
      return;
    }

    setState(() { _loading = true; _error = null; });

    try {
      final driver = ref.read(currentDriverProvider);

      // Start the linked trip → get new firebase key
      final firebaseKey = await ApiService.instance.startLinkedTrip(trip.assignmentId!);

      // Start GPS tracking with new firebase key
      await LocationService.instance.startTracking(
        firebaseKey: firebaseKey,
        driverId:    driver?.id ?? 0,
        tripId:      trip.tripId,
      );

      // Build a TripAssignment stub so the active trip provider knows what's running
      final stubAssignment = TripAssignment(
        assignmentId: trip.assignmentId!,
        tripId:       trip.tripId,
        routeNameAr:  trip.routeNameAr,
        routeNameEn:  trip.routeNameEn,
        routeColor:   trip.routeColor,
        direction:    trip.direction,
        departureTime: trip.departureTime,
        bookedCount:  trip.bookedCount,
        tripStatus:   'active',
        assignStatus: 'active',
        firebaseTripKey: firebaseKey,
      );

      ref.read(activeTripProvider.notifier).setActiveTrip(
        assignment:  stubAssignment,
        firebaseKey: firebaseKey,
      );

      if (!mounted) return;
      // Navigate to the map screen for the new trip
      context.go('/active-trip');
    } catch (e) {
      setState(() {
        _loading = false;
        _error   = formatApiError(e);
      });
    }
  }

  void _skipAndGoHome() {
    // Driver chose not to start the to_club trip right now
    // (edge case — normally they should start it)
    context.go('/trips');
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.base,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
          child: Column(
            children: [
              // ── Header ────────────────────────────────────────────────────
              const SizedBox(height: 16),
              Container(
                width: 72, height: 72,
                decoration: BoxDecoration(
                  color: AppColors.green.withValues(alpha: 0.12),
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.check_circle_outline_rounded,
                    color: AppColors.green, size: 40),
              ),
              const SizedBox(height: 16),
              const Text(
                'تم إنهاء رحلة الذهاب بنجاح',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 18,
                  fontWeight: FontWeight.w800, color: AppColors.blueDeep,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'لديك رحلة عودة مرتبطة جاهزة للبدء',
                textAlign: TextAlign.center,
                style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 13,
                  color: AppColors.textSub,
                ),
              ),

              const SizedBox(height: 32),

              // ── Linked trip card ──────────────────────────────────────────
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(20),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: AppColors.green.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                  boxShadow: [
                    BoxShadow(
                      color: AppColors.green.withValues(alpha: 0.08),
                      blurRadius: 16,
                    ),
                  ],
                ),
                child: Column(
                  children: [
                    // Direction badge
                    Container(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 14, vertical: 6),
                      decoration: BoxDecoration(
                        color: AppColors.green.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(20),
                      ),
                      child: const Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.arrow_upward_rounded,
                              color: AppColors.green, size: 16),
                          SizedBox(width: 6),
                          Text('رحلة العودة — من النادي',
                              style: TextStyle(
                                fontFamily: 'Cairo', fontSize: 12,
                                fontWeight: FontWeight.w700,
                                color: AppColors.green,
                              )),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // Route name
                    Text(
                      trip.routeNameAr,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 20,
                        fontWeight: FontWeight.w900, color: AppColors.blueDeep,
                      ),
                    ),
                    const SizedBox(height: 12),

                    // Stats row
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                      children: [
                        _statChip(Icons.access_time,
                            trip.displayTime, AppColors.blue),
                        _statChip(Icons.event_seat,
                            '${trip.bookedCount} راكب', AppColors.orange),
                        _statChip(Icons.directions_bus,
                            '${trip.maxPassengers} مقعد', AppColors.textSub),
                      ],
                    ),
                  ],
                ),
              ),

              const Spacer(),

              // ── Error banner ──────────────────────────────────────────────
              if (_error != null)
                Container(
                  padding: const EdgeInsets.all(14),
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                        color: AppColors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(
                    _error!,
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                        fontFamily: 'Cairo',
                        color: AppColors.red, fontSize: 13),
                  ),
                ),

              // ── Start button ──────────────────────────────────────────────
              GestureDetector(
                onTap: _loading ? null : _startLinked,
                child: Container(
                  height: 58,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                        colors: [AppColors.green, Color(0xFF1A8A40)]),
                    borderRadius: BorderRadius.circular(50),
                    boxShadow: [
                      BoxShadow(
                        color: AppColors.green.withValues(alpha: 0.4),
                        blurRadius: 20,
                      ),
                    ],
                  ),
                  child: Center(
                    child: _loading
                        ? const SizedBox(
                            width: 24, height: 24,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2.5))
                        : const Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.play_arrow_rounded,
                                  color: Colors.white, size: 26),
                              SizedBox(width: 8),
                              Text('ابدأ رحلة العودة',
                                  style: TextStyle(
                                    fontFamily: 'Cairo', fontSize: 17,
                                    fontWeight: FontWeight.w800,
                                    color: Colors.white,
                                  )),
                            ],
                          ),
                  ),
                ),
              ),

              const SizedBox(height: 12),

              // ── Skip (edge-case) ──────────────────────────────────────────
              TextButton(
                onPressed: _loading ? null : _skipAndGoHome,
                child: const Text(
                  'تخطي — سأبدأها لاحقاً',
                  style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 13,
                    color: AppColors.textSub,
                  ),
                ),
              ),

              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  Widget _statChip(IconData icon, String label, Color color) => Column(
    children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 4),
      Text(label,
          style: TextStyle(
            fontFamily: 'Cairo', fontSize: 12,
            fontWeight: FontWeight.w700, color: color,
          )),
    ],
  );
}
