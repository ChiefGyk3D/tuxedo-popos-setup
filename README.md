# tuxedo-popos-setup

A configurable, idempotent workstation installer for a TUXEDO Stellaris Slim
16 AMD laptop running Pop!_OS 24.04. Private repository, first version.

License: pending owner (no LICENSE file yet).

## Supported

- Pop!_OS 24.04, x86_64. Apply mode refuses any other system. `--check` and
  `--dry-run` only warn on other systems, so the tests can run anywhere.
- TUXEDO hardware for the `tuxedo` module. On other hardware it warns.

## Run

```bash
sudo ./install.sh              # apply every enabled module, stop at the first error
./install.sh --check           # read-only, no root: report what is missing, exit 1 if anything is
./install.sh --dry-run         # print the steps apply would take, change nothing
./install.sh --config FILE     # use FILE instead of config/setup.conf
```

Running it twice is safe: each step checks first and skips what is already
done. Logs go to `~/.local/state/tuxedo-popos-setup/` of the user who ran
`sudo`.

## Config

Copy `config/setup.conf.example` to `config/setup.conf` (gitignored) and edit.
With no config file the defaults in the example apply, except that the
touchpad module is off.

The file is sourced as shell, so `install.sh` refuses one that is group or
world writable, or owned by anyone but root or the invoking user.

| Setting | Default | Meaning |
| --- | --- | --- |
| `ENABLE_TUXEDO` | 1 | TUXEDO repo, drivers, Control Center |
| `ENABLE_DEVTOOLS` | 1 | Developer tools |
| `ENABLE_FLATPAKS` | 1 | Flathub and the listed apps |
| `ENABLE_TOUCHPAD_FIX` | 0 | Touchpad diagnostics (there is no fix yet) |
| `DEVTOOLS_UV`, `_RUSTUP`, `_GO`, `_TOFU`, `_GH`, `_VSCODE`, `_PODMAN` | 1 | One switch per devtools entry |
| `UV_VERSION` and `UV_SHA256`, `GO_VERSION` | pinned in the module | Override together (uv) |
| `APT_PACKAGES` | build-essential cmake pkg-config git python3-venv pipx | Plain apt packages |
| `FLATPAK_APPS` | com.discordapp.Discord one.ablaze.floorp | Flathub app ids |

## Modules

Run in this order.

1. **tuxedo**: adds TUXEDO's signed apt repo, scoped to itself, and installs
   `tuxedo-drivers` and `tuxedo-control-center`. The repo is pinned at
   priority 100 (it can add packages, never replace Pop's), and kernel,
   firmware, GPU stack and Tomte packages from it are blocked. The keyring
   package is checked against a pinned sha256 and its key against a
   fingerprint before anything is trusted, and a simulated install must
   remove nothing. **Tomte is deliberately not installed**: it treats Pop!_OS
   as Ubuntu and cannot exclude modules.
2. **devtools**: `APT_PACKAGES`; uv (pinned release tarball, sha256 checked);
   rustup (`rustup-init` checked against the sha256 served beside it); Go
   (official tarball into `/usr/local/go`, sha256 read from go.dev); OpenTofu,
   GitHub CLI and VS Code from their own signed apt repos, keys checked by
   fingerprint; rootless Podman with the `podman-docker` shim and no docker
   group. GitHub CLI must be 2.57 or newer and comes from cli.github.com,
   never Pop's own package. VS Code is the Microsoft package, not Flatpak.
   Node is left to nvm.
3. **flatpaks**: the Flathub remote and the apps in `FLATPAK_APPS`,
   system-wide.
4. **touchpad**: diagnostics only. Installs `libinput-tools` and checks the
   tools are present. It changes no driver and installs no fix.

## Touchpad

`tools/touchpad/` holds diagnostics for a touchpad click that was lost. The
HID report shows the click and `hid-multitouch` should emit `BTN_LEFT`, but
no `BTN_LEFT` reached the input node until the driver was rebound. The cause
is unproven. There is no boot-time fix in this version: it waits on a reboot
test. Read `tools/touchpad/README.md` before running anything there.

## Tests

```bash
bash tests/run.sh
```

No root needed and nothing on the machine is changed. It checks syntax of
every script, runs `install.sh --check` and `--dry-run` against a scratch log
directory, and guards the style rules (no em dashes, no hard-coded home paths
or device ids, workflow actions pinned by commit). Each guard has a negative
case that proves it bites.

CI calls the reusable workflows in
[git-your-ship-together](https://github.com/ChiefGyk3D/git-your-ship-together)
(shell lint and tests, security scans) and gates on `ci / CI green`.

## Verified and unverified

Verified (2026-11-09):

- Every script parses (`bash -n`; Python via `ast.parse`) and `tests/run.sh`
  passes without root.
- `./install.sh --check` and `--dry-run` ran without root on the TUXEDO
  laptop this was written for, and reported sensible results.
- Touchpad discovery (`common.sh`, `allkeys.py`) found the pad and its input
  nodes on that laptop without any hard-coded id.
- Vendor facts fetched from the vendor on that date: the GitHub CLI key
  fingerprint and keyring sha256 (its install doc lists both), the Flathub
  remote URL (flathub.org/setup), the Microsoft key and source file (VS Code
  docs), the OpenTofu repo and key URLs (OpenTofu docs), the Go install
  layout (go.dev/doc/install) and the rustup-init URL (rustup docs). The
  pinned uv sha256 matches both the `.sha256` file published with the release
  and a download hashed on that date. The rustup and Go checksums are read
  from the vendor at run time and were not exercised.

UNVERIFIED (not run, not confirmed, or not documented by the vendor):

- **Apply mode has never been run.** No root was available while writing this.
  Every `sudo ./install.sh` path, all apt, dpkg, flatpak and user-install
  steps, and the rootless Podman setup are untested end to end.
- **Fingerprints with no vendor docs page behind them:** the TUXEDO key, both
  OpenTofu keys and the VS Code (Microsoft) key. They were read from keys
  downloaded over HTTPS on 2026-11-09. TUXEDO's help page that should document
  the repo is JavaScript-gated and could not be fetched, so its repo URL and
  keyring package hash come from the vendor's own package index, not a docs
  page.
- The apt pin that keeps cli.github.com's `gh` winning over Pop's (priority
  1001) was not exercised against Pop's real apt preferences.
- That the VS Code package leaves the source file alone when it matches the
  docs; the rootless Podman prerequisites (`uidmap`, `slirp4netns`, subuid
  ranges) were taken from general knowledge, not the Podman docs.
- `shellcheck` and `shfmt` were not run locally (the tools could not be
  fetched and run here). The scripts follow `shfmt -i 4 -ci` by hand; CI is
  the judge.
- The sudo-only touchpad tools (`touchpad-diag.sh`, `click-hid.py`,
  `allkeys.py` capture, `trace-click.sh`, `driver-swap-test.sh`) were checked
  for syntax, option handling and device discovery only. None was run as root.
- The CI workflow has not run yet.
