# Subscription Restore Fuckup — Feb 2026

## The Problem

After deleting the app and reinstalling from TestFlight, premium features were gone. Tapping "Restore Purchases" did absolutely nothing — no error, no feedback, just a useless button.

---

## Root Causes (There Were Multiple)

### 1. Only checking `PurchaseStatus.purchased`, ignoring `PurchaseStatus.restored`

**File:** `lib/services/entitlement_service.dart` — `_onPurchaseUpdated()`

The original code only looked for `.purchased` status on the purchase stream. When `restorePurchases()` was called, restored transactions come back with `.restored` status, so they were silently ignored.

```dart
// BROKEN — only catches new purchases, not restores
if (purchase.status == PurchaseStatus.purchased) { ... }

// FIXED — catches both
if (purchase.status == PurchaseStatus.purchased ||
    purchase.status == PurchaseStatus.restored) { ... }
```

### 2. Missing `completePurchase()` call

**File:** `lib/services/entitlement_service.dart` — `_onPurchaseUpdated()`

After processing a purchase/restore, the code never called `InAppPurchase.instance.completePurchase(purchase)`. Without this, transactions get stuck in a pending state on the App Store / Play Store side.

### 3. Logic could accidentally reset subscription to `false`

**File:** `lib/services/entitlement_service.dart` — `_onPurchaseUpdated()`

The old code set `newEntitlement = false` by default, looped through purchases, and then if `_isSubscribed != newEntitlement`, it would overwrite. If any batch of purchase stream events didn't include our product (which is common), it would flip `_isSubscribed` back to `false`.

### 4. `restorePurchases()` is fundamentally broken under StoreKit 2

**File:** `lib/services/entitlement_service.dart` — `restore()` and `refreshEntitlement()`

