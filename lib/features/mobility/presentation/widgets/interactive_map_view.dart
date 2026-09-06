// lib/features/mobility/presentation/widgets/interactive_map_view.dart
// ═══════════════════════════════════════════════════════════════════════
// VEKTOLUX — Production Interactive Map SDK View
// Powered by flutter_map & OpenStreetMap with dynamic OSRM routing,
// live turn-by-turn polylines, animated markers, and real-time ETAs.
// ═══════════════════════════════════════════════════════════════════════

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';

import '../../../../core/theme/app_colors.dart';
import '../../data/services/routing_service.dart';
import '../../domain/entities/mobility_vehicle_entity.dart';
import '../../domain/entities/nearby_driver_entity.dart';
import '../../domain/entities/nearby_seller_entity.dart';
import 'smooth_driver_marker.dart';

class InteractiveMapView extends StatefulWidget {
  final double pickupLat;
  final double pickupLng;
  final double dropoffLat;
  final double dropoffLng;
  final List<VehicleListingEntity> nearbyVehicles;
  final List<NearbyDriverEntity> onDemandDrivers;
  final List<NearbySellerEntity> nearbySellers;
  final String? currentUserAvatarUrl;
  final bool showRoute;
  final bool isPinDragMode;
  final double? assignedDriverLat;
  final double? assignedDriverLng;
  final double? assignedDriverBearing;
  final String? assignedDriverCategory;
  final String? assignedDriverName;
  final String? assignedDriverPlate;
  final String? selectedCategory;
  final VoidCallback? onMapTap;
  final ValueChanged<RouteDetails>? onRouteCalculated;
  final ValueChanged<NearbyDriverEntity>? onDriverTap;
  final ValueChanged<NearbySellerEntity>? onSellerTap;
  final ValueChanged<VehicleListingEntity>? onVehicleTap;
  final ValueChanged<LatLng>? onPickupPositionChanged;
  final VoidCallback? onConfirmPinSpot;

  const InteractiveMapView({
    super.key,
    required this.pickupLat,
    required this.pickupLng,
    required this.dropoffLat,
    required this.dropoffLng,
    this.nearbyVehicles = const [],
    this.onDemandDrivers = const [],
    this.nearbySellers = const [],
    this.currentUserAvatarUrl,
    this.showRoute = true,
    this.isPinDragMode = false,
    this.assignedDriverLat,
    this.assignedDriverLng,
    this.assignedDriverBearing,
    this.assignedDriverCategory,
    this.assignedDriverName,
    this.assignedDriverPlate,
    this.selectedCategory,
    this.onMapTap,
    this.onRouteCalculated,
    this.onDriverTap,
    this.onSellerTap,
    this.onVehicleTap,
    this.onPickupPositionChanged,
    this.onConfirmPinSpot,
  });

  @override
  State<InteractiveMapView> createState() => _InteractiveMapViewState();
}

