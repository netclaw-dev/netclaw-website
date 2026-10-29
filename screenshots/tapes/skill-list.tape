# skill-list.png: `netclaw skill list` with local skills, the system skills and two feed skills.
# stack: bare
Set Shell "bash"
Set WaitTimeout 120s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 520
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

Type "netclaw skill list"
Enter
Sleep 3s
Screenshot screenshots/output/skill-list.png
Sleep 2s
