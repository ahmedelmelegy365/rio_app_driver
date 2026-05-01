// lib/screens/trip_detail_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import '../core/constants/app_colors.dart';
import '../models/driver_models.dart';
import '../providers/app_providers.dart';

class TripDetailScreen extends ConsumerStatefulWidget {
  final TripAssignment trip;
  const TripDetailScreen({super.key, required this.trip});

  @override
  ConsumerState<TripDetailScreen> createState() => _TripDetailScreenState();
}

class _TripDetailScreenState extends ConsumerState<TripDetailScreen> {

  TripAssignment get trip => widget.trip;

  @override
  void initState() {
    super.initState();
    // If the backend says this trip is active but the in-memory provider
    // doesn't know yet (app restarted, hot reload, etc.) — restore it now.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final active = ref.read(activeTripProvider);
      final alreadyKnown = active.assignment?.assignmentId == trip.assignmentId
          && active.hasActiveTrip;
      if (trip.isActive && !alreadyKnown && trip.firebaseTripKey != null) {
        ref.read(activeTripProvider.notifier).setActiveTrip(
          assignment:  trip,
          firebaseKey: trip.firebaseTripKey!,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final activeState = ref.watch(activeTripProvider);

    // isThisActive: either the provider knows it, OR the backend data says so
    final isThisActive = trip.isActive ||
        activeState.assignment?.assignmentId == trip.assignmentId;

    // otherTripActive: a DIFFERENT trip is currently running
    final otherTripActive = !isThisActive && activeState.hasActiveTrip;

    final stopsAsync = ref.watch(tripStopCountsProvider(trip.tripId));
    final dirColor   = trip.isToClub ? AppColors.orange : AppColors.green;

    return Scaffold(
      backgroundColor: AppColors.base,
      body: Column(children: [

        // ── App bar ──────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    GestureDetector(
                      onTap: () => context.pop(),
                      child: Container(
                        width: 34, height: 34,
                        decoration: BoxDecoration(
                          color: AppColors.white10,
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: const Icon(Icons.arrow_forward_ios,
                            color: Colors.white, size: 16),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text(trip.routeNameAr,
                              style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 17,
                                fontWeight: FontWeight.w800, color: Colors.white,
                              )),
                          Text(
                            trip.isToClub ? 'إلى النادي' : 'من النادي',
                            style: TextStyle(
                                fontFamily: 'Cairo', fontSize: 12, color: dirColor),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              Container(height: 3,
                  decoration: const BoxDecoration(gradient: AppColors.greenLineGradient)),
            ]),
          ),
        ),

        // ── Content ──────────────────────────────────────────────────────────
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(16),
            child: Column(children: [

              _summaryCard(dirColor),
              const SizedBox(height: 16),

              // Section label
              Align(
                alignment: Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.only(bottom: 10),
                  child: Text('محطات الركوب والحجوزات',
                      style: const TextStyle(
                        fontFamily: 'Cairo', fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: AppColors.textSub, letterSpacing: 0.5,
                      )),
                ),
              ),

              _stopsCard(stopsAsync),
              const SizedBox(height: 24),

              // Error banner
              if (activeState.error != null)
                Container(
                  padding: const EdgeInsets.all(12),
                  margin: const EdgeInsets.only(bottom: 12),
                  decoration: BoxDecoration(
                    color: AppColors.red.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: AppColors.red.withValues(alpha: 0.3)),
                  ),
                  child: Text(activeState.error!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                          fontFamily: 'Cairo', color: AppColors.red, fontSize: 13)),
                ),

              // Action button
              if (!trip.isCompleted)
                if (isThisActive)
                  _activeButtons()
                else if (otherTripActive)
                  _otherTripActiveWarning()
                else
                  _startButton(),

              const SizedBox(height: 32),
            ]),
          ),
        ),
      ]),
    );
  }

  // ── Summary card ──────────────────────────────────────────────────────────
  Widget _summaryCard(Color dirColor) => Container(
    padding: const EdgeInsets.all(18),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.07), blurRadius: 12)],
    ),
    child: Column(
      children: [
        Row(
          textDirection: TextDirection.rtl,
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: [
            _infoChip(Icons.access_time, trip.displayTime, AppColors.blue),
            _infoChip(Icons.event_seat, '${trip.bookedCount} راكب', dirColor),
            _infoChip(
              trip.isToClub ? Icons.arrow_downward : Icons.arrow_upward,
              trip.isToClub ? 'ذهاب' : 'عودة',
              dirColor,
            ),
          ],
        ),
        if (trip.hasLinkedTrip) ...[
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            decoration: BoxDecoration(
              color: AppColors.blue.withValues(alpha: 0.07),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: const [
                Icon(Icons.link_rounded, color: AppColors.blue, size: 16),
                SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'رحلة مرتبطة — بعد إنهاء هذه الرحلة ستظهر شاشة لبدء رحلة العودة',
                    style: TextStyle(
                      fontFamily: 'Cairo', fontSize: 11,
                      color: AppColors.blue, fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ],
    ),
  );

  Widget _infoChip(IconData icon, String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.07), borderRadius: BorderRadius.circular(12)),
    child: Column(children: [
      Icon(icon, color: color, size: 20),
      const SizedBox(height: 4),
      Text(label,
          style: TextStyle(
              fontFamily: 'Cairo', fontSize: 12,
              fontWeight: FontWeight.w700, color: color)),
    ]),
  );

  // ── Stops card ────────────────────────────────────────────────────────────
  Widget _stopsCard(AsyncValue<List<TripStopCount>> stopsAsync) => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(18),
      boxShadow: [BoxShadow(color: AppColors.blue.withValues(alpha: 0.07), blurRadius: 12)],
    ),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Row(
          textDirection: TextDirection.rtl,
          children: const [
            Expanded(flex: 3,
              child: Text('المحطة', textAlign: TextAlign.right,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                      fontWeight: FontWeight.w800, color: AppColors.textSub))),
            Expanded(
              child: Text('الركاب', textAlign: TextAlign.center,
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 11,
                      fontWeight: FontWeight.w800, color: AppColors.textSub))),
          ],
        ),
        const Divider(height: 16),
        stopsAsync.when(
          loading: () => const Padding(
            padding: EdgeInsets.symmetric(vertical: 16),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          ),
          error: (_, __) => _stopRow(trip.routeNameAr, trip.bookedCount, true),
          data:  (stops) => stops.isEmpty
              ? _stopRow(trip.routeNameAr, trip.bookedCount, true)
              : Column(
                  children: stops.map((s) =>
                      _stopRow(s.nameAr, s.count, s.stopOrder == 1)).toList(),
                ),
        ),
      ],
    ),
  );

  Widget _stopRow(String name, int count, bool isFirst) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 6),
    child: Row(
      textDirection: TextDirection.rtl,
      children: [
        Container(
          width: 8, height: 8,
          decoration: BoxDecoration(
            color: isFirst ? AppColors.orange : AppColors.blue,
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(flex: 3,
          child: Text(name,
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 13,
                  fontWeight: FontWeight.w600, color: AppColors.blueDeep))),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
          decoration: BoxDecoration(
            color: count > 0 ? AppColors.green.withValues(alpha: 0.1) : AppColors.base,
            borderRadius: BorderRadius.circular(20),
          ),
          child: Text(
            count > 0 ? '$count راكب' : 'لا يوجد',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w800,
              color: count > 0 ? AppColors.green : AppColors.textSub,
            ),
          ),
        ),
      ],
    ),
  );

  // ── Action buttons ────────────────────────────────────────────────────────

  /// This trip is the active one — show map link + end button
  Widget _activeButtons() {
    final isLoading = ref.watch(activeTripProvider).isLoading;
    return Column(children: [
      // Resume / open map
      GestureDetector(
        onTap: () => context.push('/active-trip'),
        child: Container(
          height: 52,
          margin: const EdgeInsets.only(bottom: 12),
          decoration: BoxDecoration(
            color: AppColors.blue,
            borderRadius: BorderRadius.circular(50),
          ),
          child: const Center(
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              Icon(Icons.map, color: Colors.white, size: 20),
              SizedBox(width: 8),
              Text('عرض الخريطة',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 15,
                      fontWeight: FontWeight.w700, color: Colors.white)),
            ]),
          ),
        ),
      ),
      // End trip
      GestureDetector(
        onTap: isLoading ? null : _confirmEnd,
        child: Container(
          height: 56,
          decoration: BoxDecoration(
            color: AppColors.red,
            borderRadius: BorderRadius.circular(50),
            boxShadow: [BoxShadow(color: AppColors.red.withValues(alpha: 0.35), blurRadius: 20)],
          ),
          child: Center(
            child: isLoading
                ? const SizedBox(width: 22, height: 22,
                    child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
                : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.stop_circle_outlined, color: Colors.white, size: 22),
                    SizedBox(width: 8),
                    Text('إنهاء الرحلة',
                        style: TextStyle(fontFamily: 'Cairo', fontSize: 16,
                            fontWeight: FontWeight.w800, color: Colors.white)),
                  ]),
          ),
        ),
      ),
    ]);
  }

  /// No active trip — show start button
  Widget _startButton() {
    final isLoading = ref.watch(activeTripProvider).isLoading;
    return GestureDetector(
      onTap: isLoading ? null : _confirmStart,
      child: Container(
        height: 56,
        decoration: BoxDecoration(
          gradient: const LinearGradient(
              colors: [AppColors.green, Color(0xFF1A8A40)]),
          borderRadius: BorderRadius.circular(50),
          boxShadow: [BoxShadow(color: AppColors.green.withValues(alpha: 0.4), blurRadius: 20)],
        ),
        child: Center(
          child: isLoading
              ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2.5))
              : const Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 22),
                  SizedBox(width: 8),
                  Text('بدء الرحلة',
                      style: TextStyle(fontFamily: 'Cairo', fontSize: 16,
                          fontWeight: FontWeight.w800, color: Colors.white)),
                ]),
        ),
      ),
    );
  }

  /// Another trip is active — block start
  Widget _otherTripActiveWarning() => Container(
    padding: const EdgeInsets.all(16),
    decoration: BoxDecoration(
      color: AppColors.orange.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(16),
      border: Border.all(color: AppColors.orange.withValues(alpha: 0.3)),
    ),
    child: const Row(
      textDirection: TextDirection.rtl,
      children: [
        Icon(Icons.warning_amber_rounded, color: AppColors.orange, size: 22),
        SizedBox(width: 10),
        Expanded(
          child: Text(
            'لديك رحلة نشطة حالياً. أنهِ الرحلة الجارية أولاً قبل بدء رحلة جديدة.',
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                fontWeight: FontWeight.w600, color: AppColors.orange),
          ),
        ),
      ],
    ),
  );

  // ── Dialogs ───────────────────────────────────────────────────────────────

  void _confirmStart() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تأكيد بدء الرحلة', textAlign: TextAlign.right,
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: Text(
          'هل أنت متأكد من بدء رحلة ${trip.routeNameAr}؟\n'
          'سيبدأ بث الموقع للركاب فور التأكيد.',
          textAlign: TextAlign.right,
          style: const TextStyle(fontFamily: 'Cairo', fontSize: 13),
        ),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSub)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final ok = await ref.read(activeTripProvider.notifier).startTrip(trip);
              if (!mounted) return;
              if (ok) {
                context.push('/active-trip');
              } else {
                final err = ref.read(activeTripProvider).error ?? 'فشل بدء الرحلة';
                _showError(err);
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.green,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('نعم، ابدأ',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _confirmEnd() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('تأكيد إنهاء الرحلة', textAlign: TextAlign.right,
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: const Text('هل أنت متأكد من إنهاء الرحلة؟\nسيتوقف بث الموقع.',
            textAlign: TextAlign.right,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء',
                style: TextStyle(fontFamily: 'Cairo', color: AppColors.textSub)),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final linked = await ref.read(activeTripProvider.notifier).endTrip();
              if (!mounted) return;
              if (linked != null && linked.showTransition) {
                context.go('/transition-trip', extra: linked);
              } else {
                context.go('/trips');
              }
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.red,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
            ),
            child: const Text('نعم، أنهِ',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white,
                    fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }

  void _showError(String msg) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(children: [
          Icon(Icons.error_outline, color: Colors.red),
          SizedBox(width: 8),
          Text('تعذّر بدء الرحلة',
              style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 15)),
        ]),
        content: Text(msg, textAlign: TextAlign.right,
            style: const TextStyle(fontFamily: 'Cairo')),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.blue,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            child: const Text('حسناً',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
