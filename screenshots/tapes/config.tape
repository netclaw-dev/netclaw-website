# netclaw config: the settings dashboard and the areas the docs show, on the shared demo install
# stack: bare
# scripts/seed-demo-install.sh builds the install every status-like capture shares. 0.27.1 shows
# thirteen rows of the dashboard, all visible in a 520 px terminal.
#
# Produces: config-dashboard, config-retention, config-channels-menu, config-inbound-webhooks, config-skills,
# config-search, config-exposure.
Output screenshots/output/config.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 520
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

Type "netclaw config"
Enter
Sleep 3s
Screenshot screenshots/output/config-dashboard.png
Sleep 500ms

# 11. Data Retention: a fresh install has no Retention key, so the row shows the default
Down
Down
Down
Down
Down
Down
Down
Down
Down
Down
Sleep 400ms
Enter
Sleep 2s
Screenshot screenshots/output/config-retention.png
Escape
Sleep 1s
Up
Up
Up
Up
Up
Up
Up
Up
Up
Up
Sleep 400ms

# 3. Channels
Down
Down
Sleep 400ms
Enter
Sleep 2s
Screenshot screenshots/output/config-channels-menu.png
Escape
Sleep 1s

# 4. Inbound Webhooks
Down
Down
Down
Sleep 400ms
Enter
Sleep 2s
Screenshot screenshots/output/config-inbound-webhooks.png
Escape
Sleep 1s

# 5. Skill Sources
Down
Down
Down
Down
Sleep 400ms
Enter
Sleep 2s
Screenshot screenshots/output/config-skills.png
Escape
Sleep 1s

# 6. Search
Down
Down
Down
Down
Down
Sleep 400ms
Enter
Sleep 2s
Screenshot screenshots/output/config-search.png
Escape
Sleep 1s

# 9. Security & Access > Exposure Mode
Down
Down
Down
Down
Down
Down
Down
Down
Sleep 400ms
Enter
Sleep 1s
Down
Down
Down
Sleep 400ms
Enter
Sleep 2s
Screenshot screenshots/output/config-exposure.png
Escape
Sleep 1s
Escape
Sleep 1s

Ctrl+Q
Sleep 1s
