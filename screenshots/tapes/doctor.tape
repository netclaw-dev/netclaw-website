# netclaw doctor: all 24 checks and the exit-code line on a typical Personal install
# stack: bare
# Same demo install as status.tape (scripts/seed-demo-install.sh). A normal install has no secrets.json (nothing to put
# in it), so the one WARN is the real one and the exit code is 2. No check fails. The terminal is
# wide enough that no line wraps and tall enough for every check.
Output screenshots/output/doctor.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1700
Set Height 700
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "bash /work/screenshots/scripts/seed-demo-install.sh"
Enter
Wait+Screen@8m /seeded: demo install/
Sleep 20s
Type "clear"
Enter
Sleep 1s
Show

Type "netclaw doctor"
Enter
Sleep 8s
Screenshot screenshots/output/doctor.png
Sleep 500ms
