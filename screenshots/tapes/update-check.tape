# netclaw update --check on an install that is one release behind
# stack: fresh
# image: 0.28.1
# This is the one tape that does not run the documented release: it runs the previous one (0.28.1),
# which is genuinely a version behind, so the check reports a real update to v0.28.2 instead of a
# staged one. The visible `netclaw --version` makes that plain.
Output screenshots/output/update-check.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 200
Set Padding 20
Set TypingSpeed 40ms

Type "netclaw --version"
Enter
Sleep 2s
Type "netclaw update --check"
Enter
Sleep 5s
Screenshot screenshots/output/update-check.png
Sleep 500ms
