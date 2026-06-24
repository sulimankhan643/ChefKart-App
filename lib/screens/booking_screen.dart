import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chef.dart';

class BookingScreen extends StatefulWidget {
  final Chef chef;
  final VoidCallback onBack;
  final Function(Map<String, dynamic>) onConfirm;

  const BookingScreen({super.key, required this.chef, required this.onBack, required this.onConfirm});

  @override
  State<BookingScreen> createState() => _BookingScreenState();
}

class _BookingScreenState extends State<BookingScreen> {
  String serviceType = "one-time";
  DateTime? selectedDate;
  String selectedTime = "";
  int guestCount = 4;
  String genderPreference = "no-preference";
  final addressController = TextEditingController(text: "DHA Phase 5, Street 12, Karachi");

  final List<String> timeSlots = [
    "10:00 AM",
    "12:00 PM",
    "2:00 PM",
    "4:00 PM",
    "6:00 PM",
    "8:00 PM",
  ];

  int calculateTotal() {
    int basePrice = serviceType == "one-time"
        ? widget.chef.startingPrice
        : (widget.chef.startingPrice * 1.5).round();
    int extraGuests = guestCount > 4 ? (guestCount - 4) * 200 : 0;
    return basePrice + extraGuests;
  }

  Future<void> pickDate() async {
    DateTime now = DateTime.now();
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: now,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (picked != null) setState(() => selectedDate = picked);
  }

  void handleConfirm() {
    if (selectedDate == null || selectedTime.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Please select date and time")),
      );
      return;
    }

    final bookingData = {
      "chef": widget.chef,
      "date": DateFormat('MMM dd, yyyy').format(selectedDate!),
      "time": selectedTime,
      "address": addressController.text,
      "serviceType": serviceType,
      "guestCount": guestCount,
      "genderPreference": genderPreference,
      "total": calculateTotal(),
    };

