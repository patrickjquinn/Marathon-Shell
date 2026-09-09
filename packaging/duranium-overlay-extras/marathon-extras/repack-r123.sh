#!/bin/sh
set -e
apk add --no-cache patchelf abuild >/dev/null 2>&1
# Generate signing key
mkdir -p /root/.abuild
abuild-keygen -a -n -q
KEY=$(ls /root/.abuild/*.rsa | head -1)
cp "${KEY}.pub" /etc/apk/keys/
echo "PACKAGER_PRIVKEY=$KEY" > /etc/abuild.conf
echo "REPODEST=/work" >> /etc/abuild.conf
# Extract r123 apk
mkdir -p /work/pkg
cd /work/pkg
tar xzf /work/marathon-shell-1.0.0-r123.apk 2>/dev/null || true
# patchelf the .so files
for f in usr/lib/qt6/qml/MarathonOS/Services/libMarathonMailService.so \
         usr/lib/qt6/plugins/messagingframework/credentials/libmarathonoauth.so \
         usr/lib/qt6/plugins/messagingframework/credentials/libmarathonclassic.so; do
  if [ -f "$f" ]; then
    patchelf --replace-needed libQmfClient.so.4 libQmfClient-qt6.so.6 "$f" 2>/dev/null || true
    patchelf --replace-needed libQmfMessageServer.so.4 libQmfMessageServer-qt6.so.6 "$f" 2>/dev/null || true
    echo "patched: $f"
  fi
done
# Rewrite .PKGINFO so:libQmf*.so.4 -> -qt6.so.6
sed -i 's/depend = so:libQmfClient\.so\.4/depend = so:libQmfClient-qt6.so.6/; s/depend = so:libQmfMessageServer\.so\.4/depend = so:libQmfMessageServer-qt6.so.6/' .PKGINFO
grep 'so:libQmf' .PKGINFO
# Bump pkgver/rel to r124 since we're modifying
sed -i 's/pkgver = 1.0.0-r123/pkgver = 1.0.0-r124/' .PKGINFO
# Repack apk
mkdir -p /work/aports/marathon-shell/pkg
cp -r * /work/aports/marathon-shell/pkg/ 2>/dev/null || true
cd /work/aports/marathon-shell
# Use abuild-tar which handles apk format
( cd pkg && tar -c .PKGINFO .post-install .SIGN.* usr 2>/dev/null | abuild-tar --hash | gzip -c ) > /work/marathon-shell-1.0.0-r124.apk.body 2>/dev/null
# Actually simpler: use the standard apk format which is gzipped tar
cd /work/pkg
tar --format=ustar -c .PKGINFO .post-install $(find usr -type f 2>/dev/null) $(find usr -type l 2>/dev/null) 2>/dev/null | gzip -9 > /work/marathon-shell-1.0.0-r124.apk
ls -la /work/*.apk
