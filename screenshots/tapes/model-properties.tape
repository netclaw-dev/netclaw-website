# model-properties.png: press P on Main in `netclaw model` to open the Model properties panel.
# stack: bare
# Same demo install as model.tape. lab-llama gets ThinkingDialect ReasoningEffort so the thinking
# level field is editable, as it is for a provider that offers it.
Output screenshots/output/model-properties.gif

Set Shell "bash"
Set Theme "Dracula"
Set FontSize 16
Set Width 1000
Set Height 460
Set Padding 20
Set TypingSpeed 40ms

Hide
Type "bash /work/screenshots/scripts/seed-demo-install.sh"
Enter
Wait+Screen@8m /seeded: demo install/
Type `python3 -c "import json,os;p=os.path.expanduser('~/.netclaw/config/netclaw.json');c=json.load(open(p));c['Providers']['lab-llama'].setdefault('VendorOptions',{})['ThinkingDialect']='ReasoningEffort';json.dump(c,open(p,'w'),indent=2)"`
Enter
Sleep 8s
Type "clear"
Enter
Sleep 1s
Show

Type "netclaw model"
Enter
Sleep 4s
Type "p"
Sleep 5s
Screenshot screenshots/output/model-properties.png
Sleep 500ms
Ctrl+Q
Sleep 1s
