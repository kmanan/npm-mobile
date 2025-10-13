# Paywall & Subscription Implementation Plan

**Version:** 1.0  
**Date:** October 12, 2025  
**App Version:** 1.0.3+10 → 1.1.0+11  
**Feature:** Premium subscription for multi-instance support and host creation

---

## Executive Summary

Implement a subscription-based paywall to monetize premium features:
- **Free Tier:** Single NPM instance, view/edit existing hosts
- **Premium Tier ($0.99/month or $9.99/year with 7-day free trial):** Multiple NPM instances + create new hosts

This document covers full compliance with Apple App Store and Google Play Store requirements, implementation using Flutter's `in_app_purchase` package, user experience considerations, and 7-day free trial implementation.

---

## Legal & Compliance Requirements

### Apple App Store Requirements

**Mandatory Compliance (App Rejection if Violated):**

1. **IAP Requirement (Guideline 3.1.1)**
   - ALL digital content and features MUST use Apple's In-App Purchase system
   - External payment links, buttons, or CTAs are STRICTLY PROHIBITED
   - Cannot mention pricing outside of IAP flow
   - Cannot direct users to website for payment

2. **Subscription Information (Guideline 3.1.2)**
   - Must clearly display subscription length, price, and billing cycle BEFORE purchase
   - Must explain what user gets with subscription
   - Must provide easy access to Terms of Service and Privacy Policy
   - Must display "Cancel Anytime" information
   - Auto-renewable subscriptions require specific App Store metadata

3. **Restore Purchases (Guideline 3.1.1)**
   - MUST provide "Restore Purchases" button/option
   - Users who purchased on one device must access content on all devices
   - Cannot require login to restore purchases (unless account-based)

4. **Family Sharing (Guideline 3.1.2)**
   - Subscriptions should support Family Sharing (optional but recommended)
   - Configured in App Store Connect

5. **Refund Policy**
   - Cannot handle refunds in-app
   - Must direct users to Apple's refund system
   - Apple handles all refund requests

6. **Grace Period**
   - Must handle subscription grace period (billing issue, waiting for payment)
   - User keeps access during grace period

7. **Privacy Policy**
   - Must have publicly accessible privacy policy
   - Must link to it in App Store Connect and in-app

**Rejection Risks:**
- Mentioning "cheaper on web" or "buy on website"
- Having external payment buttons
- Not showing subscription terms before purchase
- Not providing restore purchases option
- Unclear pricing or billing cycle

---

### Google Play Store Requirements

**Mandatory Compliance:**

1. **Google Play Billing Requirement**
   - Digital goods MUST use Google Play Billing Library
   - Cannot use external payment processors
   - Cannot direct users to website for payment

2. **Subscription Information**
   - Must clearly show price, billing cycle, and renewal terms
   - Must show what user gets with subscription
   - Must link to Terms of Service and Privacy Policy
   - Auto-renewable subscriptions need specific Play Console configuration

3. **Subscription Management**
   - Must provide link to Google Play subscription management
   - Users can manage/cancel through Play Store
   - Cannot implement custom cancellation in-app

4. **Grace Period & Account Hold**
   - Must handle grace period (3 days default)
   - Must handle account hold status
   - User keeps access during grace period

5. **Proration**
   - Must handle subscription upgrades/downgrades
   - Google manages proration automatically

6. **Restore Purchases**
   - Must sync purchase state across devices
   - Use Google account for purchase recognition

7. **Privacy Policy**
   - Must have publicly accessible privacy policy
   - Must link to it in Play Console

**Rejection Risks:**
- Using external payment systems
- Not linking to subscription management
- Unclear pricing or terms
- Not handling subscription states properly

---

## Subscription Model

### Free Tier
**Features:**
- ✅ Single NPM instance
- ✅ View all proxy hosts
- ✅ Enable/disable existing hosts
- ✅ Edit existing host configurations
- ✅ Biometric authentication
- ✅ View ports list
- ✅ All existing functionality

**Limitations:**
- ❌ Cannot add additional NPM instances (locked at 1)
- ❌ Cannot create new proxy hosts
- 💡 Show paywall when attempting to add instance or create host

