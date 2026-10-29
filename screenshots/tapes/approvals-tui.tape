# approvals-tui.png and approvals-tui-revoke-confirm.png: the approvals manager and its
# revoke confirmation, over the same grants as approvals-list.tape.
Set Shell "bash"
Set WaitTimeout 240s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 430
Set Padding 20
Set TypingSpeed 40ms

Source "/tapes/include/seed-approvals.tape"

Type "netclaw approvals"
Enter
Sleep 3s
Screenshot screenshots/output/approvals-tui.png
Sleep 2s
Down
Sleep 500ms
Type "r"
Sleep 1s
Screenshot screenshots/output/approvals-tui-revoke-confirm.png
Sleep 2s
Escape
Sleep 500ms
Ctrl+Q
Sleep 1s
