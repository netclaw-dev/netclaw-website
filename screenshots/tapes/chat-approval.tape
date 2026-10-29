# Chat approval prompts: chat-approval-prompt.png (getting-started: home directory, five options),
# chat-tui-approval-prompt.png (cli/chat) and approval-prompt-tui.png (security/approvals). The last
# two run in the demo repository /home/netclaw/projects/website so all six options are offered.
# The session is idle at the prompt when the image is taken, so nothing is answered.
Set Shell "bash"
Set WaitTimeout 240s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 540
Set Padding 20
Set TypingSpeed 40ms

# First image: the getting-started prompt, run from the home directory (no repository), so the
# prompt offers five options, exactly as the tutorial's text block says.
Type "netclaw chat"
Enter
Sleep 3s
Type "Use curl to download https://example.com and save it as ~/example.html, then tell me how many bytes it is."
Enter
Wait+Screen@240s /5\. Deny/
Sleep 1s
Screenshot screenshots/output/chat-approval-prompt.png
Sleep 2s
Ctrl+Q
Sleep 2s

# The other two run inside the demo repository.
Hide
Type "bash screenshots/scripts/seed-projects.sh && cd ~/projects/website && clear"
Enter
Sleep 4s
Show

Type "netclaw chat"
Enter
Sleep 3s
Type "Set the working directory to /home/netclaw/projects/website, then use shell_execute to run exactly: npm run build"
Enter
Wait+Screen@240s /6\. Deny/
Sleep 1s
Screenshot screenshots/output/chat-tui-approval-prompt.png
Sleep 2s
Ctrl+Q
Sleep 2s

Hide
Type "clear"
Enter
Show
Type "netclaw chat"
Enter
Sleep 3s
Type "Set the working directory to /home/netclaw/projects/website, then use shell_execute to run exactly: git push origin main"
Enter
Wait+Screen@240s /6\. Deny/
Sleep 1s
Screenshot screenshots/output/approval-prompt-tui.png
Sleep 2s
Ctrl+Q
Sleep 2s
