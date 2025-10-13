# Legal Documents Upload Guide

## 📄 Files Created

I've created the following legal documents for your paywall implementation:

### 1. **privacy.md** (Updated)
- ✅ Updated existing privacy policy
- ✅ Added subscription & payment data section
- ✅ Added free trial information
- ✅ Added data sharing details

### 2. **terms-of-service.md** (New)
- ✅ Complete Terms of Service
- ✅ Detailed subscription terms
- ✅ 7-day free trial terms
- ✅ Billing, renewal, and cancellation policies
- ✅ Refund policy

### 3. **privacy-policy.html** (New)
- ✅ HTML version of privacy policy
- ✅ Ready to upload to your website
- ✅ Mobile-responsive design

### 4. **terms-of-service.html** (New)
- ✅ HTML version of terms of service
- ✅ Ready to upload to your website
- ✅ Mobile-responsive design

---

## 🌐 How to Upload to Your Website

### Option 1: Direct HTML Upload (Recommended)
1. Upload `privacy-policy.html` to your website
2. Upload `terms-of-service.html` to your website
3. Note the URLs (e.g., https://yourwebsite.com/privacy-policy.html)

### Option 2: Convert to Your Site's Format
If you have a CMS (WordPress, etc.):
1. Copy content from the HTML files
2. Create new pages in your CMS
3. Paste the content
4. Publish

### Option 3: GitHub Pages (Free Hosting)
1. Create a GitHub repository (e.g., `npm-mobile-legal`)
2. Push the HTML files to the repo
3. Enable GitHub Pages in repository settings
4. Access via: https://yourusername.github.io/npm-mobile-legal/privacy-policy.html

---

## 🔗 Update App Code with URLs

After uploading, update these URLs in your app:

### File: `lib/screens/paywall_screen.dart`

**Line 157:** Privacy Policy URL
```dart
// REPLACE THIS:
final uri = Uri.parse('https://YOUR_ACTUAL_URL/privacy.md');

// WITH YOUR ACTUAL URL:
final uri = Uri.parse('https://yourwebsite.com/privacy-policy.html');
```

**Line 165:** Terms of Service URL
```dart
// REPLACE THIS:
final uri = Uri.parse('https://YOUR_ACTUAL_URL/terms-of-service.md');

// WITH YOUR ACTUAL URL:
final uri = Uri.parse('https://yourwebsite.com/terms-of-service.html');
```

---

## 📋 Store Configuration

### Apple App Store Connect
1. Go to App Information
2. Scroll to "Privacy Policy"
3. Enter URL: `https://yourwebsite.com/privacy-policy.html`

### Google Play Console
1. Go to Store presence → Privacy Policy
2. Enter URL: `https://yourwebsite.com/privacy-policy.html`

---

## ⚠️ IMPORTANT: Before Publishing

Update the placeholder text in BOTH documents:

### Privacy Policy & Terms of Service:

**Replace:**
- `[your-email@example.com]` → Your actual support email
- `[your-github-repo-url]` → Your actual GitHub repository URL
- `[Your Country/State]` (Terms only) → Your jurisdiction (e.g., "California, USA")
- `[Your Jurisdiction]` (Terms only) → Your court jurisdiction

### Example Updates:

**Before:**
```
Email: [your-email@example.com]
GitHub: [your-github-repo-url]
```

**After:**
```
Email: support@yourdomain.com
GitHub: https://github.com/yourusername/npm-phone-app
```

---

## 🎯 Quick Checklist

Before launching:
- [ ] Replace all placeholder text in HTML files
- [ ] Upload HTML files to your website
- [ ] Verify both URLs are publicly accessible
- [ ] Update URLs in `paywall_screen.dart`
- [ ] Add Privacy Policy URL to App Store Connect
- [ ] Add Privacy Policy URL to Google Play Console
- [ ] Test clicking links in the app

---

## 📱 Testing the Links

1. Build and run your app
2. Navigate to the paywall screen
3. Click "Privacy Policy" at the bottom
4. Verify it opens in browser
5. Click "Terms of Service" at the bottom
6. Verify it opens in browser

Both should open in the device's default browser, NOT in-app.

---

## 🆘 Troubleshooting

### "Links don't open in browser"
- Make sure you're using `LaunchMode.externalApplication`
- This is already configured in your code

### "404 Not Found"
- Verify files are uploaded to correct directory
- Check URL spelling matches exactly
- Ensure files are publicly accessible (not behind login)

### "Need to update privacy policy later"
- Just edit the HTML files on your server
- No need to update the app
- Changes reflect immediately

---

## 💡 Pro Tips

1. **Keep URLs Simple:**
   - `yoursite.com/privacy-policy.html`
   - `yoursite.com/terms-of-service.html`

2. **Use HTTPS:**
   - Both Apple and Google require HTTPS URLs
   - Free options: GitHub Pages, Netlify, Vercel

3. **Version Control:**
   - Keep the markdown (.md) files in your Git repo
   - Upload HTML versions to your website
   - Update "Last updated" date when making changes

4. **Email Setup:**
   - Use a dedicated support email
   - Consider: support@, legal@, or privacy@yourdomain.com

---

## ✅ You're All Set!

Once you:
1. Replace placeholder text
2. Upload to your website
3. Update the app code with URLs
4. Test the links

Your legal documents will be compliant with Apple and Google requirements! 🎉

