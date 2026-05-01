# Netclaw Init Wizard - Full walkthrough (Personal + Ollama + DuckDuckGo)
# Requires: Ollama running on localhost:11434 with qwen2:0.5b
# Captures every wizard screen for documentation.
Output screenshots/output/init-full.gif

Set Shell "bash"
Set Theme "Dracula"
Set Width 1200
Set Height 700
Set FontSize 16
Set Padding 20
Set TypingSpeed 50ms

# Clean netclaw home for fresh wizard
Hide
Type "export NETCLAW_HOME=/tmp/netclaw-screenshot-home"
Enter
Sleep 300ms
Type "rm -rf /tmp/netclaw-screenshot-home && mkdir -p /tmp/netclaw-screenshot-home"
Enter
Sleep 300ms
Type "clear"
Enter
Sleep 500ms
Show

# ═══════════════════════════════════════════════
# STEP 1: LLM Provider
# ═══════════════════════════════════════════════

Type "netclaw init"
Enter
Sleep 3s

# Sub-step 0: Provider list (Anthropic highlighted by default)
Screenshot screenshots/output/init-01-provider-list.png
Sleep 300ms

# Move to Ollama and capture
Down
Sleep 300ms
Screenshot screenshots/output/init-01-provider-ollama.png
Sleep 300ms

# Select Ollama
Enter
Sleep 2s

# Sub-step 2: Endpoint input (default http://localhost:11434)
Screenshot screenshots/output/init-01-endpoint.png
Sleep 300ms

# Accept default endpoint
Enter
Sleep 5s

# Sub-step 3/4: Model discovery + selection (qwen2:0.5b found)
Screenshot screenshots/output/init-01-model-select.png
Sleep 300ms

# Select qwen2:0.5b
Enter
Sleep 2s

# ═══════════════════════════════════════════════
# STEP 2: Security Posture
# ═══════════════════════════════════════════════
Screenshot screenshots/output/init-02-security-posture.png
Sleep 300ms

# Select Personal (already highlighted)
Enter
Sleep 2s

# (Feature Selection is SKIPPED for Personal posture)

# ═══════════════════════════════════════════════
# STEP 3: Communication Channels (Channel Picker)
# ═══════════════════════════════════════════════
Screenshot screenshots/output/init-03-channels.png
Sleep 300ms

# Press 'd' to skip channels (done without selecting any)
Type "d"
Sleep 2s

# ═══════════════════════════════════════════════
# STEP 4: Web Search
# ═══════════════════════════════════════════════
Screenshot screenshots/output/init-04-search.png
Sleep 300ms

# Select DuckDuckGo (default, first item)
Enter
Sleep 2s

# ═══════════════════════════════════════════════
# STEP 5: Browser Automation
# ═══════════════════════════════════════════════
Screenshot screenshots/output/init-05-browser.png
Sleep 300ms

# Select "No" (skip browser automation, first item)
Enter
Sleep 2s

# ═══════════════════════════════════════════════
# STEP 6: Identity
# ═══════════════════════════════════════════════

# Sub-step 0: Agent name
Screenshot screenshots/output/init-06-identity-name.png
Sleep 300ms

# Accept default name "Netclaw"
Enter
Sleep 2s

# Sub-step 1: Communication style
Screenshot screenshots/output/init-06-identity-style.png
Sleep 300ms

# Select "Concise & casual" (first item)
Enter
Sleep 2s

# Sub-step 2: User name
Screenshot screenshots/output/init-06-identity-user.png
Sleep 300ms

# Type a name
Type "Aaron"
Sleep 300ms
Enter
Sleep 2s

# Sub-step 3: Timezone
Screenshot screenshots/output/init-06-identity-timezone.png
Sleep 300ms

# Accept default timezone
Enter
Sleep 2s

# Sub-step 4: Workspaces directory
Screenshot screenshots/output/init-06-identity-workspaces.png
Sleep 300ms

# Accept default
Enter
Sleep 2s

# Sub-step 5: Webhook URL (optional)
Screenshot screenshots/output/init-06-identity-webhook.png
Sleep 300ms

# Skip (leave blank)
Enter
Sleep 2s

# ═══════════════════════════════════════════════
# STEP 7: External Skills (conditional - Claude Code detected)
# ═══════════════════════════════════════════════
Screenshot screenshots/output/init-07-external-skills.png
Sleep 300ms

# Accept detected skills and continue
Enter
Sleep 2s

# Sub-step 1: Custom skill directory path (optional)
Screenshot screenshots/output/init-07-custom-skills-path.png
Sleep 300ms

# Skip (leave blank)
Enter
Sleep 2s

# ═══════════════════════════════════════════════
# STEP 8: Skill Feeds
# ═══════════════════════════════════════════════
Screenshot screenshots/output/init-08-skill-feeds.png
Sleep 300ms

# Select "No — skip" (second item)
Down
Sleep 300ms
Enter
Sleep 2s

# ═══════════════════════════════════════════════
# STEP 9: Network Exposure
# ═══════════════════════════════════════════════
Screenshot screenshots/output/init-09-exposure.png
Sleep 300ms

# Select "Local" (first item, recommended)
Enter
Sleep 2s

# Sub-step: Inbound Webhooks toggle
Screenshot screenshots/output/init-09-webhooks.png
Sleep 300ms

# Select "No" (second item)
Down
Sleep 300ms
Enter
Sleep 2s

# ═══════════════════════════════════════════════
# STEP 10: Health Check
# ═══════════════════════════════════════════════
Screenshot screenshots/output/init-10-health-check.png
Sleep 300ms

# Press Enter to start health check
Enter
Sleep 8s

# Capture final health check results
Screenshot screenshots/output/init-10-health-check-complete.png

Sleep 2s
Ctrl+C
