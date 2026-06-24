import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:http/http.dart' as http;

/// InDrive-style Live Tracking Screen
/// Features:
/// - Real-time Firebase location updates
/// - Smooth chef marker animation
/// - Live route updates
/// - Distance & Time estimation
/// - Clean bottom panel UI
class IndriveLiveTrackingScreen extends StatefulWidget {
  final String chefId;
  final String chefName;
  final String? chefImage;
  final LatLng customerLocation;
  final String? bookingTime;
  final String? bookingDate;
  final VoidCallback? onChat;
  final VoidCallback? onCall;

  const IndriveLiveTrackingScreen({
    super.key,
    required this.chefId,
    required this.chefName,
    this.chefImage,
    required this.customerLocation,
    this.bookingTime,
    this.bookingDate,
    this.onChat,
    this.onCall,
  });

  @override
  State<IndriveLiveTrackingScreen> createState() => _IndriveLiveTrackingScreenState();
}

class _IndriveLiveTrackingScreenState extends State<IndriveLiveTrackingScreen>
    with TickerProviderStateMixin {

  LatLng? _chefLocation;
  List<LatLng> _routePoints = [];
  double _distanceKm = 0;
  double _estimatedMinutes = 0;
  String _statusMessage = "Loading...";
  bool _isSimulationMode = false;
  bool _isInitializing = true; // Track initial loading state

  late AnimationController _animationController;
  Animation<LatLng>? _markerAnimation;

  final MapController _mapController = MapController();
  StreamSubscription? _locationSubscription;
  Timer? _simulationTimer;
  Timer? _timeoutTimer;

  // OpenRouteService API Key (Free)
  static const String _orsApiKey = "5b3ce3597851110001cf6248b5cc8869d7f9411f94988ba7cef94e5b";

  @override
  void initState() {
    super.initState();

    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 800),
    );

    _initializeTracking();
  }

  Future<void> _initializeTracking() async {
    setState(() {
      _statusMessage = "Connecting to chef...";
      _isInitializing = true;
    });

    // Listen to chef's location from Firebase first
    _listenToChefLocation();

    // Set timeout - if no chef location in 5 seconds, start simulation
    _timeoutTimer = Timer(const Duration(seconds: 5), () {
      if (_chefLocation == null && mounted) {
        debugPrint('IndriveLiveTracking: No chef location received, starting simulation');
        _startSimulation();
      }
    });

    // Mark initialization complete after a brief delay to allow data to load
    Future.delayed(const Duration(milliseconds: 500), () {
      if (mounted) {
        setState(() {
          _isInitializing = false;
        });
      }
    });
  }


  @override
  void dispose() {
    _animationController.dispose();
    _locationSubscription?.cancel();
    _simulationTimer?.cancel();
    _timeoutTimer?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  /// Listen to chef's real-time location from Firestore
  void _listenToChefLocation() {
    debugPrint('IndriveLiveTracking: Listening to chef ${widget.chefId} location from Firestore');

    _locationSubscription = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.chefId)
        .snapshots()
        .listen((snapshot) {
      if (!snapshot.exists) {
        debugPrint('IndriveLiveTracking: Chef document does not exist');
        return;
      }

      final data = snapshot.data();
      if (data == null) {
        debugPrint('IndriveLiveTracking: Chef data is null');
        return;
      }

      // Check if chef has location data
      final lat = data['lat'];
      final lng = data['lng'];

      if (lat == null || lng == null) {
        debugPrint('IndriveLiveTracking: Chef location not available in Firestore');
        return;
      }

      // Cancel timeout and simulation if we get real data
      _timeoutTimer?.cancel();
      _simulationTimer?.cancel();
      _isSimulationMode = false;

      final newLocation = LatLng(
        (lat is num) ? lat.toDouble() : double.tryParse(lat.toString()) ?? 0,
        (lng is num) ? lng.toDouble() : double.tryParse(lng.toString()) ?? 0,
      );

      debugPrint('IndriveLiveTracking: Got chef location: ${newLocation.latitude}, ${newLocation.longitude}');

      // Validate location (not 0,0)
      if (newLocation.latitude == 0 && newLocation.longitude == 0) {
        debugPrint('IndriveLiveTracking: Invalid chef location (0,0), ignoring');
        return;
      }

      // Animate marker to new position
      _animateChefMarker(newLocation);

      // Update route
      _getRoute(newLocation);

      // Update status
      _updateStatus();
    }, onError: (error) {
      debugPrint('IndriveLiveTracking: Error listening to chef location: $error');
    });
  }

  /// Start simulation mode when no Firebase data available
  void _startSimulation() {
    if (_isSimulationMode) return;

    setState(() {
      _isSimulationMode = true;
      _statusMessage = "Demo Mode - Chef approaching";
    });

    // If no chef location yet, create one
    if (_chefLocation == null) {
      final random = Random();
      final offsetLat = (random.nextDouble() - 0.5) * 0.04;
      final offsetLng = (random.nextDouble() - 0.5) * 0.04;

      _chefLocation = LatLng(
        widget.customerLocation.latitude + offsetLat + 0.02,
        widget.customerLocation.longitude + offsetLng + 0.02,
      );
    }

    // Get initial route
    _getRoute(_chefLocation!);

    // Simulate chef moving towards customer every 3 seconds
    _simulationTimer = Timer.periodic(const Duration(seconds: 3), (timer) {
      if (!mounted || _chefLocation == null) {
        timer.cancel();
        return;
      }

      // Calculate direction towards customer
      final latDiff = widget.customerLocation.latitude - _chefLocation!.latitude;
      final lngDiff = widget.customerLocation.longitude - _chefLocation!.longitude;

      // Move 10% closer each time (realistic movement)
      final newLat = _chefLocation!.latitude + (latDiff * 0.1);
      final newLng = _chefLocation!.longitude + (lngDiff * 0.1);

      final newLocation = LatLng(newLat, newLng);

      // Animate to new position
      _animateChefMarker(newLocation);

      // Update route
      _getRoute(newLocation);

      // Update status
      _updateStatus();

      // Stop when chef arrives
      if (_distanceKm < 0.05) {
        timer.cancel();
        setState(() {
          _statusMessage = "Chef has arrived!";
        });
      }
    });
  }

  /// Smooth marker animation (InDrive style)
  void _animateChefMarker(LatLng newPos) {
    if (_chefLocation == null) {
      setState(() {
        _chefLocation = newPos;
      });
      return;
    }

    _markerAnimation = _LatLngTween(
      begin: _chefLocation!,
      end: newPos,
    ).animate(CurvedAnimation(
      parent: _animationController,
      curve: Curves.easeInOut,
    ));

    _animationController.forward(from: 0);

    _markerAnimation!.addListener(() {
      if (mounted) {
        setState(() {
          _chefLocation = _markerAnimation!.value;
        });
      }
    });
  }

  /// Get route from routing APIs (OpenRouteService with OSRM fallback)
  Future<void> _getRoute(LatLng from) async {
    try {
      debugPrint('IndriveLiveTracking: Getting route from ${from.latitude},${from.longitude} to ${widget.customerLocation.latitude},${widget.customerLocation.longitude}');

      // Try OpenRouteService first
      bool routeFound = await _tryOpenRouteService(from);

      // If OpenRouteService fails, try OSRM as fallback
      if (!routeFound) {
        routeFound = await _tryOSRM(from);
      }

      // If all APIs fail, use straight line
      if (!routeFound) {
        _calculateStraightLine(from);
      }
    } catch (e) {
      debugPrint('Route error: $e');
      _calculateStraightLine(from);
    }
  }

  /// Try OpenRouteService API
  Future<bool> _tryOpenRouteService(LatLng from) async {
    try {
      final url = Uri.parse(
        "https://api.openrouteservice.org/v2/directions/driving-car"
        "?api_key=$_orsApiKey"
        "&start=${from.longitude},${from.latitude}"
        "&end=${widget.customerLocation.longitude},${widget.customerLocation.latitude}"
      );

      debugPrint('IndriveLiveTracking: Trying OpenRouteService...');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final json = jsonDecode(response.body);

        if (json["features"] != null && json["features"].isNotEmpty) {
          final coords = json["features"][0]["geometry"]["coordinates"] as List;
          final props = json["features"][0]["properties"]["summary"];

          debugPrint('IndriveLiveTracking: OpenRouteService success - ${coords.length} points');

          setState(() {
            _routePoints = coords.map((c) => LatLng(c[1].toDouble(), c[0].toDouble())).toList();
            _distanceKm = (props["distance"] ?? 0) / 1000;
            _estimatedMinutes = (props["duration"] ?? 0) / 60;
          });
          return true;
        }
      } else {
        debugPrint('IndriveLiveTracking: OpenRouteService failed with status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('IndriveLiveTracking: OpenRouteService error: $e');
    }
    return false;
  }

  /// Try OSRM API as fallback
  Future<bool> _tryOSRM(LatLng from) async {
    try {
      // OSRM free public API for routing
      final url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/"
        "${from.longitude},${from.latitude};${widget.customerLocation.longitude},${widget.customerLocation.latitude}"
        "?overview=full&geometries=geojson"
      );

      debugPrint('IndriveLiveTracking: Trying OSRM...');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["routes"] != null && data["routes"].isNotEmpty) {
          final route = data["routes"][0];
          final coordinates = route["geometry"]["coordinates"] as List;
          final distance = route["distance"]; // in meters
          final duration = route["duration"]; // in seconds

          debugPrint('IndriveLiveTracking: OSRM success - ${coordinates.length} points');

          setState(() {
            _routePoints = coordinates
                .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();
            _distanceKm = (distance ?? 0) / 1000;
            _estimatedMinutes = (duration ?? 0) / 60;
          });
          return true;
        }
      } else {
        debugPrint('IndriveLiveTracking: OSRM failed with status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('IndriveLiveTracking: OSRM error: $e');
    }
    return false;
  }

  void _calculateStraightLine(LatLng from) {
    const Distance distance = Distance();
    final km = distance.as(LengthUnit.Kilometer, from, widget.customerLocation);

    setState(() {
      _routePoints = [from, widget.customerLocation];
      _distanceKm = km;
      _estimatedMinutes = km * 2; // Approximate 2 min per km
    });
  }

  void _updateStatus() {
    setState(() {
      if (_distanceKm > 5) {
        _statusMessage = "Chef is on the way";
      } else if (_distanceKm > 2) {
        _statusMessage = "Chef is getting closer";
      } else if (_distanceKm > 0.5) {
        _statusMessage = "Chef is nearby";
      } else if (_distanceKm > 0.1) {
        _statusMessage = "Chef is arriving soon";
      } else {
        _statusMessage = "Chef has arrived!";
      }
    });
  }

  void _centerOnRoute() {
    // Guard against null or invalid data
    if (_chefLocation == null) {
      debugPrint('_centerOnRoute: Chef location is null, skipping');
      return;
    }

    // Validate both points before creating bounds
    if (_chefLocation!.latitude == 0 && _chefLocation!.longitude == 0) {
      debugPrint('_centerOnRoute: Invalid chef location (0,0), skipping');
      return;
    }

    if (widget.customerLocation.latitude == 0 && widget.customerLocation.longitude == 0) {
      debugPrint('_centerOnRoute: Invalid customer location (0,0), skipping');
      return;
    }

    try {
      final points = [_chefLocation!, widget.customerLocation];
      final bounds = LatLngBounds.fromPoints(points);

      _mapController.fitCamera(
        CameraFit.bounds(
          bounds: bounds,
          padding: const EdgeInsets.all(80),
        ),
      );
    } catch (e) {
      debugPrint('_centerOnRoute error: $e');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          // Map
          _buildMap(),

          // Top Bar
          _buildTopBar(),

          // Zoom Controls
          _buildZoomControls(),

          // Bottom Panel (InDrive style)
          _buildBottomPanel(),
        ],
      ),
    );
  }

  Widget _buildMap() {
    // Show loading state while initializing or waiting for chef location
    if (_isInitializing || _chefLocation == null) {
      return Container(
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.blue.shade50,
              Colors.blue.shade100,
            ],
          ),
        ),
        child: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              // Animated loading indicator
              Container(
                width: 80,
                height: 80,
                decoration: BoxDecoration(
                  color: Colors.white,
                  shape: BoxShape.circle,
                  boxShadow: [
                    BoxShadow(
                      color: Colors.blue.withValues(alpha: 0.2),
                      blurRadius: 20,
                      spreadRadius: 5,
                    ),
                  ],
                ),
                child: const Center(
                  child: CircularProgressIndicator(
                    strokeWidth: 3,
                    valueColor: AlwaysStoppedAnimation<Color>(Colors.blue),
                  ),
                ),
              ),
              const SizedBox(height: 24),
              Text(
                _statusMessage,
                style: TextStyle(
                  fontSize: 16,
                  color: Colors.blue.shade700,
                  fontWeight: FontWeight.w500,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'Please wait...',
                style: TextStyle(
                  fontSize: 14,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _chefLocation!,
        initialZoom: 14,
        minZoom: 5,
        maxZoom: 18,
      ),
      children: [
        // Map Tiles
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          userAgentPackageName: "com.chefkart.app",
        ),

        // Route Line - showing actual road path
        if (_routePoints.length > 2)
          PolylineLayer(
            polylines: [
              // Shadow/outline for the route
              Polyline(
                points: _routePoints,
                strokeWidth: 8,
                color: Colors.green.shade900.withValues(alpha: 0.4),
              ),
              // Main route line
              Polyline(
                points: _routePoints,
                strokeWidth: 5,
                color: Colors.green.shade600,
                borderColor: Colors.white,
                borderStrokeWidth: 1,
              ),
            ],
          ),
        // Fallback: dotted line when only straight line available
        if (_routePoints.length == 2)
          PolylineLayer(
            polylines: [
              Polyline(
                points: _routePoints,
                strokeWidth: 4,
                color: Colors.orange.shade600,
                pattern: const StrokePattern.dotted(), // Dotted line for straight path
              ),
            ],
          ),

        // Markers
        MarkerLayer(
          markers: [
            // Chef Marker (Animated)
            Marker(
              point: _chefLocation!,
              width: 60,
              height: 60,
              child: _buildChefMarker(),
            ),

            // Customer Marker
            Marker(
              point: widget.customerLocation,
              width: 50,
              height: 50,
              child: _buildCustomerMarker(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildChefMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.orange,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.5),
            blurRadius: 10,
            spreadRadius: 3,
          ),
        ],
      ),
      child: const Center(
        child: Text(
          "👨‍🍳",
          style: TextStyle(fontSize: 28),
        ),
      ),
    );
  }

  Widget _buildCustomerMarker() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.red,
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        boxShadow: [
          BoxShadow(
            color: Colors.red.withValues(alpha: 0.5),
            blurRadius: 8,
            spreadRadius: 2,
          ),
        ],
      ),
      child: const Icon(
        Icons.location_on,
        color: Colors.white,
        size: 28,
      ),
    );
  }

  Widget _buildTopBar() {
    return Positioned(
      top: 0,
      left: 0,
      right: 0,
      child: Container(
        padding: EdgeInsets.fromLTRB(8, MediaQuery.of(context).padding.top + 8, 8, 8),
        decoration: BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Colors.white,
              Colors.white.withValues(alpha: 0.9),
              Colors.white.withValues(alpha: 0),
            ],
          ),
        ),
        child: Row(
          children: [
            // Back Button
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: () => Navigator.pop(context),
              ),
            ),

            const SizedBox(width: 12),

            // Title
            Expanded(
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                decoration: BoxDecoration(
                  color: Colors.white,
                  borderRadius: BorderRadius.circular(25),
                  boxShadow: [
                    BoxShadow(
                      color: Colors.black.withValues(alpha: 0.1),
                      blurRadius: 8,
                    ),
                  ],
                ),
                child: Row(
                  children: [
                    Container(
                      width: 10,
                      height: 10,
                      decoration: BoxDecoration(
                        color: Colors.green,
                        shape: BoxShape.circle,
                        boxShadow: [
                          BoxShadow(
                            color: Colors.green.withValues(alpha: 0.5),
                            blurRadius: 4,
                            spreadRadius: 1,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    const Text(
                      "Live Tracking",
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 16,
                      ),
                    ),
                  ],
                ),
              ),
            ),

            const SizedBox(width: 12),

            // Center on route button
            Container(
              decoration: BoxDecoration(
                color: Colors.white,
                shape: BoxShape.circle,
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.1),
                    blurRadius: 8,
                  ),
                ],
              ),
              child: IconButton(
                icon: const Icon(Icons.center_focus_strong),
                onPressed: _centerOnRoute,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildZoomControls() {
    return Positioned(
      right: 16,
      top: MediaQuery.of(context).size.height * 0.4,
      child: Column(
        children: [
          _buildZoomButton(Icons.add, () {
            final currentZoom = _mapController.camera.zoom;
            _mapController.move(_mapController.camera.center, currentZoom + 1);
          }),
          const SizedBox(height: 8),
          _buildZoomButton(Icons.remove, () {
            final currentZoom = _mapController.camera.zoom;
            _mapController.move(_mapController.camera.center, currentZoom - 1);
          }),
        ],
      ),
    );
  }

  Widget _buildZoomButton(IconData icon, VoidCallback onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 8,
          ),
        ],
      ),
      child: IconButton(
        icon: Icon(icon),
        onPressed: onPressed,
        color: Colors.grey[700],
      ),
    );
  }

  Widget _buildBottomPanel() {
    return Positioned(
      bottom: 0,
      left: 0,
      right: 0,
      child: Container(
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: const BorderRadius.vertical(top: Radius.circular(25)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.15),
              blurRadius: 20,
              offset: const Offset(0, -5),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Drag Handle
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey[300],
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // Demo Mode Banner
            if (_isSimulationMode)
              Container(
                margin: const EdgeInsets.fromLTRB(20, 12, 20, 0),
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: Colors.orange.shade50,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.orange.shade200),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.info_outline, size: 16, color: Colors.orange.shade700),
                    const SizedBox(width: 6),
                    Text(
                      "Demo Mode - Chef simulation active",
                      style: TextStyle(fontSize: 12, color: Colors.orange.shade700),
                    ),
                  ],
                ),
              ),

            Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                children: [
                  // Chef Info Row
                  Row(
                    children: [
                      // Chef Avatar
                      Container(
                        width: 56,
                        height: 56,
                        decoration: BoxDecoration(
                          color: Colors.orange.shade100,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.orange, width: 2),
                        ),
                        child: widget.chefImage != null && widget.chefImage!.isNotEmpty
                            ? ClipOval(
                                child: Image.network(
                                  widget.chefImage!,
                                  fit: BoxFit.cover,
                                  errorBuilder: (_, _, _) => const Center(
                                    child: Text("👨‍🍳", style: TextStyle(fontSize: 28)),
                                  ),
                                ),
                              )
                            : const Center(
                                child: Text("👨‍🍳", style: TextStyle(fontSize: 28)),
                              ),
                      ),

                      const SizedBox(width: 16),

                      // Chef Name & Status
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              widget.chefName,
                              style: const TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: 18,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Row(
                              children: [
                                Container(
                                  width: 8,
                                  height: 8,
                                  decoration: BoxDecoration(
                                    color: _statusMessage.contains("arrived")
                                        ? Colors.green
                                        : Colors.orange,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    _statusMessage,
                                    style: TextStyle(
                                      color: Colors.grey[600],
                                      fontSize: 14,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),

                      // Call & Chat Buttons
                      Row(
                        children: [
                          _buildActionButton(
                            Icons.chat_bubble_outline,
                            const Color(0xFF2B3A67),
                            widget.onChat,
                          ),
                          const SizedBox(width: 8),
                          _buildActionButton(
                            Icons.phone,
                            Colors.green,
                            widget.onCall,
                          ),
                        ],
                      ),
                    ],
                  ),

                  const SizedBox(height: 20),

                  // Distance & Time Cards
                  Row(
                    children: [
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.route,
                          label: "Distance",
                          value: "${_distanceKm.toStringAsFixed(1)} km",
                          color: const Color(0xFF2B3A67),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildInfoCard(
                          icon: Icons.access_time,
                          label: "ETA",
                          value: _formatTime(_estimatedMinutes),
                          color: Colors.orange,
                        ),
                      ),
                    ],
                  ),

                  // Booking Info
                  if (widget.bookingTime != null || widget.bookingDate != null) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.grey[100],
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceAround,
                        children: [
                          if (widget.bookingDate != null)
                            _buildBookingInfo(Icons.calendar_today, widget.bookingDate!),
                          if (widget.bookingTime != null)
                            _buildBookingInfo(Icons.schedule, widget.bookingTime!),
                        ],
                      ),
                    ),
                  ],

                  // Arrived Message
                  if (_statusMessage.contains("arrived")) ...[
                    const SizedBox(height: 16),
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(color: Colors.green.shade200),
                      ),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(Icons.check_circle, color: Colors.green.shade700, size: 24),
                          const SizedBox(width: 8),
                          Flexible(
                            child: Text(
                              "Chef has arrived! Please welcome them.",
                              style: TextStyle(
                                color: Colors.green.shade700,
                                fontWeight: FontWeight.w500,
                              ),
                              textAlign: TextAlign.center,
                              overflow: TextOverflow.ellipsis,
                              maxLines: 2,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ),

            // Safe area padding
            SizedBox(height: MediaQuery.of(context).padding.bottom),
          ],
        ),
      ),
    );
  }

  Widget _buildActionButton(IconData icon, Color color, VoidCallback? onPressed) {
    return Container(
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        shape: BoxShape.circle,
      ),
      child: IconButton(
        icon: Icon(icon, color: color),
        onPressed: onPressed ?? () {},
      ),
    );
  }

  Widget _buildInfoCard({
    required IconData icon,
    required String label,
    required String value,
    required Color color,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.2),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: color, size: 24),
          ),
          const SizedBox(width: 12),
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: TextStyle(
                  color: Colors.grey[600],
                  fontSize: 12,
                ),
              ),
              Text(
                value,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildBookingInfo(IconData icon, String text) {
    return Row(
      children: [
        Icon(icon, size: 16, color: Colors.grey[600]),
        const SizedBox(width: 6),
        Text(
          text,
          style: TextStyle(
            color: Colors.grey[700],
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }

  String _formatTime(double minutes) {
    if (minutes < 1) return "< 1 min";
    if (minutes < 60) return "${minutes.toStringAsFixed(0)} min";
    final hours = (minutes / 60).floor();
    final mins = (minutes % 60).toStringAsFixed(0);
    return "$hours hr $mins min";
  }
}

/// Tween for smooth LatLng animation
class _LatLngTween extends Tween<LatLng> {
  _LatLngTween({required LatLng begin, required LatLng end})
      : super(begin: begin, end: end);

  @override
  LatLng lerp(double t) {
    return LatLng(
      begin!.latitude + (end!.latitude - begin!.latitude) * t,
      begin!.longitude + (end!.longitude - begin!.longitude) * t,
    );
  }
}

