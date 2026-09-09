# Duranium overlay extras

Files the duranium tree needs that are not carried by a patch in
`../pipeline-patches/`, because they are binary-ish or standalone rather
than a diff against an upstream file.

- `mkosi.images/base/mkosi.skeleton/etc/apk/keys/marathon-snapshot@local-1.rsa.pub`
  The public half of the key Marathon's own apks are signed with. Patch 0018
  sets `RepositoryKeyCheck=no` so the build sandbox stops checking each
  package; this key is what keeps on-device trust intact, because mkosi bakes
  the skeleton into the rootfs. Without it that patch weakens trust instead of
  relocating it.

- `marathon-extras/repack-r123.sh`
  Ad-hoc helper that re-signs and repacks an r123 apk with a throwaway abuild
  key. Named in 0008's commit message as a per-build helper but never actually
  committed, so it only ever existed in one scratch checkout.

Copy into the duranium tree alongside the patches when bootstrapping by hand.
