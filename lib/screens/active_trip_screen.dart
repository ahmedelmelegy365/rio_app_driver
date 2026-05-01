// lib/screens/active_trip_screen.dart

import 'dart:async';
import 'dart:ui' as ui;
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:geolocator/geolocator.dart';
import '../core/constants/app_colors.dart';
import '../models/driver_models.dart';
import '../providers/app_providers.dart';
import '../services/api_service.dart';
import '../services/error_formatter.dart';

class ActiveTripScreen extends ConsumerStatefulWidget {
  const ActiveTripScreen({super.key});

  @override
  ConsumerState<ActiveTripScreen> createState() => _ActiveTripScreenState();
}

class _ActiveTripScreenState extends ConsumerState<ActiveTripScreen> {
  GoogleMapController? _mapController;
  StreamSubscription<Position>? _posSub;

  // ── Smooth animation state ────────────────────────────────
  LatLng _displayPos   = const LatLng(31.2001, 29.9187); // Alex city center default
  LatLng _animFrom     = const LatLng(31.2001, 29.9187);
  LatLng _animTo       = const LatLng(31.2001, 29.9187);
  DateTime? _lastFixTime;
  Duration  _animDuration = const Duration(seconds: 2);
  Timer?    _animTimer;
  double    _heading = 0;

  // ── Custom marker icons ───────────────────────────────────
  BitmapDescriptor? _busIcon;
  final Map<int, BitmapDescriptor> _stopIcons      = {}; // stopId -> icon with count badge
  final Map<int, int>              _stopIconCounts  = {}; // stopId -> last rendered count
  double _pixelRatio = 1.0;

  // ── Stop counts auto-refresh ──────────────────────────────
  Timer? _stopRefreshTimer;

  // ── Alexandria bounding box ───────────────────────────────
  static bool _isValidPosition(double lat, double lng) =>
      lat >= 30.8 && lat <= 31.6 && lng >= 29.4 && lng <= 30.6;

  @override
  void initState() {
    super.initState();
    _pixelRatio = WidgetsBinding.instance.platformDispatcher.views.first.devicePixelRatio;
    _buildBusIcon().catchError((e) {
      debugPrint('⚠️ Bus icon build failed: $e');
    });
    _startListening();
    // Start 30-second auto-refresh for stop passenger counts
    WidgetsBinding.instance.addPostFrameCallback((_) => _startStopRefresh());
  }

  @override
  void dispose() {
    _stopRefreshTimer?.cancel();
    _animTimer?.cancel();
    _posSub?.cancel();
    _mapController?.dispose();
    super.dispose();
  }

  void _startStopRefresh() {
    _stopRefreshTimer = Timer.periodic(const Duration(seconds: 30), (_) {
      if (!mounted) return;
      final trip = ref.read(activeTripProvider).assignment;
      if (trip != null) {
        // Refresh per-trip stops AND chain-aware stops so both the
        // single-line and the multi-line views stay current.
        ref.invalidate(tripStopCountsProvider(trip.tripId));
        ref.invalidate(chainStopCountsProvider(trip.tripId));
      }
    });
  }

  /// Seeds [activeExtendedChildrenProvider] from the backend on screen
  /// mount. Without this, killing the app mid-chain wipes the strip even
  /// though the chain is still running in DB. Called once after first
  /// build with a non-null active trip.
  bool _childrenSeeded = false;
  void _seedExtendedChildrenIfNeeded(int rootTripId) {
    if (_childrenSeeded) return;
    _childrenSeeded = true;
    Future.microtask(() async {
      if (!mounted) return;
      final children = await ApiService.instance.fetchExtensionChain(rootTripId);
      if (!mounted || children.isEmpty) return;
      // Don't clobber if the user just extended manually (provider already
      // populated). Merge by trip_id so the user's optimistic add survives.
      final existing = ref.read(activeExtendedChildrenProvider);
      final seenIds  = existing.map((c) => c.tripId).toSet();
      final merged   = [
        ...existing,
        ...children.where((c) => !seenIds.contains(c.tripId)),
      ];
      ref.read(activeExtendedChildrenProvider.notifier).state = merged;
    });
  }

