#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
TS="$(date -u +%Y-%m-%dT%H-%M-%SZ)"
OUT_DIR="$ROOT/.reports/codex/calibration/$TS"
mkdir -p "$OUT_DIR"

PROJECT_CFG="$ROOT/.codex/config.toml"
HOME_CFG="$HOME/.codex/config.toml"
TASKS="$ROOT/.codex/calibration/tasks.json"
BENCHMARKS="$ROOT/.codex/calibration/benchmarks.json"
SKILLS=(review develop resolve audit calibrate release investigate sync manage analyse optimize research)
AGENTS=(sw-engineer qa-specialist squeezer doc-scribe security-auditor data-steward cicd-steward linting-expert oss-shepherd solution-architect web-explorer curator)

LEAKS=0
FAILS=0

check_contains() {
  local file="$1"
  local pattern="$2"
  if ! grep -qi "$pattern" "$file"; then
    echo "missing:$pattern:$file" >> "$OUT_DIR/leaks.txt"
    LEAKS=$((LEAKS + 1))
    return 1
  fi
  return 0
}

check_model() {
  local file="$1"
  local label="$2"
  if grep -q 'model[[:space:]]*=[[:space:]]*"gpt-5.4-mini"' "$file"; then
    echo "$label:model=ok" >> "$OUT_DIR/checks.txt"
  else
    echo "$label:model=fail" >> "$OUT_DIR/checks.txt"
    echo "model-not-gpt-5.4-mini:$file" >> "$OUT_DIR/leaks.txt"
    FAILS=$((FAILS + 1))
    LEAKS=$((LEAKS + 1))
  fi
}

echo "calibration-start:$TS" > "$OUT_DIR/checks.txt"
check_model "$PROJECT_CFG" "project-config"
check_model "$HOME_CFG" "home-config"

for skill in "${SKILLS[@]}"; do
  SKILL_FILE="$ROOT/.codex/skills/$skill/SKILL.md"
  if [[ ! -f "$SKILL_FILE" ]]; then
    echo "missing-skill:$skill" >> "$OUT_DIR/leaks.txt"
    FAILS=$((FAILS + 1))
    LEAKS=$((LEAKS + 1))
    continue
  fi
  check_contains "$SKILL_FILE" "^# "
  check_contains "$SKILL_FILE" "Workflow"
  check_contains "$SKILL_FILE" "Output Contract"
  check_contains "$SKILL_FILE" "quality-gates"
  check_contains "$SKILL_FILE" ".reports/codex/$skill/"
  check_contains "$SKILL_FILE" "\"status\""
  check_contains "$SKILL_FILE" "\"checks_run\""
  check_contains "$SKILL_FILE" "\"checks_failed\""
  check_contains "$SKILL_FILE" "\"findings\""
  check_contains "$SKILL_FILE" "\"confidence\""
  check_contains "$SKILL_FILE" "\"artifact_path\""
  check_contains "$PROJECT_CFG" "path[[:space:]]*=[[:space:]]*\"skills/$skill\""
  if ! grep -qiE "path[[:space:]]*=[[:space:]]*\"(.*\\/)?skills/$skill\"" "$HOME_CFG"; then
    echo "missing:skills/$skill:$HOME_CFG" >> "$OUT_DIR/leaks.txt"
    LEAKS=$((LEAKS + 1))
  fi
done

if [[ ! -f "$TASKS" ]]; then
  echo "missing-tasks:$TASKS" >> "$OUT_DIR/leaks.txt"
  FAILS=$((FAILS + 1))
  LEAKS=$((LEAKS + 1))
fi

if [[ ! -f "$BENCHMARKS" ]]; then
  echo "missing-benchmarks:$BENCHMARKS" >> "$OUT_DIR/leaks.txt"
  FAILS=$((FAILS + 1))
  LEAKS=$((LEAKS + 1))
fi

for agent in "${AGENTS[@]}"; do
  check_contains "$PROJECT_CFG" "\\[agents\\.$agent\\]"
  check_contains "$HOME_CFG" "\\[agents\\.$agent\\]"
  if [[ -f "$ROOT/.codex/agents/$agent.toml" ]]; then
    check_contains "$ROOT/.codex/agents/$agent.toml" "developer_instructions"
  else
    echo "missing-agent-file:$agent" >> "$OUT_DIR/leaks.txt"
    FAILS=$((FAILS + 1))
    LEAKS=$((LEAKS + 1))
  fi
done

RUN_GATES="$ROOT/.codex/skills/_shared/run-gates.sh"
WRITE_RESULT="$ROOT/.codex/skills/_shared/write-result.sh"

