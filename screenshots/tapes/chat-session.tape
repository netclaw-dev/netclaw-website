# chat-tui-idle.png: a resumed session (replayed history, idle status bar) and
# slash-unknown-command.png: the reply to an unknown slash command (no model call).
Set Shell "bash"
Set WaitTimeout 240s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 600
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "netclaw chat -p --resume demo-notes 'In two sentences, what is a good structure for weekly meeting notes?' > /dev/null && netclaw chat -p --resume demo-notes 'Turn that into a three-item checklist.' > /dev/null; echo SE''EDED"
Enter
Wait+Screen@240s /SEEDED/
Type "clear"
Enter
Sleep 1s
Show

Type "netclaw chat --resume demo-notes"
Enter
Wait+Screen@60s /End of history/
Sleep 3s
Screenshot screenshots/output/chat-tui-idle.png
Sleep 2s
Ctrl+Q
Sleep 2s

Hide
Type "clear"
Enter
Show
Type "netclaw chat"
Enter
Sleep 3s
Type "/nope"
Enter
Wait+Screen@30s /Unknown command/
Sleep 2s
Screenshot screenshots/output/slash-unknown-command.png
Sleep 2s
Ctrl+Q
Sleep 2s
