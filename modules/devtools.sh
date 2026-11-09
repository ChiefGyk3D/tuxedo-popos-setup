#!/usr/bin/env bash
# Module: developer tools. Sourced by install.sh, never run.
# shellcheck shell=bash
#
# Not touched: Node. It is managed by nvm.
#
# How each tool is installed, and what vouches for it (fetched 2026-11-09):
#   apt list      build-essential cmake pkg-config git python3-venv pipx
#                 (APT_PACKAGES in the config), from Pop's own repos.
#   uv            Release tarball from github.com/astral-sh/uv, version and
#                 sha256 pinned below (the hash matches the .sha256 file
#                 published beside the release). Not the curl-pipe installer.
#   rustup        rustup-init from static.rust-lang.org, checked against the
#                 .sha256 file served beside it. Documented method:
#                 https://rust-lang.github.io/rustup/installation/other.html
#   Go            Official tarball from go.dev. The sha256 is read at run time
#                 from https://go.dev/dl/?mode=json (the vendor's own listing)
#                 for the pinned version. Extracted into /usr/local/go as
#                 https://go.dev/doc/install describes.
#   OpenTofu      Official signed apt repo, per
#                 https://opentofu.org/docs/intro/install/deb/ . Two keys, one
#                 merged keyring. That page lists no fingerprints, so the two
#                 below were read from the downloaded keys: UNVERIFIED
#                 against vendor docs.
#   GitHub CLI    Official apt repo at cli.github.com, per
#                 https://github.com/cli/cli/blob/trunk/docs/install_linux.md
#                 That page lists the signing fingerprints and the sha256 of
#                 the keyring file; both are checked here. Never Pop's own gh
#                 package (too old); a pin keeps cli.github.com's gh winning.
#   VS Code       Microsoft's signed apt repo (not Flatpak), per
#                 https://code.visualstudio.com/docs/setup/linux . The page
#                 gives the key URL and the source file but no fingerprint,
#                 so the fingerprint below was read from the downloaded key:
#                 UNVERIFIED against vendor docs.
#   Podman        Pop/Ubuntu packages: rootless, with the podman-docker shim
#                 (a docker command that runs podman). No docker group. The
#                 rootless prerequisites (uidmap, subuid/subgid ranges) are
#                 UNVERIFIED against the Podman docs.

UV_VERSION_DEFAULT=0.13.7
UV_SHA256_DEFAULT=c5221ff41b7892bfc223543883600125f6a47fe845093e0f5bdff4f359196d83
GO_VERSION_DEFAULT=1.27.3

GH_MIN_VERSION=2.57.0
GH_KEY_URL=https://cli.github.com/packages/githubcli-archive-keyring.gpg
GH_KEY_SHA256=6084d5d7bd8e288441e0e94fc6275570895da18e6751f70f057485dc2d1a811b
GH_KEY_FPR=2C6106201985B60E6C7AC87323F3D4EA75716059
GH_KEYRING=/etc/apt/keyrings/githubcli-archive-keyring.gpg

TOFU_KEY1_URL=https://get.opentofu.org/opentofu.gpg
TOFU_KEY1_FPR=E3E6E43D84CB852EADB0051D0C0AF313E5FD9F80
TOFU_KEY2_URL=https://packages.opentofu.org/opentofu/tofu/gpgkey
TOFU_KEY2_FPR=F4AF70F66EAC4337EEECC97407D3DFCD4C61499F
TOFU_KEYRING=/etc/apt/keyrings/opentofu.gpg

VSCODE_KEY_URL=https://packages.microsoft.com/keys/microsoft.asc
VSCODE_KEY_FPR=BC528686B50D79E339D3721CEB3E94ADBE1229CF
VSCODE_KEYRING=/usr/share/keyrings/microsoft.gpg

PODMAN_PACKAGES=(podman podman-docker uidmap slirp4netns)

dev_uv_bin() { printf '%s/.local/bin/uv' "$TARGET_HOME"; }
dev_rustup_bin() { printf '%s/.cargo/bin/rustup' "$TARGET_HOME"; }

