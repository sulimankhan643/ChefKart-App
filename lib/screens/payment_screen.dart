import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../models/chef.dart';

class PaymentScreen extends StatefulWidget {
  final Map<String, dynamic> bookingData;
  final VoidCallback onBack;
  final VoidCallback onPaymentSuccess;

  const PaymentScreen({
    super.key,
    required this.bookingData,
    required this.onBack,
    required this.onPaymentSuccess,
  });

  @override
  State<PaymentScreen> createState() => _PaymentScreenState();
}

class _PaymentScreenState extends State<PaymentScreen> {
  String selectedMethod = "easypaisa";
  String promoCode = "";
  bool promoApplied = false;
  bool isProcessing = false;

  Future<void> _processPaymentAndSaveBooking() async {
    setState(() => isProcessing = true);

    try {
      final currentUser = FirebaseAuth.instance.currentUser;
      if (currentUser == null) {
        throw Exception("User not logged in");
      }

      final bookingData = widget.bookingData;
      final chef = bookingData["chef"] is Chef ? bookingData["chef"] as Chef : null;

      final discount = promoApplied ? 200 : 0;
      final int total = bookingData["total"] ?? 0;
      final finalTotal = total - discount;

      // Get customer data
      final customerDoc = await FirebaseFirestore.instance
          .collection("users")
          .doc(currentUser.uid)
          .get();

      final customerName = customerDoc.data()?["name"] ?? "Customer";
      final customerPhone = customerDoc.data()?["phone"] ?? "";

      // Create booking in Firebase
      await FirebaseFirestore.instance.collection("bookings").add({
        "customerId": currentUser.uid,
        "customerName": customerName,
        "customerPhone": customerPhone,
        "chefId": chef?.id ?? "",
        "chefName": chef?.name ?? "Chef",
        "serviceType": bookingData["serviceType"] ?? "one-time",
        "date": bookingData["date"] ?? "",
        "time": bookingData["time"] ?? "",
        "guestCount": bookingData["guestCount"] ?? 4,
        "address": bookingData["address"] ?? "",
        "genderPreference": bookingData["genderPreference"] ?? "any",
        "total": finalTotal,
        "originalTotal": total,
        "discount": discount,
        "promoCode": promoApplied ? promoCode : "",
        "paymentMethod": selectedMethod,
        "status": "pending", // pending, accepted, rejected, completed
        "createdAt": FieldValue.serverTimestamp(),
        "updatedAt": FieldValue.serverTimestamp(),
      });

      if (mounted) {
        setState(() => isProcessing = false);

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Booking confirmed! Chef will be notified."),
            backgroundColor: Colors.green,
          ),
        );

        widget.onPaymentSuccess();
      }
    } catch (e) {
      if (mounted) {
        setState(() => isProcessing = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text("Error: $e"), backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final bookingData = widget.bookingData;
    // Attempt to get Chef object if available in bookingData
    final chef = bookingData["chef"] is Chef ? bookingData["chef"] as Chef : null;
    // Fallback for chef name if chef object is not available directly or has different structure
    final chefName = chef?.name ?? "Chef";

    final discount = promoApplied ? 200 : 0;
    final int total = bookingData["total"] ?? 0;
    final finalTotal = total - discount;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,

      // -------------------- HEADER --------------------
      body: Column(
        children: [
          Container(
            padding: const EdgeInsets.only(top: 40, left: 12, right: 12, bottom: 15),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: const Border(
                bottom: BorderSide(width: 0.5, color: Colors.black12),
              ),
            ),
            child: Row(
              children: [
                IconButton(
                  onPressed: widget.onBack,
                  icon: const Icon(Icons.arrow_back),
                ),
                const SizedBox(width: 8),
                const Text(
                  "Payment",
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
                ),
              ],
            ),
          ),

          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(14),
              child: Column(
                children: [
                  // -------------------- BOOKING SUMMARY --------------------
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _title("Booking Summary"),
                        const SizedBox(height: 8),
                        _row("Chef", chefName),
                        _row("Date & Time", "${bookingData["date"].toString().substring(0, 10)} at ${bookingData["time"]}"),
                        _row("Guests", "${bookingData["guestCount"]} people"),
                        _row("Service", bookingData["serviceType"].toString().replaceAll('-', ' ')),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // -------------------- PAYMENT METHODS --------------------
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _title("Payment Method"),
                        const SizedBox(height: 8),

                        _paymentOption("easypaisa", "Easypaisa"),
                        _paymentOption("jazzcash", "JazzCash"),
                        _paymentOption("card", "Credit / Debit Card"),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // -------------------- PROMO CODE --------------------
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _title("Promo Code"),
                        const SizedBox(height: 12),

                        Row(
                          children: [
                            Expanded(
                              child: TextField(
                                enabled: !promoApplied,
                                decoration: InputDecoration(
                                  hintText: "Enter promo code",
                                  prefixIcon: const Icon(Icons.card_giftcard, size: 20),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(10),
                                  ),
                                ),
                                onChanged: (v) => setState(() => promoCode = v),
                              ),
                            ),

                            const SizedBox(width: 10),

                            ElevatedButton(
                              onPressed: promoApplied || promoCode.isEmpty
                                  ? null
                                  : () {
                                if (promoCode.toLowerCase() == "first10") {
                                  setState(() => promoApplied = true);
                                }
                              },
                              child: Text(promoApplied ? "Applied" : "Apply"),
                            )
                          ],
                        ),

                        if (promoApplied)
                          const Padding(
                            padding: EdgeInsets.only(top: 8.0),
                            child: Text("✓ Promo code applied! Rs. 200 discount",
                                style: TextStyle(color: Colors.green)),
                          ),

                        const SizedBox(height: 4),
                        const Text(
                          'Try "FIRST10" for new customers',
                          style: TextStyle(fontSize: 12, color: Colors.black54),
                        ),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // -------------------- PRICE DETAILS --------------------
                  _card(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _title("Price Details"),
                        const SizedBox(height: 8),

                        _row("Service charge", "Rs. ${total.toString()}"),

                        if (promoApplied)
                          _row("Promo discount", "-Rs. $discount",
                              color: Colors.green),

                        const Divider(height: 22),

                        _row("Total to pay", "Rs. ${finalTotal.toString()}",
                            bold: true),
                      ],
                    ),
                  ),

                  const SizedBox(height: 14),

                  // -------------------- PAYMENT INFO --------------------
                  if (selectedMethod != "card")
                    _card(
                      color: Colors.green.withAlpha(13),
                      child: Text(
                        "You will be redirected to $selectedMethod to complete the payment. "
                            "The amount will be charged after service confirmation.",
                        style: const TextStyle(fontSize: 13, color: Colors.black54),
                      ),
                    ),
                ],
              ),
            ),
          ),

          // -------------------- PAY BUTTON --------------------
          Container(
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: const Border(top: BorderSide(width: 0.4, color: Colors.black26)),
            ),
            padding: const EdgeInsets.all(14),
            child: Column(
              children: [
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: isProcessing
                        ? null
                        : _processPaymentAndSaveBooking,
                    child: Text(
                      isProcessing
                          ? "Processing..."
                          : "Pay Rs. ${finalTotal.toString()}",
                    ),
                  ),
                ),

                const SizedBox(height: 6),
                const Text(
                  "Your payment is secure and encrypted",
                  style: TextStyle(fontSize: 11, color: Colors.black54),
                )
              ],
            ),
          ),
        ],
      ),
    );
  }

  // -------------------- WIDGET HELPERS --------------------

  Widget _card({required Widget child, Color? color}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: color ?? Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.black12, width: 0.8),
      ),
      child: child,
    );
  }

  Widget _title(String txt) {
    return Text(
      txt,
      style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w600),
    );
  }

  Widget _row(String left, String right, {Color? color, bool bold = false}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(left, style: TextStyle(fontSize: 14, color: color)),
          Text(
            right,
            style: TextStyle(
              fontSize: 14,
              color: color,
              fontWeight: bold ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
        ],
      ),
    );
  }

  Widget _paymentOption(String id, String label) {
    final isSelected = selectedMethod == id;
    return InkWell(
      onTap: () => setState(() => selectedMethod = id),
      child: Container(
        padding: const EdgeInsets.symmetric(vertical: 10),
        child: Row(
          children: [
            Container(
              width: 20,
              height: 20,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected ? Theme.of(context).primaryColor : Colors.grey,
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
            Text(label, style: const TextStyle(fontSize: 14)),
          ],
        ),
      ),
    );
  }
}
