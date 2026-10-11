#!/usr/bin/env bash
# Drives the real bitewrite window with real keys and clicks (Qt's own test
# runner, offscreen) and checks what lands on disk. Everything happens in a
# throwaway folder: your notes, code, Documents and ~/.local/bin are never
# touched (the tests only install .html files, which never become commands).
#
#   tools/test-bitewrite.sh           run every test
#   tools/test-bitewrite.sh browser   run tst_browser.qml only
#
# Screenshots from tst_shot land in the throwaway folder; its path is printed.
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
TOY="$HERE/../src/toys/bitewrite"
RUNNER=/usr/lib/qt6/bin/qmltestrunner          # /usr/bin/qmltestrunner is the Qt 5 one
[[ -x "$RUNNER" ]] || { echo "needs qt6-declarative's qmltestrunner at $RUNNER" >&2; exit 2; }

WORK="$(mktemp -d "${TMPDIR:-/tmp}/bitewrite-test.XXXXXX")"
RUN="$WORK/run"
export DATA="$WORK/data" DOCS="$WORK/docs"
mkdir -p "$RUN" "$DATA" "$DOCS"

python3 "$TOY/engine.py" --prep "$RUN" >/dev/null || { echo "engine --prep failed" >&2; exit 1; }
cp -f "$TOY"/*.qml "$TOY"/*.js "$HERE"/bitewrite-tests/tst_*.qml "$RUN/"

python3 "$TOY/engine.py" --serve "$RUN" >"$WORK/engine.log" 2>&1 &
ENGINE=$!
trap 'kill "$ENGINE" 2>/dev/null' EXIT

# Qt logs to the journal when it isn't on a terminal; the tests need to see it
export QT_FORCE_STDERR_LOGGING=1 QT_QPA_PLATFORM=offscreen
export QML_XHR_ALLOW_FILE_READ=1 QML_XHR_ALLOW_FILE_WRITE=1

cd "$RUN" || exit 1
status=0
for t in tst_features tst_browser tst_shot; do
    [[ -n "${1:-}" && "$t" != "tst_$1" ]] && continue
    echo "── $t"
    # warnings from bitewrite itself count as failures; the one about the
    # test's own property name doesn't
    out="$(timeout 120 "$RUNNER" -input "$t.qml" 2>&1)" || status=1
    printf '%s\n' "$out" | grep -E '^(PASS|FAIL|Totals)|Loc:'
    if printf '%s\n' "$out" | grep -E '^QWARN' | grep -q 'bitewrite\|Write.qml\|Files.qml\|Notes.qml\|Browser.qml\|Diff.qml\|Picker.qml\|Stage.qml'; then
        printf '%s\n' "$out" | grep -E '^QWARN'
        status=1
    fi
done
echo "── screenshots and data: $WORK"
exit $status
