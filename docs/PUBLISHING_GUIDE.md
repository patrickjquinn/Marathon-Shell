# Marathon App Publishing Guide

This guide walks you through publishing your app to the Marathon App Store.

## Prerequisites

- Completed app following Marathon guidelines
- A minisign key for code signing
- Marathon Developer Account
- App tested on real device

## Step 1: Prepare Your App

### 1.1 Final Testing

```bash
# Test installation of the unpackaged app (directories are unsigned)
MARATHON_ALLOW_UNSIGNED=1 marathon-dev install ./my-app

# Test on actual device
# Verify all features work correctly
```

### 1.2 Optimize Assets

- **Icons**: Provide SVG icon (512x512 design size)
- **Images**: Optimize and compress all images
- **Code**: Remove debug logging and test code

### 1.3 Update Manifest

Ensure your `manifest.json` is complete:

```json
{
  "id": "com.yourcompany.appname",
  "name": "Your App Name",
  "version": "1.0.0",
  "entryPoint": "YourApp.qml",
  "icon": "assets/icon.svg",
  "author": "Your Name or Company",
  "description": "Brief description of your app",
  "permissions": ["network"],
  "minShellVersion": "1.0.0",
  "categories": ["Productivity"],
  "searchKeywords": ["keyword1", "keyword2"]
}
```

## Step 2: Code Signing

### 2.1 Make a minisign key (first time only)

```bash
minisign -G     # ~/.minisign/minisign.key and ~/.minisign/minisign.pub
```

You'll submit `minisign.pub` with your first app. See
[CODE_SIGNING_GUIDE.md](CODE_SIGNING_GUIDE.md).

## Step 3: Package and Sign Your App

```bash
# Creates my-app.marathon and my-app.marathon.minisig
marathon-dev package ./my-app my-app.marathon --key ~/.minisign/minisign.key

# Check the signature against your device's trusted keys
marathon-dev verify my-app.marathon
```

## Step 4: Create Developer Account

1. Go to https://apps.marathonos.org
2. Click "Developer Sign Up"
3. Fill in your information:
   - Name/Company name
   - Email address
   - Developer bio
   - Upload your minisign public key (`minisign.pub`)
4. Verify your email
5. Accept developer agreement

## Step 5: Submit Your App

### 5.1 Upload Package

1. Log in to Developer Portal
2. Click "Submit New App"
3. Upload your `.marathon` package and its `.minisig`
4. System will validate:
   - Package structure
   - minisign signature
   - Manifest completeness

### 5.2 Fill in Store Listing

- **App Name**: Display name in store
- **Short Description**: 1-2 sentences (80 chars)
- **Long Description**: Full description (500-4000 chars)
- **Screenshots**: 3-5 screenshots (1080x1920 or 1920x1080)
- **Category**: Primary category
- **Tags**: Searchable keywords
- **Privacy Policy URL**: If collecting user data
- **Support URL/Email**: For user support

### 5.3 Pricing & Distribution

- **Price**: Free or set price
- **Countries**: Select distribution regions
- **Age Rating**: Based on content
- **License**: Open source license (if applicable)

### 5.4 Submit for Review

1. Review all information
2. Click "Submit for Review"
3. Review process typically takes 2-5 business days

## Step 6: Review Process

### What We Check

- **Functionality**: App works as described
- **Performance**: Responsive and stable
- **Security**: No malicious code or vulnerabilities
- **Privacy**: Permissions used appropriately
- **Content**: Appropriate for Marathon platform
- **Design**: Follows UI guidelines

### Possible Outcomes

- **Approved**: App published to store
- **Rejected**: Issues identified, resubmit after fixes
- **Needs Info**: Clarification needed from developer

## Step 7: App Updates

### Update Your App

1. Increment version in `manifest.json`
2. Update changelog
3. Test thoroughly
4. Sign and package again
5. Submit as app update

### Update Submission

```bash
# Update your app
cd my-app
# Make changes...

# Increment version in manifest.json
# "version": "1.1.0"

# Package and sign
marathon-dev package . my-app.marathon --key ~/.minisign/minisign.key

# Upload to developer portal
# Select "Update Existing App"
```

### Version Numbering

Use semantic versioning: `MAJOR.MINOR.PATCH`

- **MAJOR**: Breaking changes
- **MINOR**: New features, backwards compatible
- **PATCH**: Bug fixes

## App Store Guidelines

### Do's

 Provide clear app description
 Use high-quality screenshots
 Request only necessary permissions
 Handle errors gracefully
 Support portrait and landscape
 Follow Marathon UI guidelines
 Provide user support
 Keep app updated

### Don'ts

 Copy other apps
 Request unnecessary permissions
 Include hidden functionality
 Collect data without disclosure
 Show inappropriate content
 Spam keywords
 Use misleading screenshots
 Violate trademarks

## Monetization

### Free Apps

- No cost to users
- Can include optional donations
- Must not require payment for core features

### Paid Apps

- Set one-time purchase price
- Marathon handles payments
- 70/30 revenue split (developer/platform)
- Monthly payouts

### In-App Purchases

*Coming soon in Marathon OS 1.1*

## Analytics & Feedback

### Developer Dashboard

Access at https://apps.marathonos.org/dashboard

- Download statistics
- User ratings and reviews
- Crash reports
- Revenue tracking

### Responding to Reviews

- Reply to user reviews
- Address common issues
- Thank users for feedback

## App Promotion

### Best Practices

1. **Social Media**: Share on Twitter, Reddit, etc.
2. **Demo Video**: Create walkthrough video
3. **Blog Post**: Write about your app's development
4. **Community**: Engage in Marathon forums
5. **Updates**: Regular updates keep users interested

## Troubleshooting

### Package Validation Fails

- Check manifest.json syntax
- Verify all required fields present
- Ensure icon file exists
- Check QML syntax with `qmllint`

### Signature Verification Fails

- Ship `my-app.marathon.minisig` with the package
- Re-sign after any change to the package
- Make sure the key you signed with is the one you registered

### App Rejected

- Read rejection reason carefully
- Fix issues mentioned
- Re-test thoroughly
- Resubmit with explanation of changes

## Support

### Developer Resources

- **Documentation**: https://docs.marathonos.org
- **API Reference**: https://docs.marathonos.org/api
- **Sample Apps**: https://github.com/marathonos/example-apps
- **Developer Forum**: https://forum.marathonos.org

### Contact

- **Email**: developers@marathonos.org
- **Discord**: discord.gg/marathonos
- **Issue Tracker**: github.com/marathonos/marathon-shell/issues

Good luck with your app! 

