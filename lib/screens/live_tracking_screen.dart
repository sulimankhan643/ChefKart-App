import 'dart:async';
import 'package:flutter/material.dart';
import 'package:latlong2/latlong.dart';
import '../models/chef.dart';
import '../services/location_service.dart';
import 'chef_route_map_screen.dart';

class LiveTrackingScreen extends StatefulWidget {
  final Chef chef;
  final Map<String, dynamic>? bookingData;
  final VoidCallback onBack;
  final VoidCallback onChat;

  const LiveTrackingScreen({
    super.key,
    required this.chef,
    required this.bookingData,
    required this.onBack,
    required this.onChat,
  });

  @override
  State<LiveTrackingScreen> createState() => _LiveTrackingScreenState();
}

class _LiveTrackingScreenState extends State<LiveTrackingScreen> {
  double progress = 45;
  String eta = "25 mins";
  String distance = "3.2 km";
  Timer? timer;

  // Real location tracking
  LatLng? _customerLocation;
  LatLng? _chefLocation;
  StreamSubscription? _chefLocationSubscription;

  @override
  void initState() {
    super.initState();
    _loadLocations();
    timer = Timer.periodic(const Duration(seconds: 5), (_) {
      setState(() {
        progress = (progress + 5).clamp(0, 100);
        int mins = int.tryParse(eta.split(" ").first) ?? 0;
        eta = mins > 0 ? "${mins - 1} mins" : "Arriving soon";
        double km = double.tryParse(distance.split(" ").first) ?? 0;
        distance = km > 0.5 ? "${(km - 0.2).toStringAsFixed(1)} km" : "Nearby";
      });
    });
  }

  Future<void> _loadLocations() async {
    // Get customer's current location
    final customerLoc = await LocationService.getCurrentLocation();
    if (customerLoc != null && mounted) {
      setState(() {
        _customerLocation = customerLoc;
      });
    }

    // Listen to chef's live location from Firestore
    _chefLocationSubscription = LocationService.getUserLiveLocation(widget.chef.id).listen((chefLoc) {
      if (chefLoc != null && mounted) {
        setState(() {
          _chefLocation = chefLoc;
          if (_customerLocation != null) {
            final dist = LocationService.calculateDistance(_chefLocation!, _customerLocation!);
            distance = "${dist.toStringAsFixed(1)} km";
            final time = LocationService.estimateTime(dist);
            eta = time < 60 ? "${time.toStringAsFixed(0)} mins" : "${(time / 60).toStringAsFixed(1)} hrs";
          }
        });
      }
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    _chefLocationSubscription?.cancel();
    super.dispose();
  }

  String getStatusMessage() {
    if (progress < 30) return "Chef is on the way";
    if (progress < 70) return "Chef is nearby";
    if (progress < 100) return "Chef is arriving soon";
    return "Chef has arrived!";
  }

  void _openRealMap() {
    // Use customer location or default Peshawar location
    final customerLoc = _customerLocation ?? const LatLng(34.0151, 71.5249);

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ChefRouteMapScreen(
          customerLocation: customerLoc,
          customerName: 'Your Location',
          customerAddress: widget.bookingData?['address'],
          isChefView: false,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final chef = widget.chef;
    final bookingData = widget.bookingData ?? {};

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 12),
            color: Colors.white,
            child: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    "Track Your Chef",
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
                // View Real Map Button
                TextButton.icon(
                  onPressed: _openRealMap,
                  icon: const Icon(Icons.map, size: 18),
                  label: const Text('Real Map'),
                  style: TextButton.styleFrom(
                    foregroundColor: Theme.of(context).primaryColor,
                  ),
                ),
              ],
            ),
          ),

