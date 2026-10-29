# Setup helper, not a tape: Source it between Hide and Show to run the real `netclaw init` wizard
# (Personal posture, Ollama, the stack's one model, identity "Netclaw" / "alice") against the
# first-run daemon. Leaves the shell at a clean prompt with a completed Personal setup, so a
# tape can start from what a reader has right after the quickstart.
# Needs `# stack: fresh` or `# stack: bare` (empty ~/.netclaw, Ollama on localhost:11434).
Type "netclaw init"
Enter
Sleep 3s
Type "4"
Sleep 1500ms
Enter
Sleep 5s
Enter
Sleep 2s
Enter
Sleep 1s
Enter
Sleep 1s
Type "alice"
Enter
Sleep 1s
Enter
Sleep 2s
Enter
# Health check, then the wizard hands over to chat
Sleep 14s
Ctrl+Q
Sleep 2s
Type "clear"
Enter
Sleep 1s
