# approvals-list.png: `netclaw approvals list` with grants made by trust-verb and by real
# prompt answers (see lib/seed-approvals.tape).
Set Shell "bash"
Set WaitTimeout 240s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 380
Set Padding 20
Set TypingSpeed 40ms

Source "/tapes/include/seed-approvals.tape"

Type "netclaw approvals list"
Enter
Sleep 2s
Screenshot screenshots/output/approvals-list.png
Sleep 2s
