import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import '../widgets/cached_chef_image.dart';
import '../services/commission_service.dart';
import 'commission_payment_screen.dart';

/// Chef Earnings Screen - Shows earnings, completed jobs, commission tracking
///
/// This screen displays the COD (Cash on Delivery) commission model:
/// - Chef's total earnings (cash collected from customers)
/// - Platform commission (10% deducted from earnings)
/// - Pending commission to be paid to platform via EasyPaisa
/// - Payment history and completed jobs
class ChefEarningsScreen extends StatefulWidget {
  final VoidCallback? onBack;

  const ChefEarningsScreen({super.key, this.onBack});

  @override
  State<ChefEarningsScreen> createState() => _ChefEarningsScreenState();
}

class _ChefEarningsScreenState extends State<ChefEarningsScreen> {
  final _firestore = FirebaseFirestore.instance;
  final _auth = FirebaseAuth.instance;

  String _selectedFilter = 'all'; // all, week, month
  bool _isLoading = true;

  double _totalEarnings = 0;
  double _weekEarnings = 0;
  double _monthEarnings = 0;
  int _completedJobs = 0;
  List<Map<String, dynamic>> _completedBookings = [];

  // Commission tracking
  Map<String, dynamic> _commissionSummary = {};
  double _pendingCommission = 0;
  double _paidCommission = 0;
  double _lifetimeEarnings = 0; // From Firestore - NEVER reset
  double _currentCycleEarnings = 0; // Resets when commission is paid
  double _earningCycleThreshold = 5000; // Threshold for blocking orders
  double _cycleProgressPercentage = 0;
  double _earningsUntilBlock = 5000;

  @override
  void initState() {
    super.initState();
    _loadEarnings();
    _loadCommissionData();
  }

  Future<void> _loadCommissionData() async {
    try {
      final summary = await CommissionService.getChefCommissionSummary();
      if (mounted) {
        setState(() {
          _commissionSummary = summary;
          _pendingCommission = (summary['commission_pending'] ?? 0.0) as double;
          _lifetimeEarnings = (summary['total_earnings'] ?? 0.0) as double;
          _paidCommission = (summary['commission_paid'] ?? 0.0) as double;
          _currentCycleEarnings = (summary['current_cycle_earnings'] ?? 0.0) as double;
          _earningCycleThreshold = (summary['earning_cycle_threshold'] ?? 5000.0) as double;
          _cycleProgressPercentage = (summary['cycle_progress_percentage'] ?? 0.0) as double;
          _earningsUntilBlock = (summary['earnings_until_block'] ?? 5000.0) as double;
        });
      }
    } catch (e) {
      debugPrint('Error loading commission data: $e');
    }
  }