class _InteractiveMapViewState extends State<InteractiveMapView>
    with TickerProviderStateMixin {
  late final MapController _mapController;
  final RoutingService _routingService = RoutingService();
  late final AnimationController _pulseController;
  late final AnimationController _driverInterpolationController;

  RouteDetails _currentRoute = RouteDetails.empty();
  bool _isLoadingRoute = false;

  // Smooth driver marker interpolation state
  LatLng? _currentDriverPosition;
  LatLng? _prevDriverPosition;
  LatLng? _targetDriverPosition;
  double _currentBearing = 0.0;
  double _prevBearing = 0.0;
  double _targetBearing = 0.0;

  LatLng get _pickup => LatLng(widget.pickupLat, widget.pickupLng);
  LatLng get _dropoff => LatLng(widget.dropoffLat, widget.dropoffLng);

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _pulseController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1800),
    )..repeat(reverse: true);

    _driverInterpolationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 1200),
    );

    if (widget.assignedDriverLat != null && widget.assignedDriverLng != null) {
      final initialPos = LatLng(widget.assignedDriverLat!, widget.assignedDriverLng!);
      _currentDriverPosition = initialPos;
      _prevDriverPosition = initialPos;
      _targetDriverPosition = initialPos;
      _currentBearing = widget.assignedDriverBearing ?? 0.0;
      _prevBearing = _currentBearing;
      _targetBearing = _currentBearing;
    }

    _driverInterpolationController.addListener(() {
      if (_prevDriverPosition != null && _targetDriverPosition != null) {
        final t = CurvedAnimation(
          parent: _driverInterpolationController,
          curve: Curves.easeInOut,
        ).value;
        setState(() {
          _currentDriverPosition = GeoBearingHelper.lerpLatLng(
            _prevDriverPosition!,
            _targetDriverPosition!,
            t,
          );
          _currentBearing = GeoBearingHelper.lerpAngle(
            _prevBearing,
            _targetBearing,
            t,
          );
        });
      }
    });

    _calculateAndFitRoute();
  }

  @override
  void didUpdateWidget(covariant InteractiveMapView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.selectedCategory != widget.selectedCategory ||
        oldWidget.pickupLat != widget.pickupLat ||
        oldWidget.pickupLng != widget.pickupLng ||
        oldWidget.dropoffLat != widget.dropoffLat ||
        oldWidget.dropoffLng != widget.dropoffLng ||
        oldWidget.showRoute != widget.showRoute) {
      _calculateAndFitRoute();
    }

    // Handle assigned driver coordinate updates with smooth interpolation
    if (widget.assignedDriverLat != null && widget.assignedDriverLng != null) {
      final newTarget = LatLng(widget.assignedDriverLat!, widget.assignedDriverLng!);
      if (_targetDriverPosition == null) {
        _currentDriverPosition = newTarget;
        _prevDriverPosition = newTarget;
        _targetDriverPosition = newTarget;
        _currentBearing = widget.assignedDriverBearing ?? 0.0;
        _prevBearing = _currentBearing;
        _targetBearing = _currentBearing;
      } else if (newTarget.latitude != _targetDriverPosition!.latitude ||
          newTarget.longitude != _targetDriverPosition!.longitude) {
        _prevDriverPosition = _currentDriverPosition ?? _targetDriverPosition!;
        _targetDriverPosition = newTarget;
        _prevBearing = _currentBearing;
        _targetBearing = widget.assignedDriverBearing ??
            GeoBearingHelper.calculateBearing(_prevDriverPosition!, _targetDriverPosition!);
        _driverInterpolationController.forward(from: 0.0);
      }
    }
  }

  @override
  void dispose() {
    _mapController.dispose();
    _pulseController.dispose();
    _driverInterpolationController.dispose();
    super.dispose();
  }

  Future<void> _calculateAndFitRoute() async {
    if (!widget.showRoute) return;

    setState(() => _isLoadingRoute = true);

    try {
      final route = await _routingService.getDirections(_pickup, _dropoff);
      if (mounted) {
        setState(() {
          _currentRoute = route;
          _isLoadingRoute = false;
        });

        widget.onRouteCalculated?.call(route);

        // Auto-fit bounds
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (!mounted) return;
          try {
            final boundPoints = [
              _pickup,
              _dropoff,
              if (_currentDriverPosition != null) _currentDriverPosition!,
              ...route.points,
            ];
            final bounds = LatLngBounds.fromPoints(boundPoints);
            _mapController.fitCamera(
              CameraFit.bounds(
                bounds: bounds,
                padding: const EdgeInsets.only(
                  top: 90,
                  bottom: 260,
                  left: 40,
                  right: 40,
                ),
              ),
            );
          } catch (_) {}
        });
      }
    } catch (_) {
      if (mounted) setState(() => _isLoadingRoute = false);
    }
  }

  void _zoomIn() {
    final zoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, zoom + 1);
  }

  void _zoomOut() {
    final zoom = _mapController.camera.zoom;
    _mapController.move(_mapController.camera.center, zoom - 1);
  }

  void _recenterOnPickup() {
    _mapController.move(_pickup, 15.0);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        // ── 1. Real Tile Map Layer ──────────────────────────────────
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _pickup,
            initialZoom: 14.2,
            minZoom: 4.0,
            maxZoom: 18.0,
            cameraConstraint: CameraConstraint.contain(
              bounds: LatLngBounds(
                const LatLng(6.85, -13.55),
                const LatLng(10.15, -10.20),
              ),
            ),
            onTap: (_, point) {
              if (widget.isPinDragMode) {
                widget.onPickupPositionChanged?.call(point);
              } else {
                widget.onMapTap?.call();
              }
            },
          ),
          children: [
            // Standard OSM OpenStreetMap tile layer
            TileLayer(
              urlTemplate: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
              userAgentPackageName: 'com.vektolux.app',
              maxZoom: 19,
            ),

            // Dynamic Road Polyline Layer
            if (widget.showRoute && _currentRoute.points.isNotEmpty) ...[
              // Outer glow / outline
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _currentRoute.points,
                    color: AppColors.obsidian.withValues(alpha: 0.35),
                    strokeWidth: 7.0,
                  ),
                ],
              ),
              // Main road path
              PolylineLayer(
                polylines: [
                  Polyline(
                    points: _currentRoute.points,
                    color: AppColors.emerald,
                    strokeWidth: 4.5,
                  ),
                ],
              ),
            ],

            // Markers: Pickup, Dropoff, Nearby Fleet Drivers
            MarkerLayer(
              markers: [
                // ── A. Pickup Marker with animated pulse ring ─────────
                Marker(
                  point: _pickup,
                  width: 60,
                  height: 60,
                  child: AnimatedBuilder(
                    animation: _pulseController,
                    builder: (context, child) {
                      return Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 24 + (_pulseController.value * 24),
                            height: 24 + (_pulseController.value * 24),
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: AppColors.emerald.withValues(
                                alpha: 0.35 * (1 - _pulseController.value),
                              ),
                            ),
                          ),
                          Container(
                            width: 34,
                            height: 34,
                            decoration: BoxDecoration(
                              color: AppColors.emerald,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.white, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: (widget.currentUserAvatarUrl != null &&
                                      widget.currentUserAvatarUrl!.isNotEmpty)
                                  ? Image.network(
                                      widget.currentUserAvatarUrl!,
                                      width: 34,
                                      height: 34,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Icon(
                                        Icons.my_location_rounded,
                                        size: 17,
                                        color: AppColors.white,
                                      ),
                                    )
                                  : const Icon(
                                      Icons.my_location_rounded,
                                      size: 17,
                                      color: AppColors.white,
                                    ),
                            ),
                          ),
                        ],
                      );
                    },
                  ),
                ),

                // ── B. Dropoff Destination Pin ────────────────────────
                if (widget.showRoute)
                  Marker(
                    point: _dropoff,
                    width: 44,
                    height: 44,
                    child: Container(
                      decoration: BoxDecoration(
                        color: AppColors.obsidian,
                        shape: BoxShape.circle,
                        border: Border.all(color: AppColors.white, width: 2.5),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.25),
                            blurRadius: 6,
                            offset: const Offset(0, 3),
                          ),
                        ],
                      ),
                      child: const Icon(
                        Icons.location_on_rounded,
                        size: 22,
                        color: AppColors.emerald,
                      ),
                    ),
                  ),

                // ── C. Nearby Fleet Drivers ───────────────────────────
                ...widget.nearbyVehicles.map((vehicle) {
                  return Marker(
                    point: LatLng(vehicle.latitude, vehicle.longitude),
                    width: 44,
                    height: 44,
                    child: GestureDetector(
                      onTap: () {
                        _mapController.move(LatLng(vehicle.latitude, vehicle.longitude), 16.0);
                        widget.onVehicleTap?.call(vehicle);
                      },
                      child: Container(
                        decoration: BoxDecoration(
                          color: AppColors.white,
                          shape: BoxShape.circle,
                          border: Border.all(color: AppColors.obsidian, width: 2),
                          boxShadow: [
                            BoxShadow(
                              color: Colors.black.withValues(alpha: 0.2),
                              blurRadius: 6,
                              offset: const Offset(0, 2),
                            ),
                          ],
                        ),
                        child: Center(
                          child: Icon(
                            vehicle.vehicleType.iconData,
                            size: 22,
                            color: AppColors.obsidian,
                          ),
                        ),
                      ),
                    ),
                  );
                }),

                // ── D. On-Demand Live Drivers (ETAs & Category Icons) ──
                ...widget.onDemandDrivers.map((driver) {
                  final isKekeh = driver.vehicle?.category == DriverVehicleCategory.kekehTricycle ||
                      driver.vehicle?.categoryIconKey == 'kekeh_tricycle';
                  final isBike = driver.vehicle?.category == DriverVehicleCategory.deliveryBike ||
                      driver.vehicle?.categoryIconKey == 'two_wheeler_delivery';
                  final pinColor = isKekeh
                      ? AppColors.amber
                      : (isBike ? const Color(0xFFF97316) : AppColors.emerald);
                  final pinIcon = isKekeh
                      ? Icons.moped_rounded
                      : (isBike ? Icons.two_wheeler_rounded : Icons.local_taxi_rounded);
                  final labelText = isKekeh
                      ? 'KEKEH ${driver.etaMinutes}m'
                      : (isBike ? 'BIKE ${driver.etaMinutes}m' : 'TAXI ${driver.etaMinutes}m');

                  return Marker(
                    point: LatLng(driver.currentLat, driver.currentLng),
                    width: 68,
                    height: 64,
                    child: GestureDetector(
                      onTap: () {
                        _mapController.move(LatLng(driver.currentLat, driver.currentLng), 16.0);
                        widget.onDriverTap?.call(driver);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.obsidian,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: pinColor, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              labelText,
                              style: TextStyle(
                                color: pinColor,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: pinColor, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: (driver.avatarUrl != null && driver.avatarUrl!.isNotEmpty)
                                  ? Image.network(
                                      driver.avatarUrl!,
                                      width: 38,
                                      height: 38,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => Center(
                                        child: Icon(
                                          pinIcon,
                                          size: 19,
                                          color: AppColors.obsidian,
                                        ),
                                      ),
                                    )
                                  : Center(
                                      child: Icon(
                                        pinIcon,
                                        size: 19,
                                        color: AppColors.obsidian,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // ── E. Nearby Verified Sellers (Vendors & Merchants) ──
                ...widget.nearbySellers.map((seller) {
                  return Marker(
                    point: LatLng(seller.latitude, seller.longitude),
                    width: 72,
                    height: 66,
                    child: GestureDetector(
                      onTap: () {
                        _mapController.move(LatLng(seller.latitude, seller.longitude), 16.0);
                        widget.onSellerTap?.call(seller);
                      },
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: AppColors.obsidian,
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(color: AppColors.emerald, width: 1.2),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.3),
                                  blurRadius: 5,
                                  offset: const Offset(0, 2),
                                ),
                              ],
                            ),
                            child: Text(
                              'STORE ${seller.etaMinutes}m',
                              style: const TextStyle(
                                color: AppColors.emerald,
                                fontSize: 9.5,
                                fontWeight: FontWeight.w800,
                              ),
                            ),
                          ),
                          const SizedBox(height: 3),
                          Container(
                            width: 38,
                            height: 38,
                            decoration: BoxDecoration(
                              color: AppColors.white,
                              shape: BoxShape.circle,
                              border: Border.all(color: AppColors.emerald, width: 2.5),
                              boxShadow: [
                                BoxShadow(
                                  color: Colors.black.withValues(alpha: 0.25),
                                  blurRadius: 6,
                                  offset: const Offset(0, 3),
                                ),
                              ],
                            ),
                            child: ClipOval(
                              child: (seller.avatarUrl != null && seller.avatarUrl!.isNotEmpty)
                                  ? Image.network(
                                      seller.avatarUrl!,
                                      width: 38,
                                      height: 38,
                                      fit: BoxFit.cover,
                                      errorBuilder: (_, __, ___) => const Center(
                                        child: Icon(
                                          Icons.storefront_rounded,
                                          size: 20,
                                          color: AppColors.emerald,
                                        ),
                                      ),
                                    )
                                  : const Center(
                                      child: Icon(
                                        Icons.storefront_rounded,
                                        size: 20,
                                        color: AppColors.emerald,
                                      ),
                                    ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                }),

                // ── F. Assigned Active Driver Moving Marker ───────────
                if (_currentDriverPosition != null ||
                    (widget.assignedDriverLat != null && widget.assignedDriverLng != null))
                  Marker(
                    point: _currentDriverPosition ??
                        LatLng(widget.assignedDriverLat!, widget.assignedDriverLng!),
                    width: 70,
                    height: 70,
                    child: SmoothDriverMarker(
                      bearingDegrees: _currentBearing,
                      vehicleCategory: widget.assignedDriverCategory,
                      driverName: widget.assignedDriverName,
                      licensePlate: widget.assignedDriverPlate,
                      isLiveTracking: true,
                    ),
                  ),
              ],
            ),
          ],
        ),

        // ── 3. Quick Map Controls (Zoom & Recenter) ─────────────────
        Positioned(
          right: 16,
          top: 130,
          child: Column(
            children: [
              _buildMapButton(
                icon: Icons.add,
                onTap: _zoomIn,
                tooltip: 'Zoom in',
              ),
              const SizedBox(height: 8),
              _buildMapButton(
                icon: Icons.remove,
                onTap: _zoomOut,
                tooltip: 'Zoom out',
              ),
              const SizedBox(height: 8),
              _buildMapButton(
                icon: Icons.my_location_rounded,
                onTap: _recenterOnPickup,
                tooltip: 'Recenter pickup',
              ),
            ],
          ),
        ),

        // Loading spinner while route calculates
        if (_isLoadingRoute)
          Positioned(
            top: 130,
            right: 65,
            child: Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: AppColors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.15),
                    blurRadius: 6,
                  ),
                ],
              ),
              child: const SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: AppColors.emerald,
                ),
              ),
            ),
          ),

        // ── 4. Pin-Drag Mode Banner Overlay ─────────────────────────
        if (widget.isPinDragMode)
          Positioned(
            top: 130,
            left: 16,
            right: 65,
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: AppColors.obsidian,
                borderRadius: BorderRadius.circular(16),
                border: Border.all(color: AppColors.emerald, width: 1.5),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    blurRadius: 10,
                    offset: const Offset(0, 3),
                  ),
                ],
              ),
              child: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(6),
                    decoration: BoxDecoration(
                      color: AppColors.emerald.withValues(alpha: 0.2),
                      shape: BoxShape.circle,
                    ),
                    child: const Icon(
                      Icons.touch_app_rounded,
                      color: AppColors.emerald,
                      size: 18,
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          'Pin-Drag Mode Active',
                          style: TextStyle(
                            color: AppColors.white,
                            fontSize: 12,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                        SizedBox(height: 1),
                        Text(
                          'Tap map to place pickup pin',
                          style: TextStyle(
                            color: AppColors.gray300,
                            fontSize: 10,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    onPressed: widget.onConfirmPinSpot,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.emerald,
                      foregroundColor: AppColors.obsidian,
                      elevation: 0,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      minimumSize: Size.zero,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: const Text(
                      'Confirm',
                      style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildMapButton({
    required IconData icon,
    required VoidCallback onTap,
    required String tooltip,
  }) {
    return Container(
      width: 38,
      height: 38,
      decoration: BoxDecoration(
        color: AppColors.white,
        shape: BoxShape.circle,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.15),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: IconButton(
        padding: EdgeInsets.zero,
        icon: Icon(icon, size: 18, color: AppColors.obsidian),
        tooltip: tooltip,
        onPressed: onTap,
      ),
    );
  }
}
