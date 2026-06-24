import 'package:flutter/material.dart';
import "package:intl/intl.dart";
import '../models/chef.dart';
import '../widgets/rating_dialog.dart';

class BookingConfirmationScreen extends StatelessWidget {
  final Map<String, dynamic> bookingData;
  final Chef chef;
  final VoidCallback onChat;
  final VoidCallback onTrackChef;
  final VoidCallback onHome;
  final String? bookingId;

  const BookingConfirmationScreen({
    super.key,
    required this.bookingData,
    required this.chef,
    required this.onChat,
    required this.onTrackChef,
    required this.onHome,
    this.bookingId,
  });

  @override
  Widget build(BuildContext context) {
    final estimatedArrival = DateTime.now().add(const Duration(hours: 2));
    final displayBookingId = bookingId ?? "#CHF${(100000 + (DateTime.now().millisecondsSinceEpoch % 900000)).toString()}";

    return Scaffold(
      backgroundColor: Colors.grey[100],
      body: SafeArea(
        child: SingleChildScrollView(
          child: Column(
            children: [
              // Success Header
              Container(
                width: double.infinity,
                padding: const EdgeInsets.fromLTRB(16, 32, 16, 24),
                color: Colors.green,
                child: Column(
                  children: [
                    Align(
                      alignment: Alignment.topRight,
                      child: IconButton(
                        icon: const Icon(Icons.close, color: Colors.white),
                        onPressed: onHome,
                      ),
                    ),
                    const Icon(Icons.check_circle, color: Colors.white, size: 64),
                    const SizedBox(height: 8),
                    const Text(
                      "Booking Confirmed!",
                      style: TextStyle(color: Colors.white, fontSize: 20, fontWeight: FontWeight.w600),
                    ),
                    const SizedBox(height: 4),
                    const Text(
                      "Your chef will arrive in 2-3 hours",
                      style: TextStyle(color: Colors.white70),
                    ),
                  ],
                ),
              ),

              const SizedBox(height: 16),

              // Chef Info
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 32,
                        backgroundColor: Colors.grey.shade200,
                        backgroundImage: chef.image.isNotEmpty
                            ? NetworkImage(chef.image)
                            : null,
                        onBackgroundImageError: chef.image.isNotEmpty
                            ? (_, _) {}
                            : null,
                        child: chef.image.isEmpty
                            ? Text(
                                chef.name.isNotEmpty ? chef.name[0] : 'C',
                                style: const TextStyle(fontSize: 28, fontWeight: FontWeight.bold),
                              )
                            : null,
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(chef.name, style: const TextStyle(fontWeight: FontWeight.bold)),
                            Text(chef.cuisines.join(", "), style: const TextStyle(fontSize: 12, color: Colors.grey)),
                            const SizedBox(height: 4),
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                              decoration: BoxDecoration(
                                color: Colors.blueGrey,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Text(chef.gender, style: const TextStyle(color: Colors.white, fontSize: 10)),
                            ),
                          ],
                        ),
                      ),
                      Column(
                        children: [
                          IconButton(icon: const Icon(Icons.message), onPressed: onChat),
                          IconButton(icon: const Icon(Icons.phone), onPressed: () {}),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Booking Details
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Booking Details", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      ListTile(
                        leading: const Icon(Icons.calendar_today, size: 20),
                        title: Text(DateFormat('yyyy-MM-dd').format(bookingData['date'])),
                        subtitle: Text(bookingData['time']),
                      ),
                      ListTile(
                        leading: const Icon(Icons.location_on, size: 20),
                        title: const Text("Service Address"),
                        subtitle: Text(bookingData['address']),
                      ),
                      ListTile(
                        leading: const Icon(Icons.access_time, size: 20),
                        title: const Text("Estimated Arrival"),
                        subtitle: Text(DateFormat.jm().format(estimatedArrival)),
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Service Info
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Service Information", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      GridView(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: 2,
                          childAspectRatio: 3,
                          crossAxisSpacing: 8,
                          mainAxisSpacing: 4,
                        ),
                        children: [
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Service Type", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              Text(bookingData['serviceType'].toString().replaceAll('-', ' '), style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Guest Count", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              Text("${bookingData['guestCount']} people", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Total Paid", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              Text("Rs. ${bookingData['total']}", style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text("Booking ID", style: TextStyle(color: Colors.grey, fontSize: 12)),
                              Text(displayBookingId, style: const TextStyle(fontWeight: FontWeight.bold)),
                            ],
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Status Timeline
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text("Status", style: TextStyle(fontWeight: FontWeight.bold)),
                      const SizedBox(height: 8),
                      Column(
                        children: [
                          statusRow(true, "Booking Confirmed", "Just now"),
                          statusRow(false, "Chef Preparation", "In progress"),
                          statusRow(false, "On the way", "Pending"),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),

              // Important Notes
              Card(
                margin: const EdgeInsets.symmetric(horizontal: 16),
                color: Colors.amber[50],
                child: Padding(
                  padding: const EdgeInsets.all(12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text("Important Notes", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.amber[800])),
                      const SizedBox(height: 4),
                      Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text("• Chef will call before arrival", style: TextStyle(fontSize: 12, color: Colors.amber[700])),
                          Text("• Please keep ingredients ready if discussed", style: TextStyle(fontSize: 12, color: Colors.amber[700])),
                          Text("• Kitchen access should be clean and available", style: TextStyle(fontSize: 12, color: Colors.amber[700])),
                          Text("• Payment already processed", style: TextStyle(fontSize: 12, color: Colors.amber[700])),
                        ],
                      ),
                    ],
                  ),
                ),
              ),

              const SizedBox(height: 16),
            ],
          ),
        ),
      ),

      // Bottom Actions
      bottomNavigationBar: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // Rate Chef Button
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  RatingDialog.show(
                    context,
                    chefId: chef.id,
                    chefName: chef.name,
                    bookingId: bookingId ?? displayBookingId,
                  );
                },
                icon: const Icon(Icons.star, color: Colors.amber),
                label: const Text("Rate Your Chef"),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.amber[50],
                  foregroundColor: Colors.amber[800],
                  padding: const EdgeInsets.symmetric(vertical: 12),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onChat,
                    icon: const Icon(Icons.message),
                    label: const Text("Chat"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: onTrackChef,
                    icon: const Icon(Icons.navigation),
                    label: const Text("Track Chef"),
                    style: ElevatedButton.styleFrom(backgroundColor: Colors.grey[300], foregroundColor: Colors.black),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton(
                    onPressed: onHome,
                    child: const Text("Go Home"),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton(
                    onPressed: () {
                      // Cancel Booking Modal can be implemented here
                    },
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.red,
                      side: const BorderSide(color: Colors.red),
                    ),
                    child: const Text("Cancel Booking"),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget statusRow(bool active, String title, String subtitle) {
    return Row(
      children: [
        Container(
          width: 12,
          height: 12,
          decoration: BoxDecoration(
            color: active ? Colors.green : Colors.transparent,
            border: Border.all(color: active ? Colors.green : Colors.grey),
            shape: BoxShape.circle,
          ),
        ),
        const SizedBox(width: 8),
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: TextStyle(fontWeight: active ? FontWeight.bold : FontWeight.normal, color: active ? Colors.black : Colors.grey)),
            Text(subtitle, style: const TextStyle(fontSize: 12, color: Colors.grey)),
          ],
        ),
      ],
    );
  }
}
