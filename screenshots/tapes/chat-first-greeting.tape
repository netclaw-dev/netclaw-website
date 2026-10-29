# stack: fresh
# chat-first-greeting.png: the chat that `netclaw init` hands off to, with the agent's
# greeting and first question. Walks the real wizard (OpenAI-compatible provider, Personal
# posture) against the stack's inference endpoint; the wizard steps are not part of the image.
Set Shell "bash"
Set WaitTimeout 300s
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 600
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "netclaw init"
Enter
Sleep 4s
Type "6"
Sleep 2s
Backspace 30
Type "http://llm.example.internal:8081"
Sleep 500ms
Enter
Sleep 2s
Enter
Wait+Screen@60s /Select a model/
Enter
Sleep 2s
Enter
Sleep 2s
Enter
Sleep 2s
Type "Sam"
Enter
Sleep 2s
Enter
Sleep 2s
Enter
Wait+Screen@240s /Netclaw Chat/
Wait+Screen@300s /Ready +\| +demo-model/
Sleep 2s
Show
Screenshot screenshots/output/chat-first-greeting.png
Sleep 2s
