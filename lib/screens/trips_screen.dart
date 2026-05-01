// lib/screens/trips_screen.dart

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:dio/dio.dart';
import '../core/constants/app_colors.dart';
import '../models/driver_models.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';
import '../services/location_service.dart';

// ─────────────────────────────────────────────────────────────────────────────
// TripsScreen
// ─────────────────────────────────────────────────────────────────────────────

class TripsScreen extends ConsumerStatefulWidget {
  const TripsScreen({super.key});

  @override
  ConsumerState<TripsScreen> createState() => _TripsScreenState();
}

class _TripsScreenState extends ConsumerState<TripsScreen>
    with SingleTickerProviderStateMixin {
  late TabController _tab;

  @override
  void initState() {
    super.initState();
    _tab = TabController(length: 2, vsync: this);
  }

  @override
  void dispose() {
    _tab.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final driver     = ref.watch(currentDriverProvider);
    final activeTrip = ref.watch(activeTripProvider);

    return Scaffold(
      backgroundColor: AppColors.base,
      body: Column(children: [

        // ── Header ─────────────────────────────────────────────────────────
        Container(
          decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
          child: SafeArea(
            bottom: false,
            child: Column(children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(18, 14, 18, 0),
                child: Row(
                  textDirection: TextDirection.rtl,
                  children: [
                    Container(
                      width: 42, height: 42,
                      decoration: BoxDecoration(
                        color: AppColors.white20,
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: const Icon(Icons.person, color: Colors.white, size: 24),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.end,
                        children: [
                          Text('مرحباً، ${driver?.name ?? 'السائق'}',
                              style: const TextStyle(
                                fontFamily: 'Cairo', fontSize: 16,
                                fontWeight: FontWeight.w800, color: Colors.white,
                              )),
                          Text('رحلات اليوم',
                              style: TextStyle(
                                fontFamily: 'Cairo', fontSize: 12,
                                color: Colors.white.withValues(alpha: 0.6),
                              )),
                        ],
                      ),
                    ),
                    IconButton(
                      onPressed: () async {
                        await ApiService.instance.logout();
                        ref.read(currentDriverProvider.notifier).state = null;
                        if (context.mounted) context.go('/login');
                      },
                      icon: Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: AppColors.white10,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.logout, color: Colors.white, size: 18),
                      ),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 12),

              Container(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: TabBar(
                  controller: _tab,
                  indicator: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  indicatorSize: TabBarIndicatorSize.tab,
                  labelColor: AppColors.blueDeep,
                  unselectedLabelColor: Colors.white70,
                  labelStyle: const TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w800, fontSize: 13,
                  ),
                  tabs: const [
                    Tab(text: 'كل الرحلات'),
                    Tab(text: 'رحلاتي'),
                  ],
                ),
              ),

              const SizedBox(height: 10),

              Container(height: 3,
                  decoration: const BoxDecoration(gradient: AppColors.greenLineGradient)),
            ]),
          ),
        ),

        // ── Active trip banner ────────────────────────────────────────────
        if (activeTrip.hasActiveTrip)
          GestureDetector(
            onTap: () => context.push('/active-trip'),
            child: Container(
              margin: const EdgeInsets.fromLTRB(16, 12, 16, 0),
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                gradient: const LinearGradient(
                    colors: [AppColors.green, Color(0xFF1A8A40)]),
                borderRadius: BorderRadius.circular(12),
                boxShadow: [BoxShadow(
                    color: AppColors.green.withValues(alpha: 0.4), blurRadius: 14)],
              ),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.2),
                      borderRadius: BorderRadius.circular(9),
                    ),
                    child: const Icon(Icons.navigation, color: Colors.white, size: 18),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        const Text('رحلة جارية الآن — اضغط للخريطة',
                            style: TextStyle(fontFamily: 'Cairo',
                                color: Colors.white, fontSize: 13,
                                fontWeight: FontWeight.w800)),
                        Text(activeTrip.assignment?.routeNameAr ?? '',
                            style: TextStyle(fontFamily: 'Cairo',
                                color: Colors.white.withValues(alpha: 0.8),
                                fontSize: 11)),

                      ],
                    ),
                  ),
                  const Icon(Icons.arrow_back_ios, color: Colors.white, size: 14),
                ],
              ),
            ),
          ),

        // ── Tab views ─────────────────────────────────────────────────────
        Expanded(
          child: TabBarView(
            controller: _tab,
            children: [
              _AllTripsTab(tabController: _tab),
              const _MyTripsTab(),
            ],
          ),
        ),
      ]),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 1 — All Today's Trips  (with route filter chips)
