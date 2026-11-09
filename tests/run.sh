#!/usr/bin/env bash
# Tests that need no root and change nothing on the machine:
#   bash tests/run.sh
# Guards collect loosely (every script found) and assert strictly (counts,
# exact patterns); each guard has a negative case proving it bites.
set -u

ROOT=$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)
SCRATCH=$(mktemp -d)
trap 'rm -rf "$SCRATCH"' EXIT

PASS=0
FAIL=0
pass() {
    PASS=$((PASS + 1))
    printf 'ok   %s\n' "$1"
}
fail() {
    FAIL=$((FAIL + 1))
    printf 'FAIL %s\n' "$1"
}
# verdict NAME RESULT: RESULT is 0 for a pass.
verdict() {
    if [ "$2" = 0 ]; then
        pass "$1"
    else
        fail "$1"
    fi
}
# expect NAME CMD...: passes when CMD succeeds.
expect() {
    local name=$1
    shift
    "$@" >/dev/null 2>&1
    verdict "$name" $?
}
# expect_not NAME CMD...: passes when CMD fails (the negative case).
expect_not() {
    local name=$1
    shift
    if "$@" >/dev/null 2>&1; then
        fail "$name"
    else
        pass "$name"
    fi
}
# expect_status NAME WANT CMD...: passes when CMD exits with status WANT.
expect_status() {
    local name=$1 want=$2 rc
    shift 2
    "$@" >/dev/null 2>&1
    rc=$?
    if [ "$rc" = "$want" ]; then
        pass "$name"
    else
        fail "$name (exit $rc, wanted $want)"
    fi
}
# contains NAME TEXT PATTERN: passes when TEXT has a line matching PATTERN.
contains() {
    grep -q -E "$3" <<<"$2"
    verdict "$1" $?
}

# --- guards -----------------------------------------------------------------

# All files that are scripts, by suffix, outside .git.
collect_scripts() {
    find "$ROOT" -path "$ROOT/.git" -prune -o -type f \( -name '*.sh' -o -name '*.py' \) -print | sort
}

syntax_ok() {
    case $1 in
        *.py)
            python3 -I -c 'import ast, sys; ast.parse(open(sys.argv[1]).read())' "$1"
            ;;
        *)
            bash -n "$1"
            ;;
    esac
}

# Files the style rules apply to: everything outside .git and tests/.
scannable() {
    find "$ROOT" -path "$ROOT/.git" -prune -o -path "$ROOT/tests" -prune -o -type f -print
}

EM_DASH=$(printf '\342\200\224')

has_em_dash() {
    grep -q -F -e "$EM_DASH" "$1"
}

has_home_path() {
    grep -q -E '/home/[a-z]' "$1"
}

has_device_id() {
    grep -q -E 'UNIW0001|0018:[0-9A-Fa-f]{4}:[0-9A-Fa-f]{4}\.[0-9]{4}|/dev/hidraw[0-9]|/dev/input/event[0-9]' "$1"
}

# True when a workflow has a uses: line that is not a 40-hex SHA plus "# vN".
has_unpinned_uses() {
    grep -E '^[[:space:]]*(-[[:space:]]+)?uses:' "$1" | grep -v -q -E '@[0-9a-f]{40}[[:space:]]+#[[:space:]]*v[0-9]'
}

# --- structure and syntax ----------------------------------------------------

REQUIRED="install.sh lib/common.sh modules/tuxedo.sh modules/devtools.sh modules/flatpaks.sh modules/touchpad.sh
tools/touchpad/common.sh tools/touchpad/touchpad-diag.sh tools/touchpad/click-hid.py tools/touchpad/allkeys.py
tools/touchpad/trace-click.sh tools/touchpad/driver-swap-test.sh tools/touchpad/README.md
config/setup.conf.example .gitignore .github/workflows/ci.yml"
for f in $REQUIRED; do
    expect "exists: $f" test -f "$ROOT/$f"
done

mapfile -t SCRIPTS < <(collect_scripts)
if [ "${#SCRIPTS[@]}" -ge 12 ]; then
    pass "collected ${#SCRIPTS[@]} scripts (>= 12)"
else
    fail "collected only ${#SCRIPTS[@]} scripts"
fi
for f in "${SCRIPTS[@]}"; do
    expect "syntax: ${f#"$ROOT"/}" syntax_ok "$f"
done

printf 'if then\n' >"$SCRATCH/broken.sh"
printf 'def f(:\n' >"$SCRATCH/broken.py"
expect_not "negative: syntax guard rejects a broken .sh" syntax_ok "$SCRATCH/broken.sh"
expect_not "negative: syntax guard rejects a broken .py" syntax_ok "$SCRATCH/broken.py"

# --- style rules -------------------------------------------------------------

