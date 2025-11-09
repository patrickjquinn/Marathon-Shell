# Marathon Code Signing Guide

Code signing ensures app integrity and authenticity on Marathon OS.

## Why Code Signing?

- **Authenticity**: Verify apps come from trusted developers
- **Integrity**: Detect tampering or modification
- **Security**: Protect users from malicious apps
- **Trust**: Build confidence in the app ecosystem

## Overview

Marathon uses GPG (GNU Privacy Guard) for code signing:

1. Developer signs `manifest.json` with private key
2. Signature stored in `SIGNATURE.txt`
3. Marathon verifies signature during installation
4. Users can trust signed apps

## Setup GPG

### Install GPG

```bash
# Fedora/RHEL
sudo dnf install gnupg2

# Ubuntu/Debian
sudo apt install gnupg

# macOS
brew install gnupg

# Verify installation
gpg --version
```

### Generate Key Pair

```bash
# Generate new key
gpg --full-generate-key

# Follow prompts:
# 1. Key type: RSA and RSA (default)
# 2. Key size: 4096 bits
# 3. Expiration: 0 = never expire (or set expiration)
# 4. Real name: Your Name
# 5. Email: your@email.com
# 6. Comment: (optional, e.g., "Marathon Developer Key")
# 7. Passphrase: Choose strong passphrase
```

Example session:
```
gpg (GnuPG) 2.3.8; Copyright (C) 2021 Free Software Foundation, Inc.

Please select what kind of key you want:
   (1) RSA and RSA (default)
Your selection? 1

RSA keys may be between 1024 and 4096 bits long.
What keysize do you want? (3072) 4096

Key is valid for? (0) 0

Real name: Jane Developer
Email address: jane@example.com
Comment: Marathon Developer
```

### List Your Keys

```bash
# List public keys
gpg --list-keys

# List private keys
gpg --list-secret-keys

# Output shows key ID, e.g.:
# pub   rsa4096 2024-01-01 [SC]
#       ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234
# uid           Jane Developer <jane@example.com>
```

### Export Public Key

```bash
# Export public key (ASCII format)
gpg --armor --export your@email.com > my-public-key.asc

# This file will be submitted to Marathon developer portal
```

### Backup Keys

**Important**: Backup your private key securely!

```bash
# Export private key (KEEP SECURE!)
gpg --armor --export-secret-keys your@email.com > private-key-backup.asc

# Store in secure location:
# - Encrypted USB drive
# - Password manager
# - Secure cloud storage with encryption
```

## Signing Your App

### Using marathon-dev Tool

```bash
# Navigate to your app directory
cd my-app/

# Sign with default key
marathon-dev sign .

# Or specify key ID
marathon-dev sign . ABCD1234ABCD1234
```

This creates `SIGNATURE.txt` in your app directory.

### Manual Signing

```bash
# Sign manifest.json
gpg --detach-sign --armor --output SIGNATURE.txt manifest.json

# Verify signature
gpg --verify SIGNATURE.txt manifest.json
```

### Sign Output

```
gpg: Signature made Mon 01 Jan 2024 12:00:00 PM PST
gpg:                using RSA key ABCD1234ABCD1234ABCD1234ABCD1234ABCD1234
gpg: Good signature from "Jane Developer <jane@email.com>" [ultimate]
```

## Verification

### Verify Locally

```bash
# Verify your signature
marathon-dev validate my-app/

# Or manually with GPG
gpg --verify my-app/SIGNATURE.txt my-app/manifest.json
```

### Marathon Verification Process

When users install your app:

1. Extract `.marathon` package
2. Read `manifest.json` and `SIGNATURE.txt`
3. Verify signature matches manifest
4. Check if signing key is trusted
5. If valid, proceed with installation
6. If invalid, reject installation

## Trust Management

### Development Mode

During development, Marathon accepts any valid signature (signed but not necessarily trusted).

### Production Mode

In production, Marathon only accepts:
- Apps signed by verified developer keys (registered in developer portal)
- System apps signed by Marathon OS master key

### Add Trusted Keys

Users can manually trust additional developer keys:

```bash
# Import developer's public key
gpg --import developer-key.asc

# Trust the key
gpg --edit-key developer@example.com trust
# Select trust level: 5 = I trust ultimately
```

## Key Management

### Key Rotation

If your key is compromised:

1. **Revoke old key**:
```bash
# Generate revocation certificate
gpg --output revoke.asc --gen-revoke your@email.com

# Import and publish revocation
gpg --import revoke.asc
gpg --send-keys YOUR_KEY_ID
```

2. **Generate new key** (see Setup GPG section)

3. **Update developer portal** with new public key

4. **Re-sign all apps** with new key

5. **Publish updates** so users get newly signed versions