  // ── Build bus icon ────────────────────────────────────────
  Future<void> _buildBusIcon() async {
    const int size = 100;
    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));

    canvas.drawCircle(const Offset(size / 2, size / 2 + 3), size / 2 - 4,
        Paint()..color = Colors.black.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 6));
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 5,
        Paint()..color = AppColors.orange);
    canvas.drawCircle(const Offset(size / 2, size / 2), size / 2 - 5,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 4);

    final iconData = Icons.directions_bus_rounded;
    final builder  = ui.ParagraphBuilder(ui.ParagraphStyle(fontFamily: iconData.fontFamily, fontSize: 48))
      ..pushStyle(ui.TextStyle(color: Colors.white, fontSize: 48, fontFamily: iconData.fontFamily))
      ..addText(String.fromCharCode(iconData.codePoint));
    final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: size.toDouble()));
    canvas.drawParagraph(paragraph,
        Offset((size - paragraph.longestLine) / 2, (size - paragraph.height) / 2));

    final img  = await recorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data != null && mounted) {
      setState(() => _busIcon = BitmapDescriptor.bytes(
        data.buffer.asUint8List(),
        imagePixelRatio: _pixelRatio,
      ));
    }
  }

  // ── Build stop icon with count badge ─────────────────────
  Future<BitmapDescriptor?> _buildStopIcon(int count, Color color) async {
    const int size  = 80;
    const double cx = size / 2;
    const double r  = size * 0.35;

    final recorder = ui.PictureRecorder();
    final canvas   = Canvas(recorder, Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()));

    // Shadow
    canvas.drawCircle(Offset(cx, cx + 3), r,
        Paint()..color = Colors.black.withValues(alpha: 0.2)..maskFilter = const MaskFilter.blur(BlurStyle.normal, 5));
    // Fill
    canvas.drawCircle(Offset(cx, cx), r, Paint()..color = color);
    // White border
    canvas.drawCircle(Offset(cx, cx), r,
        Paint()..color = Colors.white..style = PaintingStyle.stroke..strokeWidth = 3);

    // Count text
    final text = count.toString();
    final builder = ui.ParagraphBuilder(
      ui.ParagraphStyle(fontFamily: 'Cairo', fontSize: 22, textAlign: TextAlign.center),
    )
      ..pushStyle(ui.TextStyle(
        color: Colors.white, fontSize: 22,
        fontWeight: FontWeight.w900,
      ))
      ..addText(text);
    final paragraph = builder.build()..layout(ui.ParagraphConstraints(width: size.toDouble()));
    canvas.drawParagraph(paragraph,
        Offset(0, cx - paragraph.height / 2));

    final img  = await recorder.endRecording().toImage(size, size);
    final data = await img.toByteData(format: ui.ImageByteFormat.png);
    if (data != null) {
      return BitmapDescriptor.bytes(
        data.buffer.asUint8List(),
        imagePixelRatio: _pixelRatio,
      );
    }
    return null;
  }

  // ── GPS listener with filter + smooth animation ───────────
  Future<void> _startListening() async {
    // Check permission before subscribing — Samsung One UI kills GPS
    // aggressively and the stream can error immediately on some devices.
    try {
      LocationPermission perm = await Geolocator.checkPermission();
      if (perm == LocationPermission.denied ||
          perm == LocationPermission.deniedForever) {
        debugPrint('⚠️ Map GPS: location permission not granted');
        return; // Map still shows with static default marker — no crash
      }

      final serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('⚠️ Map GPS: location service disabled');
        return;
      }

      _posSub = Geolocator.getPositionStream(
        locationSettings: const LocationSettings(
          accuracy:       LocationAccuracy.high,
          distanceFilter: 5,
        ),
      ).listen(
        (pos) {
          if (!mounted) return;
          if (!_isValidPosition(pos.latitude, pos.longitude)) return;
          _smoothMoveTo(LatLng(pos.latitude, pos.longitude), pos.heading);
        },
        onError: (Object e) {
          // GPS stream error (permission revoked mid-trip, service killed, etc.)
          // Log and swallow — the map continues with the last known position.
          debugPrint('❌ Map GPS stream error: $e');
        },
        cancelOnError: false, // Keep subscription alive after error
      );
    } catch (e) {
      debugPrint('❌ _startListening failed: $e');
      // Non-fatal — map renders with static default marker
    }
  }

  void _smoothMoveTo(LatLng target, double heading) {
    final now = DateTime.now();

    // Calculate animation duration from real GPS interval, capped 0.5–3s
    if (_lastFixTime != null) {
      final interval = now.difference(_lastFixTime!).inMilliseconds;
      _animDuration  = Duration(milliseconds: interval.clamp(500, 3000));
    }
    _lastFixTime = now;

    _animFrom = _displayPos;
    _animTo   = target;
    setState(() => _heading = heading);

    // Move camera to target immediately (not interpolated — map pans smoothly by itself)
    _mapController?.animateCamera(CameraUpdate.newLatLng(target));

    _animTimer?.cancel();
    final startMs = now.millisecondsSinceEpoch;
    final durMs   = _animDuration.inMilliseconds;

    _animTimer = Timer.periodic(const Duration(milliseconds: 16), (timer) {
      final elapsed = DateTime.now().millisecondsSinceEpoch - startMs;
      final t       = (elapsed / durMs).clamp(0.0, 1.0);
      final ease    = t * t * (3 - 2 * t); // smoothstep

      if (mounted) {
        setState(() {
          _displayPos = LatLng(
            _animFrom.latitude  + (_animTo.latitude  - _animFrom.latitude)  * ease,
            _animFrom.longitude + (_animTo.longitude - _animFrom.longitude) * ease,
          );
        });
      }
      if (t >= 1.0) timer.cancel();
    });
  }

  // ── Build all map markers ─────────────────────────────────
  Set<Marker> _buildMarkers(List<TripStopCount> stops) {
    final markers = <Marker>{};

    // Stop markers
    for (final stop in stops) {
      if (stop.lat == 0 || stop.lng == 0) continue;
      final icon = _stopIcons[stop.stopId];
      markers.add(Marker(
        markerId:   MarkerId('stop_${stop.stopId}'),
        position:   LatLng(stop.lat, stop.lng),
        anchor:     const Offset(0.5, 0.5),
        icon:       icon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueBlue),
        infoWindow: InfoWindow(
          title:   stop.nameAr,
          snippet: '${stop.count} راكب',
        ),
      ));
    }

    // Bus marker (smooth animated position)
    markers.add(Marker(
      markerId: const MarkerId('bus'),
      position: _displayPos,
      rotation: _heading,
      anchor:   const Offset(0.5, 0.5),
      icon:     _busIcon ?? BitmapDescriptor.defaultMarkerWithHue(BitmapDescriptor.hueOrange),
      infoWindow: const InfoWindow(title: 'موقع الباص'),
    ));

    return markers;
  }

  // ── Rebuild stop icons whenever count changes ─────────────
  Future<void> _ensureStopIcons(List<TripStopCount> stops) async {
    for (final stop in stops) {
      // Skip only if icon exists AND count hasn't changed
      if (_stopIcons.containsKey(stop.stopId) &&
          _stopIconCounts[stop.stopId] == stop.count) continue;
      try {
        final color = stop.count == 0 ? Colors.grey.shade400 : AppColors.blue;
        final icon  = await _buildStopIcon(stop.count, color);
        if (icon != null && mounted) {
          setState(() {
            _stopIcons[stop.stopId]     = icon;
            _stopIconCounts[stop.stopId] = stop.count;
          });
        }
      } catch (e) {
        debugPrint('⚠️ Stop icon build failed for stop ${stop.stopId}: $e');
        // Non-fatal — falls back to defaultMarkerWithHue in _buildMarkers
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final activeState = ref.watch(activeTripProvider);
    final trip = activeState.assignment;

    if (trip == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => context.go('/trips'));
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Seed the chain children list once on mount so the linked-extension
    // strip repopulates after app kill / cold resume.
    _seedExtendedChildrenIfNeeded(trip.tripId);

    final chainStopsAsync = ref.watch(chainStopCountsProvider(trip.tripId));
    // Fall back to single-trip stops when the chain endpoint isn't ready
    // yet so the screen never blank-flashes.
    final fallbackStopsAsync = ref.watch(tripStopCountsProvider(trip.tripId));

    // Flatten the chain into a single stop list for the legacy map markers.
    // Each TripStopCount keeps its own (lat, lng) so markers still render
    // correctly across lines.
    final chainGroups   = chainStopsAsync.valueOrNull ?? const [];
    final flattenedStops = chainGroups.expand((g) => g.stops).toList();
    final stops = flattenedStops.isNotEmpty
        ? flattenedStops
        : (fallbackStopsAsync.valueOrNull ?? const []);

    // Rebuild stop icons when data arrives or changes
    if (flattenedStops.isNotEmpty) {
      _ensureStopIcons(flattenedStops);
    } else {
      fallbackStopsAsync.whenData(_ensureStopIcons);
    }

    final dirColor = trip.isToClub ? AppColors.orange : AppColors.green;

    final extensionOptionsAsync = ref.watch(extensionOptionsProvider(trip.tripId));
    final extendedChildren      = ref.watch(activeExtendedChildrenProvider);

    return Scaffold(
      backgroundColor: const Color(0xFFF2EFE9),
      body: Column(children: [

        // ── Top bar ───────────────────────────────────────────
        _TopBar(trip: trip),

        // ── Map (compact) ─────────────────────────────────────
        SizedBox(
          height: 220,
          child: GoogleMap(
            onMapCreated: (ctrl) {
              _mapController = ctrl;
              _mapController!.animateCamera(
                CameraUpdate.newLatLngZoom(_displayPos, 14),
              );
            },
            initialCameraPosition: CameraPosition(target: _displayPos, zoom: 14),
            myLocationEnabled:       false,
            myLocationButtonEnabled: false,
            zoomControlsEnabled:     false,
            mapToolbarEnabled:       false,
            markers: _buildMarkers(stops),
          ),
        ),

        // ── Stats row ─────────────────────────────────────────
        Container(
          margin: const EdgeInsets.fromLTRB(14, 10, 14, 0),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(16),
            boxShadow: const [BoxShadow(color: Color(0x18032B52), blurRadius: 10)],
          ),
          child: Row(
            textDirection: TextDirection.rtl,
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _stat(Icons.access_time, trip.displayTime, 'وقت الانطلاق', AppColors.blue),
              _stat(Icons.event_seat, '${trip.bookedCount}', 'ركاب', dirColor),
              _stat(
                trip.isToClub ? Icons.arrow_downward : Icons.arrow_upward,
                trip.isToClub ? 'ذهاب' : 'عودة',
                'الاتجاه',
                dirColor,
              ),
            ],
          ),
        ),

        // ── Extension chain (parallel multi-line) ─────────────
        // Only renders when the backend allow-list returns ≥1 option, OR
        // the driver has already extended into one or more children. No-op
        // (zero-height) when the trip has no extension config.
        _ExtendStrip(
          sourceTrip: trip,
          options: extensionOptionsAsync.valueOrNull ?? const [],
          activeChildren: extendedChildren,
        ),

        // ── Stop list with counts ──────────────────────────────
        // When chain has descendants, render one section per line with
        // its own stops + counts. Single-line trips fall back to the
        // legacy flat list (renders identically to before).
        Expanded(
          child: chainGroups.length > 1
              ? _ChainStopList(groups: chainGroups)
              : stops.isEmpty
                  ? const Center(child: Text(
                      'جاري تحميل المحطات...',
                      style: TextStyle(fontFamily: 'Cairo', color: Color(0xFF8A9BB0)),
                    ))
                  : ListView.builder(
                      padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
                      itemCount: stops.length,
                      itemBuilder: (context, i) => _StopCard(
                        stop: stops[i],
                        isFirst: i == 0,
                        isLast: i == stops.length - 1,
                      ),
                    ),
        ),
      ]),

      // ── End trip FAB ──────────────────────────────────────
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _confirmEnd(context, ref),
        backgroundColor: AppColors.red,
        icon: const Icon(Icons.stop_circle_outlined, color: Colors.white),
        label: const Text('إنهاء الرحلة',
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800, color: Colors.white)),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.centerFloat,
    );
  }

  Widget _stat(IconData icon, String value, String label, Color color) => Column(children: [
    Container(
      width: 40, height: 40,
      decoration: BoxDecoration(color: color.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(10)),
      child: Icon(icon, color: color, size: 18),
    ),
    const SizedBox(height: 4),
    Text(value, style: TextStyle(fontFamily: 'Cairo', fontSize: 14, fontWeight: FontWeight.w900, color: color)),
    Text(label, style: const TextStyle(fontFamily: 'Cairo', fontSize: 10, color: Color(0xFF8A9BB0))),
  ]);

  void _confirmEnd(BuildContext context, WidgetRef ref) {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: const Text('إنهاء الرحلة', textAlign: TextAlign.right,
            style: TextStyle(fontFamily: 'Cairo', fontWeight: FontWeight.w800)),
        content: const Text('هل أنت متأكد؟ سيتوقف بث الموقع.', textAlign: TextAlign.right,
            style: TextStyle(fontFamily: 'Cairo', fontSize: 13)),
        actionsAlignment: MainAxisAlignment.center,
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء', style: TextStyle(fontFamily: 'Cairo', color: Color(0xFF8A9BB0))),
          ),
          ElevatedButton(
            onPressed: () async {
              Navigator.pop(context);
              final linked = await ref.read(activeTripProvider.notifier).endTrip();
              if (!context.mounted) return;
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
            child: const Text('نعم',
                style: TextStyle(fontFamily: 'Cairo', color: Colors.white, fontWeight: FontWeight.w800)),
          ),
        ],
      ),
    );
  }
}