dev_flag() { [ "${!1}" = 1 ]; }

user_in_group() {
    local groups
    groups=$(id -nG "$1")
    [[ " $groups " == *" $2 "* ]]
}

# --- check ------------------------------------------------------------------

mod_devtools_check() {
    check_pkgs "${APT_PACKAGES[@]}"
    if dev_flag DEVTOOLS_UV; then
        if [ -x "$(dev_uv_bin)" ]; then
            report ok "uv ($(as_user "$(dev_uv_bin)" --version))"
        else
            report missing "uv in $TARGET_HOME/.local/bin"
        fi
    fi
    if dev_flag DEVTOOLS_RUSTUP; then
        if [ -x "$(dev_rustup_bin)" ]; then
            report ok "rustup"
        else
            report missing "rustup in $TARGET_HOME/.cargo/bin"
        fi
    fi
    if dev_flag DEVTOOLS_GO; then
        if [ -x /usr/local/go/bin/go ]; then
            report ok "Go ($(/usr/local/go/bin/go version | cut -d' ' -f3))"
        else
            report missing "Go in /usr/local/go"
        fi
    fi
    if dev_flag DEVTOOLS_TOFU; then
        if pkg_installed tofu && [ -f /etc/apt/sources.list.d/opentofu.sources ]; then
            report ok "OpenTofu from its apt repo"
        else
            report missing "OpenTofu (package tofu and its apt source)"
        fi
    fi
    if dev_flag DEVTOOLS_GH; then
        dev_check_gh
    fi
    if dev_flag DEVTOOLS_VSCODE; then
        if pkg_installed code && [ -f /etc/apt/sources.list.d/vscode.sources ]; then
            report ok "VS Code from Microsoft's apt repo"
        else
            report missing "VS Code (package code and its apt source)"
        fi
    fi
    if dev_flag DEVTOOLS_PODMAN; then
        dev_check_podman
    fi
}

dev_check_gh() {
    local have
    if ! pkg_installed gh; then
        report missing "GitHub CLI (package gh from cli.github.com)"
        return 0
    fi
    have=$(dpkg-query -W -f='${Version}' gh)
    if [ -f /etc/apt/sources.list.d/github-cli.sources ] && ver_ge "$have" "$GH_MIN_VERSION"; then
        report ok "GitHub CLI $have from cli.github.com"
    else
        report missing "GitHub CLI >= $GH_MIN_VERSION from cli.github.com (have $have)"
    fi
}

dev_check_podman() {
    check_pkgs "${PODMAN_PACKAGES[@]}"
    if grep -q "^$TARGET_USER:" /etc/subuid 2>/dev/null && grep -q "^$TARGET_USER:" /etc/subgid 2>/dev/null; then
        report ok "subuid and subgid ranges for $TARGET_USER"
    else
        report missing "subuid and subgid ranges for $TARGET_USER (rootless podman)"
    fi
    if user_in_group "$TARGET_USER" docker; then
        report missing "$TARGET_USER is in the docker group (not wanted; remove with: sudo gpasswd -d $TARGET_USER docker)"
    else
        report ok "$TARGET_USER is not in the docker group"
    fi
}

# --- apply ------------------------------------------------------------------

mod_devtools_apply() {
    if step "apt packages: ${APT_PACKAGES[*]}"; then
        apt_install_missing "${APT_PACKAGES[@]}"
    fi
    if dev_flag DEVTOOLS_UV; then
        dev_apply_uv
    fi
    if dev_flag DEVTOOLS_RUSTUP; then
        dev_apply_rustup
    fi
    if dev_flag DEVTOOLS_GO; then
        dev_apply_go
    fi
    if dev_flag DEVTOOLS_TOFU; then
        dev_apply_tofu
    fi
    if dev_flag DEVTOOLS_GH; then
        dev_apply_gh
    fi
    if dev_flag DEVTOOLS_VSCODE; then
        dev_apply_vscode
    fi
    if dev_flag DEVTOOLS_PODMAN; then
        dev_apply_podman
    fi
}

