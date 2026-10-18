#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."

flags=(-c release --arch "${SEARCH_ARCH:-$(uname -m)}" -Xswiftc -Osize)
# Several native UI fixtures own a process-wide probe/data store. Keep each
# class in its own process so its teardown cannot delete another class's world.
classes="$(swift test "${flags[@]}" --list-tests | sed -nE 's#^SearcheXtraTests\.([^/]+)/.*#\1#p' | sort -u)"
[[ -n "$classes" ]] || { echo 'No macOS regression classes discovered' >&2; exit 1; }
while IFS= read -r test_class; do
  [[ "$test_class" == ExtensionScriptCatTests ]] && continue
  echo "=== $test_class ==="
  SEARCH_PROBE=interface-tests swift test "${flags[@]}" --skip-build --filter "SearcheXtraTests\.$test_class/"
done <<< "$classes"
