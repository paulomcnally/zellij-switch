#!/usr/bin/env bash
#
# Scenario tests for zellij-switch.
#
# Runs every command against isolated sandbox config dirs (ZELLIJ_CONFIG_DIR),
# covering happy paths, switch/revert flows, drift detection, install, and all
# environment validations. Used locally and in GitHub Actions (Ubuntu).
#
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$REPO_ROOT/zellij-switch"
FIXTURES="$REPO_ROOT/test/fixtures"

PASS=0
FAIL=0
FAILED_TESTS=()

pass() {
    PASS=$((PASS + 1))
}

fail() {
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$1")
    echo "FAIL: $1"
}

assert_ok() {
    local desc="$1"
    shift
    if "$@"; then
        pass
    else
        fail "$desc"
    fi
}

# Assert that a command FAILS and its output contains the given string.
run_fails_with() {
    local desc="$1"
    local expected="$2"
    shift 2
    local out
    if out="$("$@" 2>&1)"; then
        fail "$desc (expected failure, but it succeeded)"
    elif grep -qF "$expected" <<<"$out"; then
        pass
    else
        fail "$desc (expected output to contain '$expected'; got: $out)"
    fi
}

# Fresh sandbox: empty ZELLIJ_CONFIG_DIR with the given fixture as config.kdl.
fresh_sandbox() {
    SANDBOX="$(mktemp -d)"
    export ZELLIJ_CONFIG_DIR="$SANDBOX"
    cp "$FIXTURES/$1.kdl" "$SANDBOX/config.kdl"
}

# Validate a config file by asking the real zellij binary to parse it.
# shellcheck disable=SC2317 # invoked indirectly via assert_ok
validate_with_zellij() {
    local cfg="$1"
    local dir
    dir="$(mktemp -d)"
    cp "$cfg" "$dir/config.kdl"
    ZELLIJ_CONFIG_DIR="$dir" zellij setup --check >/dev/null 2>&1
}

check_status() {
    local expected="$1"
    local desc="$2"
    local out
    out="$("$SCRIPT" status 2>&1)" || true
    if grep -qF "$expected" <<<"$out"; then
        pass
    else
        fail "$desc (expected '$expected'; got: $out)"
    fi
}

test_cli_basics() {
    assert_ok "help exits 0" "$SCRIPT" help
    assert_ok "version exits 0" "$SCRIPT" version
    run_fails_with "unknown command fails" "Usage" "$SCRIPT" does-not-exist
}

test_missing_zellij() {
    fresh_sandbox custom
    run_fails_with \
        "missing zellij binary is reported" \
        "zellij is not installed or not in your PATH" \
        env PATH=/usr/bin:/bin "$SCRIPT" status
}

test_missing_config() {
    SANDBOX="$(mktemp -d)"
    export ZELLIJ_CONFIG_DIR="$SANDBOX"
    run_fails_with \
        "missing config file is reported" \
        "no Zellij config found" \
        "$SCRIPT" status
}

test_switch_flow() {
    # Parametrized: run the full flow against a given fixture.
    local fixture="$1"

    fresh_sandbox "$fixture"

    # Before any snapshot there are no variants: status must say unknown.
    check_status "unknown" "initial status is unknown ($fixture)"

    assert_ok "snapshot ok ($fixture)" "$SCRIPT" snapshot
    assert_ok "actual.kdl created ($fixture)" test -f "$SANDBOX/variants/actual.kdl"
    assert_ok "a.kdl created ($fixture)" test -f "$SANDBOX/variants/a.kdl"
    assert_ok "b.kdl created ($fixture)" test -f "$SANDBOX/variants/b.kdl"
    assert_ok "actual is exact backup of config ($fixture)" cmp "$SANDBOX/config.kdl" "$SANDBOX/variants/actual.kdl"
    assert_ok "zellij accepts actual variant ($fixture)" validate_with_zellij "$SANDBOX/variants/actual.kdl"
    assert_ok "zellij accepts variant a ($fixture)" validate_with_zellij "$SANDBOX/variants/a.kdl"
    assert_ok "zellij accepts variant b ($fixture)" validate_with_zellij "$SANDBOX/variants/b.kdl"

    # Only the Ctrl+P line may differ between actual and the variants.
    local diff_lines
    diff_lines="$(diff "$SANDBOX/variants/actual.kdl" "$SANDBOX/variants/a.kdl" | grep -c '^[<>]' || true)"
    assert_ok "actual vs a differ in exactly 2 diff lines ($fixture)" test "$diff_lines" -eq 2

    assert_ok "switch to a ($fixture)" "$SCRIPT" a
    check_status "active variant: a" "status shows a after switch ($fixture)"
    grep -q 'SwitchFocus' "$SANDBOX/config.kdl" || fail "variant a contains SwitchFocus ($fixture)"
    grep -q 'NewPane' "$SANDBOX/config.kdl" && fail "variant a drops NewPane ($fixture)"

    assert_ok "switch to b ($fixture)" "$SCRIPT" b
    check_status "active variant: b" "status shows b after switch ($fixture)"
    grep -q 'LaunchOrFocusPlugin "session-manager"' "$SANDBOX/config.kdl" \
        || fail "variant b launches session-manager ($fixture)"

    assert_ok "switch back to actual ($fixture)" "$SCRIPT" actual
    check_status "active variant: actual" "status shows actual after revert ($fixture)"
    assert_ok "config restored exactly ($fixture)" cmp "$SANDBOX/config.kdl" "$SANDBOX/variants/actual.kdl"

    # Drift: manual edit makes status report unknown.
    printf '\n// manual edit\n' >>"$SANDBOX/config.kdl"
    check_status "unknown" "drift detected after manual edit ($fixture)"

    # Switching again overwrites the drift and works.
    assert_ok "switch after drift still works ($fixture)" "$SCRIPT" a
    check_status "active variant: a" "status shows a after re-switch ($fixture)"
}