    widget.onConfirm(bookingData);
  }

  @override
  void dispose() {
    addressController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
              children: [
                IconButton(
                  icon: const Icon(Icons.arrow_back),
                  onPressed: widget.onBack,
                ),
                const SizedBox(width: 8),
                const Text(
                  "Book Chef",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
              ],
            ),
          ),

          // Chef Summary
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(bottom: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Row(
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: Colors.grey.shade200,
                  backgroundImage: widget.chef.image.isNotEmpty
                      ? NetworkImage(widget.chef.image)
                      : null,
                  onBackgroundImageError: widget.chef.image.isNotEmpty
                      ? (_, _) {}
                      : null,
                  child: widget.chef.image.isEmpty
                      ? Text(widget.chef.name.isNotEmpty ? widget.chef.name[0] : "C")
                      : null,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        widget.chef.name,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      Row(
                        children: [
                          Text(
                            widget.chef.cuisines.take(2).join(", "),
                            style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                          ),
                          const SizedBox(width: 8),
                          Container(
                            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(4),
                            ),
                            child: Text(
                              widget.chef.gender,
                              style: const TextStyle(fontSize: 10),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),

          // Form
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Service Type Card
                  _buildCard(
                    title: "Service Type",
                    child: Column(
                      children: [
                        _buildRadioOption(
                          value: "one-time",
                          groupValue: serviceType,
                          label: "One-time service",
                          subtitle: "Rs. ${widget.chef.startingPrice}",
                          onChanged: (val) => setState(() => serviceType = val!),
                        ),
                        _buildRadioOption(
                          value: "event",
                          groupValue: serviceType,
                          label: "Event catering",
                          subtitle: "Rs. ${(widget.chef.startingPrice * 1.5).round()}",
                          onChanged: (val) => setState(() => serviceType = val!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Date & Time Card
                  _buildCard(
                    title: "Date & Time",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Date Picker
                        Text(
                          "Date",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          onTap: pickDate,
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                            decoration: BoxDecoration(
                              border: Border.all(color: Colors.grey.shade300),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Row(
                              children: [
                                Icon(Icons.calendar_today, size: 18, color: Colors.grey.shade600),
                                const SizedBox(width: 12),
                                Text(
                                  selectedDate != null
                                      ? DateFormat('MMM dd, yyyy').format(selectedDate!)
                                      : "Select Date",
                                  style: TextStyle(
                                    color: selectedDate != null ? Colors.black : Colors.grey,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 16),

                        // Time Picker
                        Text(
                          "Time",
                          style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                        ),
                        const SizedBox(height: 8),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: timeSlots.map((time) {
                            final isSelected = selectedTime == time;
                            return GestureDetector(
                              onTap: () => setState(() => selectedTime = time),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                decoration: BoxDecoration(
                                  color: isSelected ? Theme.of(context).primaryColor : Colors.white,
                                  border: Border.all(
                                    color: isSelected
                                        ? Theme.of(context).primaryColor
                                        : Colors.grey.shade300,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: Text(
                                  time,
                                  style: TextStyle(
                                    color: isSelected ? Colors.white : Colors.black87,
                                    fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  ),
                                ),
                              ),
                            );
                          }).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Guest Count Card
                  _buildCard(
                    title: "Guest Count",
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                          decoration: BoxDecoration(
                            border: Border.all(color: Colors.grey.shade300),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Row(
                            children: [
                              Icon(Icons.people, size: 18, color: Colors.grey.shade600),
                              const SizedBox(width: 12),
                              Expanded(
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<int>(
                                    value: guestCount,
                                    isExpanded: true,
                                    items: List.generate(12, (i) => i + 1).map((count) {
                                      return DropdownMenuItem(
                                        value: count,
                                        child: Text("$count ${count == 1 ? 'person' : 'people'}"),
                                      );
                                    }).toList(),
                                    onChanged: (val) => setState(() => guestCount = val!),
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                        if (guestCount > 4)
                          Padding(
                            padding: const EdgeInsets.only(top: 8),
                            child: Text(
                              "Additional Rs. 200 per person for more than 4 guests",
                              style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Address Card
                  _buildCard(
                    title: "Service Address",
                    child: TextField(
                      controller: addressController,
                      decoration: InputDecoration(
                        prefixIcon: Icon(Icons.location_on, color: Colors.grey.shade600),
                        hintText: "Enter your address",
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(8),
                        ),
                        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Gender Preference Card
                  _buildCard(
                    title: "Gender Preference",
                    child: Column(
                      children: [
                        _buildRadioOption(
                          value: "no-preference",
                          groupValue: genderPreference,
                          label: "No preference",
                          onChanged: (val) => setState(() => genderPreference = val!),
                        ),
                        _buildRadioOption(
                          value: "female",
                          groupValue: genderPreference,
                          label: "Female chef only",
                          onChanged: (val) => setState(() => genderPreference = val!),
                        ),
                        _buildRadioOption(
                          value: "male",
                          groupValue: genderPreference,
                          label: "Male chef only",
                          onChanged: (val) => setState(() => genderPreference = val!),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),

                  // Price Summary Card
                  _buildCard(
                    title: "Price Summary",
                    child: Column(
                      children: [
                        _buildPriceRow(
                          "Base service (${serviceType == 'one-time' ? 'One-time' : 'Event'})",
                          serviceType == "one-time"
                              ? widget.chef.startingPrice
                              : (widget.chef.startingPrice * 1.5).round(),
                        ),
                        if (guestCount > 4)
                          _buildPriceRow(
                            "Additional guests (${guestCount - 4})",
                            (guestCount - 4) * 200,
                          ),
                        const Divider(),
                        _buildPriceRow("Total", calculateTotal(), isBold: true),
                      ],
                    ),
                  ),
                  const SizedBox(height: 100), // Space for bottom button
                ],
              ),
            ),
          ),
        ],
      ),

      // Bottom Action
      bottomNavigationBar: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: Theme.of(context).cardColor,
          border: Border(top: BorderSide(color: Colors.grey.shade200)),
        ),
        child: SafeArea(
          child: ElevatedButton(
            onPressed: (selectedDate != null && selectedTime.isNotEmpty)
                ? handleConfirm
                : null,
            style: ElevatedButton.styleFrom(
              padding: const EdgeInsets.symmetric(vertical: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            child: Text("Continue to Payment • Rs. ${calculateTotal()}"),
          ),
        ),
      ),
    );
  }

  Widget _buildCard({required String title, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).cardColor,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }

  Widget _buildRadioOption({
    required String value,
    required String groupValue,
    required String label,
    String? subtitle,
    required Function(String?) onChanged,
  }) {
    final isSelected = value == groupValue;
    return GestureDetector(
      onTap: () => onChanged(value),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 10,
                        height: 10,
                        decoration: BoxDecoration(
                          shape: BoxShape.circle,
                          color: Theme.of(context).primaryColor,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Text(label),
            ),
            if (subtitle != null)
              Text(
                subtitle,
                style: TextStyle(color: Colors.grey.shade600),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildPriceRow(String label, int amount, {bool isBold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            label,
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
          Text(
            "Rs. $amount",
            style: TextStyle(
              fontWeight: isBold ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }
}
