# Paywall Testing Checklist

## 📋 Pre-Testing Setup

### iOS Setup
- [ ] Create sandbox tester account in App Store Connect
- [ ] Sign out of real App Store account on test device
- [ ] Build app in debug mode
- [ ] Install on physical device (simulator has limitations)

### Android Setup
- [ ] Add test account to License Testing in Play Console
- [ ] Sign in to Play Store with test account
- [ ] Install app from internal testing track

---

## 🧪 Test Scenarios

### 1. Free Trial Flow (New User)

#### Starting Trial
- [ ] Install fresh app (no previous trial)
- [ ] Set up first NPM instance (should work - free tier)
- [ ] Try to add 2nd instance
  - [ ] Paywall appears
  - [ ] "Start 7-Day Free Trial" button is visible
  - [ ] Trial terms are displayed
- [ ] Click "Start 7-Day Free Trial"
  - [ ] Success message appears
  - [ ] Returns to previous screen
  - [ ] Can now add 2nd instance
- [ ] Try to create new proxy host
  - [ ] Works without paywall (trial grants premium)

#### During Trial
- [ ] Force close and reopen app
  - [ ] Premium access persists
- [ ] Try to add 3rd instance
  - [ ] Works (premium active)
- [ ] Create multiple proxy hosts
  - [ ] All work (premium active)

#### Trial Expiration
- [ ] Manually advance device time by 7+ days
- [ ] Reopen app
- [ ] Try to add new instance
  - [ ] Paywall appears (trial expired)
  - [ ] NO trial button (already used trial)
  - [ ] Only subscription options available
- [ ] Try to create proxy host
  - [ ] Paywall appears (premium revoked)

---

### 2. Subscription Purchase Flow

#### Monthly Subscription
- [ ] Fresh install OR expired trial user
- [ ] Trigger paywall (add instance or create host)
- [ ] Select monthly plan ($0.99)
- [ ] Click "Subscribe Now"
- [ ] Complete purchase in test environment
  - [ ] iOS: Shows sandbox payment prompt
  - [ ] Android: Shows "Test purchase"
- [ ] Premium unlocked successfully
- [ ] Can add multiple instances
- [ ] Can create proxy hosts

#### Yearly Subscription
- [ ] Repeat above with yearly plan ($9.99)
- [ ] Verify "SAVE 16%" badge appears
- [ ] Complete purchase
- [ ] Premium unlocked

---

### 3. Restore Purchases Flow

#### Single Device Restore
- [ ] Purchase subscription (monthly or yearly)
- [ ] Force close app
- [ ] Delete and reinstall app
- [ ] Try to add 2nd instance (triggers paywall)
- [ ] Click "Restore Purchases"
- [ ] Premium access restored
- [ ] Can add instances and create hosts

#### Multi-Device Restore
- [ ] Purchase on Device A
- [ ] Install app on Device B (same Apple ID/Google account)
- [ ] Trigger paywall on Device B
- [ ] Click "Restore Purchases"
- [ ] Premium access granted on Device B

---

### 4. Edge Cases

#### Trial Already Used
- [ ] Complete trial on device
- [ ] Delete and reinstall app
- [ ] Try to add 2nd instance
- [ ] Paywall appears WITHOUT trial button
- [ ] Only subscription options available

#### Subscription Canceled
- [ ] Subscribe to monthly plan
- [ ] Cancel subscription (but still in billing period)
- [ ] Premium should still work until period ends
- [ ] After period ends, premium revoked
- [ ] Can resubscribe anytime

#### Multiple Instances After Trial Expires
- [ ] Start trial
- [ ] Add 10 NPM instances
- [ ] Wait for trial to expire
- [ ] User can still VIEW all 10 instances
- [ ] Cannot add 11th instance
- [ ] Cannot switch between instances (optional: you can allow this)
- [ ] Prompt to resubscribe

---

### 5. UI/UX Testing

#### Paywall Appearance
- [ ] Paywall matches app theme (black background)
- [ ] All text is readable
- [ ] Buttons are properly styled
- [ ] Icons render correctly
- [ ] Feature list is complete
- [ ] Pricing is clear
- [ ] Terms are visible

#### Trial Eligible UI
- [ ] Green "Start 7-Day Free Trial" button is prominent
- [ ] "No charge for 7 days" text is visible
- [ ] "Or subscribe now:" divider is clear
- [ ] Monthly/yearly options below trial button

#### Non-Trial Eligible UI
- [ ] No trial button visible
- [ ] Only "Subscribe Now" option
- [ ] "Restore Purchases" button accessible
- [ ] Clear why trial isn't available (already used)

