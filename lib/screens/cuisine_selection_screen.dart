import 'package:flutter/material.dart';

class CuisineSelectionScreen extends StatefulWidget {
  final Function(Map<String, dynamic>) onComplete;

  const CuisineSelectionScreen({super.key, required this.onComplete});

  @override
  State<CuisineSelectionScreen> createState() => _CuisineSelectionScreenState();
}

class _CuisineSelectionScreenState extends State<CuisineSelectionScreen> {
  int step = 1;
  String selectedCuisine = "";
  List<String> selectedDishes = [];
  String selectedGender = "any";

  final cuisines = [
    {"id": "pakistani", "name": "Pakistani", "icon": "🇵🇰"},
    {"id": "chinese", "name": "Chinese", "icon": "🇨🇳"},
    {"id": "italian", "name": "Italian", "icon": "🇮🇹"},
    {"id": "continental", "name": "Continental", "icon": "🍽️"},
    {"id": "bbq", "name": "BBQ", "icon": "🍖"},
    {"id": "fast-food", "name": "Fast Food", "icon": "🍔"},
    {"id": "desserts", "name": "Desserts", "icon": "🍰"},
    {"id": "traditional", "name": "Traditional", "icon": "🥘"},
  ];

  final dishOptions = {
    "pakistani": ["Biryani", "Karahi", "Nihari", "Haleem", "Pulao", "Korma", "Sajji", "Chapli Kebab"],
    "chinese": ["Chow Mein", "Fried Rice", "Manchurian", "Spring Rolls", "Hakka Noodles", "Sweet & Sour", "Szechuan"],
    "italian": ["Pizza", "Pasta", "Lasagna", "Risotto", "Tiramisu", "Bruschetta"],
    "continental": ["Steaks", "Grilled Chicken", "Salads", "Soups", "Sandwiches"],
    "bbq": ["Tikka", "Seekh Kebab", "Malai Boti", "Beef Ribs", "Grilled Fish", "Chicken Wings"],
    "fast-food": ["Burgers", "Fries", "Hot Dogs", "Nuggets", "Wraps", "Tacos"],
    "desserts": ["Gulab Jamun", "Kheer", "Ras Malai", "Ice Cream", "Brownies", "Cake"],
    "traditional": ["Daal Chawal", "Aloo Gosht", "Saag", "Cholay", "Paya", "Maghaz"],
  };

  void toggleDish(String dish) {
    setState(() {
      if (selectedDishes.contains(dish)) {
        selectedDishes.remove(dish);
      } else {
        selectedDishes.add(dish);
      }
    });
  }

  bool canProceed() {
    if (step == 1) return selectedCuisine.isNotEmpty;
    if (step == 2) return selectedDishes.isNotEmpty;
    if (step == 3) return selectedGender.isNotEmpty;
    return false;
  }

  void handleContinue() {
    if (step < 3) {
      setState(() => step++);
    } else {
      widget.onComplete({
        "cuisine": selectedCuisine,
        "dishes": selectedDishes,
        "gender": selectedGender,
      });
    }
  }