Since `in_app_purchase_storekit 0.4.0`, StoreKit 2 is the default on iOS 15+. The `restorePurchases()` method fires events onto the `purchaseStream`, but under StoreKit 2, this stream is unreliable for restores — events may never arrive, arrive duplicated, or arrive with malformed data. This is a known Flutter issue (flutter/flutter#160498, #159631, #127927).

**Fix:** Replaced the entire iOS restore flow with StoreKit 2 native APIs:
- `AppStore().sync()` — syncs transaction data with the App Store (triggers Apple ID auth)
- `SK2Transaction.transactions()` — directly queries all transactions, checks for active subscriptions with valid expiration dates

Android still uses `restorePurchases()` via the purchase stream since Google Play Billing doesn't have this issue.

### 5. Every error was silently swallowed

**File:** `lib/services/entitlement_service.dart` — every single method

Every `catch` block was:
```dart
catch (e) {
  // Handle X errors silently
}
```

Zero logging, zero feedback. Completely flying blind. Replaced all of them with `debugPrint('[Entitlement] ...')` logging.

### 6. `restore()` returned `void` — UI had no way to show feedback

**Files:** `lib/services/entitlement_service.dart`, `lib/screens/paywall_screen.dart`, `lib/screens/subscription_details_screen.dart`

`restore()` returned `Future<void>`. If it completed without error but found 0 transactions, the UI had no idea. The spinner would appear briefly and disappear with zero feedback to the user.

**Fix:** Changed `restore()` to return `Future<bool>` — `true` if an active subscription was found, `false` if not. Both UI screens now show appropriate messages:
- Found: "Purchases restored successfully!"
- Not found: "No active subscription found. Make sure you're signed in with the account you used to subscribe."
- Error: "Restore failed: [error details]"

### 7. TestFlight ≠ Production (Apple platform limitation)

TestFlight builds use the **sandbox** App Store environment. Production purchases are invisible to sandbox. So if you bought a subscription through the real App Store, deleted the app, and reinstalled from TestFlight, no restore mechanism — no matter how correct — will find that production purchase.

This is not a code bug. It's how Apple's StoreKit works:
- **TestFlight / debug builds** → sandbox environment → only sees sandbox purchases
- **App Store release builds** → production environment → sees production purchases

To test restore on TestFlight, you need a sandbox Apple ID with a sandbox purchase.

### 8. `AppStore().sync()` ran on every app launch — Apple ID prompt on every startup

**File:** `lib/services/subscription_service.dart` — `initialize()` and `_restorePurchasesIOS()`

After fixing restore (issues 1–7), `initialize()` called `restorePurchases()` on every launch. On iOS, that meant `AppStore().sync()` ran every single startup — for all users, including free users with no subscription. `AppStore().sync()` is designed for user-initiated restores and can trigger an Apple ID sign-in prompt. Users reported being asked to sign into their Apple account after updating the app.

On Android, the same `initialize()` called `_iap.restorePurchases()` every launch, which hit Google Play servers and added a hard 5-second `Future.delayed()` to every startup. It also created a duplicate purchase stream listener on top of the one already set up in `initialize()`.

**Fix:** Split the subscription check into two paths:

1. **`_checkSubscriptionLocal()`** — fast, offline, no prompts. Called during `initialize()`.
   - **iOS:** Reads cached `SK2Transaction.transactions()` directly. Apple keeps this updated in the background — no need for `sync()`.
   - **Android:** Reads cached `SharedPreferences` premium status + checks trial validity. The purchase stream listener (already set up in `initialize()`) handles any new events automatically.

2. **`restorePurchases()`** — full server sync, user-initiated only. Called only from the "Restore Purchases" button.
   - **iOS:** `AppStore().sync()` + `SK2Transaction.transactions()` (Apple ID prompt expected and acceptable here).
   - **Android:** `_iap.restorePurchases()` using the existing stream listener (no duplicate listener).

Also removed the `await` on `subscriptionService.initialize()` in `main.dart` so the app doesn't block on startup, and moved product loading to the background.

---

## Files Changed (Round 2 — Feb 2026)

| File | Change |
|------|--------|
| `lib/services/subscription_service.dart` | Split into local check (`_checkSubscriptionLocal()`) for startup and full restore (`restorePurchases()`) for user-initiated only. Removed `AppStore().sync()` from startup path. Removed duplicate Android stream listener. Background product loading. |
| `lib/main.dart` | Removed `await` on `subscriptionService.initialize()` — no longer blocks app startup |

---

## Files Changed (Round 1 — Feb 2026)

| File | Change |
|------|--------|
| `pubspec.yaml` | Upgraded `in_app_purchase: ^3.2.3`, added `in_app_purchase_storekit: '>=0.4.0 <0.4.4+1'` |
| `lib/services/entitlement_service.dart` | Complete rewrite — SK2 APIs for iOS, proper stream handling for Android, debug logging everywhere, `restore()` returns `bool` |
| `lib/screens/paywall_screen.dart` | Restore button now shows success/not-found/error feedback |
| `lib/screens/subscription_details_screen.dart` | Restore button now shows success/not-found/error feedback |

---

## Key Takeaways

1. Never silently swallow errors. Always log, always give user feedback.
2. The `in_app_purchase` package's `restorePurchases()` is unreliable on iOS with StoreKit 2. Use `AppStore().sync()` + `SK2Transaction.transactions()` instead.
3. `SharedPreferences` is not a source of truth for subscription status — it's a cache. The store is the source of truth.
4. TestFlight is sandbox. Production purchases don't exist there. You must test with sandbox accounts or release to the App Store.
5. A "Restore Purchases" button that does nothing with no feedback is worse than not having the button at all.
6. `AppStore().sync()` is for **user-initiated restores only** — never call it on startup. Use `SK2Transaction.transactions()` (local cached data) for launch-time checks. Calling `sync()` every launch prompts users to sign into their Apple account.
7. Don't block `main()` with network calls. Subscription init should be fast and local; product loading can happen in the background.