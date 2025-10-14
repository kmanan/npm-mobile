import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'dart:async';

enum SubscriptionStatus {
  free,
  trial,
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
  static const String monthlyProductId = 'npm_premium_monthly';
  static const String yearlyProductId = 'npm_premium_yearly';

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
    try {
      // Check if IAP is available with timeout
      final bool available = await _iap
          .isAvailable()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);

      if (!available) {
        _status = SubscriptionStatus.free;
        return;
      }

      // Load products with timeout
      await _loadProducts().timeout(const Duration(seconds: 10));

      // Restore purchases (check existing subscription) with timeout
      await restorePurchases().timeout(const Duration(seconds: 10));

      // Listen to purchase updates
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (error) => debugPrint('Purchase stream error: $error'),
      );
    } catch (e) {
      debugPrint('Initialization error: $e');
      _status = SubscriptionStatus.free;
    }
  }

  /// Load available products from stores
  Future<void> _loadProducts() async {
    const Set<String> productIds = {monthlyProductId, yearlyProductId};

    try {
      final ProductDetailsResponse response =
          await _iap.queryProductDetails(productIds);

      if (response.notFoundIDs.isNotEmpty) {
        debugPrint('Products not found: ${response.notFoundIDs}');
      }

      _products = response.productDetails;
      _products.sort((a, b) => a.rawPrice.compareTo(b.rawPrice));
    } catch (e) {
      debugPrint('Error loading products: $e');
    }
  }

  /// Purchase a subscription
  Future<bool> purchaseSubscription(ProductDetails product) async {
    final PurchaseParam purchaseParam = PurchaseParam(productDetails: product);

    try {
      // Use buyNonConsumable for both iOS and Android subscriptions
      // in_app_purchase treats subscriptions as non-consumables
      return await _iap.buyNonConsumable(purchaseParam: purchaseParam);
    } catch (e) {
      debugPrint('Purchase error: $e');
      return false;
    }
  }

  /// Restore previous purchases
  Future<void> restorePurchases() async {
    try {
      await _iap.restorePurchases();

      // Also check for active trial
      await _checkTrialStatus();

      // Purchase stream will handle the restored purchases
    } catch (e) {
      debugPrint('Restore error: $e');
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
        debugPrint('Purchase error: ${purchase.error}');
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
    // Remove trial status when premium is granted
    await prefs.remove('trial_start_time');
  }

  /// Revoke premium access
  Future<void> _revokePremiumAccess() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setBool('is_premium', false);
  }

  /// Start free trial
  Future<void> startFreeTrial() async {
    final prefs = await SharedPreferences.getInstance();
    final now = DateTime.now().millisecondsSinceEpoch;
    await prefs.setInt('trial_start_time', now);
    await prefs.setBool('is_premium', true); // Grant premium during trial
    _status = SubscriptionStatus.trial;
    _notifyListeners();
  }

  /// Check if user is eligible for free trial
  Future<bool> isTrialEligible() async {
    final prefs = await SharedPreferences.getInstance();

    // Check if user has ever had a trial or premium subscription
    final hadTrial = prefs.containsKey('trial_start_time');
    final hadPremium = prefs.getBool('is_premium') ?? false;

    // User is eligible if they've never had trial or premium
    return !hadTrial && !hadPremium;
  }

  /// Check trial status and update accordingly
  Future<void> _checkTrialStatus() async {
    final prefs = await SharedPreferences.getInstance();
    final trialStartTime = prefs.getInt('trial_start_time');

    if (trialStartTime == null) {
      return; // No active trial
    }

    final startDate = DateTime.fromMillisecondsSinceEpoch(trialStartTime);
    final now = DateTime.now();
    final difference = now.difference(startDate);

    if (difference.inDays >= 7) {
      // Trial expired
      await _revokePremiumAccess();
      _status = SubscriptionStatus.expired;
      _notifyListeners();
    } else {
      // Trial still active
      _status = SubscriptionStatus.trial;
      _notifyListeners();
    }
  }

  /// Get days remaining in trial
  Future<int> getTrialDaysRemaining() async {
    final prefs = await SharedPreferences.getInstance();
    final trialStartTime = prefs.getInt('trial_start_time');

    if (trialStartTime == null) {
      return 0;
    }

    final startDate = DateTime.fromMillisecondsSinceEpoch(trialStartTime);
    final now = DateTime.now();
    final difference = now.difference(startDate);
    final daysRemaining = 7 - difference.inDays;

    return daysRemaining > 0 ? daysRemaining : 0;
  }

  /// Check if user has premium access (includes trial)
  Future<bool> isPremium() async {
    // Check trial status first
    await _checkTrialStatus();

    // During restore/initialization, use in-memory status
    if (_status == SubscriptionStatus.premium ||
        _status == SubscriptionStatus.trial) {
      return true;
    }

    // Check stored premium status
    final prefs = await SharedPreferences.getInstance();
    return prefs.getBool('is_premium') ?? false;
  }

  /// Check if user is currently on trial
  Future<bool> isOnTrial() async {
    await _checkTrialStatus();
    return _status == SubscriptionStatus.trial;
  }

  /// Check if user can add more instances
  Future<bool> canAddInstance(int currentInstanceCount) async {
    if (await isPremium()) {
      return currentInstanceCount < 50; // Premium limit
    }
    // Free users can only have 1 instance total
    // If they have 1 or more, they cannot add another
    return currentInstanceCount == 0;
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