// ─────────────────────────────────────────────────────────────────────────────

class _AllTripsTab extends ConsumerStatefulWidget {
  final TabController tabController;
  const _AllTripsTab({required this.tabController});

  @override
  ConsumerState<_AllTripsTab> createState() => _AllTripsTabState();
}

class _AllTripsTabState extends ConsumerState<_AllTripsTab> {
  /// null = show all routes
  String? _selectedRoute;

  // ── helpers ───────────────────────────────────────────────────────────────

  static Color _hexColor(String hex) {
    final h = hex.replaceAll('#', '');
    return Color(int.parse('FF$h', radix: 16));
  }

  // ── build ─────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final async = ref.watch(allTripsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => _errorView(e),
      data:    (trips) {
        if (trips.isEmpty) return _emptyView('لا توجد رحلات اليوم');

        // Collect distinct routes preserving first-seen order
        final routeMap = <String, String>{}; // nameAr → colorHex
        for (final t in trips) {
          routeMap.putIfAbsent(t.routeNameAr, () => t.routeColor);
        }

        // Apply filter
        final filtered = _selectedRoute == null
            ? trips
            : trips.where((t) => t.routeNameAr == _selectedRoute).toList();

        return Column(children: [
          // ── Route filter chips (only if >1 distinct route) ────────────────
          if (routeMap.length > 1) _chipsBar(routeMap),

          // ── Trip list ─────────────────────────────────────────────────────
          Expanded(
            child: RefreshIndicator(
              onRefresh: () async {
                _selectedRoute = null; // reset filter on pull-to-refresh
                ref.invalidate(allTripsProvider);
                await ref.read(allTripsProvider.future);
              },
              child: filtered.isEmpty
                  ? _emptyView('لا توجد رحلات لهذا الخط')
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
                      itemCount: filtered.length,
                      itemBuilder: (_, i) => _AllTripCard(
                        trip: filtered[i],
                        tabController: widget.tabController,
                      ),
                    ),
            ),
          ),
        ]);
      },
    );
  }

  // ── Chips bar ─────────────────────────────────────────────────────────────

  Widget _chipsBar(Map<String, String> routeMap) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Directionality(
        textDirection: TextDirection.rtl,
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(
            children: [
              // "All" chip — always first (rightmost in RTL)
              _routeChip(
                label: 'الكل',
                color: AppColors.blue,
                selected: _selectedRoute == null,
                onTap: () => setState(() => _selectedRoute = null),
              ),
              ...routeMap.entries.map((e) {
                final color = _hexColor(e.value);
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: _routeChip(
                    label: e.key,
                    color: color,
                    selected: _selectedRoute == e.key,
                    onTap: () => setState(() => _selectedRoute = e.key),
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  Widget _routeChip({
    required String label,
    required Color color,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 180),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
        decoration: BoxDecoration(
          color: selected ? color : color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: selected ? color : color.withValues(alpha: 0.3),
            width: 1.5,
          ),
          boxShadow: selected
              ? [BoxShadow(
                  color: color.withValues(alpha: 0.30),
                  blurRadius: 8, offset: const Offset(0, 2))]
              : null,
        ),
        child: Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 12,
            fontWeight: FontWeight.w800,
            color: selected ? Colors.white : color,
          ),
        ),
      ),
    );
  }

  // ── Error & empty helpers ─────────────────────────────────────────────────

  Widget _errorView(Object e) => Center(
    child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
      const Icon(Icons.error_outline, color: AppColors.red, size: 48),
      const SizedBox(height: 12),
      Text(formatApiError(e), textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.red, fontSize: 12, fontFamily: 'Cairo')),
      const SizedBox(height: 16),
      ElevatedButton(
        onPressed: () => ref.invalidate(allTripsProvider),
        style: ElevatedButton.styleFrom(backgroundColor: AppColors.blue),
        child: const Text('إعادة المحاولة',
            style: TextStyle(color: Colors.white, fontFamily: 'Cairo')),
      ),
    ]),
  );
}

