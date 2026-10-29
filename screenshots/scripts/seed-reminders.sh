#!/bin/bash
# Neutral reminders for the reminder tapes: a daily cron reminder and a weekly one.
# Run inside the capture container (talks to the stack's daemon).
set -eu
netclaw reminder create daily-uptime-check cron "0 9 * * *" \
  "Check that the website and API respond, and note anything slower than usual." \
  --name "Daily uptime check" >/dev/null
netclaw reminder create weekly-report cron "CRON_TZ=America/Chicago 0 16 * * FRI" \
  "Summarize this week's completed tasks and open follow-ups in five bullets." \
  --name "Weekly report" >/dev/null
