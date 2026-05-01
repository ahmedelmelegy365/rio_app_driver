// lib/models/driver_models.dart

int _i(dynamic v) => v == null ? 0 : int.tryParse(v.toString()) ?? 0;
String _s(dynamic v) => v?.toString() ?? '';
bool _b(dynamic v) => v == true || v == 1 || v == '1';

// ─────────────────────────────────────────────
// Driver
// ─────────────────────────────────────────────
class DriverModel {
  final int id;
  final String name;
  final String username;
  final String? licenseNumber;
  final bool isActive;

  const DriverModel({
    required this.id,
    required this.name,
    required this.username,
    this.licenseNumber,
    required this.isActive,
  });

  factory DriverModel.fromJson(Map<String, dynamic> j) => DriverModel(
    id:            _i(j['id']),
    name:          _s(j['name']),
    username:      _s(j['username']),
    licenseNumber: j['license_number'] as String?,
    isActive:      _b(j['is_active']),
  );
}

// ─────────────────────────────────────────────
// BusModel
// ─────────────────────────────────────────────
class BusModel {
  final int id;
  final String busNumber;
  final String plate;
  final int capacity;

  const BusModel({
    required this.id,
    required this.busNumber,
    required this.plate,
    required this.capacity,
  });

  factory BusModel.fromJson(Map<String, dynamic> j) => BusModel(
    id:        _i(j['id']),
    busNumber: _s(j['bus_number']),
    plate:     _s(j['plate']),
    capacity:  _i(j['capacity']) == 0 ? 28 : _i(j['capacity']),
  );
}

// ─────────────────────────────────────────────
// TripRelationPreview — lightweight info about a related trip, used for
// rendering relationship badges (linked return source, extension source,
// extension target) on trip cards.
// ─────────────────────────────────────────────
class TripRelationPreview {
  final int tripId;
  final String tripNumber;
  final String routeNameAr;
  final String routeNameEn;
  final String routeColor;
  final String direction;
  final String departureTime;
  final String status;

  const TripRelationPreview({
    required this.tripId,
    required this.tripNumber,
    required this.routeNameAr,
    required this.routeNameEn,
    required this.routeColor,
    required this.direction,
    required this.departureTime,
    required this.status,
  });

  factory TripRelationPreview.fromJson(Map<String, dynamic> j) => TripRelationPreview(
    tripId:        _i(j['id']),
    tripNumber:    _s(j['trip_number']).isEmpty
        ? 'R-${_i(j['id'])}'
        : _s(j['trip_number']),
    routeNameAr:   _s(j['route_name_ar']),
    routeNameEn:   _s(j['route_name_en']),
    routeColor:    _s(j['route_color']).isEmpty ? '#425BD6' : _s(j['route_color']),
    direction:     _s(j['direction']).isEmpty ? 'to_club' : _s(j['direction']),
    departureTime: _s(j['departure_time']).isEmpty ? '00:00:00' : _s(j['departure_time']),
    status:        _s(j['status']).isEmpty ? 'open' : _s(j['status']),
  );

  bool get isToClub => direction == 'to_club';

  String get displayTime {
    final parts = departureTime.split(':');
    if (parts.length < 2) return departureTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final period = h >= 12 ? 'م' : 'ص';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $period';
  }
}

// ─────────────────────────────────────────────
// AllTripItem — from driver-all-trips endpoint
// ─────────────────────────────────────────────
class AllTripItem {
  final int tripId;
  final String routeNameAr;
  final String routeNameEn;
  final String routeColor;
  final String direction;
  final String departureTime;
  final int bookedCount;
  final int maxPassengers;
  final String tripStatus;
  final String tripNumber;

  // null = free, 'assigned' | 'active' | 'completed' = mine, 'assigned_to_other' = taken
  final String? assignmentStatus;
  final int? assignmentId;
  final String? firebaseTripKey;
  final bool isAssignable;
  final int? linkedTripId;