// ─────────────────────────────────────────────────────────────────────────────
// Tab 2 — My Trips
// ─────────────────────────────────────────────────────────────────────────────

class _MyTripsTab extends ConsumerWidget {
  const _MyTripsTab();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final async = ref.watch(tripsProvider);
    return async.when(
      loading: () => const Center(child: CircularProgressIndicator()),
      error:   (e, _) => Center(child: Text(formatApiError(e),
          textAlign: TextAlign.center,
          style: const TextStyle(color: AppColors.red, fontFamily: 'Cairo'))),
      data:    (trips) {
        if (trips.isEmpty) return _emptyView('لم تُعيَّن لأي رحلة اليوم');
        return RefreshIndicator(
          onRefresh: () => ref.refresh(tripsProvider.future),
          child: ListView.builder(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
            itemCount: trips.length,
            itemBuilder: (_, i) => _MyTripCard(trip: trips[i]),
          ),
        );
      },
    );
  }
}

Widget _emptyView(String msg) => Center(
  child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
    const Icon(Icons.directions_bus_outlined, size: 56, color: AppColors.textSub),
    const SizedBox(height: 14),
    Text(msg, style: const TextStyle(
      fontFamily: 'Cairo', fontSize: 15, color: AppColors.textSub,
    )),
  ]),
);

// ─────────────────────────────────────────────────────────────────────────────
// All-trips card
// ─────────────────────────────────────────────────────────────────────────────

