# netclaw config > Channels > Mattermost > Channels & Permissions: the per-channel audience screen
# stack: fresh
# The old ten-step init wizard had a Channels step. In 0.27.1 the same screen lives in `netclaw config`, once an adapter is enabled and has channels. Runs the
# real `netclaw init` out of sight, then enables a Mattermost adapter whose channels resolve against
# a small API fixture (scripts/mock-mattermost.py) so the rows show names, not raw IDs.
Output screenshots/output/channel-audiences.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 520
Set Padding 20
Set TypingSpeed 40ms

Hide
Source "/tapes/include/init-personal.tape"
Type "nohup python3 /work/screenshots/scripts/mock-mattermost.py >/dev/null 2>&1 &"
Enter
Sleep 2s
Type "bash /work/screenshots/scripts/seed-channel-audiences.sh"
Enter
Sleep 25s
Type "clear"
Enter
Sleep 1s
Show

Type "netclaw config"
Enter
Sleep 3s

# 3. Channels, then Mattermost (the third adapter)
Down
Down
Sleep 400ms
Enter
Sleep 2s
Down
Down
Sleep 400ms
Enter
Sleep 3s

# Manage channels and permissions
Enter
Sleep 4s
Screenshot screenshots/output/config-channel-audiences.png
Sleep 500ms
Ctrl+Q
Sleep 1s