### Premium Tier

**7-Day Free Trial**
- ✅ Full premium access for 7 days
- ✅ No charge during trial period
- ✅ Cancel anytime at no cost
- ✅ One-time offer for new users
- ⚡ Instant activation (no payment info required during trial setup)

**Monthly: $0.99 USD/month**
- 7-day free trial for new users
- Billed monthly after trial
- Cancel anytime
- Auto-renews until canceled

**Yearly: $9.99 USD/year**
- 7-day free trial for new users
- Billed annually after trial
- Cancel anytime
- Auto-renews until canceled
- Save $1.89/year (16% discount)

**Premium Features:**
- ✅ Up to 50 NPM instances
- ✅ Create unlimited proxy hosts
- ✅ All free tier features
- 🎁 Future premium features at no extra cost

**Pricing Strategy:**
- 7-day free trial removes friction and increases conversion
- Low barrier to entry ($0.99/month)
- Yearly option encourages long-term subscriptions
- Competitive with similar utility apps
- Sustainable revenue for development

---

## Flutter Implementation

### Required Package

**Add to `pubspec.yaml`:**
```yaml
dependencies:
  flutter:
    sdk: flutter
  # ... existing dependencies ...
  in_app_purchase: ^3.1.13
```

**Why `in_app_purchase`:**
- Official Flutter plugin maintained by Flutter team
- Supports both iOS (StoreKit) and Android (Google Play Billing)
- Handles platform differences automatically
- Active development and updates
- Well-documented

---

## Implementation Architecture

### 1. Subscription State Management

**New File:** `lib/services/subscription_service.dart`

