# reminder.gif: the Reminder Builder from the first step to Create, about 15 seconds.
# reminder-builder-review.png: the review step, taken just before Create.
# The recording starts inside the builder (the launch is hidden) and ends on the result.
Output screenshots/output/reminder.gif

Set Shell "bash"
Set WaitTimeout 60s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 440
Set Padding 20
Set TypingSpeed 45ms

Hide
Type "netclaw reminder ui"
Enter
Wait+Screen /Step 1 of 6/
Show

Sleep 300ms
Type "daily-uptime-check"
Sleep 600ms
Enter
Sleep 1200ms
Down
Sleep 400ms
Down
Sleep 600ms
Enter
Sleep 1200ms
Type "0 9 * * *"
Sleep 600ms
Enter
Sleep 1200ms
Type "Check that the website and API respond."
Sleep 600ms
Enter
Sleep 1200ms
Enter
Wait+Screen /Step 6 of 6/
Sleep 1500ms
Screenshot screenshots/output/reminder-builder-review.png
Sleep 2s
Enter
Sleep 2500ms
