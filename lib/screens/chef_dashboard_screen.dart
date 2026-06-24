import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../services/booking_request_service.dart';

class ChefDashboardScreen extends StatefulWidget {
  final Function(String)? onNavigate;

  const ChefDashboardScreen({super.key, this.onNavigate});

  @override
  State<ChefDashboardScreen> createState() => _ChefDashboardScreenState();
}

class _ChefDashboardScreenState extends State<ChefDashboardScreen> {
  Map<String, dynamic>? chefData;
  bool loading = true;
  List<Map<String, dynamic>> confirmedBookings = [];
  double totalEarnings = 0;

  Future<void> loadChefData() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;
      final doc = await FirebaseFirestore.instance.collection("users").doc(uid).get();

      if (doc.exists) {
        if (mounted) {
          setState(() {
            chefData = doc.data();
          });
        }
      }

      // Load confirmed bookings from Firebase
      await loadConfirmedBookings();

    } catch (e) {
      if (mounted) {
        setState(() => loading = false);
      }
    }
  }

  Future<void> loadConfirmedBookings() async {
    try {
      final uid = FirebaseAuth.instance.currentUser!.uid;

      // Fetch CONFIRMED bookings where this chef is booked
      final bookingsSnapshot = await FirebaseFirestore.instance
          .collection("bookings")
          .where("chefId", isEqualTo: uid)
          .orderBy("createdAt", descending: true)
          .get();

      List<Map<String, dynamic>> loadedBookings = [];

      for (var doc in bookingsSnapshot.docs) {
        final data = doc.data();

        loadedBookings.add({
          "id": doc.id,
          "customer": data["customerName"] ?? "Customer",
          "customerImage": data["customerImage"] ?? "",
          "service": data["serviceType"] ?? "Cooking Service",
          "date": data["date"] ?? "Today",
          "time": data["time"] ?? "6:00 PM",
          "guests": data["guestCount"] ?? 4,
          "amount": data["price"] ?? 0,
          "status": data["status"] ?? "confirmed",
          "phone": data["customerPhone"] ?? "",
          "address": data["address"] ?? "",
        });
      }

      // Calculate total earnings from accepted/completed bookings
      double earnings = 0;
      for (var booking in loadedBookings) {
        if (booking["status"] == "confirmed" || booking["status"] == "completed") {
          earnings += (booking["amount"] as num).toDouble();
        }
      }

      if (mounted) {
        setState(() {
          confirmedBookings = loadedBookings;
          totalEarnings = earnings;
          loading = false;
        });
      }
    } catch (e) {
      // If no bookings collection exists yet, just set empty
      if (mounted) {
        setState(() {
          confirmedBookings = [];
          loading = false;
        });
      }
    }
  }

  Future<void> handleRequestAction(String requestId, String action) async {
    try {
      bool success = false;

      if (action == "accept") {
        success = await BookingRequestService.acceptRequest(requestId);
      } else {
        success = await BookingRequestService.rejectRequest(requestId);
      }

      if (!mounted) return;

      if (success) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(action == "accept" ? "✅ Booking accepted!" : "❌ Booking declined"),
            backgroundColor: action == "accept" ? Colors.green : Colors.red,
          ),
        );
        // Reload confirmed bookings if accepted
        if (action == "accept") {
          loadConfirmedBookings();
        }
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Failed to ${action == "accept" ? "accept" : "reject"} request. Please try again."),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
      );
    }
  }

  @override
  void initState() {
    super.initState();
    loadChefData();
  }

  List<Map<String, dynamic>> get acceptedBookings =>
      confirmedBookings.where((b) => b["status"] == "confirmed" || b["status"] == "accepted").toList();

  List<Map<String, dynamic>> get completedBookings =>
      confirmedBookings.where((b) => b["status"] == "completed").toList();

  @override
  Widget build(BuildContext context) {
    if (loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final name = chefData?["name"] ?? "Chef";
    final initials = name.isNotEmpty
        ? name.split(' ').map((n) => n.isNotEmpty ? n[0] : '').take(2).join().toUpperCase()
        : "CH";
    final rating = (chefData?["rating"] ?? 4.5).toDouble();

    return Scaffold(
      body: Column(
        children: [
          // Header
          Container(
            padding: const EdgeInsets.fromLTRB(16, 48, 16, 16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () => Navigator.of(context).maybePop(),
                    ),
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          "Chef Dashboard",
                          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
                        ),
                        Text(
                          name,
                          style: TextStyle(fontSize: 14, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                  ],
                ),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.refresh),
                      onPressed: () {
                        setState(() => loading = true);
                        loadChefData();
                      },
                    ),
                    IconButton(
                      icon: const Icon(Icons.logout),
                      onPressed: () async {
                        await FirebaseAuth.instance.signOut();
                      },
                    ),
                    Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: Text(
                          initials,
                          style: TextStyle(
                            color: Theme.of(context).primaryColor,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Stats Cards
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Row(
                      children: [
                        Expanded(child: _buildStatCard(
                          icon: Icons.payments,
                          iconColor: Colors.green,
                          label: "Total Earnings",
                          value: "Rs. ${totalEarnings.toInt()}",
                        )),
                        const SizedBox(width: 12),
                        Expanded(child: _buildStatCard(
                          icon: Icons.star,
                          iconColor: Colors.amber,
                          label: "Rating",
                          value: rating.toStringAsFixed(1),
                        )),
                      ],
                    ),
                  ),

                  // Real-time Pending Requests using StreamBuilder
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _getPendingRequestsStream(),
                    builder: (context, snapshot) {
                      // Handle connection states
                      if (snapshot.hasError) {
                        debugPrint('Stream error: ${snapshot.error}');
                        return Padding(
                          padding: const EdgeInsets.all(16),
                          child: Card(
                            color: Colors.red.shade50,
                            child: Padding(
                              padding: const EdgeInsets.all(16),
                              child: Row(
                                children: [
                                  Icon(Icons.error_outline, color: Colors.red.shade700),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'Error loading requests',
                                          style: TextStyle(
                                            fontWeight: FontWeight.bold,
                                            color: Colors.red.shade700,
                                          ),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Pull to refresh or try again later',
                                          style: TextStyle(
                                            fontSize: 12,
                                            color: Colors.red.shade600,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  IconButton(
                                    icon: const Icon(Icons.refresh),
                                    onPressed: () {
                                      setState(() {});
                                    },
                                  ),
                                ],
                              ),
                            ),
                          ),
                        );
                      }

                      final pendingRequests = snapshot.data ?? [];

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Bookings count
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 16),
                            child: Row(
                              children: [
                                _buildMiniStat("Total Bookings", confirmedBookings.length.toString()),
                                const SizedBox(width: 12),
                                _buildMiniStat("Pending", pendingRequests.length.toString()),
                                const SizedBox(width: 12),
                                _buildMiniStat("Confirmed", acceptedBookings.length.toString()),
                              ],
                            ),
                          ),
                          const SizedBox(height: 16),

                          // Pending Booking Requests (Real-time from bookingRequests collection)
                          if (pendingRequests.isNotEmpty) ...[
                            Padding(
                              padding: const EdgeInsets.symmetric(horizontal: 16),
                              child: Row(
                                children: [
                                  const Icon(Icons.notifications_active, color: Colors.orange, size: 20),
                                  const SizedBox(width: 8),
                                  Text(
                                    "New Booking Requests (${pendingRequests.length})",
                                    style: TextStyle(
                                      fontSize: 16,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.grey.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(height: 12),
                            ...pendingRequests.map((request) => _buildPendingRequestCard(request)),
                          ],
                        ],
                      );
                    },
                  ),

                  // Accepted/Confirmed Bookings
                  if (acceptedBookings.isNotEmpty) ...[
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: Text(
                        "Confirmed Bookings (${acceptedBookings.length})",
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                          color: Colors.grey.shade800,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    ...acceptedBookings.map((booking) => _buildAcceptedBookingCard(booking)),
                  ],

                  // Empty State - show only when no pending requests AND no bookings
                  StreamBuilder<List<Map<String, dynamic>>>(
                    stream: _getPendingRequestsStream(),
                    builder: (context, snapshot) {
                      final pendingRequests = snapshot.data ?? [];
                      if (confirmedBookings.isEmpty && pendingRequests.isEmpty) {
                        return _buildEmptyState();
                      }
                      return const SizedBox.shrink();
                    },
                  ),

                  // Quick Actions
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(
                      children: [
                        _buildActionButton(
                          icon: Icons.calendar_today,
                          label: "Manage Schedule & Availability",
                          onTap: () => widget.onNavigate?.call('chef-schedule'),
                        ),
                        const SizedBox(height: 12),
                        _buildActionButton(
                          icon: Icons.payments,
                          label: "View Earnings & Reports",
                          onTap: () => widget.onNavigate?.call('chef-earnings'),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildMiniStat(String label, String value) {
    return Expanded(
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: Colors.grey.shade100,
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          children: [
            Text(
              value,
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
            Text(
              label,
              style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
            ),
          ],
        ),
      ),
    );
  }

  // Stream for real-time pending requests from bookingRequests collection
  Stream<List<Map<String, dynamic>>> _getPendingRequestsStream() {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return Stream.value([]);

    // Simplified query without orderBy to avoid composite index issues
    // Filter and sort locally instead
    return FirebaseFirestore.instance
        .collection('bookingRequests')
        .where('chefId', isEqualTo: uid)
        .snapshots()
        .handleError((error) {
          debugPrint('Firestore stream error: $error');
          return <QueryDocumentSnapshot<Map<String, dynamic>>>[];
        })
        .map((snapshot) {
          final docs = snapshot.docs.where((doc) {
            final data = doc.data();
            return data['status'] == 'pending';
          }).toList();

          // Sort locally by createdAt descending
          docs.sort((a, b) {
            final aTime = a.data()['createdAt'];
            final bTime = b.data()['createdAt'];
            if (aTime == null && bTime == null) return 0;
            if (aTime == null) return 1;
            if (bTime == null) return -1;
            if (aTime is Timestamp && bTime is Timestamp) {
              return bTime.compareTo(aTime);
            }
            return 0;
          });

          return docs.map((doc) {
            final data = doc.data();
            return {
              'id': doc.id,
              'customerId': data['customerId'] ?? '',
              'customerName': data['customerName'] ?? 'Customer',
              'customerPhone': data['customerPhone'] ?? '',
              'customerImage': data['customerImage'] ?? '',
              'serviceType': data['serviceType'] ?? 'Cooking Service',
              'date': data['date'] ?? 'Today',
              'time': data['time'] ?? '6:00 PM',
              'guestCount': data['guestCount'] ?? 4,
              'offeredPrice': data['offeredPrice'] ?? 0,
              'note': data['note'] ?? '',
              'location': data['location'] ?? '',
              'address': data['address'] ?? '',
              'status': data['status'] ?? 'pending',
              'createdAt': data['createdAt'],
            };
          }).toList();
        });
  }

  Widget _buildPendingRequestCard(Map<String, dynamic> request) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.orange.shade300, width: 2),
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.orange.withValues(alpha: 0.1),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer Image
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.orange.shade100,
            backgroundImage: request["customerImage"] != null && request["customerImage"].toString().isNotEmpty
                ? NetworkImage(request["customerImage"])
                : null,
            child: request["customerImage"] == null || request["customerImage"].toString().isEmpty
                ? Text(
                    request["customerName"].toString().isNotEmpty ? request["customerName"][0].toUpperCase() : "C",
                    style: TextStyle(color: Colors.orange.shade700, fontWeight: FontWeight.bold),
                  )
                : null,
          ),
          const SizedBox(width: 12),
          // Request Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          request["customerName"],
                          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                        ),
                        Text(
                          request["serviceType"],
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: Colors.green.shade50,
                        border: Border.all(color: Colors.green),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        "Rs. ${request["offeredPrice"]}",
                        style: TextStyle(
                          color: Colors.green.shade700,
                          fontWeight: FontWeight.bold,
                          fontSize: 14,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                // Date, Time, Guests
                Row(
                  children: [
                    _buildInfoChip(Icons.calendar_today, request["date"]),
                    const SizedBox(width: 12),
                    _buildInfoChip(Icons.access_time, request["time"]),
                    const SizedBox(width: 12),
                    _buildInfoChip(Icons.people, "${request["guestCount"]} guests"),
                  ],
                ),
                if (request["address"] != null && request["address"].toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(Icons.location_on, size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Expanded(
                        child: Text(
                          request["address"],
                          style: TextStyle(fontSize: 11, color: Colors.grey.shade600),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
                if (request["note"] != null && request["note"].toString().isNotEmpty) ...[
                  const SizedBox(height: 6),
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Row(
                      children: [
                        Icon(Icons.note, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            request["note"],
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade700),
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 14),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () => handleRequestAction(request["id"], "accept"),
                        icon: const Icon(Icons.check_circle, size: 18, color: Colors.white),
                        label: const Text("Accept", style: TextStyle(color: Colors.white)),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () => handleRequestAction(request["id"], "reject"),
                        icon: Icon(Icons.cancel, size: 18, color: Colors.red.shade700),
                        label: Text("Decline", style: TextStyle(color: Colors.red.shade700)),
                        style: OutlinedButton.styleFrom(
                          side: BorderSide(color: Colors.red.shade300),
                          padding: const EdgeInsets.symmetric(vertical: 10),
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: iconColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  label,
                  style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
          ),
        ],
      ),
    );
  }


  Widget _buildAcceptedBookingCard(Map<String, dynamic> booking) {
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        border: Border.all(color: Colors.grey.shade200),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Customer Image
          CircleAvatar(
            radius: 24,
            backgroundColor: Colors.grey.shade200,
            backgroundImage: booking["customerImage"] != null && booking["customerImage"].toString().isNotEmpty
                ? NetworkImage(booking["customerImage"])
                : null,
            onBackgroundImageError: booking["customerImage"] != null && booking["customerImage"].toString().isNotEmpty
                ? (_, _) {}
                : null,
            child: booking["customerImage"] == null || booking["customerImage"].toString().isEmpty
                ? Text(booking["customer"].toString().isNotEmpty ? booking["customer"][0] : "C")
                : null,
          ),
          const SizedBox(width: 12),
          // Booking Details
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          booking["customer"],
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Text(
                          booking["service"],
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                      ],
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                      decoration: BoxDecoration(
                        color: Colors.green,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: const Text(
                        "Confirmed",
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                // Time, Guests, Amount
                Row(
                  children: [
                    _buildInfoChip(Icons.access_time, booking["time"]),
                    const SizedBox(width: 12),
                    _buildInfoChip(Icons.people, "${booking["guests"]} guests"),
                    const SizedBox(width: 12),
                    Text(
                      "Rs. ${booking["amount"]}",
                      style: TextStyle(
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                        color: Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.chat, size: 16),
                        label: const Text("Chat"),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: ElevatedButton.icon(
                        onPressed: () {},
                        icon: const Icon(Icons.play_arrow, size: 16),
                        label: const Text("Start"),
                        style: ElevatedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(vertical: 8),
                        ),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInfoChip(IconData icon, String text) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, size: 14, color: Colors.grey.shade600),
        const SizedBox(width: 4),
        Text(
          text,
          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(48),
      child: Column(
        children: [
          Icon(Icons.calendar_today, size: 64, color: Colors.grey.shade400),
          const SizedBox(height: 16),
          const Text(
            "No bookings yet",
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            "You will see bookings here when customers book your services",
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey.shade600),
          ),
        ],
      ),
    );
  }

  Widget _buildActionButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return OutlinedButton(
      onPressed: onTap,
      style: OutlinedButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Expanded(child: Text(label)),
          const Icon(Icons.chevron_right, size: 20),
        ],
      ),
    );
  }
}