dev_apply_uv() {
    local ver=${UV_VERSION:-$UV_VERSION_DEFAULT} sha=${UV_SHA256:-$UV_SHA256_DEFAULT}
    local name=uv-x86_64-unknown-linux-gnu tarball
    if ! step "install uv $ver into $TARGET_HOME/.local/bin"; then
        return 0
    fi
    check_arch_x86_64
    if [ -x "$(dev_uv_bin)" ] && [ "$(as_user "$(dev_uv_bin)" --version | cut -d' ' -f2)" = "$ver" ]; then
        info "uv $ver already installed"
        return 0
    fi
    tarball=$WORKDIR/$name.tar.gz
    fetch "https://github.com/astral-sh/uv/releases/download/$ver/$name.tar.gz" "$tarball"
    sha256_ok "$tarball" "$sha" || die "uv checksum mismatch, stopping"
    mkdir "$WORKDIR/uv"
    tar -xzf "$tarball" -C "$WORKDIR/uv" --strip-components=1
    as_user mkdir -p "$TARGET_HOME/.local/bin"
    install -o "$TARGET_USER" -m 0755 "$WORKDIR/uv/uv" "$WORKDIR/uv/uvx" "$TARGET_HOME/.local/bin/"
}

dev_apply_rustup() {
    local base=https://static.rust-lang.org/rustup/dist/x86_64-unknown-linux-gnu want
    if ! step "install rustup for $TARGET_USER"; then
        return 0
    fi
    check_arch_x86_64
    if [ -x "$(dev_rustup_bin)" ]; then
        info "rustup already installed"
        return 0
    fi
    fetch "$base/rustup-init" "$WORKDIR/rustup-init"
    fetch "$base/rustup-init.sha256" "$WORKDIR/rustup-init.sha256"
    want=$(cut -d' ' -f1 "$WORKDIR/rustup-init.sha256")
    sha256_ok "$WORKDIR/rustup-init" "$want" || die "rustup-init checksum mismatch, stopping"
    chmod 0755 "$WORKDIR/rustup-init"
    chmod 0711 "$WORKDIR" # the user may run the file, not list the directory
    # The user's shell profile gets the cargo bin directory, the rustup default.
    as_user "$WORKDIR/rustup-init" -y --profile default
}

