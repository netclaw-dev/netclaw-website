# netclaw model: the model manager with Main, Fallback and Compaction all assigned
# stack: bare
# Same three neutral providers as provider.tape (scripts/seed-demo-install.sh). The Provider column is capped
# at 40 characters, so the long OpenAI-compatible label ends in an ellipsis at any width.
#
# Produces model-manager.
Output screenshots/output/model.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 340
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

Type "netclaw model"
Enter
Sleep 4s
Screenshot screenshots/output/model-manager.png
Sleep 500ms
Ctrl+Q
Sleep 1s