```dart
import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';
import 'dart:io' show Platform;

enum SubscriptionStatus {
  free,
  premium,
  expired,
  unknown,
}

class SubscriptionService {
  static final SubscriptionService _instance = SubscriptionService._internal();
  factory SubscriptionService() => _instance;
  SubscriptionService._internal();

  final InAppPurchase _iap = InAppPurchase.instance;
  StreamSubscription<List<PurchaseDetails>>? _subscription;
  
  // Product IDs (must match App Store Connect and Play Console)
  static const String monthlyProductId = Platform.isIOS
      ? 'npm_premium_monthly'
      : 'npm_premium_monthly';
  static const String yearlyProductId = Platform.isIOS
      ? 'npm_premium_yearly'
      : 'npm_premium_yearly';
  
  // Current subscription state
  SubscriptionStatus _status = SubscriptionStatus.unknown;
  SubscriptionStatus get status => _status;
  
  // Available products
  List<ProductDetails> _products = [];
  List<ProductDetails> get products => _products;
  
  // Listeners
  final List<VoidCallback> _listeners = [];
  
  /// Initialize the subscription service
  Future<void> initialize() async {
    // Check if IAP is available
    final bool available = await _iap.isAvailable();
    if (!available) {
      _status = SubscriptionStatus.free;
      return;
    }
    
    // Load products
    await _loadProducts();
    
    // Restore purchases (check existing subscription)
    await restorePurchases();
    
    // Listen to purchase updates
    _subscription = _iap.purchaseStream.listen(
      _onPurchaseUpdate,
      onDone: () => _subscription?.cancel(),
      onError: (error) => print('Purchase stream error: $error'),
    );
  }
  
  /// Load available products from stores
  Future<void> _loadProducts() async {
    const Set<String> productIds = {monthlyProductId, yearlyProductId};
    
    try {
      final ProductDetailsResponse response =
          await _iap.queryProductDetails(productIds);
      
      if (response.notFoundIDs.isNotEmpty) {
        print('Products not found: ${response.notFoundIDs}');
      }
      
      _products = response.productDetails;
      _products.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    } catch (e) {
      print('Error loading products: $e');
    }
  }
  
  /// Purchase a subscription
  Future<bool> purchaseSubscription(ProductDetails product) async {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);
    
    try {
      return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      print('Purchase error: $e');
      return false;
    }
  }
  
  /// Restore previous purchases
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();
      // Purchase stream will handle the restored purchases
    } catch (e) {
      print('Restore error: $e');
    }
  }
  
  /// Handle purchase updates
  Future<void> _onPurchaseUpdate(List<PurchaseDetails> purchases) async {
    for (final PurchaseDetails purchase in purchases) {
      if (purchase.status == PurchaseStatus.purchased ||
          purchase.status == PurchaseStatus.restored) {
        // Verify purchase (important for security)
        final bool valid = await _verifyPurchase(purchase);
        
        if (valid) {
          // Grant premium access
          await _grantPremiumAccess();
          _status = SubscriptionStatus.premium;
          _notifyListeners();
        }
      } else if (purchase.status == PurchaseStatus.error) {
        print('Purchase error: ${purchase.error}');
      }
      
      // Complete the purchase (required by both platforms)
      if (purchase.pendingCompletePurchase) {
        await _iap.completePurchase(purchase);
      }
    }
  }
  
  /// Verify purchase (basic client-side check)
  /// For production, should verify with server
  Future<bool> _verifyPurchase(PurchaseDetails purchase) async {
    // TODO: Implement server-side verification for production
    // For now, trust the platform's purchase status
    return purchase.productID == monthlyProductId ||
           purchase.productID == yearlyProductId;
  }
  
  /// Grant premium access
  Future<void> _grantPremiumAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', true);
    await prefs.setInt(
      'premium_granted_at',
      DateTime.now().millisecondsSinceEpoch,
    );
  }
  
  /// Revoke premium access
  Future<void> _revokePremiumAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', false);
  }
  
  /// Check if user has premium access
  Future<bool> isPremium() async {
    // During restore/initialization, use in-memory status
    if (_status == SubscriptionStatus.premium) {
      return true;
    }
    
    // Check stored premium status
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_premium') ?? false;
  }
  
  /// Check if user can add more instances
  Future<bool> canAddInstance(int currentInstanceCount) async {
    if (await isPremium()) {
      return currentInstanceCount < 50; // Premium limit
    }
    return currentInstanceCount < 1; // Free limit
  }
  
  /// Check if user can create hosts
  Future<bool> canCreateHost() async {
    return await isPremium();
  }
  
  /// Add listener for subscription changes
  void addListener(VoidCallback listener) {
    _listeners.add(listener);
  }
  
  /// Remove listener
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
  }
  
  /// Notify all listeners
  void _notifyListeners() {
    for (final listener in _listeners) {
      listener();
    }
  }
  
  /// Dispose
  void dispose() {
    _subscription?.cancel();
    _listeners.clear();
  }
}
```

---

### 2. Paywall Screen

**New File:** `lib/screens/paywall_screen.dart`

```dart
import 'package:flutter/material.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
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

  @override
  void initState() {
    super.initState();
    _loadProducts();
  }

  Future<void> _loadProducts() async {
    setState(() => _isLoading = true);
    await _subscriptionService.initialize();
    
    if (_subscriptionService.products.isEmpty) {
      await _subscriptionService._loadProducts();
    }
    
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
        Navigator.pop(context, true); // Return true to indicate success
      } else {
        setState(() => _isLoading = false);
      }
    } else {
      setState(() => _isLoading = false);
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
                  const SizedBox(height: 32),
                  
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
                      onPressed: _selectedProductId != null ? _handlePurchase : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.blue,
                        foregroundColor: Colors.white,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                        ),
                      ),
                      child: const Text(
                        'Subscribe Now',
                        style: TextStyle(
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
                    '• Subscription auto-renews unless canceled\n'
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
                        onPressed: () {
                          // TODO: Open privacy policy
                        },
                        child: const Text(
                          'Privacy Policy',
                          style: TextStyle(fontSize: 12),
                        ),
                      ),
                      const Text('•', style: TextStyle(color: Colors.grey)),
                      TextButton(
                        onPressed: () {
                          // TODO: Open terms of service
                        },
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
          Text(
            text,
            style: const TextStyle(color: Colors.white, fontSize: 16),
          ),
        ],
      ),
    );
  }

  Widget _buildSubscriptionOption({
    required ProductDetails product,
    required bool isSelected,
    String? badge,
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
                    product.price,
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
```

