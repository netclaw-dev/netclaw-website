# netclaw approvals — persistent tool approval management
# Seeds a realistic tool-approvals.json, then captures list + TUI + revoke flow
Output screenshots/output/approvals.gif

Set Shell "bash"
Set Theme "Dracula"
Set Width 1200
Set Height 700
Set FontSize 16
Set Padding 20
Set TypingSpeed 50ms

# Seed approvals data (hidden from recording)
Hide
Type "bash screenshots/scripts/seed-approvals.sh"
Enter
Sleep 500ms
Type "clear"
Enter
Sleep 500ms
Show

# ═══════════════════════════════════════════════
# SCENE 1: netclaw approvals list
# ═══════════════════════════════════════════════

Type "netclaw approvals list"
Enter
Sleep 2s

Screenshot screenshots/output/approvals-list.png
Sleep 1s

Type "clear"
Enter
Sleep 500ms

# ═══════════════════════════════════════════════
# SCENE 2: netclaw approvals list --json
# ═══════════════════════════════════════════════

Type "netclaw approvals list --json"
Enter
Sleep 2s

Screenshot screenshots/output/approvals-list-json.png
Sleep 1s

Type "clear"
Enter
Sleep 500ms

# ═══════════════════════════════════════════════
# SCENE 3: netclaw approvals TUI — browse and revoke
# ═══════════════════════════════════════════════

Type "netclaw approvals"
Enter
Sleep 3s

# TUI list view — all approvals
Screenshot screenshots/output/approvals-tui.png
Sleep 500ms

# Navigate down to an entry
Down
Sleep 300ms
Down
Sleep 300ms
Down
Sleep 300ms

Screenshot screenshots/output/approvals-tui-selected.png
Sleep 500ms

# Press Delete to initiate revoke
Delete
Sleep 1s

# Revoke confirmation dialog
Screenshot screenshots/output/approvals-tui-revoke-confirm.png
Sleep 500ms

# Confirm the revoke
Enter
Sleep 1s

# Post-revoke state
Screenshot screenshots/output/approvals-tui-revoke-done.png
Sleep 1s

# Exit TUI
Ctrl+Q
Sleep 1s