### Multiple Developers

For team development:

#### Option 1: Shared Key (Simpler)
- Generate one key for the team
- Securely share private key among team members
- All apps signed with same key

#### Option 2: Multiple Keys (More Secure)
- Each developer has own key
- Add all public keys to trusted keys
- Apps can be signed by any team member
- Better accountability

## Best Practices

### Security

 **Do**:
- Use strong passphrase
- Store private key securely
- Backup key in multiple secure locations
- Use 4096-bit keys
- Set key expiration (e.g., 2 years)
- Rotate keys periodically

 **Don't**:
- Share private key publicly
- Store key in version control
- Use weak passphrase
- Leave key unencrypted on disk

### Signing Workflow

```bash
# 1. Develop app
vim my-app/MyApp.qml

# 2. Test thoroughly
marathon-dev validate my-app/

# 3. Update version in manifest.json
# "version": "1.1.0"

# 4. Sign manifest
marathon-dev sign my-app/

# 5. Package
marathon-dev package my-app/

# 6. Verify package
marathon-dev validate my-app.marathon

# 7. Upload to store
```

### Automation

For CI/CD pipelines:

```bash
# Store GPG key as environment variable
export GPG_PRIVATE_KEY="$(cat private-key.asc)"
export GPG_PASSPHRASE="your-passphrase"

# Import key in CI
echo "$GPG_PRIVATE_KEY" | gpg --import --batch

# Sign non-interactively
echo "$GPG_PASSPHRASE" | gpg --batch --yes --passphrase-fd 0 \
  --detach-sign --armor --output SIGNATURE.txt manifest.json
```

 **Security Note**: Use CI/CD secrets management, not plain text!

## Troubleshooting

### "gpg: signing failed: No secret key"

Your private key isn't available:

```bash
# Check if private key exists
gpg --list-secret-keys

# If missing, import from backup
gpg --import private-key-backup.asc
```

### "gpg: signing failed: Inappropriate ioctl for device"

GPG can't prompt for passphrase:

```bash
# Set GPG_TTY environment variable
export GPG_TTY=$(tty)

# Or use passphrase file (less secure)
echo "passphrase" > passphrase.txt
gpg --passphrase-file passphrase.txt --detach-sign manifest.json
```

### "gpg: BAD signature"

Signature doesn't match manifest:

- Manifest was modified after signing
- Wrong signature file
- Corrupted file

Solution: Re-sign the manifest

### "gpg: Can't check signature: No public key"

Verifier doesn't have your public key:

```bash
# Send public key to keyserver
gpg --send-keys YOUR_KEY_ID

# Or export and share manually
gpg --armor --export your@email.com > public-key.asc
```

## Advanced Topics

### Subkeys

Use subkeys for enhanced security:

```bash
# Generate signing subkey
gpg --edit-key your@email.com
gpg> addkey
# Select (4) RSA (sign only)
gpg> save

# Separate master key from signing key
# Store master key offline
# Use signing subkey for daily signing
```

### Timestamping

Add timestamp to signatures:

```bash
# Sign with timestamp
gpg --detach-sign --armor --sig-notation timestamp="$(date -u +%Y-%m-%dT%H:%M:%SZ)" \
  --output SIGNATURE.txt manifest.json
```

### Hardware Tokens

Use YubiKey or similar for key storage:

```bash
# Generate key on hardware token
gpg --card-edit
gpg/card> admin
gpg/card> generate

# Signing uses hardware token
# Private key never leaves device
```

## Reference

### File Structure

```
my-app/
├── manifest.json       # App metadata
├── SIGNATURE.txt       # GPG signature (detached)
├── MyApp.qml
└── assets/
    └── icon.svg
```

### SIGNATURE.txt Format

```
-----BEGIN PGP SIGNATURE-----

iQIzBAABCAAdFiEEabcdef...
...
-----END PGP SIGNATURE-----
```

### Verification Command

```bash
gpg --verify SIGNATURE.txt manifest.json
```

Expected output:
```
gpg: Signature made Mon 01 Jan 2024 12:00:00 PM PST
gpg:                using RSA key ABCD1234...
gpg: Good signature from "Developer <dev@example.com>"
```

## Resources

- **GPG Documentation**: https://gnupg.org/documentation/
- **Best Practices**: https://riseup.net/en/security/message-security/openpgp/best-practices
- **Key Management**: https://help.ubuntu.com/community/GnuPrivacyGuardHowto
- **Marathon Developer Portal**: https://apps.marathonos.org

## Support

Questions about code signing:
- **Email**: security@marathonos.org
- **Forum**: https://forum.marathonos.org/c/development
- **Documentation**: https://docs.marathonos.org/signing

Remember: Keep your private key secure! 🔐