---

### 3. Integrate Paywall into App Flow

**Modify `lib/screens/dashboard_screen.dart`:**

Add at top:
```dart
import '../services/subscription_service.dart';
import 'paywall_screen.dart';
```

Modify `_addProxyHost()` method:
```dart
Future<void> _addProxyHost() async {
  final subscriptionService = SubscriptionService();
  
  // Check if user can create hosts
  final canCreate = await subscriptionService.canCreateHost();
  
  if (!canCreate) {
    // Show paywall
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const PaywallScreen(feature: 'create_host'),
      ),
    );
    
    if (result != true) {
      return; // User didn't subscribe
    }
  }
  
  // Proceed with creating host
  final result = await Navigator.push<bool>(
    context,
    MaterialPageRoute(
      builder: (context) => const ProxyHostAddScreen(),
    ),
  );

  if (result == true && mounted) {
    setState(() => _isLoading = true);
    _loadProxyHosts();
  }
}
```

**Modify `lib/screens/login_screen.dart`:**

When user tries to add second instance:
```dart
Future<void> _showAddInstanceDialog() async {
  final subscriptionService = SubscriptionService();
  final instanceCount = _instances.length;
  
  // Check if user can add more instances
  final canAdd = await subscriptionService.canAddInstance(instanceCount);
  
  if (!canAdd) {
    // Show paywall
    final result = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (context) => const PaywallScreen(feature: 'multi_instance'),
      ),
    );
    
    if (result != true) {
      return; // User didn't subscribe
    }
  }
  
  // Proceed with adding instance
  // ... existing add instance logic
}
```

---

## Store Configuration

### Apple App Store Connect

**Step 1: Create Subscription Group**
1. Log in to App Store Connect
2. Go to your app → Features → In-App Purchases
3. Click "+" to create subscription group
4. Name: "Premium Subscription"
5. Reference Name: "npm_premium_group"

**Step 2: Create Monthly Subscription**
1. Click "+" in subscription group
2. Type: Auto-Renewable Subscription
3. Reference Name: "NPM Premium Monthly"
4. Product ID: `npm_premium_monthly`
5. Subscription Duration: 1 Month
6. Price: $0.99 USD (Tier 1)
7. **Free Trial: 7 Days** ⭐
8. Localized Information:
   - Display Name: "Premium Monthly"
   - Description: "Unlock multiple NPM instances and create unlimited proxy hosts. 7-day free trial included."
9. Review Information:
   - Screenshot of paywall screen
   - Subscription benefits description

**Step 3: Create Yearly Subscription**
1. Click "+" in subscription group
2. Type: Auto-Renewable Subscription
3. Reference Name: "NPM Premium Yearly"
4. Product ID: `npm_premium_yearly`
5. Subscription Duration: 1 Year
6. Price: $9.99 USD (Tier 10)
7. **Free Trial: 7 Days** ⭐
8. Localized Information:
   - Display Name: "Premium Yearly"
   - Description: "Unlock multiple NPM instances and create unlimited proxy hosts. Save 16% compared to monthly. 7-day free trial included."
9. Review Information:
   - Screenshot of paywall screen
   - Subscription benefits description

**Step 4: Configure Subscription Group**
- Family Sharing: Enabled (recommended)
- Grace Period: 16 days (recommended)
- Billing Retry: Enabled

**Step 5: Add App Store Information**
1. Go to App Information
2. Scroll to Subscriptions section
3. Add subscription URL (optional): Link to your website explaining subscriptions
4. Privacy Policy URL: Required (must be publicly accessible)

---

### Google Play Console

**Step 1: Set Up Merchant Account**
1. Link Google Play Console to Google Payments merchant account
2. Complete tax information
3. Verify bank account for payouts

**Step 2: Create Monthly Subscription**
1. Go to Monetize → Products → Subscriptions
2. Click "Create subscription"
3. Product ID: `npm_premium_monthly`
4. Name: "Premium Monthly"
5. Description: "Unlock multiple NPM instances and create unlimited proxy hosts. 7-day free trial included."
6. Billing period: 1 Month
7. Price: $0.99 USD
8. Grace period: 3 days (default)
9. **Free trial: 7 days** ⭐
10. Base plans: Create "Monthly" plan

