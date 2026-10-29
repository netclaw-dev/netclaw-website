# webhooks-list.png: `netclaw webhooks list` with two routes (see scripts/seed-webhooks.sh).
# stack: bare
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

Type "netclaw webhooks list"
Enter
Sleep 2s
Screenshot screenshots/output/webhooks-list.png
Sleep 2s