  // Relationship flags computed by the backend.
  // isLinkedReturn: this trip is the to_club partner of a from_club round-trip
  //                 pair — it auto-locks when the from_club source starts.
  // isExtensionTarget: another trip can extend INTO this one. It activates
  //                    via the source trip's extend endpoint, not direct start.
  final bool isLinkedReturn;
  final bool isExtensionTarget;
  final List<TripRelationPreview> extensionSources;  // trips that can extend INTO this
  final List<TripRelationPreview> extensionTargets;  // trips THIS trip can extend TO

  const AllTripItem({
    required this.tripId,
    required this.routeNameAr,
    required this.routeNameEn,
    required this.routeColor,
    required this.direction,
    required this.departureTime,
    required this.bookedCount,
    required this.maxPassengers,
    required this.tripStatus,
    required this.tripNumber,
    this.assignmentStatus,
    this.assignmentId,
    this.firebaseTripKey,
    required this.isAssignable,
    this.linkedTripId,
    this.isLinkedReturn = false,
    this.isExtensionTarget = false,
    this.extensionSources = const [],
    this.extensionTargets = const [],
  });

  factory AllTripItem.fromJson(Map<String, dynamic> j) => AllTripItem(
    tripId:           _i(j['trip_id']),
    routeNameAr:      _s(j['route_name_ar']),
    routeNameEn:      _s(j['route_name_en']),
    routeColor:       _s(j['route_color']).isEmpty ? '#425BD6' : _s(j['route_color']),
    direction:        _s(j['direction']).isEmpty ? 'to_club' : _s(j['direction']),
    departureTime:    _s(j['departure_time']).isEmpty ? '00:00:00' : _s(j['departure_time']),
    bookedCount:      _i(j['booked_count']),
    maxPassengers:    _i(j['max_passengers']) == 0 ? 28 : _i(j['max_passengers']),
    tripStatus:       _s(j['trip_status']).isEmpty ? 'open' : _s(j['trip_status']),
    assignmentStatus: j['assignment_status'] as String?,
    assignmentId:     j['assignment_id'] == null ? null : _i(j['assignment_id']),
    firebaseTripKey:  j['firebase_trip_key'] as String?,
    isAssignable:     _b(j['is_assignable']),
    tripNumber: _s(j['trip_number']).isEmpty
        ? 'R-${_i(j['trip_id'])}'
        : _s(j['trip_number']),
    linkedTripId: j['linked_trip_id'] == null ? null : _i(j['linked_trip_id']),
    isLinkedReturn:    _b(j['is_linked_return']),
    isExtensionTarget: _b(j['is_extension_target']),
    extensionSources: (j['extension_sources'] is List)
        ? (j['extension_sources'] as List)
            .map((e) => TripRelationPreview.fromJson(e as Map<String, dynamic>))
            .toList()
        : const [],
    extensionTargets: (j['extension_targets'] is List)
        ? (j['extension_targets'] as List)
            .map((e) => TripRelationPreview.fromJson(e as Map<String, dynamic>))
            .toList()
        : const [],
  );

  String get displayTime {
    final parts = departureTime.split(':');
    if (parts.length < 2) return departureTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final period = h >= 12 ? 'م' : 'ص';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $period';
  }

  bool get isToClub    => direction == 'to_club';
  bool get isMine      => assignmentStatus != null && assignmentStatus != 'assigned_to_other';
  bool get isTakenByOther => assignmentStatus == 'assigned_to_other';
  bool get isCompleted => assignmentStatus == 'completed';
  bool get isMyActive  => assignmentStatus == 'active';
  bool get hasLinkedTrip => linkedTripId != null;
}

// ─────────────────────────────────────────────
// TripAssignment — from driver-my-trips endpoint
// ─────────────────────────────────────────────
class TripAssignment {
  final int assignmentId;
  final int tripId;
  final String routeNameAr;
  final String routeNameEn;
  final String routeColor;
  final String direction;
  final String departureTime;
  final int bookedCount;
  final String tripStatus;
  final String assignStatus;
  final String? firebaseTripKey;
  final String? startedAt;
  final String? endedAt;
  final int? linkedTripId;

  const TripAssignment({
    required this.assignmentId,
    required this.tripId,
    required this.routeNameAr,
    required this.routeNameEn,
    required this.routeColor,
    required this.direction,
    required this.departureTime,
    required this.bookedCount,
    required this.tripStatus,
    required this.assignStatus,
    this.firebaseTripKey,
    this.startedAt,
    this.endedAt,
    this.linkedTripId,
  });

