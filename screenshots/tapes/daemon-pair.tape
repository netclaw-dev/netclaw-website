# netclaw daemon pair and netclaw daemon devices: a pairing code and the paired-device list
# stack: fresh
# A device named alice-laptop is paired out of sight (scripts/seed-paired-device.sh runs the device
# side with its own NETCLAW_HOME), so the visible commands show a fresh code and a one-device list.
# The config seeded first (scripts/seed-providers.sh) only gives the CLI something to run against.
Output screenshots/output/daemon-pair.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 360
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "bash /work/screenshots/scripts/seed-providers.sh && bash /work/screenshots/scripts/seed-paired-device.sh"
Enter
Wait+Screen@3m /seeded: paired device/
Type "clear"
Enter
Sleep 1s
Show

Type "netclaw daemon pair"
Enter
Sleep 3s
Type "netclaw daemon devices"
Enter
Sleep 3s
Screenshot screenshots/output/daemon-pair.png
Sleep 500ms
