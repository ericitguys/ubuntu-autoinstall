#!/usr/bin/env bash
# Build the Ubuntu 26.04.1 Desktop autoinstall ISO:
#   stock ISO + autoinstall seed at /cdrom/autoinstall (user-data, meta-data,
#   bundled Chrome deb) + a first GRUB entry that boots straight into
#   autoinstall. The original "manual install" entries are kept below it.
#
# Root privileges NOT required if xorriso is system-installed or unpacked in
# ./tools/xorriso (see README).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"
BUILD="$ROOT/build"
ISO="$BUILD/ubuntu-26.04.1-desktop-amd64.iso"
SHA_URL="https://releases.ubuntu.com/26.04/SHA256SUMS"
ISO_URL="https://releases.ubuntu.com/26.04/ubuntu-26.04.1-desktop-amd64.iso"
CHROME_URL="https://dl.google.com/linux/direct/google-chrome-stable_current_amd64.deb"
WORK="$BUILD/cd"
OUT="$ROOT/ubuntu-26.04.1-desktop-autoinstall-amd64.iso"
SEED_URL="https://raw.githubusercontent.com/ericitguys/ubuntu-autoinstall/main"

# --- xorriso (system, or the unpacked tools/xorriso prefix) ---
if command -v xorriso >/dev/null 2>&1; then
  XR="$(command -v xorriso)"
elif [ -x "$ROOT/tools/xorriso/usr/bin/xorriso" ]; then
  export LD_LIBRARY_PATH="$ROOT/tools/xorriso/usr/lib/x86_64-linux-gnu${LD_LIBRARY_PATH:+:$LD_LIBRARY_PATH}"
  XR="$ROOT/tools/xorriso/usr/bin/xorriso"
else
  echo "ERROR: xorriso not found (apt-get install xorriso, or unpack it into tools/xorriso)" >&2
  exit 1
fi
"$XR" --version | head -1

# --- fetch + verify the stock ISO ---
mkdir -p "$BUILD"
if [ ! -f "$ISO" ]; then
  curl -fL --retry 3 -C - -o "$ISO" "$ISO_URL"
fi
curl -fsS -o "$BUILD/SHA256SUMS" "$SHA_URL"
(cd "$BUILD" && grep -E " [ *]$(basename "$ISO")$" SHA256SUMS | sha256sum -c -)

# --- bundled Chrome deb (used by the ISO seed; user-data falls back to network) ---
mkdir -p "$ROOT/assets"
[ -f "$ROOT/assets/google-chrome-stable_current_amd64.deb" ] || \
  curl -fL --retry 3 -C - -o "$ROOT/assets/google-chrome-stable_current_amd64.deb" "$CHROME_URL"

# --- extract the ISO ---
[ -d "$WORK" ] && { chmod -R u+rwX "$WORK" 2>/dev/null || true; rm -rf "$WORK"; }
mkdir -p "$WORK"
"$XR" -osirrox on -indev "$ISO" -extract / "$WORK" >/dev/null 2>&1
chmod -R u+rwX "$WORK"

# --- seed ---
mkdir -p "$WORK/autoinstall/debs"
cp "$ROOT/user-data" "$ROOT/meta-data" "$WORK/autoinstall/"
cp "$ROOT/assets/google-chrome-stable_current_amd64.deb" "$WORK/autoinstall/debs/"

# --- patch boot config: AUTOINSTALL as the first/default entry ---
python3 - "$WORK" <<'PY'
import os, re, sys
work = sys.argv[1]

cfgp = os.path.join(work, 'boot/grub/grub.cfg')
cfg = open(cfgp).read()
cands = re.findall(r'^\s*linux\s+(/\S+)\s+(.*?)\s*$', cfg, re.M)
kpath, kargs = next(c for c in cands if 'vmlinuz' in c[0])
kargs = re.sub(r'\s*---.*$', '', kargs).strip()
ipath = re.search(r'^\s*initrd\s+(/\S+)\s*$', cfg, re.M).group(1)

entry = (
    'menuentry "Ubuntu 26.04.1 Desktop - AUTOINSTALL (MedEvent)" {\n'
    '\tset gfxpayload=keep\n'
    f'\tlinux\t{kpath} {kargs} autoinstall "ds=nocloud;s=/cdrom/autoinstall/" ---\n'
    f'\tinitrd\t{ipath}\n'
    '}\n'
)
cfg, n = re.subn(r'^(\s*)set default=.*$', r'\1set default=0', cfg, count=1, flags=re.M)
if n == 0:
    entry = 'set default=0\n' + entry
cfg, n = re.subn(r'^(\s*)set timeout=.*$', r'\1set timeout=10', cfg, count=1, flags=re.M)
if n == 0:
    entry = 'set timeout=10\n' + entry
i = cfg.find('menuentry ')
assert i >= 0, 'no menuentry found'
open(cfgp, 'w').write(cfg[:i] + entry + '\n' + cfg[i:])
print('grub.cfg: AUTOINSTALL entry inserted (default, timeout=10)')

txt = os.path.join(work, 'isolinux/txt.cfg')
isocfg = os.path.join(work, 'isolinux/isolinux.cfg')
if os.path.exists(txt):
    t = open(txt).read()
    m = re.search(r'^\s*append\s+(initrd=\S+)\s+(.*?)\s*$', t, re.M)
    assert m, 'no isolinux append line'
    args = re.sub(r'\s*---.*$', '', m.group(2)).strip()
    t += ('\nlabel autoinstall\n'
          '  menu label ^AUTOINSTALL Ubuntu 26.04.1 (MedEvent)\n'
          '  kernel /casper/vmlinuz\n'
          f'  append {m.group(1)} {args} autoinstall ds=nocloud;s=/cdrom/autoinstall/ ---\n')
    open(txt, 'w').write(t)
    if os.path.exists(isocfg):
        c = open(isocfg).read()
        c = re.sub(r'^default\s+.*$', 'default autoinstall', c, count=1, flags=re.M)
        c = re.sub(r'^(TIMEOUT|timeout)\s+.*$', 'TIMEOUT 100', c, count=1, flags=re.M)
        open(isocfg, 'w').write(c)
    print('isolinux: AUTOINSTALL label added (BIOS boot path)')
PY

# --- rebuild ---
OPTS="$("$XR" -indev "$ISO" -report_el_torito as_mkisofs | tail -n +2)"
JOINED="$(printf '%s\n' "$OPTS" | tr '\n' ' ')"
echo "xorriso opts: $JOINED"
eval "$XR -as mkisofs $JOINED -o \"$OUT\" \"$WORK\""

# --- verify ---
rm -rf /tmp/seedcheck /tmp/grubcheck
"$XR" -osirrox on -indev "$OUT" -extract /autoinstall /tmp/seedcheck >/dev/null 2>&1
diff -r "$WORK/autoinstall" /tmp/seedcheck && echo "seed-identical: OK"
"$XR" -osirrox on -indev "$OUT" -extract /boot/grub/grub.cfg /tmp/grubcheck >/dev/null 2>&1
grep -q 'AUTOINSTALL (MedEvent)' /tmp/grubcheck/grub.cfg 2>/dev/null || grep -q 'AUTOINSTALL (MedEvent)' /tmp/grubcheck
echo "grub-entry-check: OK"

rm -rf "$WORK" /tmp/seedcheck /tmp/grubcheck
echo
ls -l "$OUT"
sha256sum "$OUT"
echo "DONE: $OUT"