  Future<void> _loadEarnings() async {
    try {
      final uid = _auth.currentUser?.uid;
      if (uid == null) return;

      final now = DateTime.now();
      final weekAgo = now.subtract(const Duration(days: 7));
      final monthAgo = now.subtract(const Duration(days: 30));

      // Get all completed bookings
      final snapshot = await _firestore
          .collection('bookings')
          .where('chefId', isEqualTo: uid)
          .where('status', isEqualTo: 'completed')
          .orderBy('completedAt', descending: true)
          .get();

      double total = 0;
      double week = 0;
      double month = 0;
      List<Map<String, dynamic>> bookings = [];

      for (var doc in snapshot.docs) {
        final data = doc.data();
        final price = (data['price'] ?? data['total'] ?? 0).toDouble();
        final completedAt = (data['completedAt'] as Timestamp?)?.toDate();

        total += price;

        if (completedAt != null) {
          if (completedAt.isAfter(weekAgo)) {
            week += price;
          }
          if (completedAt.isAfter(monthAgo)) {
            month += price;
          }
        }

        // Get customer details
        String customerName = 'Customer';
        String customerImage = '';
        if (data['customerId'] != null) {
          final customerDoc = await _firestore
              .collection('users')
              .doc(data['customerId'])
              .get();
          if (customerDoc.exists) {
            customerName = customerDoc.data()?['name'] ?? 'Customer';
            customerImage = customerDoc.data()?['image'] ?? '';
          }
        }

        bookings.add({
          'id': doc.id,
          'customerName': customerName,
          'customerImage': customerImage,
          'price': price,
          'date': data['date'] ?? '',
          'serviceType': data['serviceType'] ?? 'Cooking Service',
          'completedAt': completedAt,
        });
      }

      if (mounted) {
        setState(() {
          _totalEarnings = total;
          _weekEarnings = week;
          _monthEarnings = month;
          _completedJobs = snapshot.docs.length;
          _completedBookings = bookings;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<Map<String, dynamic>> get _filteredBookings {
    if (_selectedFilter == 'all') return _completedBookings;

    final now = DateTime.now();
    final cutoff = _selectedFilter == 'week'
        ? now.subtract(const Duration(days: 7))
        : now.subtract(const Duration(days: 30));

    return _completedBookings.where((booking) {
      final completedAt = booking['completedAt'] as DateTime?;
      return completedAt != null && completedAt.isAfter(cutoff);
    }).toList();
  }

  double get _filteredEarnings {
    switch (_selectedFilter) {
      case 'week':
        return _weekEarnings;
      case 'month':
        return _monthEarnings;
      default:
        return _totalEarnings;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        leading: widget.onBack != null
            ? IconButton(
                icon: const Icon(Icons.arrow_back),
                onPressed: widget.onBack,
              )
            : null,
        title: const Text('My Earnings'),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: () {
              setState(() => _isLoading = true);
              _loadEarnings();
              _loadCommissionData();
            },
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : RefreshIndicator(
              onRefresh: () async {
                await _loadEarnings();
                await _loadCommissionData();
              },
              child: SingleChildScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                child: Column(
                  children: [
                    // Earnings Summary Card
                    _buildEarningsSummaryCard(),

                    // Commission Card (COD Model)
                    _buildCommissionCard(),
                    // Filter Chips
                    _buildFilterChips(),

                    // Stats Row
                    _buildStatsRow(),

                    // Completed Jobs Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'Completed Jobs (${_filteredBookings.length})',
                            style: const TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            'Rs. ${_filteredEarnings.toStringAsFixed(0)}',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                              color: Colors.green[700],
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Completed Jobs List
                    if (_filteredBookings.isEmpty)
                      _buildEmptyState()
                    else
                      ..._filteredBookings.map((booking) => _buildJobCard(booking)),

                    const SizedBox(height: 100),
                  ],
                ),
              ),
            ),
    );
  }

  Widget _buildEarningsSummaryCard() {
    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [Colors.green.shade400, Colors.green.shade700],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: Colors.green.withValues(alpha: 0.3),
            blurRadius: 10,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: Column(
        children: [
          const Icon(Icons.account_balance_wallet, color: Colors.white, size: 40),
          const SizedBox(height: 12),
          const Text(
            'Total Earnings (Lifetime)',
            style: TextStyle(color: Colors.white70, fontSize: 16),
          ),
          const SizedBox(height: 8),
          // Display lifetime earnings from Firestore (NEVER reset)
          Text(
            'Rs. ${_lifetimeEarnings > 0 ? _lifetimeEarnings.toStringAsFixed(0) : _totalEarnings.toStringAsFixed(0)}',
            style: const TextStyle(
              color: Colors.white,
              fontSize: 36,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          // Explanatory text about earnings never being reset
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.2),
              borderRadius: BorderRadius.circular(12),
            ),
            child: const Text(
              '💡 Earnings are lifetime and never reset',
              style: TextStyle(
                color: Colors.white,
                fontSize: 11,
                fontWeight: FontWeight.w500,
              ),
            ),
          ),
          const SizedBox(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceAround,
            children: [
              _buildEarningsSubStat('This Week', 'Rs. ${_weekEarnings.toStringAsFixed(0)}'),
              Container(
                width: 1,
                height: 40,
                color: Colors.white30,
              ),
              _buildEarningsSubStat('This Month', 'Rs. ${_monthEarnings.toStringAsFixed(0)}'),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildEarningsSubStat(String label, String value) {
    return Column(
      children: [
        Text(
          value,
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 4),
        Text(
          label,
          style: const TextStyle(color: Colors.white70, fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildFilterChips() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          _buildFilterChip('All Time', 'all'),
          const SizedBox(width: 8),
          _buildFilterChip('This Week', 'week'),
          const SizedBox(width: 8),
          _buildFilterChip('This Month', 'month'),
        ],
      ),
    );
  }

  Widget _buildFilterChip(String label, String value) {
    final isSelected = _selectedFilter == value;
    return FilterChip(
      label: Text(label),
      selected: isSelected,
      onSelected: (selected) {
        setState(() => _selectedFilter = value);
      },
      selectedColor: Colors.green.shade100,
      checkmarkColor: Colors.green.shade700,
    );
  }

  Widget _buildStatsRow() {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Row(
        children: [
          Expanded(
            child: _buildStatCard(
              'Completed Jobs',
              '$_completedJobs',
              Icons.check_circle,
              Colors.blue,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: _buildStatCard(
              'Avg. Per Job',
              _completedJobs > 0
                  ? 'Rs. ${(_totalEarnings / _completedJobs).toStringAsFixed(0)}'
                  : 'Rs. 0',
              Icons.trending_up,
              Colors.orange,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatCard(String label, String value, IconData icon, Color color) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        children: [
          Icon(icon, color: color, size: 28),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 20,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              color: Colors.grey[600],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildEmptyState() {
    return Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        children: [
          Icon(Icons.receipt_long_outlined, size: 80, color: Colors.grey[400]),
          const SizedBox(height: 16),
          const Text(
            'No completed jobs',
            style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 8),
          Text(
            'Completed bookings will appear here',
            style: TextStyle(color: Colors.grey[600]),
          ),
        ],
      ),
    );
  }

  Widget _buildJobCard(Map<String, dynamic> booking) {
    final completedAt = booking['completedAt'] as DateTime?;
    final dateStr = completedAt != null
        ? '${completedAt.day}/${completedAt.month}/${completedAt.year}'
        : booking['date'] ?? '';

    return Card(
      margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
      child: ListTile(
        leading: CachedChefAvatar(
          imageUrl: booking['customerImage'],
          name: booking['customerName'],
          radius: 24,
        ),
        title: Text(
          booking['customerName'] ?? 'Customer',
          style: const TextStyle(fontWeight: FontWeight.w500),
        ),
        subtitle: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(booking['serviceType'] ?? 'Service'),
            Text(
              dateStr,
              style: TextStyle(fontSize: 12, color: Colors.grey[500]),
            ),
          ],
        ),
        trailing: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Text(
              'Rs. ${(booking['price'] as double).toStringAsFixed(0)}',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                color: Colors.green[700],
                fontSize: 16,
              ),
            ),
            const Icon(Icons.check_circle, color: Colors.green, size: 16),
          ],
        ),
        isThreeLine: true,
      ),
    );
  }

  /// Commission Card - Shows cycle earnings, pending commission and pay button
  /// Part of the EARNING CYCLE BASED COD (Cash on Delivery) commission model
  ///
  /// KEY BUSINESS RULE:
  /// "Chef lifetime earnings are permanent. Orders are blocked only when unpaid
  /// cycle earnings reach 5000 PKR, and unblocked after commission settlement."
  Widget _buildCommissionCard() {
    final shouldBlockOrders = (_commissionSummary['should_block_orders'] ?? false) as bool;
    final paymentPending = (_commissionSummary['commission_payment_pending'] ?? false) as bool;
    final isNearThreshold = _currentCycleEarnings >= _earningCycleThreshold * 0.8;
    final isAtThreshold = _currentCycleEarnings >= _earningCycleThreshold;

    return Container(
      margin: const EdgeInsets.all(16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: isAtThreshold
            ? Colors.red.shade50
            : isNearThreshold
                ? Colors.orange.shade50
                : Colors.green.shade50,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: isAtThreshold
              ? Colors.red.shade200
              : isNearThreshold
                  ? Colors.orange.shade200
                  : Colors.green.shade200,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Header
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Row(
                children: [
                  Icon(
                    isAtThreshold
                        ? Icons.block
                        : isNearThreshold
                            ? Icons.warning_amber_rounded
                            : Icons.check_circle,
                    color: isAtThreshold
                        ? Colors.red.shade700
                        : isNearThreshold
                            ? Colors.orange.shade700
                            : Colors.green.shade700,
                    size: 24,
                  ),
                  const SizedBox(width: 8),
                  Text(
                    'Earning Cycle',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 16,
                      color: isAtThreshold
                          ? Colors.red.shade800
                          : isNearThreshold
                              ? Colors.orange.shade800
                              : Colors.green.shade800,
                    ),
                  ),
                ],
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                decoration: BoxDecoration(
                  color: isAtThreshold
                      ? Colors.red.shade100
                      : isNearThreshold
                          ? Colors.orange.shade100
                          : Colors.green.shade100,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${CommissionService.commissionPercentage.toStringAsFixed(0)}% commission',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 11,
                    color: isAtThreshold
                        ? Colors.red.shade800
                        : isNearThreshold
                            ? Colors.orange.shade800
                            : Colors.green.shade800,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Current Cycle Earnings Progress Bar
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  const Text(
                    'Current Cycle Earnings',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    'Rs. ${_currentCycleEarnings.toStringAsFixed(0)} / ${_earningCycleThreshold.toStringAsFixed(0)}',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.bold,
                      color: isAtThreshold
                          ? Colors.red.shade700
                          : isNearThreshold
                              ? Colors.orange.shade700
                              : Colors.green.shade700,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 8),
              // Progress bar
              Stack(
                children: [
                  Container(
                    height: 10,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade200,
                      borderRadius: BorderRadius.circular(5),
                    ),
                  ),
                  FractionallySizedBox(
                    widthFactor: (_cycleProgressPercentage / 100).clamp(0.0, 1.0),
                    child: Container(
                      height: 10,
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          colors: isAtThreshold
                              ? [Colors.red.shade400, Colors.red.shade600]
                              : isNearThreshold
                                  ? [Colors.orange.shade400, Colors.orange.shade600]
                                  : [Colors.green.shade400, Colors.green.shade600],
                        ),
                        borderRadius: BorderRadius.circular(5),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                isAtThreshold
                    ? '⚠️ Threshold reached! Pay commission to continue.'
                    : 'Rs. ${_earningsUntilBlock.toStringAsFixed(0)} more until orders blocked',
                style: TextStyle(
                  fontSize: 11,
                  color: isAtThreshold
                      ? Colors.red.shade700
                      : Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),

          // Pending and Paid Commission Row
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Commission Pending',
                      style: TextStyle(
                        color: Colors.grey,
                        fontSize: 12,
                      ),
                    ),
                    Text(
                      'Rs. ${_pendingCommission.toStringAsFixed(0)}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: _pendingCommission > 0
                            ? Colors.orange.shade700
                            : Colors.green.shade700,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                width: 1,
                height: 40,
                color: Colors.grey.shade300,
              ),
              Expanded(
                child: Padding(
                  padding: const EdgeInsets.only(left: 16),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Total Paid',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                      Text(
                        'Rs. ${_paidCommission.toStringAsFixed(0)}',
                        style: TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: Colors.green.shade700,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),

          // Warning message if orders are blocked
          if (shouldBlockOrders) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.red.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.block, color: Colors.red.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'New orders blocked! Cycle earnings reached Rs. ${_earningCycleThreshold.toStringAsFixed(0)}. Pay commission to start new cycle.',
                      style: TextStyle(
                        color: Colors.red.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Payment pending notice
          if (paymentPending) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Colors.blue.shade50,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.blue.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.hourglass_empty, color: Colors.blue.shade700, size: 20),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Payment under review. New cycle will start after approval.',
                      style: TextStyle(
                        color: Colors.blue.shade700,
                        fontSize: 12,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],

          // Pay Commission Button
          if (_pendingCommission > 0 && !paymentPending) ...[
            const SizedBox(height: 16),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => CommissionPaymentScreen(
                        onBack: () => Navigator.pop(context),
                        onPaymentSuccess: () {
                          _loadCommissionData();
                        },
                      ),
                    ),
                  );
                },
                icon: const Icon(Icons.payment, size: 18),
                label: Text(
                  shouldBlockOrders
                      ? 'Pay Commission to Unblock Orders'
                      : 'Pay Commission via EasyPaisa',
                ),
                style: ElevatedButton.styleFrom(
                  backgroundColor: shouldBlockOrders
                      ? Colors.red.shade600
                      : Colors.orange.shade600,
                  foregroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(vertical: 12),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8),
                  ),
                ),
              ),
            ),
          ],

          // Info text
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Row(
              children: [
                Icon(Icons.info_outline, color: Colors.grey.shade600, size: 16),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Lifetime earnings are never reset. Orders blocked at Rs. ${_earningCycleThreshold.toStringAsFixed(0)} cycle earnings. Pay commission to start new cycle.',
                    style: TextStyle(
                      color: Colors.grey.shade600,
                      fontSize: 10,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
