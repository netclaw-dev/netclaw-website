# A netclaw container reaching healthy, as the Docker quick start checks it
# stack: fresh
# host-docker: true
# The only tape that talks to the host's Docker (the capture container gets the socket and the host's
# docker client, see compose/docker-host.yml). It starts its own container from the release image,
# gives it the name the docs use, and every command it prints is filtered to that one container, so
# nothing else on the host appears. Names its container <project>-docker-health while it starts and
# renames it to `netclaw` just before the visible part; the end of the tape removes it (by label, so a container that merely shares the name is never touched).
Output screenshots/output/docker-health.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1600
Set Height 300
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "bash /work/screenshots/scripts/docker-health-up.sh"
Enter
Wait+Screen@3m /container is healthy/
Type "clear"
Enter
Sleep 1s
Show

Type "docker ps --filter name=^netclaw$"
Enter
Sleep 2s
Type "docker inspect --format '{{.State.Health.Status}}' netclaw"
Enter
Sleep 2s
Type "docker exec netclaw netclaw daemon status"
Enter
Sleep 3s
Screenshot screenshots/output/docker-health.png
Sleep 500ms

Hide
Type "bash /work/screenshots/scripts/docker-health-down.sh"
Enter
Sleep 5s
Show
