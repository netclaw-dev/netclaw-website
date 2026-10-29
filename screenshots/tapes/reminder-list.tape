# reminder-list.png: `netclaw reminder list` over two neutral reminders.
# `reminder list` prints a table with one row per reminder; 1350 px keeps each row on one line.
# stack: bare
Set Shell "bash"
Set WaitTimeout 120s
Set Theme "Dracula"
Set FontSize 16
Set Width 1350
Set Height 260
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "bash /work/screenshots/scripts/seed-demo-install.sh"
Enter
Wait+Screen@8m /seeded: demo install/
Type "clear"
Enter
Sleep 1s
Show

Type "netclaw reminder list"
Enter
Sleep 2s
Screenshot screenshots/output/reminder-list.png
Sleep 2s
