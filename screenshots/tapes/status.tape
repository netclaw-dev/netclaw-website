# netclaw status: a healthy daemon with its connectors, one of them an MCP server
# stack: bare
# seed-demo-install.sh builds the one demo install every status-like capture shares (providers,
# model roles, the demo MCP server, skills, webhooks, reminders), written with the real CLI. The model endpoint is the stack's forwarder
# (INFERENCE_UPSTREAM) when set. Nothing in the output names it.
Output screenshots/output/status.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 600
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "bash /work/screenshots/scripts/seed-demo-install.sh"
Enter
Wait+Screen@8m /seeded: demo install/
# Let the daemon run for a minute or two so the uptime reads like a real one
Sleep 75s
Type "clear"
Enter
Sleep 1s
Show

Type "netclaw status"
Enter
Sleep 3s
Screenshot screenshots/output/status.png
Sleep 500ms
