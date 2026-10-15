#!/bin/bash
# Launch the assembled app away from SwiftPM's build tree. A missing second
# argument/path is valid when checking a downloaded release before building.
# Usage: bash Tests/verify-macos-app-launch.sh [app] [SwiftPM resource bundle]
set -euo pipefail

repo_dir="$(cd "$(dirname "$0")/.." && pwd -P)"
app="${1:-$repo_dir/build/SearcheXtra.app}"
app="$(cd "$(dirname "$app")" && pwd -P)/$(basename "$app")"
resources="$app/Contents/Resources/SearcheXtra_SearcheXtra.bundle"
[[ -x "$app/Contents/MacOS/SearcheXtra" ]] || { echo "Missing app executable: $app" >&2; exit 1; }
for resource in FlowDrag.js Translations.json; do
    [[ -f "$resources/$resource" || -f "$resources/Contents/Resources/$resource" ]] || {
        echo "Missing packaged $resource: $resources" >&2
        exit 1
    }
done

source_bundle="${2:-}"
if [[ $# -lt 2 && -d "$repo_dir/.build" ]]; then
    bin_dir="$(cd "$repo_dir" && swift build -c release --arch "${SEARCH_ARCH:-$(uname -m)}" --show-bin-path)"
    source_bundle="$bin_dir/SearcheXtra_SearcheXtra.bundle"
fi
hidden_bundle=""
work_dir="$(mktemp -d "${TMPDIR:-/tmp}/searchextra-launch.XXXXXX")"
log="$work_dir/launch.log"
probe="macos-launch-smoke-$$"
original_home="$HOME"
app_pid=""
touch "$log" "$work_dir/started"

cleanup() {
    result=$?
    trap - EXIT HUP INT TERM
    if [[ -n "$app_pid" ]]; then
        kill "$app_pid" 2>/dev/null || true
        for _ in 1 2 3 4 5; do
            kill -0 "$app_pid" 2>/dev/null || break
            sleep 0.2
        done
        kill -KILL "$app_pid" 2>/dev/null || true
        wait "$app_pid" 2>/dev/null || true
    fi
    if [[ -n "$hidden_bundle" && -d "$hidden_bundle" ]]; then
        if [[ -e "$source_bundle" ]]; then
            echo "Cannot restore hidden resource bundle; destination already exists: $source_bundle" >&2
            result=1
        elif ! mv "$hidden_bundle" "$source_bundle"; then
            echo "Failed to restore resource bundle: $hidden_bundle" >&2
            result=1
        fi
    fi
    if [[ "$result" -ne 0 ]]; then
        # Keep stdout/stderr and this probe's own reports for CI diagnostics.
        if [[ -n "$app_pid" ]]; then
            for report_dir in "$original_home/Library/Logs/DiagnosticReports"; do
                [[ -d "$report_dir" ]] || continue
                while IFS= read -r report; do
                    if grep -Eq "\"pid\"[[:space:]]*:[[:space:]]*$app_pid([,[:space:]]|$)|^Process:.*\\[$app_pid\\]" "$report"; then
                        cp "$report" "$work_dir/$(basename "$report")" || true
                    fi
                done < <(find "$report_dir" -type f \( -name 'SearcheXtra*.ips' -o -name 'SearcheXtra*.crash' \) -newer "$work_dir/started")
            done
        fi
        cat "$log" >&2
        if [[ -n "${SEARCHEXTRA_LAUNCH_LOG_DIR:-}" ]]; then
            mkdir -p "$SEARCHEXTRA_LAUNCH_LOG_DIR"
            cp "$log" "$SEARCHEXTRA_LAUNCH_LOG_DIR/launch.log"
            for report in "$work_dir"/*.ips "$work_dir"/*.crash; do
                [[ ! -f "$report" ]] || cp "$report" "$SEARCHEXTRA_LAUNCH_LOG_DIR/"
            done
        fi
        echo "Launch failed; diagnostics retained at $work_dir" >&2
    else
        rm -rf "$work_dir"
    fi
    exit "$result"
}
trap cleanup EXIT
trap 'exit 129' HUP
trap 'exit 130' INT
trap 'exit 143' TERM

ditto "$app" "$work_dir/SearcheXtra.app"
if [[ -n "$source_bundle" && -d "$source_bundle" ]]; then
    source_bundle="$(cd "$(dirname "$source_bundle")" && pwd -P)/$(basename "$source_bundle")"
    [[ "$source_bundle" != "$resources" ]] || { echo "Refusing to hide the app's packaged resources" >&2; exit 1; }
    hidden_bundle="$source_bundle.launch-smoke-$$.hidden"
    [[ ! -e "$hidden_bundle" ]] || { echo "Temporary bundle path already exists: $hidden_bundle" >&2; exit 1; }
    mv "$source_bundle" "$hidden_bundle"
fi

# Store isolates each probe's settings, files and WebKit store from the installed
# browser. The fresh blank tab builds its first WKWebView after one second.
(
    cd "$work_dir"
    export SEARCH_PROBE="$probe"
    exec ./SearcheXtra.app/Contents/MacOS/SearcheXtra \
        -start.fresh YES -start.page "" -welcomed YES -ApplePersistenceIgnoreState YES
) >"$log" 2>&1 &
app_pid=$!
printf 'App: %s\nProbe: %s\nPID: %s\n' "$app" "$probe" "$app_pid"
for _ in 1 2 3 4 5 6 7 8; do
    sleep 1
    if ! kill -0 "$app_pid" 2>/dev/null; then
        process_status=0
        wait "$app_pid" || process_status=$?
        echo "App exited before the 8-second launch check (status $process_status)." >> "$log"
        exit 1
    fi
done
if grep -Eiq 'fatal error|terminating app due to uncaught exception|uncaught exception|unable to find bundle|could not (find|load) resource bundle|missing interface translations|dyld.*(library not loaded|symbol not found)' "$log"; then
    echo "A fatal startup error appeared in the app log." >> "$log"
    exit 1
fi
echo "Packaged app survived 8 seconds outside the build tree."