**Step 3: Create Yearly Subscription**
1. Click "Create subscription"
2. Product ID: `npm_premium_yearly`
3. Name: "Premium Yearly"
4. Description: "Unlock multiple NPM instances and create unlimited proxy hosts. Save 16% compared to monthly. 7-day free trial included."
5. Billing period: 1 Year
6. Price: $9.99 USD
7. Grace period: 3 days
8. **Free trial: 7 days** ⭐
9. Base plans: Create "Yearly" plan

**Step 4: Configure Settings**
- Proration: Enabled (for upgrades/downgrades)
- Resubscribe: Enabled
- Pause: Disabled (not needed for this app)

---

## Privacy Policy Requirements

### Required Content

**Must Include:**
1. What data is collected (purchase history, user ID)
2. How data is used (verify subscription status)
3. Who data is shared with (Apple/Google only)
4. How users can request data deletion
5. Contact information for privacy questions
6. Last updated date

**Sample Privacy Policy Section:**

```
## Subscription & Payment Data

When you purchase a subscription, the following information is processed:
- Purchase transaction ID
- Subscription status (active, expired, canceled)
- Purchase date and renewal date
- Platform (iOS or Android)

This data is used solely to verify your subscription status and provide premium features. Payment is processed entirely by Apple App Store or Google Play Store. We do not store credit card information or payment details.

Your subscription data is shared with Apple or Google as required by their platforms. We do not share this data with any third parties.

To request deletion of your subscription data, contact us at [email]. Note that subscription management (cancellation, refunds) must be done through your App Store or Play Store account.
```

**Hosting:**
- Must be publicly accessible URL
- Add to: `privacy.md` (already exists in project)
- Host on: GitHub Pages, or your website
- Update links in both App Store Connect and Play Console

---

## Terms of Service

### Required Content

**Sample Terms Section:**

```
## Subscription Terms

### Premium Subscription
Our app offers two auto-renewing subscription options:
- Monthly: $0.99 USD per month
- Yearly: $9.99 USD per year

### Billing & Renewal
- Payment is charged to your App Store or Play Store account at confirmation of purchase
- Subscription automatically renews unless auto-renew is turned off at least 24 hours before the end of the current period
- Your account will be charged for renewal within 24 hours prior to the end of the current period
- Renewal cost: Same price as original subscription

### Cancellation
- You can cancel your subscription at any time through your App Store or Play Store account settings
- Cancellation takes effect at the end of the current billing period
- No partial refunds for unused time

### Free Trial (if offered)
- If we offer a free trial, you can cancel before the trial ends to avoid being charged
- Trial unused portion is forfeited when you purchase a subscription

### Refunds
- All refund requests must be made through Apple App Store or Google Play Store
- Refund policies are determined by Apple and Google, not by us
- We cannot process refunds directly

### Changes to Subscription
- We reserve the right to change subscription pricing with 30 days notice
- Existing subscribers will be notified before price changes take effect
- Price changes do not affect current subscription until renewal

### Feature Availability
- Premium features are subject to change
- We may add or remove features without notice
- Core premium features (multi-instance support, host creation) will remain available
```

---

## Testing

### iOS Sandbox Testing

**Step 1: Create Sandbox Tester**
1. App Store Connect → Users and Access → Sandbox
2. Create tester account (use unique email)
3. Note: Cannot use real Apple ID

**Step 2: Test on Device**
1. Sign out of real App Store account on device
2. Build and run app in debug mode
3. Attempt purchase - iOS will prompt for sandbox account
4. Sign in with sandbox tester account
5. Complete purchase (no actual charge)
6. Verify premium features unlock

**Step 3: Test Scenarios**
- ✅ Purchase monthly subscription
- ✅ Purchase yearly subscription
- ✅ Cancel and restore purchase
- ✅ Purchase on device A, restore on device B
- ✅ Expired subscription (sandbox accelerates time)
- ✅ Failed payment (sandbox can simulate)

