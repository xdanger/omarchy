#!/bin/bash

set -euo pipefail

source "$(dirname "$0")/base-test.sh"

test_tmp=$(mktemp -d)
trap 'rm -rf "$test_tmp"' EXIT

stub_bin="$test_tmp/bin"
git_log="$test_tmp/git.log"
mkdir -p "$stub_bin"

cat >"$stub_bin/checkupdates" <<'SH'
#!/bin/bash
case "${TEST_CHECKUPDATES:-updates}" in
  updates)
    printf 'linux 6.1-1 -> 6.1-2\nomarchy 4.0.0-1 -> 4.0.1-1\nomarchy-settings 4.0.0-1 -> 4.0.1-1\nomarchy-dev 4.1.0-1 -> 4.1.1-1\nomarchy-settings-dev 4.1.0-1 -> 4.1.1-1\n'
    exit 0
    ;;
  security)
    printf 'google-chrome 155.0.8059.84-1 -> 158.0.8127.88-1\nchromium 155.0.8059.84-1 -> 155.0.8059.84-2\nfirefox 150.0-1 -> 160.0-1 [ignored]\n'
    exit 0
    ;;
  none)
    exit 2
    ;;
  fail)
    echo "check failed" >&2
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/checkupdates"

cat >"$stub_bin/pacman" <<'SH'
#!/bin/bash
case "$1" in
  -Q)
    [[ $2 == "google-chrome" ]] || exit 1
    echo "google-chrome ${TEST_CHROME_INSTALLED:-155.0.8059.84-1}"
    exit 0
    ;;
  -Qq)
    case "${TEST_INSTALLED_PACKAGE:-omarchy}" in
      omarchy)
        [[ $2 == "omarchy" ]]; exit $?
        ;;
      omarchy-dev)
        [[ $2 == "omarchy-dev" ]]; exit $?
        ;;
      both)
        [[ $2 == "omarchy" || $2 == "omarchy-dev" ]]; exit $?
        ;;
      none)
        exit 1
        ;;
    esac
    ;;
esac
exit 0
SH
chmod +x "$stub_bin/pacman"

cat >"$stub_bin/git" <<'SH'
#!/bin/bash

printf '%s\n' "$*" >>"$TEST_GIT_LOG"

[[ $1 == "-C" ]] || exit 1
shift 2

case "$1" in
  fetch)
    [[ ${TEST_GIT_FETCH:-ok} == "ok" ]]
    ;;
  rev-parse)
    case "$2" in
      --is-inside-work-tree)
        [[ ${TEST_GIT_CHECKOUT:-yes} == "yes" ]] || exit 1
        echo true
        ;;
      --abbrev-ref)
        [[ ${TEST_GIT_UPSTREAM:-origin/quattro} != "none" ]] || exit 1
        echo "${TEST_GIT_UPSTREAM:-origin/quattro}"
        ;;
      *)
        exit 1
        ;;
    esac
    ;;
  rev-list)
    echo "${TEST_GIT_BEHIND:-0}"
    ;;
  *)
    exit 1
    ;;
esac
SH
chmod +x "$stub_bin/git"

cat >"$stub_bin/pacman-conf" <<'SH'
#!/bin/bash
printf '%s\n' 'https://pkgs.omarchy.cn/stable/x86_64' 'https://pkgs.omarchy.org/stable/x86_64'
SH
chmod +x "$stub_bin/pacman-conf"

