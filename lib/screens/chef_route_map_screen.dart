import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:geolocator/geolocator.dart';
import 'package:http/http.dart' as http;

/// Chef Route Map Screen - Shows chef's live location, customer location,
/// route between them, distance and estimated time
class ChefRouteMapScreen extends StatefulWidget {
  final LatLng customerLocation;
  final String customerName;
  final String? customerAddress;
  final bool isChefView; // true for chef, false for customer

  const ChefRouteMapScreen({
    super.key,
    required this.customerLocation,
    this.customerName = 'Customer',
    this.customerAddress,
    this.isChefView = true,
  });

  @override
  State<ChefRouteMapScreen> createState() => _ChefRouteMapScreenState();
}

class _ChefRouteMapScreenState extends State<ChefRouteMapScreen> {
  final MapController _mapController = MapController();

  LatLng? _currentLocation;
  List<LatLng> _routePoints = [];
  double _distanceInKm = 0;
  double _timeInMinutes = 0;
  bool _isLoading = true;
  String? _errorMessage;
  StreamSubscription<Position>? _positionStream;

  // OpenRouteService API Key (Free tier)
  static const String _orsApiKey = "5b3ce3597851110001cf6248b5cc8869d7f9411f94988ba7cef94e5b";

  @override
  void initState() {
    super.initState();
    _initLocation();
  }

