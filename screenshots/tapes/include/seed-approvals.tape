# Shared by approvals-list.tape and approvals-tui.tape (VHS `Source`). Everything between
# Hide and Show is not recorded. Builds the grants the approvals images show, through the
# real CLI and real prompt answers: two trust-verb grants, an MCP grant, a team grant, and
# a folder ("Always here") and a repository ("This repository") grant answered in the chat TUI.
Hide
Type "bash screenshots/scripts/seed-projects.sh && cd ~/projects/website && clear"
Enter
Sleep 2s
Type "netclaw approvals trust-verb 'git push' && netclaw approvals trust-verb gh && netclaw approvals trust-verb 'npm run' --audience team && netclaw approvals trust-verb demo-utilities/calculate --tool demo-utilities/calculate; echo SE''EDED"
Enter
Wait+Screen@60s /SEEDED/
Type "clear"
Enter
Sleep 1s

Type "netclaw chat"
Enter
Sleep 3s
Type "Call set_working_directory with /home/netclaw/projects/website, then stop. Run nothing else and ask me nothing."
Enter
Wait+Screen@240s /set_working_directory . \/home\/netclaw\/projects/
Wait+Screen@240s /Ready +\| +demo-model/
Sleep 1s
Type "Now use shell_execute to run exactly: npm run build"
Enter
Wait+Screen@240s /6\. Deny/
Sleep 1s
Type "3"
Wait+Screen@240s /Ready +\| +demo-model/
Sleep 1s
Type "Now use shell_execute to run exactly: make test"
Enter
Wait+Screen@240s /6\. Deny/
Sleep 1s
Type "4"
Wait+Screen@240s /Ready +\| +demo-model/
Sleep 1s
Ctrl+Q
Sleep 2s
Type "clear"
Enter
Sleep 1s
Show