  factory TripAssignment.fromJson(Map<String, dynamic> j) => TripAssignment(
    assignmentId:    _i(j['assignment_id']),
    tripId:          _i(j['trip_id']),
    routeNameAr:     _s(j['route_name_ar']),
    routeNameEn:     _s(j['route_name_en']),
    routeColor:      _s(j['route_color']).isEmpty ? '#425BD6' : _s(j['route_color']),
    direction:       _s(j['direction']).isEmpty ? 'to_club' : _s(j['direction']),
    departureTime:   _s(j['departure_time']).isEmpty ? '00:00:00' : _s(j['departure_time']),
    bookedCount:     _i(j['booked_count']),
    tripStatus:      _s(j['trip_status']).isEmpty ? 'open' : _s(j['trip_status']),
    assignStatus:    _s(j['assign_status']).isEmpty ? 'assigned' : _s(j['assign_status']),
    firebaseTripKey: j['firebase_trip_key'] as String?,
    startedAt:       j['started_at'] as String?,
    endedAt:         j['ended_at'] as String?,
    linkedTripId:    j['linked_trip_id'] == null ? null : _i(j['linked_trip_id']),
  );

  String get displayTime {
    final parts = departureTime.split(':');
    if (parts.length < 2) return departureTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final period = h >= 12 ? 'م' : 'ص';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $period';
  }

  bool get isActive      => assignStatus == 'active';
  bool get isAssigned    => assignStatus == 'assigned';
  bool get isCompleted   => assignStatus == 'completed';
  bool get isToClub      => direction == 'to_club';
  bool get hasLinkedTrip => linkedTripId != null;
}

// ─────────────────────────────────────────────
// LinkedTripInfo — returned inside end-trip response
// when a locked to_club trip is waiting to be started
// ─────────────────────────────────────────────
class LinkedTripInfo {
  final int tripId;
  final int? assignmentId;
  final String direction;
  final String departureTime;
  final String routeNameAr;
  final String routeNameEn;
  final String routeColor;
  final int bookedCount;
  final int maxPassengers;
  final String status;
  final bool showTransition;

  const LinkedTripInfo({
    required this.tripId,
    this.assignmentId,
    required this.direction,
    required this.departureTime,
    required this.routeNameAr,
    required this.routeNameEn,
    required this.routeColor,
    required this.bookedCount,
    required this.maxPassengers,
    required this.status,
    required this.showTransition,
  });

  factory LinkedTripInfo.fromJson(Map<String, dynamic> j) => LinkedTripInfo(
    tripId:         _i(j['id']),
    assignmentId:   j['assignment_id'] == null ? null : _i(j['assignment_id']),
    direction:      _s(j['direction']).isEmpty ? 'from_club' : _s(j['direction']),
    departureTime:  _s(j['departure_time']).isEmpty ? '00:00' : _s(j['departure_time']),
    routeNameAr:    _s(j['route_name_ar']),
    routeNameEn:    _s(j['route_name_en']),
    routeColor:     _s(j['route_color']).isEmpty ? '#425BD6' : _s(j['route_color']),
    bookedCount:    _i(j['booked_count']),
    maxPassengers:  _i(j['max_passengers']) == 0 ? 28 : _i(j['max_passengers']),
    status:         _s(j['status']).isEmpty ? 'locked' : _s(j['status']),
    showTransition: _b(j['show_transition']),
  );

  String get displayTime {
    final parts = departureTime.split(':');
    if (parts.length < 2) return departureTime;
    final h  = int.tryParse(parts[0]) ?? 0;
    final m  = parts[1];
    final period = h >= 12 ? 'م' : 'ص';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $period';
  }
}

// ─────────────────────────────────────────────
// ExtensionOption — a target trip the driver may activate as an
// extension of an already-active source trip (parallel multi-line).
// Distinct from the round-trip linked_trip pair.
// ─────────────────────────────────────────────
class ExtensionOption {
  final int tripId;
  final String direction;
  final String departureTime;
  final String status;
  final int maxPassengers;
  final String routeNameAr;
  final String routeNameEn;
  final String routeColor;
  final int bookedCount;
  final int position;

