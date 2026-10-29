# netclaw init: the Team posture, which adds a feature-selection step ("Step 4 of 5")
# stack: fresh
# Same first-run state and local Ollama as init-wizard.tape. Produces init-04-enabled-features
# (feature selection, Team posture) (the five-step flow's fourth step).
Output screenshots/output/init-team.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 420
Set Padding 20
Set TypingSpeed 40ms

Type "netclaw init"
Enter
Sleep 3s

# Ollama, default endpoint, the one model
Type "4"
Sleep 1500ms
Enter
Sleep 5s
Enter
Sleep 2s

# Identity: name, style, your name, timezone
Enter
Sleep 1s
Enter
Sleep 1s
Type "alice"
Enter
Sleep 1s
Enter
Sleep 2s

# Security posture: Team
Down
Sleep 500ms
Enter
Sleep 2s

# Feature selection: all six on for Team
Screenshot screenshots/output/init-04-enabled-features.png
Sleep 500ms
Enter
Sleep 3s
Ctrl+Q
Sleep 1s