if [[ ! -x "$RUN_GATES" ]]; then
  echo "shared-script-not-executable:$RUN_GATES" >> "$OUT_DIR/leaks.txt"
  FAILS=$((FAILS + 1))
  LEAKS=$((LEAKS + 1))
fi

if [[ ! -x "$WRITE_RESULT" ]]; then
  echo "shared-script-not-executable:$WRITE_RESULT" >> "$OUT_DIR/leaks.txt"
  FAILS=$((FAILS + 1))
  LEAKS=$((LEAKS + 1))
fi

SELFTEST_DIR="$OUT_DIR/selftest"
mkdir -p "$SELFTEST_DIR"

if [[ -x "$RUN_GATES" ]]; then
  "$RUN_GATES" \
    --out "$SELFTEST_DIR/gates" \
    --lint "true" \
    --format "true" \
    --types "true" \
    --tests "true" \
    --review "true" >/dev/null
  if [[ ! -f "$SELFTEST_DIR/gates/gates.json" ]]; then
    echo "selftest-missing:gates.json" >> "$OUT_DIR/leaks.txt"
    FAILS=$((FAILS + 1))
    LEAKS=$((LEAKS + 1))
  fi
fi

if [[ -x "$WRITE_RESULT" ]]; then
  "$WRITE_RESULT" \
    --out "$SELFTEST_DIR/result.json" \
    --status "pass" \
    --checks-run "lint,format,types,tests,review" \
    --checks-failed "" \
    --critical "0" \
    --high "0" \
    --medium "0" \
    --low "0" \
    --confidence "0.95" \
    --artifact-path "$SELFTEST_DIR/result.json" >/dev/null
  if [[ ! -f "$SELFTEST_DIR/result.json" ]]; then
    echo "selftest-missing:result.json" >> "$OUT_DIR/leaks.txt"
    FAILS=$((FAILS + 1))
    LEAKS=$((LEAKS + 1))
  fi
fi

if [[ -f "$BENCHMARKS" ]]; then
  python3 - "$ROOT" "$BENCHMARKS" "$OUT_DIR/leaks.txt" <<'PY'
import json
import re
import sys
from pathlib import Path

root = Path(sys.argv[1])
bench = Path(sys.argv[2])
leaks = Path(sys.argv[3])
data = json.loads(bench.read_text())

def record(msg: str) -> None:
    with leaks.open("a", encoding="utf-8") as fh:
        fh.write(msg + "\n")

for skill, patterns in data.get("skills", {}).items():
    path = root / ".codex" / "skills" / skill / "SKILL.md"
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    for pat in patterns:
        if not re.search(pat, text, flags=re.IGNORECASE):
            record(f"benchmark-skill-miss:{skill}:{pat}")

for agent, patterns in data.get("agents", {}).items():
    path = root / ".codex" / "agents" / f"{agent}.toml"
    text = path.read_text(encoding="utf-8") if path.exists() else ""
    for pat in patterns:
        if not re.search(pat, text, flags=re.IGNORECASE):
            record(f"benchmark-agent-miss:{agent}:{pat}")
PY
fi

if [[ -f "$OUT_DIR/leaks.txt" ]]; then
  NEW_FAILS="$(grep -c '^benchmark-.*-miss:' "$OUT_DIR/leaks.txt" || true)"
  if [[ "$NEW_FAILS" -gt 0 ]]; then
    FAILS=$((FAILS + NEW_FAILS))
    LEAKS=$((LEAKS + NEW_FAILS))
  fi
fi

STATUS="pass"
if [[ "$FAILS" -gt 0 ]]; then
  STATUS="fail"
fi

cat > "$OUT_DIR/result.json" <<EOF
{
  "status": "$STATUS",
  "timestamp": "$TS",
  "checks_run": [
    "project-model-default",
    "home-model-default",
    "skill-schema-all",
    "skill-registration-project",
    "skill-registration-home",
    "agent-registration-project",
    "agent-registration-home",
    "agent-schema-all",
    "fixed-task-set",
    "benchmark-pattern-checks",
    "shared-script-selftests"
  ],
  "checks_failed": $FAILS,
  "leaks_found": $LEAKS,
  "artifacts": {
    "checks": ".reports/codex/calibration/$TS/checks.txt",
    "leaks": ".reports/codex/calibration/$TS/leaks.txt",
    "result": ".reports/codex/calibration/$TS/result.json"
  }
}
EOF

if [[ ! -f "$OUT_DIR/leaks.txt" ]]; then
  touch "$OUT_DIR/leaks.txt"
fi

echo "$OUT_DIR/result.json"