class _AllTripCard extends ConsumerWidget {
  final AllTripItem trip;
  final TabController tabController;
  const _AllTripCard({required this.trip, required this.tabController});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final dirColor = trip.isToClub ? AppColors.orange : AppColors.green;

    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: trip.isMyActive
            ? Border.all(color: AppColors.green, width: 2)
            : trip.isMine
            ? Border.all(color: AppColors.blue.withValues(alpha: 0.3))
            : null,
        boxShadow: [BoxShadow(
            color: AppColors.blue.withValues(alpha: 0.07),
            blurRadius: 10, offset: const Offset(0, 3))],
      ),
      child: Column(children: [

        Container(
          padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
          decoration: BoxDecoration(
            color: dirColor.withValues(alpha: 0.05),
            borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            children: [
              Container(
                width: 40, height: 40,
                decoration: BoxDecoration(
                  color: dirColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(11),
                ),
                child: Icon(
                  trip.isToClub ? Icons.arrow_downward : Icons.arrow_upward,
                  color: dirColor, size: 20,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text(trip.routeNameAr,
                        style: const TextStyle(
                          fontFamily: 'Cairo', fontSize: 14,
                          fontWeight: FontWeight.w800, color: AppColors.blueDeep,
                        )),
                    Text(
                      '#${trip.tripNumber}',  // Make sure your AllTripItem has tripNumber field
                      style: TextStyle(
                        fontFamily: 'Nunito', fontSize: 11,
                        color: AppColors.textSub,
                      ),
                    ),
                    Text(trip.isToClub ? 'إلى النادي' : 'من النادي',
                        style: TextStyle(fontSize: 11, color: dirColor,
                            fontWeight: FontWeight.w600)),
                  ],
                ),
              ),
              _statusBadge(trip),
            ],
          ),
        ),

        // ── Relationship strip — only renders if this trip has any
        //    linked-return, extension-source, or extension-target relation.
        //    Zero height for unrelated trips (looks identical to before).
        _RelationshipStrip(trip: trip),

        Padding(
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          child: Row(
            textDirection: TextDirection.rtl,
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
                Row(children: [
                  const Icon(Icons.access_time, size: 12, color: AppColors.blue),
                  const SizedBox(width: 4),
                  Text(trip.displayTime,
                      style: const TextStyle(fontFamily: 'Nunito',
                          fontSize: 16, fontWeight: FontWeight.w900,
                          color: AppColors.blueDeep)),
                ]),
                Row(children: [
                  const Icon(Icons.event_seat, size: 12, color: AppColors.textSub),
                  const SizedBox(width: 4),
                  Text('${trip.bookedCount}/${trip.maxPassengers} راكب',
                      style: const TextStyle(fontSize: 11, color: AppColors.textSub)),
                ]),
              ]),
              _actionButton(context, ref, trip, tabController),
            ],
          ),
        ),
      ]),
    );
  }

  Widget _statusBadge(AllTripItem t) {
    Color c; String label;
    if (t.isMyActive)           { c = AppColors.green;   label = 'جارية';    }
    else if (t.isMine && !t.isCompleted) { c = AppColors.blue;    label = 'معيّن لي'; }
    else if (t.isCompleted)     { c = AppColors.textSub; label = 'منتهية';   }
    else if (t.isTakenByOther)  { c = AppColors.orange;  label = 'محجوزة';   }
    else                        { c = AppColors.green;   label = 'متاحة';    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.25)),
      ),
      child: Text(label, style: TextStyle(
        color: c, fontSize: 10, fontWeight: FontWeight.w800, fontFamily: 'Cairo',
      )),
    );
  }

  Widget _actionButton(BuildContext context, WidgetRef ref,
      AllTripItem t, TabController tab) {
    if (t.isMyActive) {
      return _btn('الخريطة', Icons.map, AppColors.green,
              () => context.push('/active-trip'));
    }
    if (t.isMine && !t.isCompleted) {
      return _btn('تفاصيل', Icons.arrow_back_ios, AppColors.blue, () {
        context.push('/trip-detail', extra: TripAssignment(
          assignmentId:    t.assignmentId ?? 0,
          tripId:          t.tripId,
          routeNameAr:     t.routeNameAr,
          routeNameEn:     t.routeNameEn,
          routeColor:      t.routeColor,
          direction:       t.direction,
          departureTime:   t.departureTime,
          bookedCount:     t.bookedCount,
          tripStatus:      t.tripStatus,
          assignStatus:    t.assignmentStatus ?? 'assigned',
          firebaseTripKey: t.firebaseTripKey,
        ));
      });
    }
    if (t.isCompleted) {
      return _staticChip('منتهية', AppColors.textSub);
    }
    if (t.isTakenByOther) {
      return _staticChip('سائق آخر', AppColors.orange);
    }
    // Dependent trips — the start happens via their root trip, not here.
    // Backend already sets isAssignable=false in these cases; the chip
    // just communicates WHY to the driver.
    if (t.isLinkedReturn) {
      return _staticChip('تبدأ مع رحلة الذهاب', AppColors.blue);
    }
    if (t.isExtensionTarget) {
      return _staticChip('تنشط عبر التمديد', AppColors.blue);
    }
    // بدل
    if (t.isAssignable) {
      // Check if driver has active trip
      final activeTrip = ref.watch(activeTripProvider);
      final driverBusy = activeTrip.hasActiveTrip;

      if (driverBusy) {
        return _btn('لديك رحلة نشطة', Icons.block, AppColors.orange,
                () => context.push('/active-trip'));
      }

      return _btn('تعيين وبدء', Icons.play_arrow, AppColors.green,
              () => _showAssignSheet(context, ref, t, tab));
    }
    return _staticChip('مغلقة', AppColors.textSub);
  }

  Widget _btn(String label, IconData icon, Color color, VoidCallback onTap) =>
      GestureDetector(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.08),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: color.withValues(alpha: 0.25)),
          ),
          child: Row(children: [
            Icon(icon, color: color, size: 14),
            const SizedBox(width: 5),
            Text(label, style: TextStyle(
              color: color, fontSize: 12,
              fontWeight: FontWeight.w800, fontFamily: 'Cairo',
            )),
          ]),
        ),
      );

  Widget _staticChip(String label, Color color) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
    decoration: BoxDecoration(
      color: color.withValues(alpha: 0.08),
      borderRadius: BorderRadius.circular(10),
    ),
    child: Text(label, style: TextStyle(
      fontSize: 11, color: color, fontFamily: 'Cairo',
    )),
  );

  void _showAssignSheet(BuildContext context, WidgetRef ref,
      AllTripItem trip, TabController tab) {
    // Read driver id HERE before entering bottom sheet (separate widget tree)
    final driverId = ref.read(currentDriverProvider)?.id ?? 0;
    debugPrint('showAssignSheet: driverId=$driverId');
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => _AssignSheet(
        trip:         trip,
        tabController: tab,
        driverId:     driverId,
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// Self-assign bottom sheet
// ─────────────────────────────────────────────────────────────────────────────

class _AssignSheet extends ConsumerStatefulWidget {
  final AllTripItem trip;
  final TabController tabController;
  final int driverId; // ← passed from parent, avoids null provider issue
  const _AssignSheet({
    required this.trip,
    required this.tabController,
    required this.driverId,
  });

  @override
  ConsumerState<_AssignSheet> createState() => _AssignSheetState();
}

class _AssignSheetState extends ConsumerState<_AssignSheet> {
  BusModel? _selectedBus;
  bool _loading = false;
  String? _error;

  @override
  Widget build(BuildContext context) {
    final busesAsync = ref.watch(busesProvider);
    final dirColor   = widget.trip.isToClub ? AppColors.orange : AppColors.green;

    return Container(
      decoration: const BoxDecoration(
        color: AppColors.base,
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      padding: EdgeInsets.fromLTRB(
        20, 16, 20,
        MediaQuery.of(context).viewInsets.bottom + 32,
      ),
      child: Column(mainAxisSize: MainAxisSize.min, children: [

        // Handle
        Container(width: 36, height: 4,
            decoration: BoxDecoration(
              color: AppColors.baseDim,
              borderRadius: BorderRadius.circular(4),
            )),
        const SizedBox(height: 16),

        // Title
        Row(textDirection: TextDirection.rtl, children: [
          Container(
            width: 40, height: 40,
            decoration: BoxDecoration(
              color: dirColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(11),
            ),
            child: Icon(Icons.play_arrow, color: dirColor, size: 22),
          ),
          const SizedBox(width: 12),
          Expanded(child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              const Text('تعيين وبدء الرحلة',
                  style: TextStyle(fontFamily: 'Cairo', fontSize: 16,
                      fontWeight: FontWeight.w800, color: AppColors.blueDeep)),
              Text('${widget.trip.routeNameAr} — ${widget.trip.displayTime}',
                  style: const TextStyle(fontSize: 12, color: AppColors.textSub)),
            ],
          )),
        ]),

        const SizedBox(height: 20),
        const Divider(),
        const SizedBox(height: 16),

        // Bus picker label
        const Align(
          alignment: Alignment.centerRight,
          child: Text('اختر الباص (رقم اللوحة)',
              style: TextStyle(fontFamily: 'Cairo', fontSize: 13,
                  fontWeight: FontWeight.w800, color: AppColors.textSub)),
        ),
        const SizedBox(height: 10),

        // Bus list
        busesAsync.when(
          loading: () => const Center(child: CircularProgressIndicator()),
          error:   (e, _) => Text(formatApiError(e),
              style: const TextStyle(color: AppColors.red, fontFamily: 'Cairo')),
          data: (buses) => buses.isEmpty
              ? const Text('لا توجد باصات متاحة',
              style: TextStyle(color: AppColors.textSub, fontFamily: 'Cairo'))
              : Wrap(
            spacing: 8, runSpacing: 8,
            children: buses.map((b) {
              final sel = _selectedBus?.id == b.id;
              return GestureDetector(
                onTap: () => setState(() => _selectedBus = b),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 150),
                  padding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 10),
                  decoration: BoxDecoration(
                    color: sel ? AppColors.blue : AppColors.base,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: sel ? AppColors.blue : AppColors.baseDim,
                    ),
                    boxShadow: sel ? null : [
                      const BoxShadow(color: Colors.white,
                          offset: Offset(-2, -2), blurRadius: 4),
                      BoxShadow(
                          color: AppColors.blueDeep.withValues(alpha: 0.1),
                          offset: const Offset(2, 2), blurRadius: 4),
                    ],
                  ),
                  child: Column(children: [
                    Text(b.plate,
                        style: TextStyle(
                          fontFamily: 'Nunito', fontSize: 14,
                          fontWeight: FontWeight.w900,
                          color: sel ? Colors.white : AppColors.blueDeep,
                        )),
                    Text('${b.capacity} مقعد',
                        style: TextStyle(
                          fontSize: 10,
                          color: sel ? Colors.white70 : AppColors.textSub,
                        )),
                  ]),
                ),
              );
            }).toList(),
          ),
        ),

        const SizedBox(height: 16),

        // Error message
        if (_error != null)
          Container(
            padding: const EdgeInsets.all(10),
            margin: const EdgeInsets.only(bottom: 12),
            decoration: BoxDecoration(
              color: AppColors.red.withValues(alpha: 0.08),
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: AppColors.red.withValues(alpha: 0.2)),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                const Icon(Icons.error_outline, color: AppColors.red, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(_error!,
                      style: const TextStyle(color: AppColors.red,
                          fontSize: 12, fontFamily: 'Cairo')),
                ),
              ],
            ),
          ),

        // Confirm button
        GestureDetector(
          onTap: (_selectedBus == null || _loading) ? null : _confirm,
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 200),
            height: 52,
            decoration: BoxDecoration(
              color: _selectedBus == null ? AppColors.baseDim : AppColors.green,
              borderRadius: BorderRadius.circular(14),
              boxShadow: _selectedBus == null ? null : [
                BoxShadow(color: AppColors.green.withValues(alpha: 0.4),
                    blurRadius: 16, offset: const Offset(0, 4)),
              ],
            ),
            child: Center(
              child: _loading
                  ? const SizedBox(width: 22, height: 22,
                  child: CircularProgressIndicator(
                      color: Colors.white, strokeWidth: 2.5))
                  : const Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.play_arrow, color: Colors.white, size: 20),
                  SizedBox(width: 8),
                  Text('تعيين وبدء الرحلة',
                      style: TextStyle(fontFamily: 'Cairo',
                          fontSize: 15, fontWeight: FontWeight.w800,
                          color: Colors.white)),
                ],
              ),
            ),
          ),
        ),
      ]),
    );
  }

  // ── Confirm ───────────────────────────────────────────────

  Future<void> _confirm() async {
    setState(() { _loading = true; _error = null; });
    try {
      final result = await ApiService.instance.selfAssignAndStart(
        tripId: widget.trip.tripId,
        busId:  _selectedBus!.id,
      );
      await _activateTrip(
        assignmentId: result.assignmentId,
        firebaseKey:  result.firebaseKey,
        tripStatus:   'active',
        assignStatus: 'active',
      );
    } catch (e) {
      // Special-case: server says the driver already has an active trip (5003)
      // — silently fetch it and navigate, instead of surfacing the error.
      if (e is DioException) {
        final responseData = e.response?.data;
        final errorCode = responseData is Map ? responseData['error_number'] : null;
        final serverMsg = responseData is Map ? responseData['message']?.toString() ?? '' : '';
        if (errorCode == 5003 || serverMsg.contains('لديك رحلة نشطة')) {
          setState(() { _loading = true; _error = null; });
          try {
            final active = await ApiService.instance.fetchActiveAssignment();
            if (active != null && mounted) {
              ref.read(activeTripProvider.notifier).setActiveTrip(
                assignment:  active,
                firebaseKey: active.firebaseTripKey ?? '',
              );
              Navigator.pop(context);
              ref.invalidate(allTripsProvider);
              ref.invalidate(tripsProvider);
              context.push('/active-trip');
              return;
            }
          } catch (_) {}
          setState(() { _loading = false; _error = 'لديك رحلة نشطة بالفعل'; });
          return;
        }
      }
      setState(() { _loading = false; _error = formatApiError(e); });
    }
  }

  // ── Activate trip locally + start tracking ────────────────

  Future<void> _activateTrip({
    required int assignmentId,
    required String firebaseKey,
    required String tripStatus,
    required String assignStatus,
  }) async {
    final assignment = TripAssignment(
      assignmentId:    assignmentId,
      tripId:          widget.trip.tripId,
      routeNameAr:     widget.trip.routeNameAr,
      routeNameEn:     widget.trip.routeNameEn,
      routeColor:      widget.trip.routeColor,
      direction:       widget.trip.direction,
      departureTime:   widget.trip.departureTime,
      bookedCount:     widget.trip.bookedCount,
      tripStatus:      tripStatus,
      assignStatus:    assignStatus,
      firebaseTripKey: firebaseKey,
    );

    // Use widget.driverId — safe, read before sheet opened
    debugPrint('=== _activateTrip: driverId=${widget.driverId} firebaseKey=$firebaseKey ===');

    await LocationService.instance.startTracking(
      firebaseKey: firebaseKey,
      driverId:    widget.driverId,
      tripId:      widget.trip.tripId,
    );

    ref.read(activeTripProvider.notifier).setActiveTrip(
      assignment:  assignment,
      firebaseKey: firebaseKey,
    );

    if (mounted) {
      Navigator.pop(context);
      ref.invalidate(allTripsProvider);
      ref.invalidate(tripsProvider);
      context.push('/active-trip');
    }
  }
}

