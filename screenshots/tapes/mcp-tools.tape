# netclaw mcp tools — MCP tool permissions TUI
# Shows server list, then tool grid with audience toggling
Output screenshots/output/mcp-tools.gif

Set Shell "bash"
Set Theme "Dracula"
Set Width 1200
Set Height 700
Set FontSize 16
Set Padding 20
Set TypingSpeed 50ms

Type "netclaw mcp tools"
Enter
Sleep 3s

# Server list showing connected MCP servers
Screenshot screenshots/output/mcp-tools-server-list.png
Sleep 300ms

# Select first server to see tool grid
Enter
Sleep 2s

# Tool grid — Personal audience (default)
Screenshot screenshots/output/mcp-tools-personal.png
Sleep 300ms

# Switch to Team audience (right arrow)
Right
Sleep 1s
Screenshot screenshots/output/mcp-tools-team.png
Sleep 300ms

# Switch to Public audience (right arrow again)
Right
Sleep 1s
Screenshot screenshots/output/mcp-tools-public.png
Sleep 300ms

# Return to server list and exit
Escape
Sleep 1s
Escape
Sleep 1s
