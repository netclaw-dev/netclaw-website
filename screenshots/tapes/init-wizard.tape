# netclaw init: the Personal walkthrough on 0.27.1 (provider, identity, security posture, health check)
# stack: fresh
# Runs against the first-run daemon (empty ~/.netclaw) with the stack's local Ollama on
# localhost:11434 (qwen2:0.5b, the stack's default). Nothing private is involved.
#
# The header reads "Step N of 5" until a posture is chosen, then "Step 4 of 4" for Personal.
# That is what 0.27.1 prints, so the provider, identity and posture images say "of 5" and the
# health check says "of 4".
#
# Produces: init-01-provider-list, init-01-endpoint, init-01-provider-ollama, init-01-model-select,
# init-02-identity, init-02-security-posture, init-05-health-check.
Output screenshots/output/init-wizard.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 520
Set Padding 20
Set TypingSpeed 40ms

Type "netclaw init"
Enter
Sleep 3s

# Provider list: eight entries
Screenshot screenshots/output/init-01-provider-list.png
Sleep 500ms

# 4 = Ollama: its endpoint step
Type "4"
Sleep 1500ms
Screenshot screenshots/output/init-01-provider-ollama.png
Sleep 500ms
Escape
Sleep 800ms
Escape
Sleep 1s

# 6 = OpenAI-compatible: the endpoint field arrives pre-filled with http://localhost:11434, which
# is the stack's Ollama (it serves the OpenAI-compatible API too), so the wizard carries on with it.
Type "6"
Sleep 1500ms
Screenshot screenshots/output/init-01-endpoint.png
Sleep 500ms

# Accept the endpoint, skip the optional API key, wait for the connectivity check and model discovery
Enter
Sleep 1500ms
Enter
Sleep 5s
Screenshot screenshots/output/init-01-model-select.png
Sleep 500ms
Enter
Sleep 2s

# Identity: name, style, your name, timezone
Enter
Sleep 1500ms
Screenshot screenshots/output/init-02-identity.png
Sleep 500ms
Enter
Sleep 1s
Type "alice"
Enter
Sleep 1s
Enter
Sleep 2s

# Security posture: Personal is highlighted
Screenshot screenshots/output/init-02-security-posture.png
Sleep 500ms
Enter

# Health check starts on its own and hands over to chat within a couple of seconds
# The finished checklist is on screen for about a second and a half before chat takes over,
# so wait for its last line instead of sleeping a fixed time.
Wait+Screen@60s /Configuration written/
Sleep 200ms
Screenshot screenshots/output/init-05-health-check.png
Sleep 8s
Ctrl+Q
Sleep 1s