// ── Top bar widget ────────────────────────────────────────────────────────────

class _TopBar extends StatelessWidget {
  final dynamic trip;
  const _TopBar({required this.trip});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: const BoxDecoration(gradient: AppColors.appBarGradient),
      child: SafeArea(
        bottom: false,
        child: Column(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 10, 16, 12),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                GestureDetector(
                  onTap: () => context.pop(),
                  child: Container(
                    width: 34, height: 34,
                    decoration: BoxDecoration(
                        color: AppColors.white10, borderRadius: BorderRadius.circular(9)),
                    child: const Icon(Icons.arrow_forward_ios, color: Colors.white, size: 16),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(trip.routeNameAr,
                          style: const TextStyle(
                              fontFamily: 'Cairo', fontSize: 16,
                              fontWeight: FontWeight.w800, color: Colors.white)),
                      Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                        Container(
                          width: 8, height: 8,
                          decoration: BoxDecoration(
                            color: AppColors.green,
                            shape: BoxShape.circle,
                            boxShadow: [BoxShadow(color: AppColors.green.withValues(alpha: 0.6), blurRadius: 6)],
                          ),
                        ),
                        const SizedBox(width: 5),
                        const Text('بث مباشر',
                            style: TextStyle(
                                fontFamily: 'Cairo', fontSize: 11,
                                color: AppColors.green, fontWeight: FontWeight.w700)),
                      ]),
                    ],
                  ),
                ),
              ],
            ),
          ),
          Container(height: 3, decoration: const BoxDecoration(gradient: AppColors.greenLineGradient)),
        ]),
      ),
    );
  }
}