**Sandbox Time Acceleration:**
- 1 month subscription = 5 minutes in sandbox
- 1 year subscription = 1 hour in sandbox
- Use this to test renewals and expirations

---

### Android Testing

**Step 1: Create License Tester**
1. Play Console → Settings → License Testing
2. Add your Gmail accounts (can use real accounts)
3. Save

**Step 2: Test on Device**
1. Sign in to Play Store with tester account
2. Install app from internal testing track (or debug build)
3. Attempt purchase - will show "Test purchase"
4. Complete purchase (no actual charge)
5. Verify premium features unlock

**Step 3: Test Scenarios**
- ✅ Purchase monthly subscription
- ✅ Purchase yearly subscription
- ✅ Cancel and restore purchase
- ✅ Purchase on device A, restore on device B
- ✅ Expired subscription
- ✅ Failed payment
- ✅ Grace period behavior

---

## Revenue & Analytics

### Revenue Projections

**Conservative Estimates:**
- Total downloads: 10,000 over 1 year
- Conversion rate: 2% (200 paying users)
- Monthly/Yearly split: 40% monthly, 60% yearly

**Monthly Revenue:**
- Monthly subs: 80 users × $0.99 = $79.20
- Yearly subs: 120 users × $9.99 ÷ 12 = $99.90
- **Total: ~$179/month**

**After Platform Fees (30% first year, 15% after):**
- First year: ~$125/month
- After year: ~$152/month

**Optimistic Estimates (5% conversion):**
- 500 paying users
- **~$448/month** (before fees)
- **~$313/month** (after fees)

### Analytics to Track

**Key Metrics:**
1. Paywall impressions (how many times shown)
2. Conversion rate (purchases / impressions)
3. Feature that triggered paywall (multi-instance vs create-host)
4. Time to conversion (impression to purchase)
5. Subscription retention rate
6. Cancellation rate
7. Monthly vs yearly preference
8. Revenue per user

**Implementation:**
```dart
// Add to SubscriptionService
void trackPaywallImpression(String feature) {
  // Log to analytics
  print('Paywall shown: $feature');
}

void trackPurchaseSuccess(String productId, String feature) {
  // Log to analytics
  print('Purchase: $productId for $feature');
}
```

---

## User Communication

### In-App Messaging

**Free User First Launch:**
```
Welcome to Nginx Mobile Dashboard!

You're on the free plan:
✓ Manage 1 NPM instance
✓ View and edit existing hosts

Upgrade to Premium for:
• Multiple NPM instances
• Create new hosts
• Future premium features

Try it now: Tap "Add Instance" to learn more
```

**When User Hits Paywall:**
```
Premium Feature

[Feature Name] requires a Premium subscription.

For just $0.99/month or $9.99/year, unlock:
• Up to 50 NPM instances
• Create unlimited proxy hosts
• All future premium features

[Subscribe Now]  [Learn More]
```

**After Purchase:**
```
Welcome to Premium! 🎉

You now have access to:
✓ Multiple NPM instances (up to 50)
✓ Create unlimited proxy hosts
✓ All future premium features

Thank you for supporting the app!
```

---

## Compliance Checklist

### Pre-Launch Checklist

#### Code
- [ ] `in_app_purchase` package added to `pubspec.yaml`
- [ ] `SubscriptionService` implemented
- [ ] `PaywallScreen` implemented
- [ ] Premium checks added to add instance flow
- [ ] Premium checks added to create host flow
- [ ] Restore purchases button accessible
- [ ] Demo mode bypasses paywall
- [ ] Error handling for failed purchases
- [ ] Loading states during purchase
- [ ] Success/error messages shown to user

#### App Store Connect
- [ ] Subscription group created
- [ ] Monthly subscription configured ($0.99)
- [ ] Yearly subscription configured ($9.99)
- [ ] Subscription screenshots uploaded
- [ ] Localized information complete
- [ ] Family Sharing enabled
- [ ] Grace period configured
- [ ] Privacy Policy URL added
- [ ] Subscription terms clear

