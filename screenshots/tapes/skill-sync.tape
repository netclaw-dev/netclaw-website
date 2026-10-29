# skill-sync.png: `netclaw skill sync` against the stack's skill server (feed `corp-skills`).
# stack: bare
# The first sync runs hidden so the recorded one reports the steady state.
Set Shell "bash"
Set WaitTimeout 120s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 300
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

Type "netclaw skill sync"
Enter
Sleep 6s
Screenshot screenshots/output/skill-sync.png
Sleep 2s