// ── Stop card widget ──────────────────────────────────────────────────────────

class _StopCard extends StatelessWidget {
  final TripStopCount stop;
  final bool isFirst;
  final bool isLast;

  const _StopCard({required this.stop, required this.isFirst, required this.isLast});

  @override
  Widget build(BuildContext context) {
    final hasPassengers = stop.count > 0;
    final dotColor      = isFirst
        ? AppColors.orange
        : hasPassengers
            ? AppColors.blue
            : Colors.grey.shade300;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // Timeline column
        Column(children: [
          Container(
            width: 30, height: 30,
            decoration: BoxDecoration(color: dotColor, shape: BoxShape.circle),
            child: Center(
              child: Text('${stop.stopOrder}',
                  style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w900, fontSize: 11)),
            ),
          ),
          if (!isLast)
            Container(width: 2, height: 36, color: AppColors.blue.withValues(alpha: 0.12)),
        ]),
        const SizedBox(width: 10),
        // Card
        Expanded(
          child: Container(
            margin: const EdgeInsets.only(bottom: 8),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(12),
              boxShadow: const [BoxShadow(color: Color(0x12032B52), blurRadius: 8)],
            ),
            child: Row(
              textDirection: TextDirection.rtl,
              children: [
                Expanded(
                  child: Text(stop.nameAr,
                      style: const TextStyle(
                          fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w700)),
                ),
                // Passenger count badge
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: hasPassengers
                        ? AppColors.blue.withValues(alpha: 0.1)
                        : Colors.grey.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    textDirection: TextDirection.rtl,
                    children: [
                      Icon(Icons.person_outlined, size: 13,
                          color: hasPassengers ? AppColors.blue : Colors.grey),
                      const SizedBox(width: 3),
                      Text(
                        hasPassengers ? '${stop.count} راكب' : 'لا يوجد',
                        style: TextStyle(
                          fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w700,
                          color: hasPassengers ? AppColors.blue : Colors.grey,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

// ── Extension strip (parallel multi-line activation) ─────────────────────────
//
// Sits between the stats row and the stop list. Renders nothing (zero
// height) when the active trip has no extension allow-list configured AND
// no children have been activated yet — so trips without this feature look
// exactly the same as before.

class _ExtendStrip extends ConsumerWidget {
  final TripAssignment sourceTrip;
  final List<ExtensionOption> options;
  final List<ExtensionOption> activeChildren;

  const _ExtendStrip({
    required this.sourceTrip,
    required this.options,
    required this.activeChildren,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    if (options.isEmpty && activeChildren.isEmpty) {
      return const SizedBox.shrink();
    }

    return Container(
      margin: const EdgeInsets.fromLTRB(14, 8, 14, 0),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        boxShadow: const [BoxShadow(color: Color(0x12032B52), blurRadius: 8)],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Active children — already extended into
          if (activeChildren.isNotEmpty) ...[
            ...activeChildren.map(_activeChildRow),
            const SizedBox(height: 6),
          ],

          // Extend button — only when at least one option is available
          if (options.isNotEmpty)
            ElevatedButton.icon(
              onPressed: () => _openPicker(context, ref),
              icon: const Icon(Icons.add_road, size: 18, color: Colors.white),
              label: Text(
                activeChildren.isEmpty
                    ? 'تمديد إلى خط آخر'
                    : 'تمديد إلى خط إضافي',
                style: const TextStyle(
                    fontFamily: 'Cairo', fontWeight: FontWeight.w800, color: Colors.white),
              ),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.blue,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                minimumSize: const Size.fromHeight(40),
              ),
            ),
        ],
      ),
    );
  }

  Widget _activeChildRow(ExtensionOption child) {
    Color? parsedColor;
    try {
      final hex = child.routeColor.replaceFirst('#', '');
      parsedColor = Color(int.parse('FF$hex', radix: 16));
    } catch (_) { /* fallback to AppColors.blue below */ }
    final color = parsedColor ?? AppColors.blue;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        textDirection: TextDirection.rtl,
        children: [
          Container(
            width: 28, height: 28,
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Icon(Icons.alt_route, size: 16, color: color),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              'مرتبطة: ${child.routeNameAr}',
              style: const TextStyle(
                  fontFamily: 'Cairo', fontSize: 13, fontWeight: FontWeight.w800),
            ),
          ),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${child.bookedCount}/${child.maxPassengers}',
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, fontWeight: FontWeight.w800, color: color),
            ),
          ),
        ],
      ),
    );
  }

  void _openPicker(BuildContext context, WidgetRef ref) {
    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(18)),
      ),
      builder: (_) => _ExtendPicker(sourceTrip: sourceTrip, options: options),
    );
  }
}