dev_apply_go() {
    local ver=${GO_VERSION:-$GO_VERSION_DEFAULT} file want new
    if ! step "install Go $ver into /usr/local/go"; then
        return 0
    fi
    check_arch_x86_64
    if [ -x /usr/local/go/bin/go ] && [ "$(/usr/local/go/bin/go version | cut -d' ' -f3)" = "go$ver" ]; then
        info "Go $ver already installed"
        return 0
    fi
    file=go$ver.linux-amd64.tar.gz
    fetch 'https://go.dev/dl/?mode=json&include=all' "$WORKDIR/go.json"
    want=$(python3 -I -c '
import json, sys
name = sys.argv[2]
for rel in json.load(open(sys.argv[1])):
    for f in rel["files"]:
        if f["filename"] == name:
            print(f["sha256"])
            raise SystemExit(0)
raise SystemExit("no such file in the Go listing: " + name)
' "$WORKDIR/go.json" "$file")
    fetch "https://go.dev/dl/$file" "$WORKDIR/$file"
    sha256_ok "$WORKDIR/$file" "$want" || die "Go checksum mismatch, stopping"
    new=$(mktemp -d /usr/local/.go-new.XXXXXX)
    tar -C "$new" -xzf "$WORKDIR/$file"
    rm -rf /usr/local/go
    mv "$new/go" /usr/local/go
    rmdir "$new"
    printf '%s\n' '# Managed by tuxedo-popos-setup.' 'export PATH="$PATH:/usr/local/go/bin"' |
        write_if_changed /etc/profile.d/golang.sh 0644
}

dev_apply_tofu() {
    local k1 k2
    if ! step "add the OpenTofu apt repo and install tofu"; then
        return 0
    fi
    k1=$WORKDIR/tofu1.gpg
    k2=$WORKDIR/tofu2.gpg
    keyring_prepare "$k1" "$TOFU_KEY1_URL" "$TOFU_KEY1_FPR"
    keyring_prepare "$k2" "$TOFU_KEY2_URL" "$TOFU_KEY2_FPR"
    cat "$k1" "$k2" >"$WORKDIR/opentofu.gpg"
    install -D -m 0644 "$WORKDIR/opentofu.gpg" "$TOFU_KEYRING"
    write_if_changed /etc/apt/sources.list.d/opentofu.sources 0644 <<EOF
# Managed by tuxedo-popos-setup.
Types: deb
URIs: https://packages.opentofu.org/opentofu/tofu/any/
Suites: any
Components: main
Signed-By: $TOFU_KEYRING
EOF
    apt_refresh
    apt_install_missing tofu
}

dev_apply_gh() {
    local k have
    if ! step "add the GitHub CLI apt repo and install gh (>= $GH_MIN_VERSION)"; then
        return 0
    fi
    k=$WORKDIR/gh.gpg
    keyring_prepare "$k" "$GH_KEY_URL" "$GH_KEY_FPR" "$GH_KEY_SHA256"
    install -D -m 0644 "$k" "$GH_KEYRING"
    write_if_changed /etc/apt/sources.list.d/github-cli.sources 0644 <<EOF
# Managed by tuxedo-popos-setup.
Types: deb
URIs: https://cli.github.com/packages
Suites: stable
Components: main
Signed-By: $GH_KEYRING
EOF
    # Pop's own repos carry an old gh; make sure cli.github.com's build wins.
    write_if_changed /etc/apt/preferences.d/github-cli 0644 <<'EOF'
# Managed by tuxedo-popos-setup.
Package: gh
Pin: origin cli.github.com
Pin-Priority: 1001
EOF
    apt_refresh
    # Not apt_install_missing: an older Pop gh may already be installed, and
    # this upgrades it to the cli.github.com build.
    DEBIAN_FRONTEND=noninteractive apt-get install -y --no-install-recommends gh
    have=$(dpkg-query -W -f='${Version}' gh)
    ver_ge "$have" "$GH_MIN_VERSION" || die "gh $have is older than $GH_MIN_VERSION; check 'apt-cache policy gh'"
}

dev_apply_vscode() {
    local k
    if ! step "add Microsoft's apt repo and install code"; then
        return 0
    fi
    k=$WORKDIR/microsoft.gpg
    keyring_prepare "$k" "$VSCODE_KEY_URL" "$VSCODE_KEY_FPR"
    install -D -m 0644 "$k" "$VSCODE_KEYRING"
    # File name and content follow the VS Code docs, so the package's own
    # post-install step finds the repo already configured and adds nothing.
    write_if_changed /etc/apt/sources.list.d/vscode.sources 0644 <<EOF
Types: deb
URIs: https://packages.microsoft.com/repos/code
Suites: stable
Components: main
Architectures: amd64,arm64,armhf
Signed-By: $VSCODE_KEYRING
EOF
    apt_refresh
    apt_install_missing code
}

dev_apply_podman() {
    if ! step "install rootless podman with the podman-docker shim (no docker group)"; then
        return 0
    fi
    apt_install_missing "${PODMAN_PACKAGES[@]}"
    if ! grep -q "^$TARGET_USER:" /etc/subuid 2>/dev/null || ! grep -q "^$TARGET_USER:" /etc/subgid 2>/dev/null; then
        usermod --add-subuids 100000-165535 --add-subgids 100000-165535 "$TARGET_USER"
    fi
    # Silences the "Emulate Docker CLI using podman" notice on every call.
    touch /etc/containers/nodocker
    if user_in_group "$TARGET_USER" docker; then
        warn "$TARGET_USER is in the docker group; this installer never adds it and does not remove it"
    fi
}
