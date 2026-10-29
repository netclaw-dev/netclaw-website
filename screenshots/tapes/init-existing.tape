# netclaw init on an existing install: the action menu and the start-over scope chooser
# stack: fresh
# Runs the real wizard out of sight first, so the daemon has a completed Personal setup.
# Produces init-existing-menu and init-start-over-scope.
Output screenshots/output/init-existing.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1100
Set Height 380
Set Padding 20
Set TypingSpeed 40ms

Hide
Source "/tapes/include/init-personal.tape"
Show

Type "netclaw init"
Enter
Sleep 3s
Screenshot screenshots/output/init-existing-menu.png
Sleep 500ms

# Start over from scratch
Down
Sleep 300ms
Down
Sleep 300ms
Enter
Sleep 2s
Screenshot screenshots/output/init-start-over-scope.png
Sleep 500ms
Ctrl+Q
Sleep 1s