# Serves the security list from $TEST_SECURITY_LIST, and fails like a machine
# offline when there is none. Every URL asked for is logged.
cat >"$stub_bin/curl" <<'SH'
#!/bin/bash
url=${!#}
while (( $# )); do
  [[ $1 == "-o" ]] && output=$2
  shift
done
echo "$url" >>"$TEST_CURL_LOG"
[[ -n ${TEST_SECURITY_LIST:-} && -n ${output:-} ]] || exit 6
[[ ${TEST_SECURITY_HOST:-any} == "any" || $url == "https://$TEST_SECURITY_HOST/"* ]] || exit 22
cp "$TEST_SECURITY_LIST" "$output"
SH
chmod +x "$stub_bin/curl"

for stub in omarchy-notification-send omarchy-shell; do
  printf '#!/bin/bash\nprintf "%%s\\n" "$*" >>"$TEST_NOTIFY_LOG"\n' >"$stub_bin/$stub"
  chmod +x "$stub_bin/$stub"
done

# Most cases describe a system that has been through omarchy update once.
mkdir -p "$test_tmp/home/.local/state/omarchy/done"
touch "$test_tmp/home/.local/state/omarchy/done/first-update"

run_checker() {
  OMARCHY_PATH="${TEST_OMARCHY_PATH:-/usr/share/omarchy}" \
    HOME="${TEST_HOME:-$test_tmp/home}" \
    TEST_GIT_LOG="$git_log" \
    TEST_CURL_LOG="$test_tmp/curl.log" \
    TEST_NOTIFY_LOG="$test_tmp/notify.log" \
    PATH="$stub_bin:$ROOT/bin:$PATH" \
    "$ROOT/bin/omarchy-update-available"
}

capture_checker() {
  local stdout_file="$1"
  local stderr_file="$2"
  shift 2

  set +e
  (
    export "$@"
    run_checker
  ) >"$stdout_file" 2>"$stderr_file"
  local status=$?
  set -e
  return "$status"
}

stdout="$test_tmp/stdout"
stderr="$test_tmp/stderr"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=omarchy; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when omarchy update is available"
grep -q '^omarchy ' "$stdout" || fail "update checker prints omarchy updates"
! grep -q '^omarchy-settings ' "$stdout" || fail "update checker ignores omarchy-settings updates"
! grep -q '^linux ' "$stdout" || fail "update checker ignores non-Omarchy package updates"
! grep -q '^omarchy-dev ' "$stdout" || fail "update checker ignores omarchy-dev when omarchy is installed"
pass "update checker detects installed omarchy package updates"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=omarchy-dev; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when omarchy-dev update is available"
grep -q '^omarchy-dev ' "$stdout" || fail "update checker prints omarchy-dev updates"
! grep -q '^omarchy-settings-dev ' "$stdout" || fail "update checker ignores omarchy-settings-dev updates"
! grep -q '^omarchy ' "$stdout" || fail "update checker ignores omarchy when omarchy-dev is installed"
pass "update checker detects installed omarchy-dev package updates"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=both; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker prefers omarchy-dev when both packages are installed"
grep -q '^omarchy-dev ' "$stdout" || fail "update checker prints omarchy-dev when both packages are installed"
! grep -q '^omarchy ' "$stdout" || fail "update checker ignores omarchy when omarchy-dev is installed"
pass "update checker prefers omarchy-dev over omarchy"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=updates TEST_INSTALLED_PACKAGE=none; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when no Omarchy package is installed"
[[ ! -s $stderr ]] || fail "update checker is quiet when no Omarchy package is installed"
pass "update checker ignores systems without omarchy or omarchy-dev installed"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=none TEST_INSTALLED_PACKAGE=omarchy; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when no updates are available"
grep -q '^Omarchy is up to date$' "$stdout" || fail "update checker prints up-to-date message"
pass "update checker reports up-to-date Omarchy packages"

: >"$git_log"
if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=2; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker exits successfully when dev commits are available"
grep -Fx 'omarchy-dev-checkout 2 new commits on origin/quattro' "$stdout" >/dev/null ||
  fail "update checker reports available dev commits" "$(cat "$stdout")"
grep -Fx -- "-C $test_tmp/checkout fetch --quiet" "$git_log" >/dev/null ||
  fail "update checker fetches the dev checkout upstream" "$(cat "$git_log")"
pass "update checker detects new commits in the dev checkout"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=0; then
  status=0
else
  status=$?
fi
[[ $status -eq 1 ]] || fail "update checker exits non-zero when the dev checkout is current"
grep -q '^Omarchy is up to date$' "$stdout" || fail "update checker reports a current dev checkout"
pass "update checker ignores a current dev checkout"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=none \
  TEST_INSTALLED_PACKAGE=none \
  TEST_OMARCHY_PATH="$test_tmp/checkout" \
  TEST_GIT_BEHIND=1 \
  TEST_GIT_FETCH=fail; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker uses cached upstream state when fetch fails"
grep -Fx 'omarchy-dev-checkout 1 new commit on origin/quattro' "$stdout" >/dev/null ||
  fail "update checker reports cached dev commits after a fetch failure" "$(cat "$stdout")"
[[ ! -s $stderr ]] || fail "update checker keeps dev fetch failures quiet" "$(cat "$stderr")"
pass "update checker uses cached dev state when fetching is unavailable"

if capture_checker "$stdout" "$stderr" \
  TEST_CHECKUPDATES=updates \
  TEST_INSTALLED_PACKAGE=omarchy \
  TEST_HOME="$test_tmp/fresh-home"; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "update checker reports package updates before the first omarchy update"
grep -q '^linux ' "$stdout" || fail "update checker counts any package before the first omarchy update" "$(cat "$stdout")"
pass "update checker counts any package update before the first omarchy update"

# Security minimums. google-chrome's update reaches its minimum; chromium's
# does not (a channel without the fix), and firefox's is held back by IgnorePkg:
# only google-chrome may be reported, and only while it is installed below.
security_list="$test_tmp/minimum-versions"
printf '%s\n' '# omarchy-security-minimums 1' '# a comment' 'google-chrome 157.0.8103.50' 'chromium 157.0.8103.50' 'firefox 155.0' >"$security_list"
security_home="$test_tmp/security-home"
mkdir -p "$security_home/.local/state/omarchy/done"
touch "$security_home/.local/state/omarchy/done/first-update"
: >"$test_tmp/notify.log"
: >"$test_tmp/curl.log"

if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=security TEST_HOME="$security_home" \
  TEST_SECURITY_LIST="$security_list" TEST_SECURITY_HOST=pkgs.omarchy.org; then
  status=0
else
  status=$?
fi
[[ $status -eq 0 ]] || fail "a security update counts as an update after the first omarchy update" "$(cat "$stdout" "$stderr")"
[[ $(grep '^security ' "$stdout") == "security google-chrome 155.0.8059.84-1 -> 158.0.8127.88-1" ]] ||
  fail "only an installable update that reaches the minimum is a security update" "$(cat "$stdout")"
[[ $(cat "$test_tmp/curl.log") == $'https://pkgs.omarchy.cn/security/minimum-versions\nhttps://pkgs.omarchy.org/security/minimum-versions' ]] ||
  fail "the list is fetched from the [omarchy] servers in pacman.conf order" "$(cat "$test_tmp/curl.log")"
[[ $(grep -c . "$test_tmp/notify.log") -eq 1 ]] || fail "a new security update sends one notification" "$(cat "$test_tmp/notify.log")"
pass "a security update the channel can install is reported and announced once"

: >"$test_tmp/curl.log"
capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=security TEST_HOME="$security_home" || true
grep -q '^security google-chrome ' "$stdout" || fail "a security update stays reported between fetches"
[[ ! -s "$test_tmp/curl.log" ]] || fail "the list is fetched at most once a day" "$(cat "$test_tmp/curl.log")"
[[ $(grep -c . "$test_tmp/notify.log") -eq 1 ]] || fail "a security update already announced notifies again"
pass "a later check keeps the reminder without fetching or notifying again"

[[ $(HOME="$security_home" PATH="$stub_bin:$ROOT/bin:$PATH" TEST_NOTIFY_LOG="$test_tmp/notify.log" "$ROOT/bin/omarchy-update-security" list) == \
  "google-chrome 155.0.8059.84-1 158.0.8127.88-1" ]] || fail "the update confirmation lists the pending security update"
[[ -z $(HOME="$security_home" PATH="$stub_bin:$ROOT/bin:$PATH" TEST_CHROME_INSTALLED=158.0.8127.88-1 "$ROOT/bin/omarchy-update-security" list) ]] ||
  fail "a security update already installed is still listed"
pass "the confirmation lists security updates until they are installed"

HOME="$security_home" PATH="$stub_bin:$ROOT/bin:$PATH" TEST_NOTIFY_LOG="$test_tmp/notify.log" "$ROOT/bin/omarchy-update-security" snooze
capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=security TEST_HOME="$security_home" || true
! grep -q '^security ' "$stdout" || fail "a snoozed security update is still highlighted" "$(cat "$stdout")"
pass "declining the update snoozes the reminder"

# Offline, or answered by a captive portal: nothing is reported, nothing said.
offline_home="$test_tmp/offline-home"
mkdir -p "$offline_home/.local/state/omarchy/done"
touch "$offline_home/.local/state/omarchy/done/first-update"
printf '<html>Sign in to the network</html>\n' >"$test_tmp/portal"
for list in "" "$test_tmp/portal"; do
  if capture_checker "$stdout" "$stderr" TEST_CHECKUPDATES=security TEST_HOME="$offline_home" TEST_SECURITY_LIST="$list"; then
    fail "a list that could not be fetched reports an update" "$(cat "$stdout")"
  fi
  [[ ! -s $stderr ]] || fail "a list that could not be fetched is not quiet" "$(cat "$stderr")"
done
[[ ! -e $offline_home/.local/state/omarchy/security-updates/minimum-versions ]] || fail "a captive portal page is kept as the list"
pass "an unreachable or bogus list reports nothing and stays quiet"
