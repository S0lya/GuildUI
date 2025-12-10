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
