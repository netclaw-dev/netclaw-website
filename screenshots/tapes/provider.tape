# netclaw provider: the provider manager, and its "add a provider" flow for OpenAI-compatible
# stack: bare
# Three providers with neutral names (scripts/seed-demo-install.sh). my-deepseek has a dummy key, so
# it shows the warning glyph. lab-llama is answered by the stack's forwarder when
# INFERENCE_UPSTREAM is set. The Provider column is capped at 40 characters (in builds after
# 0.27.1), so the long OpenAI-compatible label ends in an ellipsis at any width.
#
# Produces provider-manager and provider-add-openai-compatible.
Output screenshots/output/provider.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1100
Set Height 500
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

Type "netclaw provider"
Enter
# Wait for the health probes to settle
Sleep 8s
Up
Up
Sleep 500ms
Screenshot screenshots/output/provider-manager.png
Sleep 500ms

# + Add new provider... > OpenAI-compatible > name > the Endpoint step
Down
Down
Down
Down
Down
Down
Down
Down
Sleep 500ms
Enter
Sleep 2s
Down
Down
Down
Down
Down
Sleep 500ms
Enter
Sleep 2s
Enter
Sleep 2s
Screenshot screenshots/output/provider-add-openai-compatible.png
Sleep 500ms
Ctrl+Q
Sleep 1s
