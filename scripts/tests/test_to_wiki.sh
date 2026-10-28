#!/bin/bash
# Regression test for scripts/hooks/to-wiki.py, the after-meeting command that
# files a transcript into a personal wiki. A fake `claude` stands in for the
# headless run, so this covers the part that must work without it: the raw/
# file name, the byte-for-byte copy, never overwriting, and the last line the
# app shows in its notification.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
SCRIPT="$ROOT/scripts/hooks/to-wiki.py"
TMPD="$(mktemp -d)"
trap 'rm -rf "$TMPD"' EXIT
PASSED=0

fail() { echo "FAIL: $*" >&2; exit 1; }

WIKI="$TMPD/wiki"
mkdir -p "$WIKI/raw"
touch "$WIKI/AGENTS.md"
printf '[00:01] Me: привет\n[00:03] k.markidonov: привет\n' > "$TMPD/t.txt"

cat > "$TMPD/claude-ok" <<'FAKE'
#!/bin/bash
echo "args: $*"
echo "ИТОГ: обновлены 2 карточки"
FAKE
printf '#!/bin/bash\necho boom >&2\nexit 7\n' > "$TMPD/claude-fail"
chmod +x "$TMPD/claude-ok" "$TMPD/claude-fail"

run() {
    env -i PATH=/usr/bin:/bin HOME="$TMPD" \
        MT_TRANSCRIPT="$TMPD/t.txt" MT_DATE=2026-10-13 MT_TITLE="$1" MT_PARTICIPANTS="$2" \
        TO_WIKI_DIR="$WIKI" TO_WIKI_OWNER="Evgeniy Zhiltsov" TO_WIKI_CLAUDE="$3" \
        python3 "$SCRIPT"
}

# A 1-1 is named after the other person, copied byte for byte, and the
# notification line is the model's summary.
out="$(run "Maksim / Evgeniy" "k.markidonov" "$TMPD/claude-ok")"
f="$WIKI/raw/2026-10-13 Evgeniy Markidonov - 1-1.md"
[ -f "$f" ] || fail "1-1 file missing: $(ls "$WIKI/raw")"
cmp -s "$f" "$TMPD/t.txt" || fail "raw copy differs from the transcript"
[ "$(printf '%s\n' "$out" | tail -1)" = "ИТОГ: обновлены 2 карточки" ] || fail "last line: $out"
printf '%s' "$out" | grep -q "raw/2026-10-13 Evgeniy Markidonov - 1-1.md" || fail "prompt does not name the file"
PASSED=$((PASSED + 1))

# The same 1-1 again that day never overwrites.
run "Maksim / Evgeniy" "k.markidonov" "$TMPD/claude-ok" > /dev/null
[ -f "$WIKI/raw/2026-10-13 Evgeniy Markidonov - 1-1 (2).md" ] || fail "no (2) on collision"
PASSED=$((PASSED + 1))

# A group lists surnames without the owner, with the title cleaned of slashes.
run "Product/Wallet: sync" "$(printf 'a.toporov\nEvgeniy Zhiltsov\nИрина Разумова')" "$TMPD/claude-ok" > /dev/null
[ -f "$WIKI/raw/2026-10-13 Evgeniy Toporov Разумова - Product Wallet sync.md" ] \
    || fail "group name: $(ls "$WIKI/raw")"
PASSED=$((PASSED + 1))

# A company-wide call: the name keeps as many surnames as fit the byte budget
# (measured in UTF-8, so a Cyrillic surname counts double), keeps the topic,
# and the prompt carries the surnames the name could not.
many="$(printf 'Иван Разумовский\n'; for i in $(seq 1 35); do printf 'p.participant%02d\n' "$i"; done)"
out="$(run "QA monthly talks" "$many" "$TMPD/claude-ok")"
big="$(ls "$WIKI/raw" | grep 'QA monthly talks.md')"
[ -n "$big" ] || fail "company-wide call not saved: $(ls "$WIKI/raw")"
[ "$(printf '%s' "$big" | wc -c)" -le 203 ] || fail "name over the budget: $big"
printf '%s' "$big" | grep -q "^2026-10-13 Evgeniy Разумовский Participant01 " || fail "surnames not kept in order: $big"
printf '%s' "$big" | grep -q "Participant35" && fail "nothing dropped from a 36-name list: $big"
printf '%s' "$out" | grep -q "не поместились [0-9]* фамилий" || fail "prompt does not say surnames were dropped: $out"
printf '%s' "$out" | grep -q "p.participant35" || fail "prompt lacks the full list: $out"
PASSED=$((PASSED + 1))

# Nobody named: filed under the owner's full name with the title, and only
# then may the model rename the file.
out="$(run "Weekly Sync Metrics" "" "$TMPD/claude-ok")"
[ -f "$WIKI/raw/2026-10-13 Evgeniy Zhiltsov - Weekly Sync Metrics.md" ] || fail "solo name: $(ls "$WIKI/raw")"
printf '%s' "$out" | grep -q "Bash(mv:\*)" || fail "no rename tool without participants: $out"
PASSED=$((PASSED + 1))
out="$(run "Maksim / Evgeniy" "k.markidonov" "$TMPD/claude-ok")"
printf '%s' "$out" | grep -q "Bash(mv:\*)" && fail "rename tool granted with participants known"
PASSED=$((PASSED + 1))

# Claude failing still leaves the transcript in raw/, and says so.
set +e
out="$(run "Lunch" "o.pivovarova" "$TMPD/claude-fail" 2>/dev/null)"
status=$?
set -e
[ "$status" -ne 0 ] || fail "claude failure exited 0"
[ -f "$WIKI/raw/2026-10-13 Evgeniy Pivovarova - 1-1.md" ] || fail "raw file missing after claude failure"
printf '%s\n' "$out" | tail -1 | grep -q "saved, wiki not processed (claude exit 7)" || fail "failure line: $out"
PASSED=$((PASSED + 1))

# Without the wiki configured nothing is written.
before="$(ls "$WIKI/raw" | wc -l)"
set +e
env -i PATH=/usr/bin:/bin MT_TRANSCRIPT="$TMPD/t.txt" python3 "$SCRIPT" > /dev/null
status=$?
set -e
[ "$status" -ne 0 ] || fail "missing config exited 0"
[ "$(ls "$WIKI/raw" | wc -l)" = "$before" ] || fail "wrote a file without config"
PASSED=$((PASSED + 1))

echo "test_to_wiki: $PASSED cases passed"
