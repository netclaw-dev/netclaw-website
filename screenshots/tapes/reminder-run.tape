# reminder-run-approval.png: `netclaw reminder run disk-note` stopped at the approval prompt
# for the reminder's shell call, with "Always here" highlighted. Nothing is answered.
Set Shell "bash"
Set WaitTimeout 240s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 700
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "netclaw reminder create disk-note cron '0 8 * * *' 'Use shell_execute to run exactly: touch /tmp/disk-note.txt' --name 'Disk note' > /dev/null; clear"
Enter
Sleep 2s
Show

Type "netclaw reminder run disk-note"
Enter
Sleep 5s
Wait+Screen@240s /Ready +\| +demo-model/
Sleep 1s
Type "Run the reminder disk-note now."
Enter
Wait+Screen@240s /5\. Deny/
Sleep 1s
Down
Sleep 300ms
Down
Sleep 1s
Screenshot screenshots/output/reminder-run-approval.png
Sleep 2s
Ctrl+Q
Sleep 1s
