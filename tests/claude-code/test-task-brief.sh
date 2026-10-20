#!/usr/bin/env bash
# Tests for scripts/task-brief: folder plans (README + tasks/*.md), README
# section selection (Context line, --sections, --no-sections, Global
# Constraints), code-fence handling and the single-file regression.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
TB="$REPO_ROOT/skills/subagent-driven-development/scripts/task-brief"

FAILURES=0
pass() { echo "  [PASS] $1"; }
fail() { echo "  [FAIL] $1"; FAILURES=$((FAILURES + 1)); }

TEST_ROOT="$(mktemp -d)"
trap 'rm -rf "$TEST_ROOT"' EXIT
repo="$TEST_ROOT/repo"
mkdir -p "$repo/plan/tasks"
git -C "$repo" init -q

cat > "$repo/plan/README.md" <<'R'
# Plan

## Global Constraints

GC-LINE no force unwrap.

## Contract (backend <-> iOS)

CONTRACT-LINE POST /x.

### Contract details

CONTRACT-DETAIL nested.

## Russian (binding)

RUSSIAN-LINE Название.

## Rulings 2026

RULINGS-LINE ruling one.

## Other

OTHER-LINE never wanted.

```
## Task 9: fake in fence
FENCED-TASK
```
R
cat > "$repo/plan/tasks/A.md" <<'R'
# Group A header

GROUP-A-LINE shared note.

## Task 1: First

**Context:** README §Contract; Russian

TASK1-BODY

## Task 10: Tenth

TASK10-BODY
R
cat > "$repo/plan/tasks/B.md" <<'R'
# Group B header

GROUP-B-LINE

## Task 2: Second

TASK2-BODY
R

run() { (cd "$repo" && bash "$TB" "$@"); }
has() { grep -qF -- "$2" "$1"; }
check() { # description, condition-status
    if [ "$2" -eq 0 ]; then pass "$1"; else fail "$1"; fi
}

echo "=== task-brief ==="

o="$TEST_ROOT/t1.md"
msg="$(run plan/README.md 1 "$o")"
{ has "$o" "GROUP-A-LINE" && has "$o" "TASK1-BODY" && ! has "$o" "GROUP-B-LINE" && ! has "$o" "TASK10-BODY"; }; check "task from tasks file carries its group header, not task 10" $?
head -1 "$o" | grep -qx '# Group A header'; check "group header comes first" $?
{ has "$o" "CONTRACT-LINE" && has "$o" "CONTRACT-DETAIL" && has "$o" "RUSSIAN-LINE" && has "$o" "GC-LINE"; }; check "Context selects Contract (with subsection) + Russian + Global Constraints" $?
{ ! has "$o" "RULINGS-LINE" && ! has "$o" "OTHER-LINE"; }; check "unrequested sections absent" $?
has "$o" "<!-- README § Contract (backend <-> iOS) -->"; check "section marker present" $?
[ "$(grep "^<!-- README §" "$o" | sed 's/.*§ //;s/ -->//' | paste -sd'|' -)" = "Global Constraints|Contract (backend <-> iOS)|Russian (binding)" ]; check "sections in README order" $?
[ "$(tail -1 "$o")" = "<!-- brief: task 1, sections: Global Constraints | Contract (backend <-> iOS) | Russian (binding) -->" ]; check "trailing brief comment" $?
[ "$msg" = "wrote $o: $(wc -l < "$o" | tr -d ' ') lines, sections: Global Constraints, Contract (backend <-> iOS), Russian (binding)" ]; check "wrote line lists sections" $?

o="$TEST_ROOT/t10.md"
run plan/README.md 10 "$o" >/dev/null
{ has "$o" "TASK10-BODY" && ! has "$o" "TASK1-BODY" && has "$o" "GC-LINE" && ! has "$o" "CONTRACT-LINE"; }; check "task 10 is not task 1; no Context -> only Global Constraints" $?

o="$TEST_ROOT/t2.md"
run plan/README.md 2 "$o" --sections "Rulings" >/dev/null
{ has "$o" "GROUP-B-LINE" && has "$o" "RULINGS-LINE" && has "$o" "GC-LINE" && ! has "$o" "OTHER-LINE"; }; check "--sections adds Rulings, group header of B.md" $?

o="$TEST_ROOT/t2n.md"
run plan/README.md 2 "$o" --no-sections >/dev/null
{ ! has "$o" "GC-LINE" && has "$o" "TASK2-BODY" && [ "$(tail -1 "$o")" = "<!-- brief: task 2, sections: none -->" ]; }; check "--no-sections omits Global Constraints" $?

o="$TEST_ROOT/bad.md"; rc=0
err="$(run plan/README.md 2 "$o" --sections "Nonexistent" 2>&1 >/dev/null)" || rc=$?
{ [ "$rc" -eq 4 ] && [ "$err" = "task-brief: no README section matching 'Nonexistent'" ]; }; check "unknown section -> exit 4 + message" $?

rc=0; run plan/README.md 9 "$TEST_ROOT/n9.md" >/dev/null 2>&1 || rc=$?
[ "$rc" -eq 3 ]; check "heading inside a code fence is ignored (task 9 not found)" $?

# Context line parsing: anchored, fence-aware
mkdir -p "$repo/plan2/tasks"
cp "$repo/plan/README.md" "$repo/plan2/README.md"
cat > "$repo/plan2/tasks/C.md" <<'R'
# Group C header

## Task 3: Fenced context

```
**Context:** Other
```

T3-BODY

## Task 4: Prose mention

Do not remove the **Context:** line.

T4-BODY

## Task 5: Several lines

**Context:** Contract
- **Context:** Rulings

T5-BODY

## Task 6: Separators

**Context:** §Russian, §Rulings

T6-BODY
R
secs() { grep "^<!-- README §" "$1" | sed 's/.*§ //;s/ -->//' | paste -sd'|' -; }

o="$TEST_ROOT/t3.md"; rc=0
run plan2/README.md 3 "$o" >/dev/null 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && ! has "$o" "OTHER-LINE" && [ "$(secs "$o")" = "Global Constraints" ]; }; check "Context inside a fence is ignored" $?

o="$TEST_ROOT/t4.md"; rc=0
run plan2/README.md 4 "$o" >/dev/null 2>&1 || rc=$?
{ [ "$rc" -eq 0 ] && [ "$(secs "$o")" = "Global Constraints" ]; }; check "mid-line prose mention of Context is ignored" $?

o="$TEST_ROOT/t5.md"
run plan2/README.md 5 "$o" >/dev/null
[ "$(secs "$o")" = "Global Constraints|Contract (backend <-> iOS)|Rulings 2026" ]; check "several Context lines are united (bullet form too)" $?

o="$TEST_ROOT/t6.md"
run plan2/README.md 6 "$o" >/dev/null
[ "$(secs "$o")" = "Global Constraints|Russian (binding)|Rulings 2026" ]; check "comma separator and bare section prefix work" $?

# Single-file plan regression
cat > "$repo/single.md" <<'R'
# Single

## Task 1: Only

SINGLE-BODY

## Task 2: Next

NEXT-BODY
R
o="$TEST_ROOT/s.md"
run single.md 1 "$o" >/dev/null
printf '## Task 1: Only\n\nSINGLE-BODY\n\n<!-- brief: task 1, sections: none -->\n' | cmp -s - "$o"; check "single-file plan without Context: old output + trailer" $?

echo
if [ "$FAILURES" -eq 0 ]; then echo "All tests passed"; else echo "$FAILURES failed"; exit 1; fi