          // Map area simulated
          Expanded(
            child: Stack(
              children: [
                Container(
                  decoration: const BoxDecoration(
                    gradient: LinearGradient(
                      colors: [Color(0xFFE6F4EA), Color(0xFFE6F0FA)],
                      begin: Alignment.topLeft,
                      end: Alignment.bottomRight,
                    ),
                  ),
                ),

                // Chef location moving
                Positioned(
                  top: 40 + (progress * 0.4),
                  left: 30 + (progress * 0.3),
                  child: Column(
                    children: [
                      Stack(
                        alignment: Alignment.center,
                        children: [
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8C00).withAlpha(77),
                              shape: BoxShape.circle,
                            ),
                          ),
                          Container(
                            width: 64,
                            height: 64,
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8C00),
                              shape: BoxShape.circle,
                              border: Border.all(color: Colors.white, width: 4),
                            ),
                            child: const Center(child: Text("👨‍🍳", style: TextStyle(fontSize: 24))),
                          ),
                        ],
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text("Chef Location", style: TextStyle(fontSize: 12)),
                      )
                    ],
                  ),
                ),

                // Your location
                Positioned(
                  bottom: 100,
                  left: MediaQuery.of(context).size.width * 0.25,
                  child: Column(
                    children: [
                      Container(
                        width: 48,
                        height: 48,
                        decoration: BoxDecoration(
                          color: Colors.green,
                          shape: BoxShape.circle,
                          border: Border.all(color: Colors.white, width: 4),
                        ),
                        child: const Icon(Icons.location_on, color: Colors.white),
                      ),
                      const SizedBox(height: 4),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Text("Your Location", style: TextStyle(fontSize: 12)),
                      )
                    ],
                  ),
                ),

                // ETA Card
                Positioned(
                  top: 16,
                  left: 16,
                  right: 16,
                  child: Card(
                    elevation: 4,
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        children: [
                          Row(
                            children: [
                              CircleAvatar(
                                radius: 24,
                                backgroundColor: Colors.grey.shade200,
                                backgroundImage: chef.image.isNotEmpty
                                    ? NetworkImage(chef.image)
                                    : null,
                                onBackgroundImageError: chef.image.isNotEmpty
                                    ? (_, _) {}
                                    : null,
                                child: chef.image.isEmpty
                                    ? Text(
                                  chef.name[0],
                                  style: const TextStyle(fontSize: 24),
                                )
                                    : null,
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(chef.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                                  Text(getStatusMessage(), style: TextStyle(color: Colors.grey[600])),
                                ],
                              )
                            ],
                          ),
                          const SizedBox(height: 12),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("ETA:", style: TextStyle(color: Colors.grey)),
                              Text(eta, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          const SizedBox(height: 6),
                          LinearProgressIndicator(value: progress / 100, minHeight: 8),
                          const SizedBox(height: 6),
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              const Text("Distance:", style: TextStyle(color: Colors.grey)),
                              Text(distance, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          )
                        ],
                      ),
                    ),
                  ),
                ),

                // Bottom info card
                Positioned(
                  bottom: 0,
                  left: 0,
                  right: 0,
                  child: Card(
                    elevation: 4,
                    margin: const EdgeInsets.all(16),
                    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                    child: Padding(
                      padding: const EdgeInsets.all(12),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Row(
                            mainAxisAlignment: MainAxisAlignment.spaceBetween,
                            children: [
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text("Booking Time", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  Text(bookingData['time'] ?? "6:00 PM", style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.end,
                                children: [
                                  const Text("Date", style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  Text(bookingData['date'] != null ? bookingData['date'].toString().substring(0, 10) : "Today", style: const TextStyle(fontWeight: FontWeight.bold)),
                                ],
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: widget.onChat,
                                  icon: const Icon(Icons.message, size: 16),
                                  label: const Text("Chat"),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: OutlinedButton.icon(
                                  onPressed: () {},
                                  icon: const Icon(Icons.phone, size: 16),
                                  label: const Text("Call"),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          if (progress >= 100)
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.green[50],
                                border: Border.all(color: Colors.green[200]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "🎉 Chef has arrived! Please welcome them.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.green),
                              ),
                            ),
                          if (progress < 100 && progress > 70)
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: Colors.yellow[50],
                                border: Border.all(color: Colors.yellow[200]!),
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: const Text(
                                "⏰ Chef is nearby. Please ensure everything is ready.",
                                textAlign: TextAlign.center,
                                style: TextStyle(color: Colors.orange),
                              ),
                            ),
                        ],
                      ),
                    ),
                  ),
                )
              ],
            ),
          )
        ],
      ),
    );
  }
}
