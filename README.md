GuildUI — Minimal mock implementation

Usage:
- Place the `GuildUI` folder into `Interface/AddOns/` (already here).
- In WoW 3.3.5a, type `/guildui` to toggle the UI.

What this initial version contains:
- `GuildUI.toc` — addon metadata
- `GuildUI.lua` — minimal UI: member list (mock data), search box, details panel and action buttons (mock handlers)

Next steps (proposed):
- Replace mock data with actual guild roster queries (`GetGuildRosterInfo`) and event handling
- Add saved variables for layout/prefs
- Improve styling to match elvUI exact look
- Implement real actions (Invite/Promote/Demote/Kick) with permission checks

If you want — начну интеграцию реального списка гильдии и фильтров сейчас.
 
Deploy notes
------------
If you want the GitHub repository to contain the addon inside a top-level `GuildUI/` folder
(so users can download ZIP from GitHub and drop the `GuildUI` folder into their `Interface\\AddOns`),
use the provided `deploy_nested.ps1` script.

Usage (PowerShell):

```powershell
# run from repository root
.\deploy_nested.ps1
```

The script will copy the working tree into a temporary folder under `GuildUI/`, initialize a git repo there
and force-push it to `origin/main`. This leaves your local working tree unchanged while ensuring the remote
branch contains a top-level `GuildUI` folder.

Important: the script performs a force-push to the remote branch. Be certain you want to overwrite the remote history.