  @override
  void dispose() {
    _positionStream?.cancel();
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _initLocation() async {
    try {
      debugPrint('ChefRouteMap: Initializing location...');

      // Check if location services are enabled
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) {
        debugPrint('ChefRouteMap: Location services disabled');
        setState(() {
          _errorMessage = 'Location services are disabled. Please enable GPS.';
          _isLoading = false;
        });

        // Show dialog to enable location
        if (mounted) {
          _showLocationSettingsDialog();
        }
        return;
      }

      // Check and request permissions
      LocationPermission permission = await Geolocator.checkPermission();
      debugPrint('ChefRouteMap: Current permission: $permission');

      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        debugPrint('ChefRouteMap: Permission after request: $permission');

        if (permission == LocationPermission.denied) {
          setState(() {
            _errorMessage = 'Location permission denied. Please allow location access.';
            _isLoading = false;
          });
          return;
        }
      }

      if (permission == LocationPermission.deniedForever) {
        setState(() {
          _errorMessage = 'Location permission permanently denied. Please enable from settings.';
          _isLoading = false;
        });

        if (mounted) {
          _showLocationSettingsDialog();
        }
        return;
      }

      debugPrint('ChefRouteMap: Getting current position...');

      // Get current location with timeout
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      debugPrint('ChefRouteMap: Got position: ${position.latitude}, ${position.longitude}');

      setState(() {
        _currentLocation = LatLng(position.latitude, position.longitude);
      });

      // Get route
      await _getRoute();

      // Start listening to location updates for live tracking
      _startLocationUpdates();

    } on TimeoutException {
      debugPrint('ChefRouteMap: Location request timed out');

      // Try last known position
      final lastPosition = await Geolocator.getLastKnownPosition();
      if (lastPosition != null) {
        debugPrint('ChefRouteMap: Using last known: ${lastPosition.latitude}, ${lastPosition.longitude}');
        setState(() {
          _currentLocation = LatLng(lastPosition.latitude, lastPosition.longitude);
        });
        await _getRoute();
        _startLocationUpdates();
      } else {
        setState(() {
          _errorMessage = 'Could not get your location. Please try again.';
          _isLoading = false;
        });
      }
    } catch (e) {
      debugPrint('ChefRouteMap: Error getting location: $e');
      setState(() {
        _errorMessage = 'Error getting location: $e';
        _isLoading = false;
      });
    }
  }

  void _showLocationSettingsDialog() {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Location Required'),
        content: const Text(
          'Please enable location services and grant permission for the app to show your location on the map.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              Geolocator.openLocationSettings();
            },
            child: const Text('Open Settings'),
          ),
        ],
      ),
    );
  }

  void _startLocationUpdates() {
    const LocationSettings locationSettings = LocationSettings(
      accuracy: LocationAccuracy.high,
      distanceFilter: 20, // Update every 20 meters
    );
    _positionStream = Geolocator.getPositionStream(
      locationSettings: locationSettings,
    ).listen((Position position) {
      if (mounted) {
        setState(() {
          _currentLocation = LatLng(position.latitude, position.longitude);
        });
        // Refresh route when location changes significantly
        _getRoute();
      }
    });
  }

  Future<void> _getRoute() async {
    if (_currentLocation == null) return;

    try {
      final start = _currentLocation!;
      final end = widget.customerLocation;

      debugPrint('ChefRouteMap: Getting route from ${start.latitude},${start.longitude} to ${end.latitude},${end.longitude}');

      // Try OpenRouteService first
      bool routeFound = await _tryOpenRouteService(start, end);

      // If OpenRouteService fails, try OSRM as fallback
      if (!routeFound) {
        routeFound = await _tryOSRM(start, end);
      }

      // If all APIs fail, calculate straight line
      if (!routeFound) {
        _calculateStraightLineDistance();
      }
    } catch (e) {
      debugPrint('Route API error: $e');
      _calculateStraightLineDistance();
    }
  }

  Future<bool> _tryOpenRouteService(LatLng start, LatLng end) async {
    try {
      final url = Uri.parse(
        "https://api.openrouteservice.org/v2/directions/driving-car"
        "?api_key=$_orsApiKey"
        "&start=${start.longitude},${start.latitude}"
        "&end=${end.longitude},${end.latitude}"
      );

      debugPrint('ChefRouteMap: Trying OpenRouteService...');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["features"] != null && data["features"].isNotEmpty) {
          final coordinates = data["features"][0]["geometry"]["coordinates"] as List;
          final props = data["features"][0]["properties"]["summary"];

          debugPrint('ChefRouteMap: OpenRouteService success - ${coordinates.length} points');

          setState(() {
            _routePoints = coordinates
                .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();
            _distanceInKm = (props["distance"] ?? 0) / 1000;
            _timeInMinutes = (props["duration"] ?? 0) / 60;
            _isLoading = false;
            _errorMessage = null;
          });
          return true;
        }
      } else {
        debugPrint('ChefRouteMap: OpenRouteService failed with status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ChefRouteMap: OpenRouteService error: $e');
    }
    return false;
  }

  Future<bool> _tryOSRM(LatLng start, LatLng end) async {
    try {
      // OSRM free public API for routing
      final url = Uri.parse(
        "https://router.project-osrm.org/route/v1/driving/"
        "${start.longitude},${start.latitude};${end.longitude},${end.latitude}"
        "?overview=full&geometries=geojson"
      );

      debugPrint('ChefRouteMap: Trying OSRM...');
      final response = await http.get(url).timeout(const Duration(seconds: 10));

      if (response.statusCode == 200) {
        final data = jsonDecode(response.body);

        if (data["routes"] != null && data["routes"].isNotEmpty) {
          final route = data["routes"][0];
          final coordinates = route["geometry"]["coordinates"] as List;
          final distance = route["distance"]; // in meters
          final duration = route["duration"]; // in seconds

          debugPrint('ChefRouteMap: OSRM success - ${coordinates.length} points');

          setState(() {
            _routePoints = coordinates
                .map((c) => LatLng(c[1].toDouble(), c[0].toDouble()))
                .toList();
            _distanceInKm = (distance ?? 0) / 1000;
            _timeInMinutes = (duration ?? 0) / 60;
            _isLoading = false;
            _errorMessage = null;
          });
          return true;
        }
      } else {
        debugPrint('ChefRouteMap: OSRM failed with status ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('ChefRouteMap: OSRM error: $e');
    }
    return false;
  }

  void _calculateStraightLineDistance() {
    if (_currentLocation == null) return;

    final Distance distance = const Distance();
    final km = distance.as(
      LengthUnit.Kilometer,
      _currentLocation!,
      widget.customerLocation,
    );

    setState(() {
      _distanceInKm = km;
      _timeInMinutes = km * 2; // Approximate: 2 minutes per km
      _routePoints = [_currentLocation!, widget.customerLocation];
      _isLoading = false;
    });
  }

  void _centerOnRoute() {
    if (_currentLocation == null) return;

    final bounds = LatLngBounds.fromPoints([
      _currentLocation!,
      widget.customerLocation,
    ]);

    _mapController.fitCamera(
      CameraFit.bounds(
        bounds: bounds,
        padding: const EdgeInsets.all(50),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.isChefView ? 'Route to Customer' : 'Chef Location'),
        backgroundColor: Theme.of(context).primaryColor,
        foregroundColor: Colors.white,
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _initLocation();
            },
          ),
          IconButton(
            icon: const Icon(Icons.center_focus_strong),
            onPressed: _centerOnRoute,
          ),
        ],
      ),
      body: _buildBody(),
      bottomNavigationBar: _buildBottomInfo(),
    );
  }

  Widget _buildBody() {
    if (_isLoading) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            CircularProgressIndicator(),
            SizedBox(height: 16),
            Text('Getting location and route...'),
          ],
        ),
      );
    }

    if (_errorMessage != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.location_off, size: 64, color: Colors.grey[400]),
              const SizedBox(height: 16),
              Text(
                _errorMessage!,
                textAlign: TextAlign.center,
                style: const TextStyle(fontSize: 16),
              ),
              const SizedBox(height: 24),
              ElevatedButton.icon(
                onPressed: _initLocation,
                icon: const Icon(Icons.refresh),
                label: const Text('Retry'),
              ),
              const SizedBox(height: 12),
              TextButton(
                onPressed: () => Geolocator.openLocationSettings(),
                child: const Text('Open Location Settings'),
              ),
            ],
          ),
        ),
      );
    }

    if (_currentLocation == null) {
      return const Center(child: Text('Unable to get location'));
    }

    return FlutterMap(
      mapController: _mapController,
      options: MapOptions(
        initialCenter: _currentLocation!,
        initialZoom: 14,
        minZoom: 5,
        maxZoom: 18,
      ),
      children: [
        // OpenStreetMap Tiles
        TileLayer(
          urlTemplate: "https://tile.openstreetmap.org/{z}/{x}/{y}.png",
          userAgentPackageName: 'com.chefkart.app',
        ),

        // Route Line - showing actual road path
        if (_routePoints.isNotEmpty && _routePoints.length > 2)
          PolylineLayer(
            polylines: [
              // Shadow/outline for the route
              Polyline(
                points: _routePoints,
                strokeWidth: 8,
                color: Colors.blue.shade900.withValues(alpha: 0.4),
              ),
              // Main route line
              Polyline(
                points: _routePoints,
                strokeWidth: 5,
                color: Colors.blue.shade600,
                borderColor: Colors.white,
                borderStrokeWidth: 1,
              ),
            ],
          ),
        // Fallback: dashed line when no route available (straight path)
        if (_routePoints.isNotEmpty && _routePoints.length == 2)
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
            // Current Location (Chef/You)
            Marker(
              point: _currentLocation!,
              width: 50,
              height: 50,
              child: _buildChefMarker(),
            ),

            // Customer Location
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
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.green,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.green.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.restaurant,
            color: Colors.white,
            size: 24,
          ),
        ),
      ],
    );
  }

  Widget _buildCustomerMarker() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: Colors.red,
            shape: BoxShape.circle,
            border: Border.all(color: Colors.white, width: 2),
            boxShadow: [
              BoxShadow(
                color: Colors.red.withValues(alpha: 0.5),
                blurRadius: 8,
                spreadRadius: 2,
              ),
            ],
          ),
          child: const Icon(
            Icons.person,
            color: Colors.white,
            size: 24,
          ),
        ),
      ],
    );
  }

  Widget _buildBottomInfo() {
    if (_isLoading || _errorMessage != null) {
      return const SizedBox.shrink();
    }

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.1),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Customer info
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.red.shade50,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(Icons.person, color: Colors.red.shade700),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.customerName,
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                      if (widget.customerAddress != null)
                        Text(
                          widget.customerAddress!,
                          style: TextStyle(
                            color: Colors.grey[600],
                            fontSize: 12,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Distance and Time
            Row(
              children: [
                Expanded(
                  child: _buildInfoCard(
                    icon: Icons.route,
                    label: 'Distance',
                    value: '${_distanceInKm.toStringAsFixed(1)} km',
                    color: Colors.blue,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: _buildInfoCard(
                    icon: Icons.access_time,
                    label: 'Est. Time',
                    value: _formatTime(_timeInMinutes),
                    color: Colors.orange,
                  ),
                ),
              ],
            ),

            const SizedBox(height: 16),

            // Navigation Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  // Navigate in-app - enable continuous tracking mode
                  _enableNavigationMode();
                },
                icon: const Icon(Icons.navigation),
                label: const Text('Start Navigation'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Theme.of(context).primaryColor,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 14),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // Used to track navigation mode state
  // ignore: unused_field
  bool _isNavigating = false;

  void _enableNavigationMode() {
    setState(() {
      _isNavigating = true;
    });

    // Center map to follow current location
    if (_currentLocation != null) {
      _mapController.move(_currentLocation!, 16);
    }

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Row(
          children: [
            const Icon(Icons.navigation, color: Colors.white, size: 20),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Navigation started! Distance: ${_distanceInKm.toStringAsFixed(1)} km, ETA: ${_formatTime(_timeInMinutes)}',
              ),
            ),
          ],
        ),
        backgroundColor: Colors.green,
        duration: const Duration(seconds: 3),
        action: SnackBarAction(
          label: 'Stop',
          textColor: Colors.white,
          onPressed: () {
            setState(() => _isNavigating = false);
          },
        ),
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
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: color.withValues(alpha: 0.3)),
      ),
      child: Row(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(width: 8),
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
                  fontSize: 16,
                  color: color,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  String _formatTime(double minutes) {
    if (minutes < 60) {
      return '${minutes.toStringAsFixed(0)} min';
    } else {
      final hours = (minutes / 60).floor();
      final mins = (minutes % 60).toStringAsFixed(0);
      return '$hours hr $mins min';
    }
  }
}