// ─────────────────────────────────────────────────────────────────────────────
// My-trips card (tab 2)
// ─────────────────────────────────────────────────────────────────────────────

class _MyTripCard extends ConsumerWidget {
  final TripAssignment trip;
  const _MyTripCard({required this.trip});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final activeTrip   = ref.watch(activeTripProvider);
    final isThisActive = activeTrip.assignment?.assignmentId == trip.assignmentId;
    final dirColor     = trip.isToClub ? AppColors.orange : AppColors.green;

    return GestureDetector(
      onTap: () => context.push('/trip-detail', extra: trip),
      child: Container(
        margin: const EdgeInsets.only(bottom: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(16),
          border: isThisActive
              ? Border.all(color: AppColors.green, width: 2)
              : null,
          boxShadow: [BoxShadow(
              color: AppColors.blue.withValues(alpha: 0.07),
              blurRadius: 10, offset: const Offset(0, 3))],
        ),
        child: Column(children: [

          Container(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
            decoration: BoxDecoration(
              color: trip.isCompleted
                  ? Colors.grey.withValues(alpha: 0.04)
                  : dirColor.withValues(alpha: 0.05),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(16)),
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Container(
                  width: 40, height: 40,
                  decoration: BoxDecoration(
                    color: (trip.isCompleted ? AppColors.textSub : dirColor)
                        .withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(11),
                  ),
                  child: Icon(
                    trip.isToClub ? Icons.arrow_downward : Icons.arrow_upward,
                    color: trip.isCompleted ? AppColors.textSub : dirColor,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(trip.routeNameAr,
                          style: TextStyle(
                            fontFamily: 'Cairo', fontSize: 14,
                            fontWeight: FontWeight.w800,
                            color: trip.isCompleted
                                ? AppColors.textSub : AppColors.blueDeep,
                          )),
                      Text(trip.isToClub ? 'إلى النادي' : 'من النادي',
                          style: TextStyle(fontSize: 11,
                              color: trip.isCompleted
                                  ? AppColors.textSub : dirColor,
                              fontWeight: FontWeight.w600)),
                    ],
                  ),
                ),
                _statusBadge(trip.assignStatus),
              ],
            ),
          ),

          Padding(
            padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
            child: Row(
              textDirection: TextDirection.rtl,
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                _info(Icons.access_time, trip.displayTime, AppColors.blue),
                _info(Icons.event_seat, '${trip.bookedCount} راكب', AppColors.textSub),
                const Icon(Icons.arrow_back_ios, size: 13, color: AppColors.textSub),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _info(IconData icon, String text, Color color) => Row(
    textDirection: TextDirection.rtl,
    children: [
      Icon(icon, size: 13, color: color),
      const SizedBox(width: 4),
      Text(text, style: TextStyle(
          fontFamily: 'Cairo', fontSize: 12,
          color: color, fontWeight: FontWeight.w600)),
    ],
  );

  Widget _statusBadge(String s) {
    final color = switch (s) {
      'assigned'  => AppColors.blue,
      'active'    => AppColors.green,
      'completed' => AppColors.textSub,
      _           => AppColors.textSub,
    };
    final label = switch (s) {
      'assigned'  => 'مجدولة',
      'active'    => 'جارية',
      'completed' => 'منتهية',
      _           => s,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(20),
      ),
      child: Text(label, style: TextStyle(
        fontFamily: 'Cairo', fontSize: 10,
        fontWeight: FontWeight.w800, color: color,
      )),
    );
  }
}

// ── Trip relationship strip ─────────────────────────────────────────────
//
// Renders a compact row of one-line relationship pills inside a trip card,
// just below the header. Pills show:
//   - Linked-return source (when this trip is the to_club partner): "↻ مرتبطة برحلة الذهاب #R-XXXX (شارع X)"
//   - Linked-return target (when this trip is from_club with linked_trip): "↻ لها رحلة عودة #R-XXXX"
//   - Extension source(s) (when this trip is an extension target): "🔗 تمديد لرحلة #R-XXXX (شارع X)"
//   - Extension target(s) (when this trip can be extended TO others): "🔗 يمكن تمديدها إلى شارع X"
//
// The strip is zero-height when the trip has no relationships, so unrelated
// trips look identical to before.

class _RelationshipStrip extends StatelessWidget {
  final AllTripItem trip;
  const _RelationshipStrip({required this.trip});

  @override
  Widget build(BuildContext context) {
    final pills = <Widget>[];

    // Linked round-trip pair
    if (trip.isLinkedReturn) {
      // I am to_club; the partner (linked_trip_id) is the from_club source.
      pills.add(_pill(
        icon: Icons.swap_calls,
        color: AppColors.blue,
        label: 'مرتبطة بـ #R-${trip.linkedTripId ?? '—'} (الذهاب)',
      ));
    } else if (trip.linkedTripId != null && trip.direction == 'from_club') {
      // I am from_club; the partner is the return trip.
      pills.add(_pill(
        icon: Icons.swap_calls,
        color: AppColors.green,
        label: 'لها رحلة عودة #R-${trip.linkedTripId}',
      ));
    }

    // Extension relationships
    for (final src in trip.extensionSources) {
      pills.add(_pill(
        icon: Icons.alt_route,
        color: AppColors.blue,
        label: 'تمديد لـ ${src.routeNameAr} (#${src.tripNumber})',
      ));
    }
    for (final tgt in trip.extensionTargets) {
      pills.add(_pill(
        icon: Icons.alt_route,
        color: AppColors.green,
        label: 'يمكن تمديدها إلى ${tgt.routeNameAr}',
      ));
    }

    if (pills.isEmpty) return const SizedBox.shrink();

    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 0, 14, 4),
      child: Wrap(
        textDirection: TextDirection.rtl,
        spacing: 6,
        runSpacing: 6,
        children: pills,
      ),
    );
  }

  Widget _pill({
    required IconData icon,
    required Color color,
    required String label,
  }) =>
      Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: color.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: color.withValues(alpha: 0.25)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          textDirection: TextDirection.rtl,
          children: [
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 10,
                fontWeight: FontWeight.w700,
                color: color,
              ),
            ),
          ],
        ),
      );
}