class _ExtendPicker extends ConsumerStatefulWidget {
  final TripAssignment sourceTrip;
  final List<ExtensionOption> options;
  const _ExtendPicker({required this.sourceTrip, required this.options});

  @override
  ConsumerState<_ExtendPicker> createState() => _ExtendPickerState();
}

class _ExtendPickerState extends ConsumerState<_ExtendPicker> {
  bool _busy = false;
  int? _busyTargetId;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Container(
              width: 40, height: 4,
              margin: const EdgeInsets.only(bottom: 12),
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(4),
              ),
            ),
            const Text('تمديد الرحلة',
                textAlign: TextAlign.right,
                style: TextStyle(
                    fontFamily: 'Cairo', fontSize: 16, fontWeight: FontWeight.w800)),
            const SizedBox(height: 4),
            const Text(
              'اختر الخط الذي تودّ تمديد الرحلة إليه. سيتم تفعيل البث الحي '
              'لعملاء الخط فور التمديد.',
              textAlign: TextAlign.right,
              style: TextStyle(
                  fontFamily: 'Cairo', fontSize: 12, color: Color(0xFF8A9BB0)),
            ),
            const SizedBox(height: 12),
            ...widget.options.map((opt) {
              final loadingThis = _busy && _busyTargetId == opt.tripId;
              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: InkWell(
                  onTap: _busy ? null : () => _doExtend(opt),
                  borderRadius: BorderRadius.circular(12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      border: Border.all(color: Colors.grey.shade200),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Row(
                      textDirection: TextDirection.rtl,
                      children: [
                        Container(
                          width: 36, height: 36,
                          decoration: BoxDecoration(
                            color: AppColors.blue.withValues(alpha: 0.10),
                            borderRadius: BorderRadius.circular(9),
                          ),
                          child: const Icon(Icons.alt_route, color: AppColors.blue, size: 19),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.end,
                            children: [
                              Text(opt.routeNameAr,
                                  style: const TextStyle(
                                      fontFamily: 'Cairo',
                                      fontSize: 14,
                                      fontWeight: FontWeight.w800)),
                              Text(
                                '${opt.displayTime}  ·  ${opt.bookedCount}/${opt.maxPassengers} ركاب',
                                style: const TextStyle(
                                    fontFamily: 'Cairo',
                                    fontSize: 12,
                                    color: Color(0xFF8A9BB0)),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 8),
                        loadingThis
                            ? const SizedBox(
                                width: 18, height: 18,
                                child: CircularProgressIndicator(strokeWidth: 2))
                            : const Icon(Icons.chevron_left, color: AppColors.blue),
                      ],
                    ),
                  ),
                ),
              );
            }),
          ],
        ),
      ),
    );
  }

  Future<void> _doExtend(ExtensionOption opt) async {
    setState(() {
      _busy = true;
      _busyTargetId = opt.tripId;
    });
    try {
      await ApiService.instance.extendTrip(
        sourceTripId: widget.sourceTrip.tripId,
        targetTripId: opt.tripId,
      );

      // Add to active children list (consumed by the strip widget). The
      // booked_count we put here is the snapshot at extend-time; the next
      // periodic refresh of the options provider will replace it.
      final currentChildren = ref.read(activeExtendedChildrenProvider);
      ref.read(activeExtendedChildrenProvider.notifier).state = [
        ...currentChildren,
        opt,
      ];

      // Refresh extension options (the just-extended target should drop out)
      // and the trip lists so badges elsewhere update.
      ref.invalidate(extensionOptionsProvider(widget.sourceTrip.tripId));
      ref.invalidate(allTripsProvider);
      ref.invalidate(tripsProvider);

      if (!mounted) return;
      Navigator.of(context).pop();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم التمديد إلى ${opt.routeNameAr}',
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      setState(() { _busy = false; _busyTargetId = null; });
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(formatApiError(e),
              style: const TextStyle(fontFamily: 'Cairo')),
          backgroundColor: AppColors.red,
        ),
      );
    }
  }
}