mapfile -t TEXTFILES < <(scannable)
em=0
home=0
dev=0
for f in "${TEXTFILES[@]}"; do
    if has_em_dash "$f"; then em=$((em + 1)); fi
    if has_home_path "$f"; then home=$((home + 1)); fi
    case $f in
        */tools/touchpad/*)
            if has_device_id "$f"; then dev=$((dev + 1)); fi
            ;;
    esac
done
if [ "${#TEXTFILES[@]}" -gt 10 ]; then
    pass "style guard scanned ${#TEXTFILES[@]} files"
else
    fail "style guard scanned too few files"
fi
verdict "no em dashes ($em file(s))" "$em"
verdict "no hard-coded home paths ($home file(s))" "$home"
verdict "no hard-coded device ids or nodes in tools/touchpad ($dev file(s))" "$dev"

printf 'a dash %s here\n' "$EM_DASH" >"$SCRATCH/dash.txt"
printf 'cd /home/someone/x\n' >"$SCRATCH/home.txt"
printf 'dev=/dev/input/event7\n' >"$SCRATCH/dev.txt"
expect "negative: em dash guard bites" has_em_dash "$SCRATCH/dash.txt"
expect "negative: home path guard bites" has_home_path "$SCRATCH/home.txt"
expect "negative: device id guard bites" has_device_id "$SCRATCH/dev.txt"

mapfile -t WORKFLOWS < <(find "$ROOT/.github/workflows" -name '*.yml' | sort)
if [ "${#WORKFLOWS[@]}" -ge 1 ]; then
    pass "found ${#WORKFLOWS[@]} workflows"
else
    fail "workflows missing"
fi
for f in "${WORKFLOWS[@]}"; do
    expect_not "workflow uses are pinned by SHA with a version comment: ${f#"$ROOT"/}" has_unpinned_uses "$f"
done
printf '  x:\n    uses: o/r/.github/workflows/w.yml@v1\n' >"$SCRATCH/wf.yml"
expect "negative: pin guard bites" has_unpinned_uses "$SCRATCH/wf.yml"

# --- install.sh behavior (no root; logs go to the scratch dir) ---------------

export XDG_STATE_HOME="$SCRATCH/state"
cp "$ROOT/config/setup.conf.example" "$SCRATCH/setup.conf"
chmod 600 "$SCRATCH/setup.conf"

out=$("$ROOT/install.sh" --config "$SCRATCH/setup.conf" --check 2>&1)
rc=$?
if [ "$rc" = 0 ] || [ "$rc" = 1 ]; then
    pass "--check exits 0 or 1 (got $rc)"
else
    fail "--check exited $rc"
fi
for m in tuxedo devtools flatpaks; do
    contains "--check ran module $m" "$out" "^## module: $m"
done
contains "--check skips the disabled touchpad module" "$out" '^\[skip\] module touchpad is disabled'
if grep -q '^ERROR' <<<"$out"; then
    fail "--check printed an ERROR"
else
    pass "--check printed no ERROR"
fi
logs=$(find "$XDG_STATE_HOME/tuxedo-popos-setup" -name '*-check.log' 2>/dev/null | wc -l)
if [ "$logs" -ge 1 ]; then
    pass "--check wrote a log"
else
    fail "no check log written"
fi

sed 's/^ENABLE_TOUCHPAD_FIX=0/ENABLE_TOUCHPAD_FIX=1/' "$SCRATCH/setup.conf" >"$SCRATCH/touchpad-on.conf"
chmod 600 "$SCRATCH/touchpad-on.conf"
out=$("$ROOT/install.sh" --config "$SCRATCH/touchpad-on.conf" --check 2>&1)
contains "--check runs touchpad when enabled" "$out" '^## module: touchpad'

out=$("$ROOT/install.sh" --config "$SCRATCH/setup.conf" --dry-run 2>&1)
rc=$?
verdict "--dry-run exits 0 (got $rc)" "$rc"
contains "--dry-run prints planned steps" "$out" '^\[dry-run\] would:'
contains "--dry-run says nothing changed" "$out" 'nothing was changed'

if [ "$(id -u)" != 0 ]; then
    expect_not "apply without root is refused" "$ROOT/install.sh" --config "$SCRATCH/setup.conf"
fi
expect_status "unknown option exits 2" 2 "$ROOT/install.sh" --bogus

chmod 666 "$SCRATCH/setup.conf"
expect_not "negative: world-writable config is refused" "$ROOT/install.sh" --config "$SCRATCH/setup.conf" --check
chmod 600 "$SCRATCH/setup.conf"

sed 's/com.discordapp.Discord/bad id;rm/' "$SCRATCH/setup.conf" >"$SCRATCH/badid.conf"
chmod 600 "$SCRATCH/badid.conf"
expect_not "negative: invalid flatpak id is refused" "$ROOT/install.sh" --config "$SCRATCH/badid.conf" --check

# --- touchpad tools: option handling and root check, no hardware needed ------

for t in touchpad-diag.sh trace-click.sh driver-swap-test.sh; do
    expect_status "$t rejects an unknown option with exit 2" 2 bash "$ROOT/tools/touchpad/$t" --bogus
    if [ "$(id -u)" != 0 ]; then
        expect_not "$t refuses to run without root" bash "$ROOT/tools/touchpad/$t"
    fi
done
for t in allkeys.py click-hid.py; do
    expect "$t --help works" python3 -I "$ROOT/tools/touchpad/$t" --help
done

printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" = 0 ]
