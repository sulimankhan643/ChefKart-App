import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../models/chef.dart';
import '../models/review.dart';
import '../services/rating_service.dart';
import '../widgets/cached_chef_image.dart';

class ChefProfileScreen extends StatefulWidget {
  final Chef chef;
  final VoidCallback onBack;
  final VoidCallback onBook;

  const ChefProfileScreen({super.key, required this.chef, required this.onBack, required this.onBook});

  @override
  State<ChefProfileScreen> createState() => _ChefProfileScreenState();
}

class _ChefProfileScreenState extends State<ChefProfileScreen> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Review> _reviews = [];
  bool _loadingReviews = true;
  bool _isFavorite = false;

  // Default skills if chef doesn't have any
  List<String> get _chefSkills {
    if (widget.chef.skills.isNotEmpty) return widget.chef.skills;
    return [
      'Home Cooking',
      'Event Catering',
      'Menu Planning',
      'Kitchen Management',
      'Food Presentation',
      'Hygiene Standards',
    ];
  }

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 4, vsync: this);
    _loadReviews();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadReviews() async {
    final reviews = await RatingService.getChefReviewsList(widget.chef.id);
    if (mounted) {
      setState(() {
        _reviews = reviews;
        _loadingReviews = false;
      });
    }
  }

  String _formatDate(DateTime date) {
    final now = DateTime.now();
    final difference = now.difference(date);

    if (difference.inDays == 0) {
      if (difference.inHours == 0) {
        return '${difference.inMinutes} min ago';
      }
      return '${difference.inHours} hours ago';
    } else if (difference.inDays == 1) {
      return 'Yesterday';
    } else if (difference.inDays < 7) {
      return '${difference.inDays} days ago';
    } else if (difference.inDays < 30) {
      return '${(difference.inDays / 7).floor()} weeks ago';
    } else {
      return DateFormat('MMM d, yyyy').format(date);
    }
  }

  @override
  Widget build(BuildContext context) {
    final chef = widget.chef;
    final primaryColor = Theme.of(context).primaryColor;

    return Scaffold(
      backgroundColor: Colors.grey[50],
      body: CustomScrollView(
        slivers: [
          // Beautiful App Bar with Chef Image
          SliverAppBar(
            expandedHeight: 280,
            pinned: true,
            stretch: true,
            backgroundColor: primaryColor,
            leading: Container(
              margin: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: Colors.black.withValues(alpha: 0.3),
                shape: BoxShape.circle,
              ),
              child: IconButton(
                icon: const Icon(Icons.arrow_back, color: Colors.white),
                onPressed: widget.onBack,
              ),
            ),
            actions: [
              Container(
                margin: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: Icon(
                    _isFavorite ? Icons.favorite : Icons.favorite_border,
                    color: _isFavorite ? Colors.red : Colors.white,
                  ),
                  onPressed: () => setState(() => _isFavorite = !_isFavorite),
                ),
              ),
              Container(
                margin: const EdgeInsets.only(right: 8),
                decoration: BoxDecoration(
                  color: Colors.black.withValues(alpha: 0.3),
                  shape: BoxShape.circle,
                ),
                child: IconButton(
                  icon: const Icon(Icons.share, color: Colors.white),
                  onPressed: () {},
                ),
              ),
            ],
            flexibleSpace: FlexibleSpaceBar(
              background: Stack(
                fit: StackFit.expand,
                children: [
                  // Chef Image
                  CachedChefImage(
                    imageUrl: chef.image,
                    width: double.infinity,
                    height: 280,
                    borderRadius: BorderRadius.zero,
                    placeholderText: chef.name,
                  ),
                  // Gradient Overlay
                  Container(
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.transparent,
                          Colors.black.withValues(alpha: 0.7),
                        ],
                      ),
                    ),
                  ),
                  // Chef Info Overlay
                  Positioned(
                    bottom: 16,
                    left: 16,
                    right: 16,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Name and Verified Badge
                        Row(
                          children: [
                            Flexible(
                              child: Text(
                                chef.name,
                                style: const TextStyle(
                                  color: Colors.white,
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  shadows: [Shadow(blurRadius: 10, color: Colors.black54)],
                                ),
                              ),
                            ),
                            if (chef.isVerified) ...[
                              const SizedBox(width: 8),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                decoration: BoxDecoration(
                                  color: Colors.green,
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(Icons.verified, color: Colors.white, size: 14),
                                    SizedBox(width: 4),
                                    Text('Verified', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold)),
                                  ],
                                ),
                              ),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        // Rating and Location
                        Row(
                          children: [
                            // Rating
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                              decoration: BoxDecoration(
                                color: Colors.amber,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  const Icon(Icons.star, color: Colors.white, size: 16),
                                  const SizedBox(width: 4),
                                  Text(
                                    chef.rating.toStringAsFixed(1),
                                    style: const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
                                  ),
                                ],
                              ),
                            ),
                            const SizedBox(width: 8),
                            Text(
                              '(${chef.reviewCount} reviews)',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                            const SizedBox(width: 12),
                            const Icon(Icons.location_on, color: Colors.white70, size: 16),
                            const SizedBox(width: 4),
                            Text(
                              '${chef.distance.toStringAsFixed(1)} km',
                              style: const TextStyle(color: Colors.white70, fontSize: 13),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  // Online Status Badge
                  Positioned(
                    top: 100,
                    right: 16,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                      decoration: BoxDecoration(
                        color: chef.isOnline ? Colors.green : Colors.grey,
                        borderRadius: BorderRadius.circular(20),
                        boxShadow: [
                          BoxShadow(
                            color: Colors.black.withValues(alpha: 0.3),
                            blurRadius: 8,
                          ),
                        ],
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Container(
                            width: 8,
                            height: 8,
                            decoration: const BoxDecoration(
                              color: Colors.white,
                              shape: BoxShape.circle,
                            ),
                          ),
                          const SizedBox(width: 6),
                          Text(
                            chef.isOnline ? 'Online' : 'Offline',
                            style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Quick Info Cards
          SliverToBoxAdapter(
            child: Container(
              padding: const EdgeInsets.all(16),
              child: Column(
                children: [
                  // Quick Stats Row
                  Row(
                    children: [
                      Expanded(
                        child: _buildQuickStatCard(
                          icon: Icons.restaurant_menu,
                          iconColor: Colors.orange,
                          label: 'Cuisines',
                          value: chef.cuisines.length.toString(),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickStatCard(
                          icon: Icons.work_history,
                          iconColor: Colors.blue,
                          label: 'Experience',
                          value: chef.experience.isNotEmpty ? chef.experience : '5+ Years',
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: _buildQuickStatCard(
                          icon: Icons.payments,
                          iconColor: Colors.green,
                          label: 'Starting',
                          value: 'Rs. ${chef.startingPrice}',
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 16),

                  // Cuisines Chips
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.restaurant, color: primaryColor, size: 20),
                            const SizedBox(width: 8),
                            const Text(
                              'Cuisines',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        Wrap(
                          spacing: 8,
                          runSpacing: 8,
                          children: chef.cuisines.map((cuisine) => Container(
                            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                            decoration: BoxDecoration(
                              gradient: LinearGradient(
                                colors: [primaryColor.withValues(alpha: 0.1), primaryColor.withValues(alpha: 0.05)],
                              ),
                              borderRadius: BorderRadius.circular(20),
                              border: Border.all(color: primaryColor.withValues(alpha: 0.3)),
                            ),
                            child: Text(
                              cuisine,
                              style: TextStyle(
                                color: primaryColor,
                                fontWeight: FontWeight.w600,
                                fontSize: 13,
                              ),
                            ),
                          )).toList(),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 12),

                  // Location & Gender Info
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(16),
                    decoration: BoxDecoration(
                      color: Colors.white,
                      borderRadius: BorderRadius.circular(16),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.05),
                          blurRadius: 10,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.red.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: const Icon(Icons.location_on, color: Colors.red, size: 20),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text('Location', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                    Text(
                                      chef.city.isNotEmpty ? chef.city : 'Peshawar',
                                      style: const TextStyle(fontWeight: FontWeight.w600),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                        Container(
                          width: 1,
                          height: 40,
                          color: Colors.grey.shade200,
                        ),
                        Expanded(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: Colors.purple.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  chef.gender.toLowerCase() == 'female' ? Icons.female : Icons.male,
                                  color: Colors.purple,
                                  size: 20,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  const Text('Gender', style: TextStyle(color: Colors.grey, fontSize: 12)),
                                  Text(
                                    chef.gender.isNotEmpty ? chef.gender : 'Not specified',
                                    style: const TextStyle(fontWeight: FontWeight.w600),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Tab Bar
          SliverPersistentHeader(
            pinned: true,
            delegate: _SliverAppBarDelegate(
              TabBar(
                controller: _tabController,
                labelColor: primaryColor,
                unselectedLabelColor: Colors.grey,
                indicatorColor: primaryColor,
                indicatorWeight: 3,
                labelStyle: const TextStyle(fontWeight: FontWeight.bold),
                tabs: const [
                  Tab(text: 'About'),
                  Tab(text: 'Skills'),
                  Tab(text: 'Schedule'),
                  Tab(text: 'Reviews'),
                ],
              ),
            ),
          ),

          // Tab Content
          SliverFillRemaining(
            child: TabBarView(
              controller: _tabController,
              children: [
                _buildAboutTab(),
                _buildSkillsTab(),
                _buildAvailabilityTab(),
                _buildReviewsTab(),
              ],
            ),
          ),
        ],
      ),
      // Bottom Action Bar
      bottomNavigationBar: Container(
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
          child: Row(
            children: [
              // Price Info
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Starting from', style: TextStyle(color: Colors.grey, fontSize: 12)),
                    Text(
                      'Rs. ${chef.startingPrice}',
                      style: TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: primaryColor,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 16),
              // Book Now Button (Chat is only allowed after order is placed)
              Expanded(
                flex: 2,
                child: ElevatedButton(
                  onPressed: widget.onBook,
                  style: ElevatedButton.styleFrom(
                    backgroundColor: primaryColor,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(12),
                    ),
                    elevation: 0,
                  ),
                  child: const Text(
                    'Book Now',
                    style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildQuickStatCard({
    required IconData icon,
    required Color iconColor,
    required String label,
    required String value,
  }) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: iconColor.withValues(alpha: 0.1),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: iconColor, size: 22),
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            textAlign: TextAlign.center,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            label,
            style: TextStyle(color: Colors.grey[600], fontSize: 11),
          ),
        ],
      ),
    );
  }

  Widget _buildAboutTab() {
    final chef = widget.chef;
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // About Section
          _buildSectionCard(
            title: 'About Me',
            icon: Icons.person_outline,
            child: Text(
              chef.about.isNotEmpty
                  ? chef.about
                  : 'Experienced home chef specializing in authentic cuisine. Passionate about creating delicious meals with fresh ingredients and traditional recipes. I believe in bringing joy to families through homemade food.',
              style: TextStyle(color: Colors.grey[700], height: 1.6),
            ),
          ),
          const SizedBox(height: 16),

          // Signature Dishes
          if (chef.dishes.isNotEmpty)
            _buildSectionCard(
              title: 'Signature Dishes',
              icon: Icons.local_dining,
              child: Wrap(
                spacing: 8,
                runSpacing: 8,
                children: chef.dishes.map((dish) => Container(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                  decoration: BoxDecoration(
                    color: Colors.orange.shade50,
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: Colors.orange.shade200),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('🍽️ ', style: TextStyle(fontSize: 14)),
                      Text(
                        dish,
                        style: TextStyle(color: Colors.orange.shade800, fontWeight: FontWeight.w500),
                      ),
                    ],
                  ),
                )).toList(),
              ),
            ),
          const SizedBox(height: 16),

          // Pricing
          _buildSectionCard(
            title: 'Pricing',
            icon: Icons.payments,
            child: Column(
              children: [
                _buildPriceItem('One-time Service', 'Rs. ${chef.startingPrice}', Icons.schedule),
                const Divider(height: 24),
                _buildPriceItem('Event Catering', 'Rs. 500/person', Icons.celebration),
                const Divider(height: 24),
                _buildPriceItem('Monthly Package', 'Rs. ${chef.startingPrice * 20}', Icons.calendar_month),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSkillsTab() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          _buildSectionCard(
            title: 'Professional Skills',
            icon: Icons.psychology,
            child: Column(
              children: _chefSkills.map((skill) => _buildSkillItem(skill)).toList(),
            ),
          ),
          const SizedBox(height: 16),
          _buildSectionCard(
            title: 'Certifications',
            icon: Icons.verified_user,
            child: Column(
              children: [
                _buildCertificationItem('Food Safety Certified', Icons.health_and_safety, Colors.green),
                _buildCertificationItem('Professional Cooking License', Icons.card_membership, Colors.blue),
                _buildCertificationItem('Hygiene Training Complete', Icons.clean_hands, Colors.teal),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildAvailabilityTab() {
    final chef = widget.chef;
    final days = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Current Status Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(20),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: chef.isOnline
                    ? [Colors.green.shade400, Colors.green.shade600]
                    : [Colors.grey.shade400, Colors.grey.shade600],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.2),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    chef.isOnline ? Icons.check_circle : Icons.pause_circle,
                    color: Colors.white,
                    size: 32,
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        chef.isOnline ? 'Currently Available' : 'Currently Offline',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        chef.isOnline
                            ? 'Ready to accept bookings'
                            : 'Not accepting bookings right now',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9), fontSize: 13),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Weekly Schedule
          _buildSectionCard(
            title: 'Weekly Schedule',
            icon: Icons.calendar_today,
            child: Column(
              children: days.map((day) {
                final dayKey = day.toLowerCase();
                final isAvailable = chef.availability[dayKey] ?? true;
                return _buildDaySchedule(day, isAvailable);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildReviewsTab() {
    final chef = widget.chef;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: Column(
        children: [
          // Rating Summary Card
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [Colors.amber.shade400, Colors.orange.shade500],
              ),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    children: [
                      Text(
                        chef.rating.toStringAsFixed(1),
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 48,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: List.generate(5, (index) => Icon(
                          index < chef.rating.round() ? Icons.star : Icons.star_border,
                          color: Colors.white,
                          size: 20,
                        )),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        '${chef.reviewCount} reviews',
                        style: TextStyle(color: Colors.white.withValues(alpha: 0.9)),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),

          // Reviews List
          _buildSectionCard(
            title: 'Customer Reviews',
            icon: Icons.rate_review,
            child: _loadingReviews
                ? const Center(child: CircularProgressIndicator())
                : _reviews.isEmpty
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(32),
                          child: Column(
                            children: [
                              Icon(Icons.reviews, size: 48, color: Colors.grey[300]),
                              const SizedBox(height: 16),
                              Text(
                                'No reviews yet',
                                style: TextStyle(color: Colors.grey[500], fontSize: 16),
                              ),
                              const SizedBox(height: 8),
                              Text(
                                'Be the first to review this chef!',
                                style: TextStyle(color: Colors.grey[400], fontSize: 13),
                              ),
                            ],
                          ),
                        ),
                      )
                    : Column(
                        children: _reviews.map((review) => _buildReviewItem(review)).toList(),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionCard({required String title, required IconData icon, required Widget child}) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.05),
            blurRadius: 10,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, color: Theme.of(context).primaryColor, size: 20),
              const SizedBox(width: 8),
              Text(
                title,
                style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
              ),
            ],
          ),
          const SizedBox(height: 16),
          child,
        ],
      ),
    );
  }

  Widget _buildPriceItem(String label, String price, IconData icon) {
    return Row(
      children: [
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: Colors.green.withValues(alpha: 0.1),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(icon, color: Colors.green, size: 20),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Text(label, style: TextStyle(color: Colors.grey[700])),
        ),
        Text(
          price,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ],
    );
  }

  Widget _buildSkillItem(String skill) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: Colors.blue.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.check_circle, color: Colors.blue, size: 18),
          ),
          const SizedBox(width: 12),
          Text(skill, style: const TextStyle(fontSize: 14)),
        ],
      ),
    );
  }

  Widget _buildCertificationItem(String title, IconData icon, Color color) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: color.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: color, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(title, style: const TextStyle(fontSize: 14)),
          ),
          Icon(Icons.verified, color: color, size: 20),
        ],
      ),
    );
  }

  Widget _buildDaySchedule(String day, bool available) {
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: available ? Colors.green.withValues(alpha: 0.05) : Colors.grey.withValues(alpha: 0.05),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: available ? Colors.green.withValues(alpha: 0.2) : Colors.grey.withValues(alpha: 0.2),
        ),
      ),
      child: Row(
        children: [
          SizedBox(
            width: 90,
            child: Text(day, style: const TextStyle(fontWeight: FontWeight.w500)),
          ),
          Expanded(
            child: Text(
              available ? '9:00 AM - 9:00 PM' : 'Not Available',
              style: TextStyle(
                color: available ? Colors.green[700] : Colors.grey[500],
                fontSize: 13,
              ),
            ),
          ),
          Icon(
            available ? Icons.check_circle : Icons.cancel,
            color: available ? Colors.green : Colors.grey,
            size: 20,
          ),
        ],
      ),
    );
  }

  Widget _buildReviewItem(Review review) {
    return Container(
      margin: const EdgeInsets.only(bottom: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              CircleAvatar(
                backgroundColor: Theme.of(context).primaryColor.withValues(alpha: 0.1),
                child: Text(
                  review.customerName.isNotEmpty ? review.customerName[0].toUpperCase() : 'U',
                  style: TextStyle(color: Theme.of(context).primaryColor, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      review.customerName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    Row(
                      children: [
                        ...List.generate(5, (index) => Icon(
                          index < review.rating ? Icons.star : Icons.star_border,
                          color: Colors.amber,
                          size: 14,
                        )),
                        const SizedBox(width: 8),
                        Text(
                          _formatDate(review.createdAt),
                          style: TextStyle(color: Colors.grey[500], fontSize: 11),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          if (review.review.isNotEmpty) ...[
            const SizedBox(height: 12),
            Text(
              review.review,
              style: TextStyle(color: Colors.grey[700], height: 1.5),
            ),
          ],
        ],
      ),
    );
  }
}

// Custom delegate for sticky tab bar
class _SliverAppBarDelegate extends SliverPersistentHeaderDelegate {
  final TabBar tabBar;

  _SliverAppBarDelegate(this.tabBar);

  @override
  double get minExtent => tabBar.preferredSize.height;

  @override
  double get maxExtent => tabBar.preferredSize.height;

  @override
  Widget build(BuildContext context, double shrinkOffset, bool overlapsContent) {
    return Container(
      color: Colors.white,
      child: tabBar,
    );
  }

  @override
  bool shouldRebuild(_SliverAppBarDelegate oldDelegate) {
    return false;
  }
}