---

### 6. Integration Testing

#### Dashboard Integration
- [ ] Click "Add Proxy Host" FAB
- [ ] Paywall appears for free users
- [ ] Premium users bypass paywall
- [ ] After subscribing, can create hosts

#### Login Screen Integration
- [ ] First instance creates successfully (free)
- [ ] Click "Add New" for 2nd instance
- [ ] Paywall appears for free users
- [ ] After subscribing, can add instances

---

### 7. Error Handling

#### No Internet
- [ ] Disable internet
- [ ] Try to start trial
- [ ] Appropriate error message shown
- [ ] Try to purchase
- [ ] Appropriate error message shown

#### Purchase Canceled
- [ ] Start purchase flow
- [ ] Cancel in payment dialog
- [ ] Returns to paywall gracefully
- [ ] Can retry purchase

#### Purchase Failed
- [ ] Use test card that fails (if supported)
- [ ] Error message is user-friendly
- [ ] Can retry purchase

---

### 8. Platform-Specific Testing

#### iOS Specific
- [ ] Face ID/Touch ID works for payment
- [ ] Family Sharing works (if enabled)
- [ ] Subscription shows in Settings → Subscriptions
- [ ] Can cancel from Settings
- [ ] Grace period works (simulate failed payment)

#### Android Specific
- [ ] Subscription shows in Play Store → Subscriptions
- [ ] Can cancel from Play Store
- [ ] Proration works (upgrade/downgrade)
- [ ] Grace period works (3 days)
- [ ] Account hold status handled

---

## 🔍 Verification Points

### Premium Status
After each successful trial start or purchase, verify:
- [ ] `isPremium()` returns `true`
- [ ] `canAddInstance(currentCount)` allows up to 50
- [ ] `canCreateHost()` returns `true`
- [ ] Status persists across app restarts

### Trial Status
During active trial, verify:
- [ ] `isOnTrial()` returns `true`
- [ ] `getTrialDaysRemaining()` returns correct count
- [ ] `isTrialEligible()` returns `false` after trial starts
- [ ] Trial start time is saved

### Subscription Status
After purchase, verify:
- [ ] Premium flag is set in SharedPreferences
- [ ] `isOnTrial()` returns `false`
- [ ] Trial timestamp is cleared
- [ ] Purchase can be restored

---

## 📊 Test Results Template

### Test Run: [Date]
**Platform:** iOS / Android  
**Test Account:** [Sandbox email]  
**Device:** [Model]

| Test Scenario | Status | Notes |
|--------------|--------|-------|
| Start free trial | ✅/❌ | |
| Trial access persists | ✅/❌ | |
| Trial expiration | ✅/❌ | |
| Monthly purchase | ✅/❌ | |
| Yearly purchase | ✅/❌ | |
| Restore purchases | ✅/❌ | |
| Multi-device restore | ✅/❌ | |
| Trial already used | ✅/❌ | |
| Paywall UI (trial eligible) | ✅/❌ | |
| Paywall UI (not eligible) | ✅/❌ | |
| Dashboard integration | ✅/❌ | |
| Login integration | ✅/❌ | |
| Error handling | ✅/❌ | |

**Issues Found:**
1. 
2. 
3. 

**Overall Status:** PASS / FAIL

---

## 🚀 Production Readiness

Before launching to production, ensure:
- [ ] All test scenarios pass on iOS
- [ ] All test scenarios pass on Android
- [ ] Privacy Policy is updated and hosted
- [ ] Terms of Service is created and hosted
- [ ] URLs in paywall_screen.dart are updated
- [ ] App Store Connect subscriptions are configured
- [ ] Google Play Console subscriptions are configured
- [ ] Sandbox testing is complete
- [ ] Beta testing with real users is complete
- [ ] Analytics tracking is implemented (optional)
- [ ] Support documentation is ready

---

## 💡 Testing Tips

1. **Use sandbox time acceleration:**
   - iOS: 1 month = 5 minutes in sandbox
   - Test renewal behavior quickly

2. **Clear app data between tests:**
   - Ensures clean state
   - Prevents trial conflicts

3. **Test on multiple devices:**
   - Different iOS versions
   - Different Android versions
   - Different screen sizes

4. **Document all issues:**
   - Screenshots help
   - Reproduction steps essential
   - Device info important

5. **Test real-world scenarios:**
   - Slow internet
   - Interrupted purchases
   - Background app killing
   - Low storage warnings

---

## ✅ Sign-Off

**Tested by:** _______________  
**Date:** _______________  
**Approved for production:** YES / NO  
**Notes:** _______________