test_unpatchable_configs() {
    fresh_sandbox no-ctrlp
    assert_ok "snapshot ok (no-ctrlp)" "$SCRIPT" snapshot
    run_fails_with \
        "no-ctrlp: variant a fails loudly" \
        "unable to patch variant 'a'" \
        "$SCRIPT" a

    fresh_sandbox multiline-ctrlp
    assert_ok "snapshot ok (multiline)" "$SCRIPT" snapshot
    run_fails_with \
        "multiline-ctrlp: variant b fails loudly" \
        "unable to patch variant 'b'" \
        "$SCRIPT" b
}

test_real_default_config() {
    # Use the genuine default config generated by the installed zellij.
    SANDBOX="$(mktemp -d)"
    export ZELLIJ_CONFIG_DIR="$SANDBOX"
    zellij setup --dump-config >"$SANDBOX/config.kdl"

    assert_ok "snapshot ok (real default)" "$SCRIPT" snapshot
    assert_ok "switch a ok (real default)" "$SCRIPT" a
    assert_ok "zellij accepts patched a (real default)" validate_with_zellij "$SANDBOX/config.kdl"
    assert_ok "switch b ok (real default)" "$SCRIPT" b
    assert_ok "zellij accepts patched b (real default)" validate_with_zellij "$SANDBOX/config.kdl"
    assert_ok "switch actual ok (real default)" "$SCRIPT" actual
    assert_ok "config restored (real default)" cmp "$SANDBOX/config.kdl" "$SANDBOX/variants/actual.kdl"
}

test_install() {
    local dir
    dir="$(mktemp -d)"
    assert_ok "install ok" "$SCRIPT" install "$dir/zellij-switch"
    assert_ok "installed file exists" test -x "$dir/zellij-switch"
    assert_ok "installed file runs" "$dir/zellij-switch" version
}

test_snapshot_rebase() {
    fresh_sandbox custom
    assert_ok "snapshot ok" "$SCRIPT" snapshot
    assert_ok "switch a ok" "$SCRIPT" a
    # Rebase from the (currently a) config, then actual == variant a content.
    assert_ok "snapshot rebase ok" "$SCRIPT" snapshot
    assert_ok "config == new actual" cmp "$SANDBOX/config.kdl" "$SANDBOX/variants/actual.kdl"
    check_status "active variant: actual" "status shows actual after snapshot rebase"
}

main() {
    test_cli_basics
    test_missing_zellij
    test_missing_config
    test_switch_flow custom
    test_switch_flow default
    test_unpatchable_configs
    test_real_default_config
    test_install
    test_snapshot_rebase

    echo ""
    echo "zellij-switch scenario tests: PASS=$PASS FAIL=$FAIL"
    if [[ "$FAIL" -gt 0 ]]; then
        printf 'Failed tests:\n'
        for f in "${FAILED_TESTS[@]}"; do
            printf '  - %s\n' "$f"
        done
        exit 1
    fi
    exit 0
}

main "$@"