  String getSelectedCuisineIcon() {
    final cuisine = cuisines.firstWhere(
      (c) => c["id"] == selectedCuisine,
      orElse: () => {"icon": "🍽️"},
    );
    return cuisine["icon"]!;
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
            child: Column(
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back),
                          onPressed: () {
                            if (step > 1) {
                              setState(() => step--);
                            } else {
                              Navigator.of(context).maybePop();
                            }
                          },
                        ),
                        const Text(
                          "Find Your Perfect Chef",
                          style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                      ],
                    ),
                    Text(
                      "Step $step of 3",
                      style: TextStyle(fontSize: 12, color: Colors.grey.shade600),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                // Progress bar
                Row(
                  children: List.generate(3, (i) => Expanded(
                    child: Container(
                      height: 4,
                      margin: const EdgeInsets.symmetric(horizontal: 2),
                      decoration: BoxDecoration(
                        color: i < step
                            ? Theme.of(context).primaryColor
                            : Colors.grey.shade300,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  )),
                ),
              ],
            ),
          ),

          // Content
          Expanded(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: step == 1
                  ? _buildStepCuisine()
                  : step == 2
                      ? _buildStepDishes()
                      : _buildStepGender(),
            ),
          ),

          // Footer
          Container(
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).cardColor,
              border: Border(top: BorderSide(color: Colors.grey.shade200)),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: canProceed() ? handleContinue : null,
                    style: ElevatedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 16),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: Text(step == 3 ? "Find Chefs" : "Continue"),
                  ),
                ),
                if (step > 1) ...[
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => setState(() => step--),
                    child: const Text("Back"),
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStepCuisine() {
    return Column(
      children: [
        // Header Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.restaurant_menu,
            size: 40,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "Select Cuisine Type",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "What type of food are you craving today?",
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),

        // Cuisine Grid
        GridView.count(
          crossAxisCount: 2,
          crossAxisSpacing: 12,
          mainAxisSpacing: 12,
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          children: cuisines.map((cuisine) {
            final isSelected = selectedCuisine == cuisine["id"];
            return GestureDetector(
              onTap: () => setState(() => selectedCuisine = cuisine["id"]!),
              child: Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
                      : Colors.white,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                    width: isSelected ? 2 : 1,
                  ),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(cuisine["icon"]!, style: const TextStyle(fontSize: 36)),
                    const SizedBox(height: 8),
                    Text(
                      cuisine["name"]!,
                      style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w500),
                    ),
                    if (isSelected) ...[
                      const SizedBox(height: 8),
                      Container(
                        width: 24,
                        height: 24,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                        child: const Icon(Icons.check, color: Colors.white, size: 16),
                      ),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),
      ],
    );
  }

  Widget _buildStepDishes() {
    final dishes = dishOptions[selectedCuisine] ?? [];
    return Column(
      children: [
        // Header Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Center(
            child: Text(getSelectedCuisineIcon(), style: const TextStyle(fontSize: 36)),
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "Select Dishes",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "Choose the dishes you want the chef to prepare",
          style: TextStyle(color: Colors.grey.shade600),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 24),

        // Dish Chips
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: dishes.map((dish) {
            final isSelected = selectedDishes.contains(dish);
            return GestureDetector(
              onTap: () => toggleDish(dish),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.white,
                  border: Border.all(
                    color: isSelected
                        ? Theme.of(context).primaryColor
                        : Colors.grey.shade300,
                  ),
                  borderRadius: BorderRadius.circular(20),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      dish,
                      style: TextStyle(
                        color: isSelected ? Colors.white : Colors.black87,
                        fontWeight: isSelected ? FontWeight.w500 : FontWeight.normal,
                      ),
                    ),
                    if (isSelected) ...[
                      const SizedBox(width: 4),
                      const Icon(Icons.check, color: Colors.white, size: 16),
                    ],
                  ],
                ),
              ),
            );
          }).toList(),
        ),

        // Selected dishes summary
        if (selectedDishes.isNotEmpty) ...[
          const SizedBox(height: 24),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              "Selected: ${selectedDishes.join(", ")}",
              style: const TextStyle(fontWeight: FontWeight.w500),
            ),
          ),
        ],
      ],
    );
  }

  Widget _buildStepGender() {
    return Column(
      children: [
        // Header Icon
        Container(
          width: 80,
          height: 80,
          decoration: BoxDecoration(
            color: Theme.of(context).primaryColor.withValues(alpha: 0.1),
            shape: BoxShape.circle,
          ),
          child: Icon(
            Icons.people,
            size: 40,
            color: Theme.of(context).primaryColor,
          ),
        ),
        const SizedBox(height: 16),
        const Text(
          "Chef Gender Preference",
          style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 8),
        Text(
          "Select your preferred chef gender (optional)",
          style: TextStyle(color: Colors.grey.shade600),
        ),
        const SizedBox(height: 24),

        // Gender Options
        _buildGenderOption(
          value: "male",
          emoji: "👨‍🍳",
          title: "Male Chef",
          subtitle: "Show only male chefs",
        ),
        const SizedBox(height: 12),
        _buildGenderOption(
          value: "female",
          emoji: "👩‍🍳",
          title: "Female Chef",
          subtitle: "Show only female chefs",
        ),
        const SizedBox(height: 12),
        _buildGenderOption(
          value: "any",
          emoji: "👥",
          title: "No Preference",
          subtitle: "Show all available chefs",
        ),
      ],
    );
  }

  Widget _buildGenderOption({
    required String value,
    required String emoji,
    required String title,
    required String subtitle,
  }) {
    final isSelected = selectedGender == value;
    return GestureDetector(
      onTap: () => setState(() => selectedGender = value),
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected
              ? Theme.of(context).primaryColor.withValues(alpha: 0.05)
              : Colors.white,
          border: Border.all(
            color: isSelected
                ? Theme.of(context).primaryColor
                : Colors.grey.shade300,
            width: isSelected ? 2 : 1,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            // Radio button
            Container(
              width: 24,
              height: 24,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(
                  color: isSelected
                      ? Theme.of(context).primaryColor
                      : Colors.grey.shade400,
                  width: 2,
                ),
              ),
              child: isSelected
                  ? Center(
                      child: Container(
                        width: 12,
                        height: 12,
                        decoration: BoxDecoration(
                          color: Theme.of(context).primaryColor,
                          shape: BoxShape.circle,
                        ),
                      ),
                    )
                  : null,
            ),
            const SizedBox(width: 16),
            Text(emoji, style: const TextStyle(fontSize: 28)),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: const TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                  Text(
                    subtitle,
                    style: TextStyle(
                      fontSize: 12,
                      color: Colors.grey.shade600,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