// ── Chain stop list — line-grouped sections ─────────────────────────────────
//
// Renders one section per line in an active extension chain (root + each
// descendant), with the section header showing the line name + booked/
// max total, and the line's stops listed inside. Used in place of the
// legacy flat list when the active trip has been extended.

class _ChainStopList extends StatelessWidget {
  final List<ChainLineStops> groups;
  const _ChainStopList({required this.groups});

  Color _parseRouteColor(String hex) {
    try {
      final clean = hex.replaceFirst('#', '');
      return Color(int.parse('FF$clean', radix: 16));
    } catch (_) {
      return AppColors.blue;
    }
  }

  @override
  Widget build(BuildContext context) {
    return ListView.builder(
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 100),
      itemCount: groups.length,
      itemBuilder: (context, gi) {
        final group = groups[gi];
        final color = _parseRouteColor(group.routeColor);
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Section header — line name + booked/max
            Padding(
              padding: EdgeInsets.only(top: gi == 0 ? 0 : 14, bottom: 8),
              child: Row(
                textDirection: TextDirection.rtl,
                children: [
                  Container(
                    width: 28, height: 28,
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(7),
                    ),
                    child: Icon(
                      group.isRoot ? Icons.directions_bus_rounded : Icons.alt_route,
                      color: color, size: 16,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      group.isRoot
                          ? group.routeNameAr
                          : '${group.routeNameAr} (تمديد)',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 13,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${group.bookedCount}/${group.maxPassengers}',
                      style: TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: 12,
                        fontWeight: FontWeight.w800,
                        color: color,
                      ),
                    ),
                  ),
                ],
              ),
            ),
            // Stops within this line
            if (group.stops.isEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 10, right: 12),
                child: Text(
                  'لا توجد محطات بحجوزات',
                  textDirection: TextDirection.rtl,
                  style: TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: 11,
                    color: const Color(0xFF8A9BB0),
                  ),
                ),
              )
            else
              ...List.generate(group.stops.length, (i) => _StopCard(
                stop: group.stops[i],
                isFirst: i == 0,
                isLast: i == group.stops.length - 1,
              )),
          ],
        );
      },
    );
  }
}

