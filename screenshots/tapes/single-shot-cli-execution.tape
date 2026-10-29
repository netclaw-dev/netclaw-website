# netclaw chat -p: a one-shot headless prompt that calls a tool, with usage lines
# stack: bare
# Needs real inference (INFERENCE_UPSTREAM, see compose/forwarder.yml): the tool calls come from
# the model. The prompt is benign and the answer comes from the stack's demo MCP server. The tape
# waits for the shell prompt to come back, because how long the model takes isn't fixed.
Output screenshots/output/single-shot-cli-execution.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 420
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

Type `netclaw chat -p "Search your tools for a UUID generator and answer in under fifteen words."`
Enter
Sleep 10s
Wait+Screen@5m /(?m)^> *$/
Sleep 1s
Screenshot screenshots/output/single-shot-cli-execution.png
Sleep 500ms