#### Play Console
- [ ] Google Payments merchant account linked
- [ ] Monthly subscription configured ($0.99)
- [ ] Yearly subscription configured ($9.99)
- [ ] Subscription descriptions complete
- [ ] Grace period configured
- [ ] Proration enabled
- [ ] Privacy Policy URL added

#### Legal
- [ ] Privacy Policy updated with subscription section
- [ ] Privacy Policy publicly hosted
- [ ] Terms of Service created with subscription terms
- [ ] Terms of Service publicly hosted
- [ ] Refund policy clearly stated
- [ ] Auto-renewal terms clearly stated
- [ ] Cancellation process explained

#### Testing
- [ ] iOS sandbox testing complete
- [ ] Android testing complete
- [ ] Restore purchases works on iOS
- [ ] Restore purchases works on Android
- [ ] Subscription status persists across app restarts
- [ ] Grace period behavior tested
- [ ] Expired subscription tested
- [ ] Failed payment tested
- [ ] Multi-device restore tested

#### User Experience
- [ ] Paywall design matches app theme
- [ ] Subscription benefits clearly explained
- [ ] Pricing clearly displayed
- [ ] "Cancel Anytime" messaging visible
- [ ] Loading states don't block UI
- [ ] Error messages are user-friendly
- [ ] Success feedback provided
- [ ] Free tier still useful

---

## Launch Strategy

### Phase 1: Soft Launch (Week 1-2)
- Release to existing users (no new installs)
- Monitor conversion rate
- Monitor for crashes/errors
- Gather feedback
- Fix any issues

### Phase 2: Feature Complete (Week 3-4)
- Add analytics to track paywall performance
- A/B test yearly vs monthly messaging
- Optimize paywall copy based on feedback
- Add promotional messaging

### Phase 3: Full Launch (Week 5+)
- Promote premium features in app store descriptions
- Update screenshots to show premium badge
- Consider limited-time promotion (e.g., "50% off first year")
- Monitor retention and churn

### Phase 4: Optimization (Month 2+)
- Analyze conversion funnel
- Test different price points (if needed)
- Add more premium features based on feedback
- Consider introducing free trial

---

## Handling Edge Cases

### Edge Case 1: User Purchases Then Immediately Cancels
**Behavior:**
- User keeps premium access until end of billing period
- Access automatically revoked when subscription expires
- User can resubscribe at any time

**Implementation:**
- Track subscription expiration date
- Check on app launch if subscription still active
- Show warning before subscription expires

### Edge Case 2: User Deletes App And Reinstalls
**Behavior:**
- Subscription should be restored automatically
- Premium status checked on first launch
- If not automatic, "Restore Purchases" button available

**Implementation:**
- Call `restorePurchases()` on first launch after install
- Check purchase status silently in background

### Edge Case 3: Subscription Expires While User Has 10 Instances
**Behavior:**
- User can still access all 10 instances (read-only)
- Cannot add 11th instance
- Cannot switch to different instance
- Prompted to resubscribe when trying to switch

**Implementation:**
```dart
// In instance switching code
if (!await subscriptionService.isPremium() && instanceCount > 1) {
  // Show message: "Premium subscription expired. Resubscribe to switch instances."
  // Offer restore purchases and subscribe buttons
}
```

### Edge Case 4: User Has Multiple Devices
**Behavior:**
- Subscription works on all devices with same Apple ID / Google account
- Premium status syncs automatically through platform

**Implementation:**
- No special code needed - handled by iOS/Android
- Just ensure `restorePurchases()` called on app launch

### Edge Case 5: Billing Issue (Payment Declined)
**Behavior:**
- Grace period: User keeps premium access for 16 days (iOS) or 3 days (Android)
- During grace period, show message prompting to update payment
- After grace period, premium access revoked

**Implementation:**
```dart
// Check subscription status includes grace period check
// Show appropriate message based on status
if (status == SubscriptionStatus.inGracePeriod) {
  // Show: "Please update your payment method to continue Premium access"
}
```

---

## Future Enhancements

