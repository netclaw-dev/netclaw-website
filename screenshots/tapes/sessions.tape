# netclaw sessions: the sessions browser with three titled conversations
# stack: bare
# Needs real inference: set INFERENCE_UPSTREAM (see compose/forwarder.yml), because the stack's
# 0.5B Ollama model can't use tools. seed-demo-install.sh builds the shared demo install, then the tape holds
# three short chats out of sight (each one a session), which takes a few minutes.
#
# Produces sessions-tui. Same three chats as stats.tape, in a shorter window.
Output screenshots/output/sessions.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 320
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "bash /work/screenshots/scripts/seed-demo-install.sh"
Enter
Wait+Screen@8m /seeded: demo install/
Type "clear"
Enter
Sleep 1s

# Conversation demo-notes: an interactive chat, so the daemon has time to title the session
Type "netclaw chat"
Enter
Sleep 6s
Type "Give me a three-item checklist for tidying a desk."
Enter
Sleep 6s
Wait+Screen@4m /Ready/
Sleep 30s
Ctrl+Q
Sleep 2s
Type "clear"
Enter
Sleep 1s

# Conversation weekly-report: an interactive chat, so the daemon has time to title the session
Type "netclaw chat"
Enter
Sleep 6s
Type "Write a two-sentence status update: the migration is finished and docs work starts Monday."
Enter
Sleep 6s
Wait+Screen@4m /Ready/
Sleep 30s
Ctrl+Q
Sleep 2s
Type "clear"
Enter
Sleep 1s

# Conversation trip-planning: an interactive chat, so the daemon has time to title the session
Type "netclaw chat"
Enter
Sleep 6s
Type "Suggest a name for a small weekend hiking club."
Enter
Sleep 6s
Wait+Screen@4m /Ready/
Sleep 30s
Ctrl+Q
Sleep 2s
Type "clear"
Enter
Sleep 1s

Show

Type "netclaw sessions"
Enter
Sleep 3s
Screenshot screenshots/output/sessions-tui.png
Sleep 500ms
Ctrl+Q
Sleep 1s
