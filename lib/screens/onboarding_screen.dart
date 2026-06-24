import 'package:flutter/material.dart';

class OnboardingScreen extends StatefulWidget {
  final VoidCallback onComplete;
  final bool disableNetworkImages;

  const OnboardingScreen({
    super.key,
    required this.onComplete,
    this.disableNetworkImages = false,
  });

  @override

  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  int currentPage = 0;
  final PageController _pageController = PageController();

  final List<Map<String, String>> pages = [
    {
      "image": "https://images.unsplash.com/photo-1556911220-bff31c812dba?w=800",
      "title": "Find Verified Home Chefs",
      "description": "Book professional chefs for any occasion, right from your home."
    },
    {
      "image": "https://images.unsplash.com/photo-1590456564344-84b24811e479?w=800",
      "title": "Customized Culinary Experiences",
      "description": "From daily meals to party catering, get personalized services."
    },
    {
      "image": "https://images.unsplash.com/photo-1565299624946-b28f40a0ae38?w=800",
      "title": "Safe, Secure, and Delicious",
      "description": "Enjoy delicious meals with verified chefs and secure payments."
    }
  ];

  Widget _buildImage(String url) {
    if (widget.disableNetworkImages) {
      return Container(
        height: 300,
        width: double.infinity,
        decoration: BoxDecoration(
          color: Colors.grey.shade300,
          borderRadius: BorderRadius.circular(16),
        ),
        child: const Icon(Icons.image, size: 80, color: Colors.grey),
      );
    }
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: Image.network(
        url,
        height: 300,
        width: double.infinity,
        fit: BoxFit.cover,
        errorBuilder: (_, _, _) => Container(
          height: 300,
          width: double.infinity,
          color: Colors.grey.shade300,
          alignment: Alignment.center,
          child: const Icon(Icons.broken_image, size: 64, color: Colors.grey),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: PageView.builder(
                controller: _pageController,
                itemCount: pages.length,
                onPageChanged: (index) => setState(() => currentPage = index),
                itemBuilder: (context, index) {
                  final page = pages[index];
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        _buildImage(page["image"]!),
                        const SizedBox(height: 32),
                        Text(
                          page["title"]!,
                          style: Theme.of(context).textTheme.headlineSmall,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        Text(
                          page["description"]!,
                          textAlign: TextAlign.center,
                          style: Theme.of(context).textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(pages.length, (index) {
                      return AnimatedContainer(
                        duration: const Duration(milliseconds: 300),
                        margin: const EdgeInsets.symmetric(horizontal: 4),
                        height: 8,
                        width: currentPage == index ? 24 : 8,
                        decoration: BoxDecoration(
                          color: currentPage == index ? Theme.of(context).primaryColor : Colors.grey,
                          borderRadius: BorderRadius.circular(4),
                        ),
                      );
                    }),
                  ),
                  const SizedBox(height: 32),
                  ElevatedButton(
                    onPressed: () {
                      if (currentPage < pages.length - 1) {
                        _pageController.nextPage(
                          duration: const Duration(milliseconds: 500),
                          curve: Curves.ease,
                        );
                      } else {
                        widget.onComplete();
                      }
                    },
                    style: ElevatedButton.styleFrom(
                      minimumSize: const Size(double.infinity, 50),
                      backgroundColor: Theme.of(context).primaryColor,
                      foregroundColor: Colors.white,
                    ),
                    child: Text(currentPage < pages.length - 1 ? 'Next' : 'Get Started'),
                  ),
                  if (currentPage < pages.length - 1)
                    TextButton(
                      onPressed: widget.onComplete,
                      child: const Text('Skip'),
                    )
                ],
              ),
            )
          ],
        ),
      ),
    );
  }
}