### Potential Premium Features (Post-Launch)
1. **Dark/Light Theme Toggle** (premium exclusive)
2. **Custom App Icon** (premium exclusive)
3. **Export Configuration Backup** (premium exclusive)
4. **Push Notifications for Host Status** (premium exclusive)
5. **Advanced Host Templates** (premium exclusive)
6. **Bulk Operations** (premium exclusive)
7. **Analytics Dashboard** (premium exclusive)

### Promotional Strategies
1. **Free Trial:** Offer 7-day free trial for new users
2. **Lifetime Option:** One-time payment of $49.99 for lifetime access
3. **Referral Program:** Give 1 month free for successful referrals
4. **Promotional Pricing:** 50% off during app launch month
5. **Black Friday Sale:** $4.99/year (50% off)

---

## Files to Create/Modify

### New Files (3)
1. `lib/services/subscription_service.dart` - Subscription management
2. `lib/screens/paywall_screen.dart` - Paywall UI
3. `terms-of-service.md` - Terms document (host publicly)

### Modified Files (4)
1. `pubspec.yaml` - Add `in_app_purchase` package
2. `lib/screens/dashboard_screen.dart` - Add premium check for create host
3. `lib/screens/login_screen.dart` - Add premium check for add instance
4. `privacy.md` - Add subscription data section

### Modified Platform Files (2)
1. `ios/Runner/Info.plist` - May need StoreKit configuration (check docs)
2. `android/app/src/main/AndroidManifest.xml` - May need billing permissions

---

## Timeline

### Week 1: Setup & Configuration
- Add `in_app_purchase` package
- Create `SubscriptionService`
- Set up App Store Connect subscriptions
- Set up Play Console subscriptions
- Update Privacy Policy
- Create Terms of Service

### Week 2: Implementation
- Create `PaywallScreen`
- Add premium checks to dashboard
- Add premium checks to login (multi-instance)
- Implement restore purchases
- Add subscription status persistence

### Week 3: Testing
- iOS sandbox testing
- Android testing
- Multi-device testing
- Edge case testing
- UI/UX polish

### Week 4: Soft Launch
- Release to limited users
- Monitor analytics
- Fix any issues
- Gather feedback

**Total:** 4 weeks from start to soft launch

---

## Support & Refunds

### User Support

**Common Questions:**

**Q: How do I cancel my subscription?**
A: Go to your device Settings → [Your Name] → Subscriptions (iOS) or Play Store → Subscriptions (Android). Select "Nginx Mobile Dashboard" and tap Cancel.

**Q: Can I get a refund?**
A: Refunds are handled by Apple or Google. Request a refund through your App Store or Play Store account.

**Q: I canceled but still have access?**
A: You keep premium access until the end of your billing period. Access will end when the subscription expires.

**Q: I purchased on iOS, can I use on Android?**
A: No, subscriptions are platform-specific. You would need to purchase separately on Android.

**Q: Will I lose my instances if I cancel?**
A: Your instances and data are saved. You can still view them, but cannot add new instances or create hosts without premium.

### Refund Handling

**Apple App Store:**
- Direct users to: https://reportaproblem.apple.com
- Apple decides on refunds (typically within 48 hours)
- If approved, subscription is canceled immediately

**Google Play Store:**
- Direct users to: Play Store → Account → Purchase history → [App] → Request refund
- Google decides on refunds
- Refund policy: Within 48 hours for recent purchases

**Note:** Do NOT promise refunds or handle them manually. Always direct to platform.

---

## Conclusion

This paywall implementation follows all Apple and Google requirements, provides a smooth user experience, and sets up a sustainable revenue model for the app. The low price point ($0.99/month) has a low barrier to entry while the yearly option ($9.99/year) encourages long-term subscriptions.

**Key Success Factors:**
1. Free tier remains useful (single instance, view/edit)
2. Premium features are valuable and well-priced
3. Paywall appears at natural friction points
4. Restore purchases always available
5. Full platform compliance
6. Clear, transparent pricing and terms

**Next Steps:**
1. Review this document thoroughly
2. Add `in_app_purchase` package
3. Configure App Store Connect and Play Console
4. Implement `SubscriptionService`
5. Create `PaywallScreen`
6. Test extensively in sandbox
7. Soft launch to limited users
8. Monitor and iterate

---

**End of Document**

