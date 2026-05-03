#!/usr/bin/env bash
set -euo pipefail

# Write documentation pages autonomously using Claude Code + OpenProse.
# Each page gets its own context window (fresh session) running the
# write-doc-page.prose workflow.
#
# Usage:
#   ./scripts/write-docs.sh                    # Run all autonomous batches (1-7)
#   ./scripts/write-docs.sh --batch 1          # Run batch 1 only (CLI Reference)
#   ./scripts/write-docs.sh --pages cli/status cli/doctor  # Run specific pages
#   ./scripts/write-docs.sh --dry-run          # Print pages without running

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
QUEUE_FILE="$PROJECT_DIR/docs-queue.md"
LOG_DIR="$PROJECT_DIR/docs-logs"
PROSE_FILE="$PROJECT_DIR/.prose/write-doc-page.prose"

mkdir -p "$LOG_DIR"

# All autonomous pages by batch
BATCH_1=(
  cli/overview cli/init cli/chat cli/sessions cli/status cli/doctor cli/stats
  cli/provider cli/model cli/mcp-tools cli/webhooks cli/reminder cli/skill cli/secrets
)
BATCH_2=(security/security-model security/hardening security/secrets)
BATCH_3=(
  configuration/managed-providers configuration/self-hosted-providers
  configuration/models configuration/mcp-servers configuration/webhooks configuration/reminders
)
BATCH_4=(observability/operational-alerts observability/opentelemetry)
BATCH_5=(channels/troubleshooting)
BATCH_6=(deployment/docker deployment/systemd deployment/exposure-modes)
BATCH_7=(
  architecture/overview architecture/security-model
  channels/slack channels/discord
  skills/overview skills/external-skills
  guides/connecting-slack guides/mcp-tool-permissions guides/pairing-remote-devices
)

DRY_RUN=false
PAGES=()

# Parse arguments
while [[ $# -gt 0 ]]; do
  case "$1" in
    --batch)
      shift
      case "$1" in
        1) PAGES+=("${BATCH_1[@]}") ;;
        2) PAGES+=("${BATCH_2[@]}") ;;
        3) PAGES+=("${BATCH_3[@]}") ;;
        4) PAGES+=("${BATCH_4[@]}") ;;
        5) PAGES+=("${BATCH_5[@]}") ;;
        6) PAGES+=("${BATCH_6[@]}") ;;
        7) PAGES+=("${BATCH_7[@]}") ;;
        *) echo "Unknown batch: $1"; exit 1 ;;
      esac
      shift
      ;;
    --pages)
      shift
      while [[ $# -gt 0 && ! "$1" =~ ^-- ]]; do
        PAGES+=("$1")
        shift
      done
      ;;
    --dry-run)
      DRY_RUN=true
      shift
      ;;
    *)
      echo "Unknown argument: $1"
      echo "Usage: $0 [--batch N] [--pages page1 page2 ...] [--dry-run]"
      exit 1
      ;;
  esac
done

# Default: all autonomous batches
if [[ ${#PAGES[@]} -eq 0 ]]; then
  PAGES+=("${BATCH_1[@]}" "${BATCH_2[@]}" "${BATCH_3[@]}" "${BATCH_4[@]}" "${BATCH_5[@]}" "${BATCH_6[@]}" "${BATCH_7[@]}")
fi

# Check if page is already done (checked off in queue)
is_done() {
  local page="$1"
  grep -qP "^\- \[x\] \`${page}\`" "$QUEUE_FILE" 2>/dev/null
}

# Mark page as done in queue
mark_done() {
  local page="$1"
  sed -i "s/^- \[ \] \`${page//\//\\/}\`/- [x] \`${page//\//\\/}\`/" "$QUEUE_FILE"
}

echo "=== netclaw.dev doc writer ==="
echo "Pages to process: ${#PAGES[@]}"
echo ""

completed=0
skipped=0
failed=0

for page in "${PAGES[@]}"; do
  if is_done "$page"; then
    echo "[SKIP] $page (already done)"
    ((skipped++))
    continue
  fi

  if $DRY_RUN; then
    echo "[DRY ] $page"
    continue
  fi

  echo "[RUN ] $page"
  log_file="$LOG_DIR/$(echo "$page" | tr '/' '-').log"

  if claude --print --dangerously-skip-permissions -p "prose run .prose/write-doc-page.prose PAGE=$page" > "$log_file" 2>&1; then
    # Check if the page was actually written (no longer "Content coming soon")
    page_file="$PROJECT_DIR/src/content/docs/${page}.md"
    if [[ -f "$page_file" ]] && ! grep -q "Content coming soon" "$page_file"; then
      mark_done "$page"
      echo "[DONE] $page"
      ((completed++))
    else
      echo "[FAIL] $page (page not written or still has placeholder)"
      ((failed++))
    fi
  else
    echo "[FAIL] $page (claude exited non-zero)"
    ((failed++))
  fi
done

echo ""
echo "=== Summary ==="
echo "Completed: $completed"
echo "Skipped:   $skipped"
echo "Failed:    $failed"
echo "Logs:      $LOG_DIR/"
