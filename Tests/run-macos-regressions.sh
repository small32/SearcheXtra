#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

flags=(-c release --arch "${SEARCH_ARCH:-$(uname -m)}" -Xswiftc -Osize)
# Several native UI fixtures own a process-wide probe/data store. Keep each
# class in its own process and data world: profiles restore disk sessions,
# even when an earlier fixture's process has already exited.
classes="$(swift test "${flags[@]}" --list-tests | sed -nE 's#^SearcheXtraTests\.([^/]+)/.*#\1#p' | sort -u)"
[[ -n "$classes" ]] || { echo 'No macOS regression classes discovered' >&2; exit 1; }
failed=()
while IFS= read -r test_class; do
  [[ "$test_class" == ExtensionScriptCatTests ]] && continue
  echo "=== $test_class ==="
  probe="interface-$(printf '%s' "$test_class" | tr '[:upper:]' '[:lower:]')-$$"
  if ! SEARCH_PROBE="$probe" python3 Tests/run-macos-test-class.py "$test_class" \
    swift test "${flags[@]}" --skip-build --filter "SearcheXtraTests\.$test_class/"; then
    failed+=("$test_class")
  fi
done <<< "$classes"
if (( ${#failed[@]} )); then
  printf 'Failed macOS regression class: %s\n' "${failed[@]}" >&2
  exit 1
fi
