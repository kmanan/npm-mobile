import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_storekit/store_kit_2_wrappers.dart';
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

  /// Initialize the subscription service.
  /// Uses fast local checks only — no network calls, no Apple ID prompts.
  /// Product loading happens in the background.
  Future<void> initialize() async {
    try {
      // Check if IAP is available with timeout
      final bool available = await _iap
          .isAvailable()
          .timeout(const Duration(seconds: 5), onTimeout: () => false);

      if (!available) {
        debugPrint('[Subscription] IAP not available');
        _status = SubscriptionStatus.free;
        return;
      }

      // Listen to purchase updates (must be set up before any purchase/restore)
      _subscription = _iap.purchaseStream.listen(
        _onPurchaseUpdate,
        onDone: () => _subscription?.cancel(),
        onError: (error) =>
            debugPrint('[Subscription] Purchase stream error: $error'),
      );

      // Load products in the background — don't block startup
      _loadProducts().timeout(const Duration(seconds: 10)).catchError((e) {
        debugPrint('[Subscription] Product loading failed: $e');
      });

      // Fast local subscription check — no network, no prompts
      try {
        await _checkSubscriptionLocal().timeout(const Duration(seconds: 5));
      } catch (e) {
        debugPrint('[Subscription] Local check during init failed: $e');
      }
    } catch (e) {
      debugPrint('[Subscription] Initialization error: $e');
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

  /// Fast local subscription check — no network calls, no prompts.
  /// Reads cached transaction data on iOS, checks SharedPreferences + trial.
  /// Called during initialize() for a fast, silent startup check.
  Future<bool> _checkSubscriptionLocal() async {
    if (Platform.isIOS) {
      return await _checkSubscriptionLocalIOS();
    } else {
      return await _checkSubscriptionLocalAndroid();
    }
  }

  /// iOS local check: reads cached SK2 transactions (no network, no Apple ID prompt).
  Future<bool> _checkSubscriptionLocalIOS() async {
    debugPrint('[Subscription] iOS local check: querying SK2Transaction.transactions()...');

    final List<SK2Transaction> transactions = await SK2Transaction.transactions();

    debugPrint('[Subscription] iOS local check: found ${transactions.length} transaction(s)');

    bool foundActive = false;

    for (final transaction in transactions) {
      if (transaction.productId == monthlyProductId ||
          transaction.productId == yearlyProductId) {
        if (transaction.expirationDate != null) {
          final expirationDate = DateTime.tryParse(transaction.expirationDate!);
          if (expirationDate != null && expirationDate.isAfter(DateTime.now())) {
            debugPrint('[Subscription] iOS local check: found active subscription '
                '${transaction.productId}, expires ${transaction.expirationDate}');
            foundActive = true;
            break;
          } else {
            debugPrint('[Subscription] iOS local check: found expired subscription '
                '${transaction.productId}, expired ${transaction.expirationDate}');
          }
        }
      }
    }

    if (foundActive) {
      await _grantPremiumAccess();
      _status = SubscriptionStatus.premium;
      _notifyListeners();
    } else {
      await _checkTrialStatus();
    }

    return foundActive;
  }

  /// Android local check: reads cached premium status from SharedPreferences
  /// and verifies trial validity. The purchase stream listener (set up in
  /// initialize) will pick up any new/restored purchases automatically.
  Future<bool> _checkSubscriptionLocalAndroid() async {
    debugPrint('[Subscription] Android local check: reading cached status...');

    final prefs = await SharedPreferences.getInstance();
    final isPremiumCached = prefs.getBool('is_premium') ?? false;

    if (isPremiumCached) {
      debugPrint('[Subscription] Android local check: cached premium = true');
      _status = SubscriptionStatus.premium;
      _notifyListeners();
      return true;
    }

    // Not premium — check if there's an active trial
    await _checkTrialStatus();
    return _status == SubscriptionStatus.trial;
  }

  /// Restore previous purchases (user-initiated, full server sync).
  /// On iOS: calls AppStore().sync() which may trigger Apple ID auth.
  /// On Android: calls restorePurchases() via the purchase stream.
  /// Returns true if an active subscription was found, false otherwise.
  /// Throws on error so the UI can display the failure.
  Future<bool> restorePurchases() async {
    try {
      if (Platform.isIOS) {
        return await _restorePurchasesIOS();
      } else {
        return await _restorePurchasesAndroid();
      }
    } catch (e) {
      debugPrint('[Subscription] Restore error: $e');
      rethrow; // Let the UI handle and display the error
    }
  }

  /// iOS restore (user-initiated): syncs with App Store then checks transactions.
  /// This may trigger an Apple ID sign-in prompt — only call from Restore button.
  Future<bool> _restorePurchasesIOS() async {
    debugPrint('[Subscription] iOS restore: calling AppStore.sync()...');

    // Sync transaction data with the App Store (triggers Apple ID auth)
    await AppStore().sync();

    debugPrint('[Subscription] iOS restore: querying SK2Transaction.transactions()...');

    // Directly query all transactions — no purchase stream race condition
    final List<SK2Transaction> transactions = await SK2Transaction.transactions();

    debugPrint('[Subscription] iOS restore: found ${transactions.length} transaction(s)');

    bool foundActive = false;

    for (final transaction in transactions) {
      // Check if this is one of our subscription products
      if (transaction.productId == monthlyProductId ||
          transaction.productId == yearlyProductId) {
        // Check if the subscription has a valid expiration date
        if (transaction.expirationDate != null) {
          final expirationDate = DateTime.tryParse(transaction.expirationDate!);
          if (expirationDate != null && expirationDate.isAfter(DateTime.now())) {
            debugPrint('[Subscription] iOS restore: found active subscription '
                '${transaction.productId}, expires ${transaction.expirationDate}');
            foundActive = true;
            break;
          } else {
            debugPrint('[Subscription] iOS restore: found expired subscription '
                '${transaction.productId}, expired ${transaction.expirationDate}');
          }
        }
      }
    }

    if (foundActive) {
      await _grantPremiumAccess();
      _status = SubscriptionStatus.premium;
      _notifyListeners();
    } else {
      // No active subscription — still check for an active trial
      await _checkTrialStatus();
    }

    return foundActive;
  }

  /// Android restore (user-initiated): queries Google Play via the purchase stream.
  /// Only call from the Restore button.
  Future<bool> _restorePurchasesAndroid() async {
    debugPrint('[Subscription] Android restore: calling restorePurchases()...');

    bool foundActive = false;

    // Use the existing _onPurchaseUpdate listener (set up in initialize)
    // to handle restored purchases. Just trigger the restore.
    await _iap.restorePurchases();

    // Give the purchase stream a reasonable window to deliver events
    await Future.delayed(const Duration(seconds: 5));

    // Check if _onPurchaseUpdate granted premium during the wait
    if (_status == SubscriptionStatus.premium) {
      foundActive = true;
    }

    if (!foundActive) {
      // No active subscription — still check for an active trial
      await _checkTrialStatus();
    }

    return foundActive;
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
