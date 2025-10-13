import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/subscription_service.dart';

class PaywallScreen extends StatefulWidget {
  final String feature; // 'multi_instance' or 'create_host'

  const PaywallScreen({
    super.key,
    required this.feature,
  });

  @override
  State<PaywallScreen> createState() => _PaywallScreenState();
}

class _PaywallScreenState extends State<PaywallScreen> {
  final _subscriptionService = SubscriptionService();
  bool _isLoading = true;
  String? _selectedProductId;
  bool _isTrialEligible = false;

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    await _subscriptionService.initialize();

    // Check trial eligibility
    _isTrialEligible = await _subscriptionService.isTrialEligible();

    // Default to yearly product
    if (_subscriptionService.products.isNotEmpty) {
      _selectedProductId = _subscriptionService.products
          .firstWhere(
            (p) => p.id.contains('yearly'),
            orElse: () => _subscriptionService.products.first,
          )
          .id;
    }

    setState(() => _isLoading = false);
  }

  String _getFeatureTitle() {
    switch (widget.feature) {
      case 'multi_instance':
        return 'Multiple NPM Instances';
      case 'create_host':
        return 'Create New Hosts';
      default:
        return 'Premium Feature';
    }
  }

  String _getFeatureDescription() {
    switch (widget.feature) {
      case 'multi_instance':
        return 'Manage multiple Nginx Proxy Manager instances from one app. Switch between servers seamlessly.';
      case 'create_host':
        return 'Create new proxy hosts directly from your mobile device. No need to use the web interface.';
      default:
        return 'Unlock premium features to get the most out of your app.';
    }
  }

  Future<void> _handlePurchase() async {
    if (_selectedProductId == null) return;

    final product = _subscriptionService.products.firstWhere(
      (p) => p.id == _selectedProductId,
    );

    setState(() => _isLoading = true);

    final success = await _subscriptionService.purchaseSubscription(product);

    if (success && mounted) {
      // Wait a moment for purchase to process
      await Future.delayed(const Duration(seconds: 2));

      // Check if premium granted
      final isPremium = await _subscriptionService.isPremium();

      if (isPremium) {
        if (mounted) {
          Navigator.pop(context, true); // Return true to indicate success
        }
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _handleStartTrial() async {
    setState(() => _isLoading = true);

    await _subscriptionService.startFreeTrial();

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('7-day free trial started!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    }
  }

  Future<void> _handleRestore() async {
    setState(() => _isLoading = true);

    await _subscriptionService.restorePurchases();

    // Wait a moment for restore to process
    await Future.delayed(const Duration(seconds: 2));

    final isPremium = await _subscriptionService.isPremium();

    if (isPremium && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Premium subscription restored!'),
          backgroundColor: Colors.green,
        ),
      );
      Navigator.pop(context, true);
    } else if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No previous subscription found'),
        ),
      );
      setState(() => _isLoading = false);
    }
  }

  Future<void> _openPrivacyPolicy() async {
    // TODO: Replace with your actual privacy policy URL
    final uri = Uri.parse(
        'https://github.com/yourusername/npm_phone_app/blob/main/privacy.md');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  Future<void> _openTermsOfService() async {
    // TODO: Replace with your actual terms of service URL
    final uri = Uri.parse(
        'https://github.com/yourusername/npm_phone_app/blob/main/terms-of-service.md');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        title: const Text('Premium'),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : SingleChildScrollView(
              padding: const EdgeInsets.all(24.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Feature highlight
                  const Icon(
                    Icons.star,
                    size: 64,
                    color: Colors.amber,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    _getFeatureTitle(),
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 28,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    _getFeatureDescription(),
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 16,
                    ),
                  ),
                  const SizedBox(height: 32),

                  // Premium features list
                  const Text(
                    'Premium includes:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),
                  _buildFeatureItem('Up to 50 NPM instances'),
                  _buildFeatureItem('Create unlimited proxy hosts'),
                  _buildFeatureItem('All current features'),
                  _buildFeatureItem('Future premium features'),
                  _buildFeatureItem('Support app development'),

                  if (_isTrialEligible) ...[
                    const SizedBox(height: 32),
                    _buildFeatureItem('🎉 7-day free trial - no charge'),
                  ],

                  const SizedBox(height: 32),

                  // Trial CTA (if eligible)
                  if (_isTrialEligible) ...[
                    SizedBox(
                      width: double.infinity,
                      height: 56,
                      child: ElevatedButton(
                        onPressed: _handleStartTrial,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.green,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(12),
                          ),
                        ),
                        child: const Text(
                          'Start 7-Day Free Trial',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    const Center(
                      child: Text(
                        'No charge for 7 days, cancel anytime',
                        style: TextStyle(
                          color: Colors.grey,
                          fontSize: 12,
                        ),
                      ),
                    ),
                    const SizedBox(height: 24),
                    const Center(
                      child: Text(
                        'Or subscribe now:',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    const SizedBox(height: 16),
                  ],

                  // Subscription options
                  const Text(
                    'Choose your plan:',
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 16),

                  if (_subscriptionService.products.isEmpty)
                    const Text(
                      'No subscription options available',
                      style: TextStyle(color: Colors.red),
                    )
                  else
                    ..._subscriptionService.products.map((product) {
                      final isYearly = product.id.contains('yearly');
                      final isSelected = product.id == _selectedProductId;

                      return Padding(
                        padding: const EdgeInsets.only(bottom: 12),
                        child: _buildSubscriptionOption(
                          product: product,
                          isSelected: isSelected,
                          badge: isYearly ? 'SAVE 16%' : null,
                          showTrial: _isTrialEligible,
                          onTap: () {
                            setState(() => _selectedProductId = product.id);
                          },
                        ),
                      );
                    }).toList(),

                  const SizedBox(height: 24),

                  // Subscribe button
                  SizedBox(
                    width: double.infinity,
                    height: 56,
                    child: ElevatedButton(
                      onPressed:
                          _selectedProductId != null ? _handlePurchase : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: Text(
                        _isTrialEligible
                            ? 'Subscribe Without Trial'
                            : 'Subscribe Now',
                        style: const TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Restore button
                  SizedBox(
                    width: double.infinity,
                    height: 48,
                    child: TextButton(
                      onPressed: _handleRestore,
                      child: const Text(
                        'Restore Purchases',
                        style: TextStyle(color: Colors.grey),
                      ),
                    ),
                  ),

                  const SizedBox(height: 24),

                  // Terms and conditions
                  Text(
                    _isTrialEligible
                        ? '• 7-day free trial, then subscription auto-renews\n'
                            '• Cancel anytime during trial at no cost\n'
                            '• After trial, manage in App Store or Play Store settings\n'
                            '• Payment charged to your store account after trial\n'
                            '• Subscription renews at the same price'
                        : '• Subscription auto-renews unless canceled\n'
                            '• Cancel anytime in your App Store or Play Store settings\n'
                            '• Payment charged to your store account\n'
                            '• Subscription renews at the same price',
                    style: TextStyle(
                      color: Colors.grey[600],
                      fontSize: 12,
                    ),
                  ),

                  const SizedBox(height: 16),

                  // Links
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      TextButton(
                        onPressed: _openPrivacyPolicy,
                        child: const Text(
                          'Privacy Policy',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const Text('•', style: TextStyle(color: Colors.grey)),
                      TextButton(
                        onPressed: _openTermsOfService,
                        child: const Text(
                          'Terms of Service',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
    );
  }

  Widget _buildFeatureItem(String text) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        children: [
          const Icon(Icons.check_circle, color: Colors.green, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionOption({
    required ProductDetails product,
    required bool isSelected,
    String? badge,
    bool showTrial = false,
    required VoidCallback onTap,
  }) {
    final isYearly = product.id.contains('yearly');

    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: isSelected ? Colors.blue.withOpacity(0.2) : Colors.grey[900],
          border: Border.all(
            color: isSelected ? Colors.blue : Colors.grey[800]!,
            width: 2,
          ),
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            Radio<bool>(
              value: true,
              groupValue: isSelected,
              onChanged: (_) => onTap(),
              activeColor: Colors.blue,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        isYearly ? 'Yearly' : 'Monthly',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      if (badge != null) ...[
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green,
                            borderRadius: BorderRadius.circular(4),
                          ),
                          child: Text(
                            badge,
                            style: const TextStyle(
                              color: Colors.white,
                              fontSize: 10,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    showTrial ? '${product.price} after trial' : product.price,
                    style: const TextStyle(
                      color: Colors.grey,
                      fontSize: 14,
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
