# Ubuntu 26.04.1 Desktop — autoinstall seed (MedEvent desktops)

Unattended Ubuntu **26.04.1 Desktop** installer configuration. The desktops boot the
standard Ubuntu ISO and pull `user-data` + `meta-data` from this repo over the network
(cloud-init `nocloud-net` datasource), so nothing needs to be baked into the USB stick.

## Use on a desktop

1. Boot the standard `ubuntu-26.04.1-desktop-amd64.iso` USB.
2. At the GRUB menu highlight **Try or Install Ubuntu** and press **`e`**.
3. On the line starting with `linux`, before the trailing `---`, append:

   ```
   autoinstall "ds=nocloud-net;s=https://raw.githubusercontent.com/ericitguys/ubuntu-autoinstall/main/"
   ```

   So the line reads e.g.:

   ```
   linux /casper/vmlinuz maybe-ubiquity quiet splash autoinstall "ds=nocloud-net;s=https://raw.githubusercontent.com/ericitguys/ubuntu-autoinstall/main/" ---
   ```

   (the quotes matter — without them some GRUB versions truncate the value at `;`)
4. Press **F10** to boot. The installer runs unattended; the machine **powers off** when
   done — remove the USB stick, then power on.

The installer needs network (DHCP) to reach GitHub and dl.google.com.

## If the installer asks for an autoinstall URL on screen (GUI)

The desktop installer's automated-installation screen wants the URL of the
**file**, not the folder:

```
https://raw.githubusercontent.com/ericitguys/ubuntu-autoinstall/main/user-data
```

Pasting the **folder** URL (`.../main/`) into a field that fetches the literal
URL returns GitHub's `404: Not Found`, which the installer reports as
`Malformed autoinstall in 'version or interactive-sections' section`. The folder
URL is only for the kernel-cmdline method above, where cloud-init appends
`user-data` / `meta-data` itself. The file URL works in both places.

## What it configures

- **Storage:** erases the entire (largest) disk — `storage.layout.name: direct`
- **Locale / keyboard:** `en_US.UTF-8` / `us` (edit `user-data` if the site needs otherwise)
- **Hostname:** `ubuntu` (edit `identity.hostname` if wanted)
- **User:** `local_user` — password stored as a salted SHA-512 crypt hash
  (regenerate with `openssl passwd -6 'newpass'` and paste into `identity.password`)
- **Google Chrome stable** installed from the official `.deb` (auto-registers Chrome's
  apt repo for future updates)
- **Chrome as default browser:** `x-www-browser` + `gnome-www-browser` alternatives,
  GNOME defaults (`.config/mimeapps.list` → `google-chrome.desktop`), and
  `BROWSER` set in `/etc/environment` — so Chrome launches without its
  "make default browser" prompt
- **Desktop shortcut "MedEvent Login"** → `https://emile.medeventsolutions.com/auth/login`
  (`~/Desktop/medevent-login.desktop`, made executable and pre-trusted via
  `metadata::trusted` so GNOME doesn't show the untrusted-launcher prompt)
- **Dock pinned to Chrome only** (dconf system default:
  `org.gnome.shell favorite-apps = ['google-chrome.desktop']` — the app grid
  keeps all apps, only the dock pins change)

## Build a zero-keystroke autoinstall USB (optional)

```
./build-autoinstall-iso.sh
```

Produces `ubuntu-26.04.1-desktop-autoinstall-amd64.iso`: stock desktop ISO plus
the seed at `/cdrom/autoinstall` (user-data, meta-data and the bundled Chrome
deb) and a first GRUB entry — **"Ubuntu 26.04.1 Desktop - AUTOINSTALL (MedEvent)"**
— that boots straight into the unattended install (10 s timeout; the original
manual-install entries stay below it). No URL typing, no GitHub reachability at
install time; Chrome is read from the ISO itself with dl.google.com as fallback.
Flash it with balenaEtcher/Rufus, or:

```
dd if=ubuntu-26.04.1-desktop-autoinstall-amd64.iso of=/dev/sdX bs=4M conv=fsync status=progress
```

Requires `xorriso` — plain `sudo apt-get install xorriso`, or without root the
script picks up a deb-unpacked copy placed in `tools/xorriso/` (see the script's
xorriso detection block).

## Notes

- Repo is **public** so the desktops can fetch the seed without credentials. Only a
  salted hash of the password is stored, but a short numeric password is brute-forceable —
  rotate if that ever matters.
- No internet from the deskops' network at install time? Serve the two files locally:
  `cd` to this directory on any machine and run `python3 -m http.server 8000`, then use
  `autoinstall "ds=nocloud-net;s=http://<ip-reachable-from-desktop>:8000/"` in step 3.
- Files: `user-data` (cloud-config with the `autoinstall` block), `meta-data`
  (cloud-init nocloud requires it to exist).