#!/usr/bin/env bash
set -euo pipefail

OUT_DIR=""
LINT_CMD=""
FORMAT_CMD=""
TYPES_CMD=""
TESTS_CMD=""
REVIEW_CMD=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --out)
      OUT_DIR="$2"
      shift 2
      ;;
    --lint)
      LINT_CMD="$2"
      shift 2
      ;;
    --format)
      FORMAT_CMD="$2"
      shift 2
      ;;
    --types)
      TYPES_CMD="$2"
      shift 2
      ;;
    --tests)
      TESTS_CMD="$2"
      shift 2
      ;;
    --review)
      REVIEW_CMD="$2"
      shift 2
      ;;
    *)
      echo "unknown-arg:$1" >&2
      exit 2
      ;;
  esac
done

if [[ -z "$OUT_DIR" ]]; then
  echo "missing-required:--out" >&2
  exit 2
fi

mkdir -p "$OUT_DIR"
GATES_TXT="$OUT_DIR/gates.txt"
FAILED_TXT="$OUT_DIR/failed.txt"
RESULT_JSON="$OUT_DIR/gates.json"
: > "$GATES_TXT"
: > "$FAILED_TXT"

run_check() {
  local id="$1"
  local cmd="$2"

  if [[ -z "$cmd" ]]; then
    echo "$id:missing-command" >> "$GATES_TXT"
    echo "$id" >> "$FAILED_TXT"
    return 1
  fi

  if bash -lc "$cmd" >/dev/null 2>&1; then
    echo "$id:pass" >> "$GATES_TXT"
    return 0
  fi

  echo "$id:fail" >> "$GATES_TXT"
  echo "$id" >> "$FAILED_TXT"
  return 1
}

run_check "lint" "$LINT_CMD" || true
run_check "format" "$FORMAT_CMD" || true
run_check "types" "$TYPES_CMD" || true
run_check "tests" "$TESTS_CMD" || true
run_check "review" "$REVIEW_CMD" || true

FAILED_COUNT="$(wc -l < "$FAILED_TXT" | tr -d ' ')"
STATUS="pass"
if [[ "$FAILED_COUNT" -gt 0 ]]; then
  STATUS="fail"
fi

python3 - "$STATUS" "$FAILED_COUNT" "$FAILED_TXT" "$RESULT_JSON" <<'PY'
import json
import sys
from pathlib import Path

status = sys.argv[1]
failed_count = int(sys.argv[2])
failed_path = Path(sys.argv[3])
result_path = Path(sys.argv[4])
failed = [line.strip() for line in failed_path.read_text().splitlines() if line.strip()]
payload = {
    "status": status,
    "checks_run": ["lint", "format", "types", "tests", "review"],
    "checks_failed": failed,
    "failed_count": failed_count,
}
result_path.write_text(json.dumps(payload, indent=2) + "\n")
PY

echo "$RESULT_JSON"
