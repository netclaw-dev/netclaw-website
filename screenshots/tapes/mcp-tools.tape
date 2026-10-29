# MCP Permissions TUI (`netclaw mcp permissions`): server list, then the tool grid for the
# demo-utilities server under the Personal, Team and Public audiences, plus the Team "Grant all" prompt.
Set Shell "bash"
Set WaitTimeout 60s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 560
Set Padding 20
Set TypingSpeed 40ms

Type "netclaw mcp permissions"
Enter
Wait+Screen /demo-utilities/
Sleep 1s
Screenshot screenshots/output/mcp-tools-server-list.png
Sleep 1s

Enter
Sleep 2s
Screenshot screenshots/output/mcp-tools-personal.png
Sleep 1s

Right
Sleep 1s
Screenshot screenshots/output/mcp-tools-team.png
Sleep 1s

# E on a server that is not enabled for Team asks before granting anything
Type "e"
Sleep 1s
Screenshot screenshots/output/mcp-tools-confirm.png
Sleep 1s
Type "n"
Sleep 1s

Right
Sleep 1s
Screenshot screenshots/output/mcp-tools-public.png
Sleep 1s

Ctrl+Q