  const ExtensionOption({
    required this.tripId,
    required this.direction,
    required this.departureTime,
    required this.status,
    required this.maxPassengers,
    required this.routeNameAr,
    required this.routeNameEn,
    required this.routeColor,
    required this.bookedCount,
    required this.position,
  });

  factory ExtensionOption.fromJson(Map<String, dynamic> j) => ExtensionOption(
    tripId:        _i(j['trip_id']),
    direction:     _s(j['direction']).isEmpty ? 'to_club' : _s(j['direction']),
    departureTime: _s(j['departure_time']).isEmpty ? '00:00' : _s(j['departure_time']),
    status:        _s(j['status']).isEmpty ? 'open' : _s(j['status']),
    maxPassengers: _i(j['max_passengers']) == 0 ? 28 : _i(j['max_passengers']),
    routeNameAr:   _s(j['route_name_ar']),
    routeNameEn:   _s(j['route_name_en']),
    routeColor:    _s(j['route_color']).isEmpty ? '#425BD6' : _s(j['route_color']),
    bookedCount:   _i(j['booked_count']),
    position:      _i(j['position']),
  );

  String get displayTime {
    final parts = departureTime.split(':');
    if (parts.length < 2) return departureTime;
    final h = int.tryParse(parts[0]) ?? 0;
    final m = parts[1];
    final period = h >= 12 ? 'م' : 'ص';
    final dh = h == 0 ? 12 : (h > 12 ? h - 12 : h);
    return '$dh:$m $period';
  }
}

// ─────────────────────────────────────────────
// ChainLineStops — per-line group of stops + counts for the active
// extension chain (root + descendants). The driver's tracking screen
// renders one section per line, with passengers per stop inside.
// ─────────────────────────────────────────────
class ChainLineStops {
  final int tripId;
  final bool isRoot;
  final String routeNameAr;
  final String routeNameEn;
  final String routeColor;
  final String direction;
  final int bookedCount;
  final int maxPassengers;
  final List<TripStopCount> stops;

  const ChainLineStops({
    required this.tripId,
    required this.isRoot,
    required this.routeNameAr,
    required this.routeNameEn,
    required this.routeColor,
    required this.direction,
    required this.bookedCount,
    required this.maxPassengers,
    required this.stops,
  });

  factory ChainLineStops.fromJson(Map<String, dynamic> j) => ChainLineStops(
    tripId:        _i(j['trip_id']),
    isRoot:        _b(j['is_root']),
    routeNameAr:   _s(j['route_name_ar']),
    routeNameEn:   _s(j['route_name_en']),
    routeColor:    _s(j['route_color']).isEmpty ? '#425BD6' : _s(j['route_color']),
    direction:     _s(j['direction']).isEmpty ? 'to_club' : _s(j['direction']),
    bookedCount:   _i(j['booked_count']),
    maxPassengers: _i(j['max_passengers']) == 0 ? 28 : _i(j['max_passengers']),
    stops: (j['stops'] is List)
        ? (j['stops'] as List)
            .map((e) => TripStopCount.fromJson(e as Map<String, dynamic>))
            .toList()
        : const [],
  );
}

// ─────────────────────────────────────────────
// TripStopCount — per-stop passenger count for active trip
// ─────────────────────────────────────────────
class TripStopCount {
  final int    stopId;
  final String nameAr;
  final String nameEn;
  final double lat;
  final double lng;
  final int    stopOrder;
  final int    count;

  const TripStopCount({
    required this.stopId,
    required this.nameAr,
    required this.nameEn,
    required this.lat,
    required this.lng,
    required this.stopOrder,
    required this.count,
  });

  factory TripStopCount.fromJson(Map<String, dynamic> j) => TripStopCount(
    stopId:    _i(j['id']),
    nameAr:    _s(j['name_ar']),
    nameEn:    _s(j['name_en']),
    lat:       double.tryParse(j['lat']?.toString() ?? '') ?? 0.0,
    lng:       double.tryParse(j['lng']?.toString() ?? '') ?? 0.0,
    stopOrder: _i(j['stop_order']),
    count:     _i(j['count']),
  );
}