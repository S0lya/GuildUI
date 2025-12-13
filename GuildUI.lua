-- GuildUI.lua (minimal mock implementation for WoW 3.3.5a)
-- Simple UI skeleton: member list, details, action buttons

local GuildUI = {}
-- Enable debug prints to chat for diagnosing note/roster issues
-- GuildUI.debug = true

-- CreateFont wrapper: support both the Blizzard API `CreateFont(name)` and
-- project convenience calls `CreateFont(parent, size, r, g, b, outline)`.
do
  local origCreateFont = _G.CreateFont
  _G.CreateFont = function(parentOrName, size, r, g, b, outline)
    -- If called with a single string, delegate to original API
    if type(parentOrName) == "string" and (size == nil) then
      if type(origCreateFont) == "function" then
        return origCreateFont(parentOrName)
      end
      return nil
    end
    -- Otherwise create a FontString on the provided parent (or UIParent)
    local parent = parentOrName
    if not parent or type(parent.CreateFontString) ~= "function" then
      parent = UIParent
    end
    local fs = parent:CreateFontString(nil, "OVERLAY")
    local fontPath = "Fonts\\FRIZQT__.TTF"
    local fsize = tonumber(size) or 11
    local flags = ""
    if outline then flags = "OUTLINE" end
    if fs.SetFont then pcall(function() fs:SetFont(fontPath, fsize, flags) end) end
    if r and g and b and fs.SetTextColor then pcall(function() fs:SetTextColor(r, g, b) end) end
    return fs
  end
end

-- CreateButton helper: Create a standard button using UIPanelButtonTemplate.
if not _G.CreateButton then
  _G.CreateButton = function(parent, name, text, width, height)
    parent = parent or UIParent
    local b
    if name and type(name) == "string" then
      b = CreateFrame("Button", name, parent, "UIPanelButtonTemplate")
    else
      b = CreateFrame("Button", nil, parent, "UIPanelButtonTemplate")
    end
    if width and height then b:SetSize(width, height) end
    if text and type(text) == "string" then
      if b.SetText then pcall(function() b:SetText(text) end) end
    end
    return b
  end
end

-- SavedVariables fallback table (declared in .toc as GuildUILocalNotes)
-- Format: GuildUILocalNotes[realm][name] = { public = "...", officer = "..." }
if not GuildUILocalNotes then GuildUILocalNotes = {} end
-- local last-seen cache (client-side). To persist between sessions, add `GuildUILastSeen` to the .toc SavedVariables.
if not GuildUILastSeen then GuildUILastSeen = {} end
-- lightweight realm detector used early during file load (avoids calling GetRealm before it's defined)
-- members left panel is handled by members.lua (CreateMembersUI)

-- ResolveClassToken: try to map a localized/class display name to a class token (e.g. "WARRIOR").
local function ResolveClassToken(name)
  if not name then return nil end
  local lname = tostring(name):lower()
  -- 1) If the name already looks like an English token, return uppercased token
  if tostring(name):match("^[%w_]+$") then
    local cand = tostring(name):gsub("%s+", ""):upper()
    -- prefer tokens that exist in RAID_CLASS_COLORS
    if RAID_CLASS_COLORS and RAID_CLASS_COLORS[cand] then return cand end
  end
  -- 2) Try RAID_CLASS_COLORS keys (tokens) for a localized match via GetClassInfo or localized tables
  local tokens = { "WARRIOR","PALADIN","HUNTER","ROGUE","PRIEST","DEATHKNIGHT","SHAMAN","MAGE","WARLOCK","DRUID" }
  for _, token in ipairs(tokens) do
    -- try GetClassInfo(token) -> localized name (works on many clients)
    if type(GetClassInfo) == "function" then
      local loc = select(1, GetClassInfo(token))
      if loc and tostring(loc):lower() == lname then return token end
    end
    -- try localized tables if present
    if _G.LOCALIZED_CLASS_NAMES_MALE and _G.LOCALIZED_CLASS_NAMES_MALE[token] then
      if tostring(_G.LOCALIZED_CLASS_NAMES_MALE[token]):lower() == lname then return token end
    end
    if _G.LOCALIZED_CLASS_NAMES_FEMALE and _G.LOCALIZED_CLASS_NAMES_FEMALE[token] then
      if tostring(_G.LOCALIZED_CLASS_NAMES_FEMALE[token]):lower() == lname then return token end
    end
  end
  -- 3) As a last resort, try matching any key in RAID_CLASS_COLORS by comparing values
  if RAID_CLASS_COLORS then
    for token, col in pairs(RAID_CLASS_COLORS) do
      if token and tostring(token):lower() == lname then return token end
    end
  end
  -- no reliable mapping found
  return nil
end

-- GetClassColorByName: return r,g,b for a given class display name or token
local function GetClassColorByName(className)
  if not className then return 1,1,1 end
  local token = ResolveClassToken(className)
  -- try RAID_CLASS_COLORS first
  if token and RAID_CLASS_COLORS and RAID_CLASS_COLORS[token] then
    local c = RAID_CLASS_COLORS[token]
    if c.r and c.g and c.b then return c.r, c.g, c.b end
    if c[1] and c[2] and c[3] then return c[1], c[2], c[3] end
  end
  -- manual fallback palette (approximate)
  local FALLBACK = {
    WARRIOR = {0.78, 0.61, 0.43},
    PALADIN = {0.96, 0.55, 0.73},
    HUNTER = {0.67, 0.83, 0.45},
    ROGUE = {1.00, 0.96, 0.41},
    PRIEST = {1.00, 1.00, 1.00},
    DEATHKNIGHT = {0.77, 0.12, 0.23},
    SHAMAN = {0.00, 0.44, 0.87},
    MAGE = {0.25, 0.78, 0.92},
    WARLOCK = {0.53, 0.53, 0.93},
    DRUID = {1.00, 0.49, 0.04},
  }
  local k = token or tostring(className):gsub("%s+", ""):upper()
  if k and FALLBACK[k] then
    local t = FALLBACK[k]
    return t[1], t[2], t[3]
  end
  return 1,1,1
end

-- expose helpers to the module scope so other code can call them
GuildUI.ResolveClassToken = ResolveClassToken
GuildUI.GetClassColorByName = GetClassColorByName
-- Also expose as globals so other modules (members.lua) can call them directly
_G.ResolveClassToken = ResolveClassToken
_G.GetClassColorByName = GetClassColorByName

-- Local notes persistence helpers (SavedVariables table `GuildUILocalNotes`)
local function GetRealmKey()
  if type(GetRealmName) == "function" then
    return GetRealmName() or "unknown"
  elseif type(GetRealm) == "function" then
    return GetRealm() or "unknown"
  end
  return "unknown"
end

local function LoadLocalNotes(name)
  if not name then return nil, nil end
  if not GuildUILocalNotes then GuildUILocalNotes = {} end
  local realm = GetRealmKey()
  if not GuildUILocalNotes[realm] then return nil, nil end
  local rec = GuildUILocalNotes[realm][name]
  if not rec then return nil, nil end
  return rec.public, rec.officer
end

local function SaveLocalNotes(name, publicNote, officerNote)
  if not name then return end
  if not GuildUILocalNotes then GuildUILocalNotes = {} end
  local realm = GetRealmKey()
  GuildUILocalNotes[realm] = GuildUILocalNotes[realm] or {}
  GuildUILocalNotes[realm][name] = GuildUILocalNotes[realm][name] or { public = "", officer = "" }
  local rec = GuildUILocalNotes[realm][name]
  if publicNote ~= nil then rec.public = publicNote end
  if officerNote ~= nil then rec.officer = officerNote end
end

local function ClearLocalPublic(name)
  if not name or not GuildUILocalNotes then return end
  local realm = GetRealmKey()
  if not GuildUILocalNotes[realm] or not GuildUILocalNotes[realm][name] then return end
  GuildUILocalNotes[realm][name].public = nil
end

local function ClearLocalOfficer(name)
  if not name or not GuildUILocalNotes then return end
  local realm = GetRealmKey()
  if not GuildUILocalNotes[realm] or not GuildUILocalNotes[realm][name] then return end
  GuildUILocalNotes[realm][name].officer = nil
end

-- expose these helpers globally for other code
GuildUI.LoadLocalNotes = LoadLocalNotes
GuildUI.SaveLocalNotes = SaveLocalNotes
GuildUI.ClearLocalPublic = ClearLocalPublic
GuildUI.ClearLocalOfficer = ClearLocalOfficer
_G.LoadLocalNotes = LoadLocalNotes
_G.SaveLocalNotes = SaveLocalNotes
_G.ClearLocalPublic = ClearLocalPublic
_G.ClearLocalOfficer = ClearLocalOfficer

-- Last-seen cache helpers (SavedVariables table `GuildUILastSeen`)
local function LoadLastSeen(name)
  if not name then return nil end
  if not GuildUILastSeen then GuildUILastSeen = {} end
  local realm = GetRealmKey()
  if not GuildUILastSeen[realm] then return nil end
  return GuildUILastSeen[realm][name]
end

local function SaveLastSeen(name, ts)
  if not name then return end
  if not GuildUILastSeen then GuildUILastSeen = {} end
  local realm = GetRealmKey()
  GuildUILastSeen[realm] = GuildUILastSeen[realm] or {}
  GuildUILastSeen[realm][name] = ts
end

-- Simple relative time formatter (seconds -> human-friendly string)
local function FormatRelativeTime(ts)
  if not ts or ts == 0 then return "-" end
  local diff = time() - tonumber(ts)
  if diff < 60 then return tostring(diff) .. " сек" end
  if diff < 3600 then return tostring(math.floor(diff/60)) .. " мин" end
  if diff < 86400 then return tostring(math.floor(diff/3600)) .. " час" end
  return tostring(math.floor(diff/86400)) .. " дн"
end

GuildUI.LoadLastSeen = LoadLastSeen
GuildUI.SaveLastSeen = SaveLastSeen
GuildUI.FormatRelativeTime = FormatRelativeTime
_G.LoadLastSeen = LoadLastSeen
_G.SaveLastSeen = SaveLastSeen
_G.FormatRelativeTime = FormatRelativeTime

-- Try to read the built-in Blizzard guild roster UI row for a given roster index.
-- Returns a string to display (e.g. "в сети" or "4 часа") or nil if unavailable.
local function ReadGuildFrameLastSeen(rosterIndex)
  if not rosterIndex then return nil end
  -- Try multiple known button name prefixes and scrollframe globals to map rosterIndex
  local prefixes = { "GuildRosterContainerButton", "GuildRosterButton", "GuildFrameGuildListButton", "GuildFrameButton", "GuildListButton" }
  local scrollCandidates = { "GuildRosterContainer", "GuildFrameGuildList", "GuildFrame", "GuildListScrollFrame", "GuildList" }
  local tried = {}
  -- First, try to use known scrollframes to compute an offset
  for _, scn in ipairs(scrollCandidates) do
    local sf = _G[scn]
    if sf and FauxScrollFrame_GetOffset then
      local offset = FauxScrollFrame_GetOffset(sf) or 0
      local visibleIndex = rosterIndex - (offset or 0)
      if visibleIndex and visibleIndex >= 1 and visibleIndex <= 40 then
        for _, pref in ipairs(prefixes) do
          local btn = _G[pref..tostring(visibleIndex)]
          if btn then
            local regions = { btn:GetRegions() }
            for _, r in ipairs(regions) do
              if r and type(r.GetText) == "function" then
                local txt = r:GetText()
                if txt and txt ~= "" then
                  local low = tostring(txt):lower()
                  if string.find(low, "в сети") or string.find(low, "сек") or string.find(low, "мин") or string.find(low, "час") or string.find(low, "дн") or string.find(low, "посл") then
                    return txt
                  end
                end
              end
            end
          end
        end
      end
    end
    table.insert(tried, scn)
  end
  -- Fallback: brute-force visible button names across prefixes
  for vi = 1, 40 do
    for _, pref in ipairs(prefixes) do
      local btn = _G[pref..tostring(vi)]
      if btn then
        local regions = { btn:GetRegions() }
        for _, r in ipairs(regions) do
          if r and type(r.GetText) == "function" then
            local txt = r:GetText()
            if txt and txt ~= "" then
              local low = tostring(txt):lower()
              if string.find(low, "в сети") or string.find(low, "сек") or string.find(low, "мин") or string.find(low, "час") or string.find(low, "дн") or string.find(low, "посл") then
                return txt
              end
            end
          end
        end
      end
    end
  end
  return nil
end

function GuildUI:CreateUI()
  if self.frame then return end
  if self._creating then
    return
  end
  self._creating = true

  local f = CreateFrame("Frame", "GuildUIFrame", UIParent)
  f:SetSize(480, 440)
  -- anchor to left edge of the screen instead of centering
  f:SetPoint("LEFT", UIParent, "LEFT", 40, 0)
  f:EnableMouse(true)
  f:SetMovable(true)
  f:RegisterForDrag("LeftButton")
  f:SetScript("OnDragStart", function(self) self:StartMoving() end)
  f:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  -- Backdrop (dialog style)
    f:SetBackdrop({
      -- use only border here; background texture is a dedicated texture below
      edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
      tile = false, tileSize = 0, edgeSize = 16,
      -- increase insets by 3px so the border/outline appears 3px larger
      insets = { left = 14, right = 14, top = 14, bottom = 14 }
    })
  -- make backdrop fully transparent (we use f.bgTexture for the visible background)
  f:SetBackdropColor(0,0,0,0)

  -- Add a dedicated background texture (more reliable than backdrop bgFile)
  f.bgTexture = f:CreateTexture(nil, "BACKGROUND")
  f.bgTexture:SetTexture("Interface\\AddOns\\GuildUI\\media\\background\\background.blp")
  -- inset the background texture so it doesn't overlap the widened border
  local inset = 6
  f.bgTexture:SetPoint("TOPLEFT", f, "TOPLEFT", inset, -inset)
  f.bgTexture:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -inset, inset)
  -- ensure the background texture is on the lowest draw sublayer
  f.bgTexture:SetDrawLayer("BACKGROUND", -8)
  f.bgTexture:SetAlpha(1)

  -- Title (bigger, bronze color with black outline/shadow)
  local title = CreateFont(f, 18, 0.62, 0.44, 0.18, true)
  title:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -12)
  -- use a more decorative Blizzard font if available (Morpheus), keep bronze color
  if title.SetFont then title:SetFont("Fonts\\MORPHEUS.ttf", 20, "OUTLINE") end
  -- ensure a solid black outline/shadow for readability
  if title.SetShadowColor then title:SetShadowColor(0,0,0,1) end
  if title.SetShadowOffset then title:SetShadowOffset(1, -1) end
  -- expose title so other modules can update it (e.g. UpdateMembers)
  self.title = title
  -- show guild name when available, otherwise fallback to addon name
  local gname = nil
  if IsInGuild and IsInGuild() and GetGuildInfo then
    gname = GetGuildInfo("player")
  end
  local close = CreateFrame("Button", nil, f, "UIPanelCloseButton")
  close:SetPoint("TOPRIGHT", f, "TOPRIGHT", -6, -6)
  close:SetScript("OnClick", function()
    -- Hide overlay/shield/back button when main frame is closed
    if GuildUI and GuildUI.manageOverlay then
      local mp = GuildUI.manageOverlay
      if mp.shield then mp.shield:Hide() end
      if mp.backBtn then mp.backBtn:Hide() end
      mp:Hide()
    end
    f:Hide()
  end)
  -- Online/total counter under the guild name (title)
  local countFS = CreateFont(f, 11, 1, 1, 1)
  countFS:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -37)
  countFS:SetText("Онлайн: 0/0")
  if countFS.SetShadowColor then countFS:SetShadowColor(0,0,0,1) end
  self.countFS = countFS

  -- Small launcher button to open a top invite popup
  local topInviteLauncher = CreateButton(f, "GuildUI_TopInviteLauncher", "Пригл", 48, 20)
  topInviteLauncher:SetPoint("TOPRIGHT", f, "TOPRIGHT", -14, -26)
  topInviteLauncher:SetNormalFontObject("GameFontNormalSmall")
  self.topInviteLauncher = topInviteLauncher

  -- Create the top-invite popup (hidden by default)
  local function CreateTopInvitePopup()
    if GuildUI.topInvitePopup then return GuildUI.topInvitePopup end
    local pf = CreateFrame("Frame", "GuildUI_TopInvitePopup", f, "BackdropTemplate")
    pf:SetSize(260, 56)
    pf:SetPoint("TOP", f, "TOP", 0, -28)
    -- keep a border/backdrop for the frame but use a custom background texture
    pf:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 8, insets = { left = 2, right = 2, top = 2, bottom = 2 } })
    pf:SetBackdropColor(0,0,0,0)
    -- dedicated background texture using our media background (background2.blp)
    pf.bgTexture = pf:CreateTexture(nil, "BACKGROUND")
    pf.bgTexture:SetTexture("Interface\\AddOns\\GuildUI\\media\\background\\background2.blp")
    -- inset the texture so it doesn't overlap the frame border
    -- reduce inset from 6 -> 2 so the background expands 4px on each side
    local pinset = 2
    pf.bgTexture:SetPoint("TOPLEFT", pf, "TOPLEFT", pinset, -pinset)
    pf.bgTexture:SetPoint("BOTTOMRIGHT", pf, "BOTTOMRIGHT", -pinset, pinset)
    pf.bgTexture:SetDrawLayer("BACKGROUND", -2)
    pf.bgTexture:SetAlpha(1)
    pf:EnableMouse(true)
    pf:SetFrameStrata("DIALOG")

    local ed = CreateFrame("EditBox", nil, pf, "InputBoxTemplate")
    ed:SetSize(160, 22)
    ed:SetPoint("LEFT", pf, "LEFT", 10, 0)
    ed:SetAutoFocus(false)
    ed:SetText("Ник игрока")
    ed:SetScript("OnEditFocusGained", function(self) if self:GetText() == "Ник игрока" then self:SetText("") end end)
    ed:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then self:SetText("Ник игрока") end end)
    ed:SetScript("OnEscapePressed", function(self) pf:Hide() end)
    pf.edit = ed

    -- Title
    local titleText = pf:CreateFontString(nil, "OVERLAY")
    titleText:SetFont("Fonts\\FRIZQT__.TTF", 12, "OUTLINE")
    titleText:SetPoint("TOP", pf, "TOP", 0, -8)
    titleText:SetText("Пригласить игрока в гильдию")
    titleText:SetTextColor(1, 0.82, 0, 1)

    local inviteBtn = CreateButton(pf, nil, "Пригласить", 100, 22)
    inviteBtn:SetPoint("RIGHT", pf, "RIGHT", -30, 0)
    inviteBtn:SetScript("OnClick", function()
      local txt = (ed:GetText() or ""):gsub("^%s+",""):gsub("%s+$","")
      if not txt or txt == "" or txt == "Ник игрока" then
        print("[GuildUI] Введите ник для приглашения.")
        return
      end
      if UnitName("player") == txt then print("[GuildUI] Нельзя приглашать себя.") return end
      InviteUnit(txt)
      print("[GuildUI] Приглашение отправлено: "..txt)
      pf:Hide()
    end)

    -- (removed compact cancel button to simplify UI)

    pf:Hide()
    GuildUI.topInvitePopup = pf
    return pf
  end

  topInviteLauncher:SetScript("OnClick", function()
    local popup = CreateTopInvitePopup()
    if popup:IsShown() then
      popup:Hide()
    else
      popup:Show()
      if popup.edit then popup.edit:SetFocus() end
    end
  end)


  -- Left panel (member list)
  -- Separated into members.lua module
  if not self.CreateMembersUI then
    print("[GuildUI] ERROR: members module not loaded (CreateMembersUI missing)")
  else
    self:CreateMembersUI(f)
  end
  -- members left panel is created in members.lua and stored to `self.left`.
  local left = self.left
  if not left then
    print("[GuildUI] ERROR: CreateMembersUI did not set self.left")
    left = CreateFrame("Frame", nil, f)
    left:SetSize(312, 378)
    left:SetPoint("TOPLEFT", f, "TOPLEFT", 16, -46)
    self.left = left
  end

  -- UpdateList implemented in members.lua

  -- Right panel (details / actions)
  local right = CreateFrame("Frame", nil, f)
  -- make right panel match left panel height for consistent margins
  right:SetSize(136, 378)
  right:SetPoint("TOPRIGHT", f, "TOPRIGHT", -16, -46)
  right.bg = CreateFrame("Frame", nil, right)
  right.bg:SetAllPoints(right)
  right.bg:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background" })
  right.bg:SetBackdropColor(0.03,0.03,0.03,0.25)

  local infoTitle = CreateFont(right, 12, 1,1,1, true)
  infoTitle:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -8)
  infoTitle:SetText("Инфо игрока")

  local nameFS = CreateFont(right, 13, 1,1,1)
  nameFS:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -30)
  nameFS:SetText("—")
  right.nameFS = nameFS

  local classFS = CreateFont(right, 11, 0.9,0.9,0.9)
  classFS:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -48)
  classFS:SetText("")
  right.classFS = classFS
  -- icon for class in right details panel
  right.classIcon = right:CreateTexture(nil, "OVERLAY")
  right.classIcon:SetSize(18, 18)
  right.classIcon:SetPoint("LEFT", classFS, "RIGHT", 8, 0)

  local rankFS = CreateFont(right, 11, 0.8,0.8,0.8)
  -- increase vertical gap between Rank and Class (reduced to be smaller)
  rankFS:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -62)
  rankFS:SetText("")
  right.rankFS = rankFS

    local pubNoteFS = CreateFont(right, 11, 1,1,1)
  pubNoteFS:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -98)
  pubNoteFS:SetWidth(120)
  if pubNoteFS.SetWordWrap then pubNoteFS:SetWordWrap(true) end
  if pubNoteFS.SetJustifyH then pubNoteFS:SetJustifyH("LEFT") end
  if pubNoteFS.SetJustifyV then pubNoteFS:SetJustifyV("TOP") end
  pubNoteFS:SetText("(нет)")
  right.pubNoteFS = pubNoteFS
    local offNoteFS = CreateFont(right, 11, 1,1,1)
  offNoteFS:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -152)
  offNoteFS:SetWidth(120)
  if offNoteFS.SetWordWrap then offNoteFS:SetWordWrap(true) end
  if offNoteFS.SetJustifyH then offNoteFS:SetJustifyH("LEFT") end
  if offNoteFS.SetJustifyV then offNoteFS:SetJustifyV("TOP") end
  offNoteFS:SetText("(нет)")
  right.offNoteFS = offNoteFS

  -- Editable boxes for notes (single-line) and Save/Cancel buttons
  local pubEdit = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
  pubEdit:SetSize(120, 22)
  pubEdit:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -98)
  pubEdit:Hide()
  right.pubEdit = pubEdit

  local pubSave = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
  pubSave:SetSize(50, 20)
  pubSave:SetPoint("TOPLEFT", right, "TOPLEFT", 8+124, -98)
  pubSave:SetText("Сохранить")
  pubSave:Hide()

  local pubCancel = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
  pubCancel:SetSize(40, 20)
  pubCancel:SetPoint("TOPLEFT", right, "TOPLEFT", 8+124+56, -98)
  pubCancel:SetText("Отмена")
  pubCancel:Hide()

  local offEdit = CreateFrame("EditBox", nil, right, "InputBoxTemplate")
  offEdit:SetSize(120, 22)
  offEdit:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -152)
  offEdit:Hide()
  right.offEdit = offEdit

  local offSave = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
  offSave:SetSize(50, 20)
  offSave:SetPoint("TOPLEFT", right, "TOPLEFT", 8+124, -152)
  offSave:SetText("Сохранить")
  offSave:Hide()

  local offCancel = CreateFrame("Button", nil, right, "UIPanelButtonTemplate")
  offCancel:SetSize(40, 20)
  offCancel:SetPoint("TOPLEFT", right, "TOPLEFT", 8+124+56, -152)
  offCancel:SetText("Отмена")
  offCancel:Hide()

    -- expose right panel so other methods (outside CreateUI) can update it
    self.right = right
  -- Helper to toggle edit mode visibility
  local function ShowPubEdit(show)
    if show then
      pubEdit:Show(); pubSave:Show(); pubCancel:Show(); pubNoteFS:Hide()
    else
      pubEdit:Hide(); pubSave:Hide(); pubCancel:Hide(); pubNoteFS:Show()
    end
  end
  local function ShowOffEdit(show)
    if show then
      offEdit:Show(); offSave:Show(); offCancel:Show(); offNoteFS:Hide()
    else
      offEdit:Hide(); offSave:Hide(); offCancel:Hide(); offNoteFS:Show()
    end
  end

  -- Make the note labels clickable: replace static labels with button-like controls
  local pubLabelBtn = CreateFrame("Button", nil, right)
  pubLabelBtn:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -80)
  pubLabelBtn:SetSize(120, 18)
  pubLabelBtn.text = pubLabelBtn:CreateFontString(nil, "OVERLAY")
  pubLabelBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  pubLabelBtn.text:SetPoint("LEFT", pubLabelBtn, "LEFT", 0, 0)
  pubLabelBtn.text:SetText("Заметка:")
  pubLabelBtn:SetScript("OnClick", function()
    GuildUI:OpenNoteEditor("public")
  end)

  local offLabelBtn = CreateFrame("Button", nil, right)
  offLabelBtn:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -134)
  offLabelBtn:SetSize(160, 18)
  offLabelBtn.text = offLabelBtn:CreateFontString(nil, "OVERLAY")
  offLabelBtn.text:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  offLabelBtn.text:SetPoint("LEFT", offLabelBtn, "LEFT", 0, 0)
  offLabelBtn.text:SetText("Заметка офицера:")
  offLabelBtn:SetScript("OnClick", function()
    GuildUI:OpenNoteEditor("officer")
  end)

  -- Cancel handlers restore previous text
  pubCancel:SetScript("OnClick", function()
    pubEdit:SetText(right.pubNoteFS:GetText())
    ShowPubEdit(false)
  end)
  offCancel:SetScript("OnClick", function()
    offEdit:SetText(right.offNoteFS:GetText())
    ShowOffEdit(false)
  end)

  -- Save handlers: use GuildRosterSetPublicNote / GuildRosterSetOfficerNote if available
  pubSave:SetScript("OnClick", function()
    local idx = GuildUI.selected
    if not idx then print("[GuildUI] Выберите участника сначала.") return end
    local m = GuildUI.members[idx]
    if not m or not m.rosterIndex then print("[GuildUI] Не могу найти индекс ростера.") return end
    local text = pubEdit:GetText() or ""
    if type(GuildRosterSetPublicNote) == "function" then
      GuildRosterSetPublicNote(m.rosterIndex, text)
      print("[GuildUI] Заметка сохранена для: "..m.name)
      GuildRoster()
      ShowPubEdit(false)
    else
      print("[GuildUI] Функция сохранения заметки недоступна в этом клиенте.")
    end
  end)

  offSave:SetScript("OnClick", function()
    local idx = GuildUI.selected
    if not idx then print("[GuildUI] Выберите участника сначала.") return end
    local m = GuildUI.members[idx]
    if not m or not m.rosterIndex then print("[GuildUI] Не могу найти индекс ростера.") return end
    local text = offEdit:GetText() or ""
    if type(GuildRosterSetOfficerNote) == "function" then
      GuildRosterSetOfficerNote(m.rosterIndex, text)
      print("[GuildUI] Заметка офицера сохранена для: "..m.name)
      GuildRoster()
      ShowOffEdit(false)
    else
      print("[GuildUI] Функция сохранения заметки офицера недоступна в этом клиенте.")
    end
  end)

  -- Action buttons
  local inviteBtn = CreateButton(right, "GuildUI_InviteBtn", "В группу", 120, 24)
  inviteBtn:SetPoint("BOTTOMLEFT", right, "BOTTOMLEFT", 8, 8)
  inviteBtn:SetScript("OnClick", function()
    local idx = GuildUI.selected
    if not idx then print("[GuildUI] Выберите участника сначала.") return end
    local target = GuildUI.members[idx]
    if not target or not target.name then return end
    local player = UnitName("player")
    if target.name == player then print("[GuildUI] Нельзя пригласить самого себя.") return end
    InviteUnit(target.name)
    print("[GuildUI] Приглашение отправлено: "..target.name)
  end)

  local promoteBtn = CreateButton(right, "GuildUI_PromoteBtn", "Повысить", 120, 24)
  promoteBtn:SetScript("OnClick", function()
    -- derive target name from right panel (more robust if selection index is stale)
    local targetName = nil
    if GuildUI and GuildUI.right and GuildUI.right.nameFS and type(GuildUI.right.nameFS.GetText) == "function" then
      targetName = GuildUI.right.nameFS:GetText()
    end
    if not targetName or targetName == "-" or targetName == "—" or targetName == "" then
      local idx = GuildUI.selected
      if not idx then print("[GuildUI] Выберите участника сначала.") return end
      local target = GuildUI.members[idx]
      if not target or not target.name then return end
      targetName = target.name
    end
    -- strip realm suffix if present
    targetName = tostring(targetName)
    targetName = string.match(targetName, "([^%-]+)") or targetName
    local player = UnitName("player")
    if targetName == player then print("[GuildUI] Нельзя повышать себя.") return end
    -- remember to restore selection to this target after roster updates
    GuildUI.pendingRestore = targetName
    GuildPromote(targetName)
    print("[GuildUI] Повышение: "..targetName)
    -- Force a roster refresh
    if type(GuildRoster) == "function" then GuildRoster() end
  end)

  local demoteBtn = CreateButton(right, "GuildUI_DemoteBtn", "Понизить", 120, 24)
    demoteBtn:SetPoint("BOTTOMLEFT", inviteBtn, "TOPLEFT", 0, 6)
  demoteBtn:SetScript("OnClick", function()
    -- derive target name from right panel (fallback to selected index)
    local targetName = nil
    if GuildUI and GuildUI.right and GuildUI.right.nameFS and type(GuildUI.right.nameFS.GetText) == "function" then
      targetName = GuildUI.right.nameFS:GetText()
    end
    if not targetName or targetName == "-" or targetName == "—" or targetName == "" then
      local idx = GuildUI.selected
      if not idx then print("[GuildUI] Выберите участника сначала.") return end
      local target = GuildUI.members[idx]
      if not target or not target.name then return end
      targetName = target.name
    end
    targetName = tostring(targetName)
    targetName = string.match(targetName, "([^%-]+)") or targetName
    local player = UnitName("player")
    if targetName == player then print("[GuildUI] Нельзя понижать себя.") return end
    GuildUI.pendingRestore = targetName
    GuildDemote(targetName)
    print("[GuildUI] Понижение: "..targetName)
    if type(GuildRoster) == "function" then GuildRoster() end
  end)

  -- Now that demoteBtn exists, anchor promoteBtn above it so both are visible
  promoteBtn:SetPoint("BOTTOMLEFT", demoteBtn, "TOPLEFT", 0, 6)

  local kickBtn = CreateButton(right, "GuildUI_KickBtn", "Исключить", 120, 24)
  -- place Kick above Promote so buttons stack: Invite -> Demote -> Promote -> Kick
  kickBtn:SetPoint("BOTTOMLEFT", promoteBtn, "TOPLEFT", 0, 6)
  kickBtn:SetScript("OnClick", function()
    local idx = GuildUI.selected
    if not idx then print("[GuildUI] Выберите участника сначала.") return end
    local target = GuildUI.members[idx]
    if not target or not target.name then return end
    local player = UnitName("player")
    if target.name == player then print("[GuildUI] Нельзя исключить самого себя.") return end
    -- Directly uninvite; the client will enforce permissions
    GuildUninvite(target.name)
    print("[GuildUI] Исключение: "..target.name)
  end)

  -- Management button (placeholder) - shows overlay panel (functionality to be added later)
  local manageBtn = CreateButton(right, "GuildUI_ManageBtn", "Управление", 120, 24)
  -- Management button - shows modal edit form for guild MOTD and info
  local manageBtn = CreateButton(right, "GuildUI_ManageBtn", "Управление", 120, 24)
  manageBtn:SetPoint("BOTTOMLEFT", kickBtn, "TOPLEFT", 0, 6)
  manageBtn:SetScript("OnClick", function()
    if not GuildUI._editForm then
      -- Create edit form once
      local form = CreateFrame("Frame", "GuildUI_EditForm", UIParent, "BackdropTemplate")
      form:SetSize(400, 300)
      form:SetPoint("CENTER", UIParent, "CENTER")
      form:SetBackdrop({bgFile = "Interface\\AddOns\\GuildUI\\media\\background\\background2.blp", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = {left = 4, right = 4, top = 4, bottom = 4}})
      form:SetBackdropColor(1, 1, 1, 1)
      form:SetFrameStrata("FULLSCREEN")
      form:SetFrameLevel(100)
      form:EnableMouse(true)
      form:SetMovable(true)
      form:RegisterForDrag("LeftButton")
      form:SetScript("OnDragStart", function(self) self:StartMoving() end)
      form:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)
      
      -- Title
      local title = form:CreateFontString(nil, "OVERLAY", "GameFontNormal")
      title:SetPoint("TOPLEFT", form, "TOPLEFT", 12, -12)
      title:SetText("Управление гильдией")
      
      -- Close button
      local closeBtn = CreateButton(form, nil, "X", 24, 24)
      closeBtn:SetPoint("TOPRIGHT", form, "TOPRIGHT", -8, -8)
      closeBtn:SetScript("OnClick", function() form:Hide() end)
      
      -- MOTD label
      local motdLabel = form:CreateFontString(nil, "OVERLAY")
      motdLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
      motdLabel:SetPoint("TOPLEFT", form, "TOPLEFT", 12, -40)
      motdLabel:SetText("Сообщение дня (MOTD):")
      
      -- MOTD edit
      local motdEdit = CreateFrame("EditBox", nil, form, "BackdropTemplate")
      motdEdit:SetSize(370, 22)
      motdEdit:SetPoint("TOPLEFT", motdLabel, "BOTTOMLEFT", 0, -5)
      motdEdit:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 8, insets = {left = 2, right = 2, top = 2, bottom = 2}})
      motdEdit:SetBackdropColor(0, 0, 0, 0.8)
      motdEdit:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
      motdEdit:SetTextColor(1, 1, 1, 1)
      motdEdit:SetAutoFocus(false)
      motdEdit:SetText(GetGuildRosterMOTD() or "")
      motdEdit:SetTextInsets(6, 6, 3, 3)
      motdEdit:SetMaxLetters(128)
      
      -- Info label
      local infoLabel = form:CreateFontString(nil, "OVERLAY")
      infoLabel:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
      infoLabel:SetPoint("TOPLEFT", motdEdit, "BOTTOMLEFT", 0, -15)
      infoLabel:SetText("Информация о гильдии:")
      
      -- Info edit
      local infoEdit = CreateFrame("EditBox", nil, form, "BackdropTemplate")
      infoEdit:SetSize(370, 22)
      infoEdit:SetPoint("TOPLEFT", infoLabel, "BOTTOMLEFT", 0, -5)
      infoEdit:SetBackdrop({bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 8, insets = {left = 2, right = 2, top = 2, bottom = 2}})
      infoEdit:SetBackdropColor(0, 0, 0, 0.8)
      infoEdit:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
      infoEdit:SetTextColor(1, 1, 1, 1)
      infoEdit:SetAutoFocus(false)
      infoEdit:SetText(GetGuildInfoText() or "")
      infoEdit:SetTextInsets(6, 6, 3, 3)
      infoEdit:SetMaxLetters(500)
      
      -- Save button
      local saveBtn = CreateButton(form, nil, "Сохранить", 100, 24)
      saveBtn:SetPoint("BOTTOMLEFT", form, "BOTTOMLEFT", 12, 12)
      saveBtn:SetScript("OnClick", function()
        if GuildSetMOTD then GuildSetMOTD(motdEdit:GetText()) end
        if SetGuildInfoText then SetGuildInfoText(infoEdit:GetText()) end
        print("[GuildUI] Информация о гильдии сохранена")
        form:Hide()
      end)
      
      -- Cancel button
      local cancelBtn = CreateButton(form, nil, "Отмена", 100, 24)
      cancelBtn:SetPoint("LEFT", saveBtn, "RIGHT", 10, 0)
      cancelBtn:SetScript("OnClick", function() form:Hide() end)
      
      GuildUI._editForm = form
    end
    
    GuildUI._editForm:Show()
  end)
  manageBtn:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
    GameTooltip:SetText("Редактировать информацию о гильдии\n(MOTD и описание)")
    GameTooltip:Show()
  end)
  manageBtn:SetScript("OnLeave", function(self) GameTooltip:Hide() end)
  self.manageBtn = manageBtn

  -- Ensure note fields stay under the labels in the info area
  if pubNoteFS then
    pubNoteFS:ClearAllPoints()
    pubNoteFS:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -98)
  end
  if offNoteFS then
    offNoteFS:ClearAllPoints()
    offNoteFS:SetPoint("TOPLEFT", right, "TOPLEFT", 8, -152)
  end

  -- Inline manage overlay (replacement for removed manage.lua)
  function GuildUI:CreateManageOverlay()
    if self.manageOverlay then return self.manageOverlay end
    if not self.frame then return end
    print("1")
    local p = CreateFrame("Frame", "GuildUI_ManageOverlay", UIParent, "BackdropTemplate")
    p:SetPoint("TOPLEFT", self.frame, "TOPLEFT", 16, -46)
    p:SetPoint("BOTTOMRIGHT", self.frame, "BOTTOMRIGHT", -16, 16)
    p.bg = CreateFrame("Frame", nil, p)
    p.bg:SetAllPoints(p)
    p.bg:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background" })
    p.bg:SetBackdropColor(0.03,0.03,0.03,0.25)
    p:EnableMouse(false)
    p:SetFrameStrata("DIALOG")
    p:SetToplevel(true)
    local baseLevel = 50
    if self.frame and self.frame.GetFrameLevel then
      baseLevel = (self.frame:GetFrameLevel() or 0) + 50
    end
    p:SetFrameLevel(baseLevel + 30)

    local mtitle = CreateFont(p, 14, 1,1,1, true)
    mtitle:SetPoint("TOPLEFT", p, "TOPLEFT", 8, -8)
    mtitle:SetText("Управление")

    p.bg:EnableMouse(false)
    p.bg:SetFrameLevel(baseLevel)
    p.bg:SetScript("OnMouseDown", function() end)
    p:SetScript("OnMouseDown", function() end)
    -- shield: invisible frame above background that captures mouse events
    local shield = CreateFrame("Frame", "GuildUI_ManageShield", p)
    shield:SetAllPoints(p)
    shield:EnableMouse(true)
    shield:SetFrameStrata("DIALOG")
    shield:SetFrameLevel(baseLevel + 25)
    shield:SetScript("OnMouseDown", function() end)
    shield:SetScript("OnMouseUp", function() end)
    shield:Hide()
    p.shield = shield

    local back = CreateButton(p, "GuildUI_ManageBackBtn", "Назад", 120, 24)
    back:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -16, 40)
    back:SetFrameStrata("DIALOG")
    back:SetFrameLevel(baseLevel + 150)
    back:SetToplevel(true)
    back:EnableMouse(true)
    back:SetScript("OnClick", function()
      GuildUI:HideManageOverlay()
    end)
    p.backBtn = back
    -- ensure shield sits well below the back button
    if p.shield then p.shield:SetFrameLevel(baseLevel + 25) end

    -- Guild info editing
    print("3")
    local motdLabel = CreateFont(p, 12, 1,1,1, true)
    motdLabel:SetPoint("CENTER", p, "CENTER", 0, 100)
    motdLabel:SetText("Сообщение дня:")
    motdLabel:SetAlpha(1)
    motdLabel:Show()
    p.motdLabel = motdLabel

    local motdEdit = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    motdEdit:SetSize(400, 22)
    motdEdit:SetPoint("TOP", motdLabel, "BOTTOM", 0, -5)
    motdEdit:SetAutoFocus(false)
    motdEdit:EnableKeyboard(true)
    motdEdit:EnableMouse(true)
    motdEdit:SetText(GetGuildRosterMOTD() or "")
    motdEdit:SetFrameLevel(baseLevel + 200)
    motdEdit:SetAlpha(1)
    motdEdit:Show()
    -- debug background to visualize position
    local dbg = motdEdit:CreateTexture(nil, "BACKGROUND")
    dbg:SetAllPoints(motdEdit)
    dbg:SetTexture("Interface\\Buttons\\WHITE8x8")
    dbg:SetVertexColor(0, 0.2, 0.6, 0.25)
    motdEdit._dbg = dbg
    p.motdEdit = motdEdit

    local infoLabel = CreateFont(p, 12, 1,1,1, true)
    infoLabel:SetPoint("TOPLEFT", motdEdit, "BOTTOMLEFT", 0, -15)
    infoLabel:SetText("Информация о гильдии:")
    infoLabel:SetAlpha(1)
    infoLabel:Show()
    p.infoLabel = infoLabel

    local infoEdit = CreateFrame("EditBox", nil, p, "InputBoxTemplate")
    infoEdit:SetSize(400, 22)
    infoEdit:SetPoint("TOPLEFT", infoLabel, "BOTTOMLEFT", 0, -5)
    infoEdit:SetAutoFocus(false)
    infoEdit:EnableKeyboard(true)
    infoEdit:EnableMouse(true)
    infoEdit:SetText(GetGuildInfoText() or "")
    infoEdit:SetFrameLevel(baseLevel + 200)
    infoEdit:SetAlpha(1)
    infoEdit:Show()
    local dbg2 = infoEdit:CreateTexture(nil, "BACKGROUND")
    dbg2:SetAllPoints(infoEdit)
    dbg2:SetTexture("Interface\\Buttons\\WHITE8x8")
    dbg2:SetVertexColor(0.6, 0.2, 0, 0.25)
    infoEdit._dbg = dbg2
    p.infoEdit = infoEdit

    local saveBtn = CreateButton(p, "GuildUI_SaveGuildInfoBtn", "Сохранить", 120, 24)
    saveBtn:SetPoint("TOPLEFT", infoEdit, "BOTTOMLEFT", 0, -10)
    saveBtn:SetFrameLevel(baseLevel + 200)
    saveBtn:SetAlpha(1)
    saveBtn:SetScript("OnClick", function()
      local motd = motdEdit:GetText()
      local info = infoEdit:GetText()
      if GuildSetMOTD then GuildSetMOTD(motd) end
      if SetGuildInfoText then SetGuildInfoText(info) end
      print("[GuildUI] Информация о гильдии обновлена")
    end)
    saveBtn:Show()
    -- debug background for save button
    local sbg = saveBtn:CreateTexture(nil, "BACKGROUND")
    sbg:SetPoint("TOPLEFT", saveBtn, "TOPLEFT", -4, 4)
    sbg:SetPoint("BOTTOMRIGHT", saveBtn, "BOTTOMRIGHT", 4, -4)
    sbg:SetTexture("Interface\\Buttons\\WHITE8x8")
    sbg:SetVertexColor(0, 0.6, 0.2, 0.25)
    saveBtn._dbg = sbg
    p.saveBtn = saveBtn

    p:Hide()
    self.manageOverlay = p
    return p
  end

  function GuildUI:ShowManageOverlay()
    if not self.frame then return end
    if not self.manageOverlay then self:CreateManageOverlay() end
    if self._manageTransition then return end
    print("2")
    self._manageTransition = true
    local left, right, mp = self.left, self.right, self.manageOverlay
    local dur = 0.12
    -- Show overlay and its shield immediately (prevent clicks passing through during transition)
    if mp then 
      mp:SetAlpha(0)
      mp:Show()
      if mp.shield then mp.shield:Hide() end
      if mp.backBtn then mp.backBtn:Show() end
      -- Ensure guild info elements are visible
      if mp.motdLabel then mp.motdLabel:SetAlpha(1) end
      if mp.motdEdit then mp.motdEdit:SetAlpha(1) end
      if mp.infoLabel then mp.infoLabel:SetAlpha(1) end
      if mp.infoEdit then mp.infoEdit:SetAlpha(1) end
      if mp.saveBtn then mp.saveBtn:SetAlpha(1) end
      -- Debug: print strata/levels to help diagnose visibility
      if mp.GetFrameLevel and mp.GetFrameStrata then
        print("[GuildUI][DBG] overlay:", mp:GetName(), mp:GetFrameStrata(), mp:GetFrameLevel())
      end
      if mp.bg and mp.bg.GetFrameLevel then print("[GuildUI][DBG] bg:", mp.bg:GetName() or "bg", (mp.bg.GetFrameStrata and mp.bg:GetFrameStrata()) or "?", (mp.bg.GetFrameLevel and mp.bg:GetFrameLevel()) or "?") end
      if mp.shield and mp.shield.GetFrameLevel then print("[GuildUI][DBG] shield:", mp.shield:GetName() or "shield", (mp.shield.GetFrameStrata and mp.shield:GetFrameStrata()) or "?", (mp.shield.GetFrameLevel and mp.shield:GetFrameLevel()) or "?") end
      if mp.backBtn and mp.backBtn.GetFrameLevel then print("[GuildUI][DBG] backBtn:", mp.backBtn:GetName() or "backBtn", (mp.backBtn.GetFrameStrata and mp.backBtn:GetFrameStrata()) or "?", (mp.backBtn.GetFrameLevel and mp.backBtn:GetFrameLevel()) or "?") end
      if mp.motdEdit and mp.motdEdit.GetFrameLevel then print("[GuildUI][DBG] motdEdit:", mp.motdEdit:GetName() or "motdEdit", (mp.motdEdit.GetFrameStrata and mp.motdEdit:GetFrameStrata()) or "?", (mp.motdEdit.GetFrameLevel and mp.motdEdit:GetFrameLevel()) or "?") end
      if mp.infoEdit and mp.infoEdit.GetFrameLevel then print("[GuildUI][DBG] infoEdit:", mp.infoEdit:GetName() or "infoEdit", (mp.infoEdit.GetFrameStrata and mp.infoEdit:GetFrameStrata()) or "?", (mp.infoEdit.GetFrameLevel and mp.infoEdit:GetFrameLevel()) or "?") end
    end
    if left and left:IsShown() then if UIFrameFadeOut then UIFrameFadeOut(left, dur, left:GetAlpha() or 1, 0) else left:SetAlpha(0) end end
    if right and right:IsShown() then if UIFrameFadeOut then UIFrameFadeOut(right, dur, right:GetAlpha() or 1, 0) else right:SetAlpha(0) end end
    if C_Timer and C_Timer.After then
      C_Timer.After(dur, function()
        if left then left:Hide(); left:SetAlpha(1) end
        if right then right:Hide(); right:SetAlpha(1) end
        if mp then mp:SetAlpha(0); mp:Show(); if mp.shield then mp.shield:Hide() end; if mp.backBtn then mp.backBtn:Show() end; if UIFrameFadeIn then UIFrameFadeIn(mp, dur, 0, 1) else mp:SetAlpha(1) end
          -- Ensure guild info elements are visible after fade
          if mp.motdLabel then mp.motdLabel:SetAlpha(1); mp.motdLabel:Show() end
          if mp.motdEdit then mp.motdEdit:SetAlpha(1); mp.motdEdit:Show() end
          if mp.infoLabel then mp.infoLabel:SetAlpha(1); mp.infoLabel:Show() end
          if mp.infoEdit then mp.infoEdit:SetAlpha(1); mp.infoEdit:Show() end
          if mp.saveBtn then mp.saveBtn:SetAlpha(1); mp.saveBtn:Show() end
        end
        C_Timer.After(dur, function() self._manageTransition = nil end)
      end)
    else
      if left then left:Hide() end
      if right then right:Hide() end
      if mp then if mp.shield then mp.shield:Hide() end; mp:Show(); if mp.backBtn then mp.backBtn:Show() end end
      self._manageTransition = nil
    end
  end

  function GuildUI:HideManageOverlay()
    if not self.frame or not self.manageOverlay then return end
    -- Remove transition lock so repeated clicks work
    local left, right, mp = self.left, self.right, self.manageOverlay
    -- Hide overlay elements immediately
    if mp then
      if mp.shield then mp.shield:Hide() end
      if mp.backBtn then mp.backBtn:Hide() end
      mp:Hide()
    end
    -- Restore main panels immediately
    if left then left:Show(); left:SetAlpha(1) end
    if right then right:Show(); right:SetAlpha(1) end
    -- Refresh members/list
    pcall(function()
      if self and self.UpdateMembers then self:UpdateMembers() end
      if self and self.UpdateList then self:UpdateList("") end
    end)
    self._manageTransition = nil
  end

  function GuildUI:SelectMember(index)
    local m = self.members[index]
    if not m then return end
    -- record selection (index + name) so other operations (sorting, updates)
    -- can restore the visual highlight correctly
    self.selected = index
    self.selectedName = m.name
    -- update left-list visuals: highlight selected row and reset others
    if self.rows then
      for _, row in ipairs(self.rows) do
        if row and row._memberIndex then
          if row._memberIndex == index then
            if row.hl and row.hl.center then
              if UIFrameFadeIn then UIFrameFadeIn(row.hl.center, 0.15, row.hl.center:GetAlpha() or 0, 0.18) else row.hl.center:SetAlpha(0.18) end
            end
            if row.nameFS and row.nameFS.SetTextColor then pcall(function() row.nameFS:SetTextColor(1,1,1) end) end
            if row.rankFS and row.rankFS.SetTextColor then pcall(function() row.rankFS:SetTextColor(1,1,1) end) end
            -- keep class icon color unchanged on selection (do not paint it yellow)
            if row.lastFS and row.lastFS.SetTextColor then pcall(function() row.lastFS:SetTextColor(1,1,1) end) end
          else
            if row.hl and row.hl.center then
              if UIFrameFadeOut then UIFrameFadeOut(row.hl.center, 0.15, row.hl.center:GetAlpha() or 0.18, 0) else row.hl.center:SetAlpha(0) end
            end
            if row.nameFS and row.nameColor then pcall(function() row.nameFS:SetTextColor(unpack(row.nameColor)) end) end
            if row.rankFS and row.rankColor then pcall(function() row.rankFS:SetTextColor(unpack(row.rankColor)) end) end
            if row.classIcon and row.classIcon.SetVertexColor then pcall(function() row.classIcon:SetVertexColor(1,1,1) end) end
            if row.lastFS and row.lastColor then pcall(function() row.lastFS:SetTextColor(unpack(row.lastColor)) end) end
          end
        end
      end
    end

    right.nameFS:SetText(m.name)
    if right.classFS then
      right.classFS:SetText("Класс: "..(m.class or ""))
      local cr, cg, cb = GetClassColorByName(m.class)
      -- Do not color the class text in the right info panel; keep default text color
      if right.classFS.SetTextColor then right.classFS:SetTextColor(1, 1, 1) end
      -- set right panel class icon (use same robust resolution as rows)
      do
        -- use the same robust ResolveClassToken as rows so gendered/localized names map correctly
        local token = ResolveClassToken(m.class)
        local iconFile = nil
        if token then
          iconFile = "ClassIcon_"..string.lower(token)
        elseif m.class then
          iconFile = "ClassIcon_"..string.lower((m.class:gsub("%s+", "")))
        end
        if iconFile and right.classIcon then
          right.classIcon:SetTexture("Interface\\AddOns\\GuildUI\\media\\icons\\"..iconFile..".blp")
          right.classIcon:Show()
        elseif right.classIcon then
          right.classIcon:Hide()
        end
      end
    end
    right.rankFS:SetText("Ранг: "..(m.rank or ""))
    if right.pubNoteFS then right.pubNoteFS:SetText(m.publicNote and m.publicNote ~= "" and m.publicNote or "(нет)") end
      if right.pubNoteFS then
        local txt = m.publicNote and m.publicNote ~= "" and m.publicNote or "(нет)"
        if m._localPublic then txt = txt .. " (локально)" end
        right.pubNoteFS:SetText(txt)
      end
      if right.offNoteFS then
        local txt2 = m.officerNote and m.officerNote ~= "" and m.officerNote or "(нет)"
        if m._localOfficer then txt2 = txt2 .. " (локально)" end
        right.offNoteFS:SetText(txt2)
      end
    -- populate edit boxes (but keep them hidden)
    if right.pubEdit then right.pubEdit:SetText(m.publicNote or "") end
    if right.offEdit then right.offEdit:SetText(m.officerNote or "") end
    GuildUI.selected = index
  end

  -- Event frame for updating roster
  local evt = CreateFrame("Frame")
  evt:RegisterEvent("GUILD_ROSTER_UPDATE")
  evt:RegisterEvent("PLAYER_GUILD_UPDATE")
  evt:SetScript("OnEvent", function(_, event, ...)
    GuildUI:OnEvent(event, ...)
  end)
  self.eventFrame = evt

  -- Search handling
  local search = self.search or (self.left and self.left.search)
  if search then
    search:SetScript("OnTextChanged", function(self)
      local txt = self:GetText() or ""
      if txt == "Поиск..." then txt = "" end
      GuildUI:UpdateList(txt)
    end)
    search:SetScript("OnEditFocusGained", function(self) if self:GetText() == "Поиск..." then self:SetText("") end end)
    search:SetScript("OnEditFocusLost", function(self) if self:GetText() == "" then self:SetText("Поиск...") end end)
    search:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
  else
    if self.debug then print("[GuildUI][WARN] search box not found; skipping search handlers") end
  end

  -- expose frame
  f:Hide()
  self.frame = f
  -- Request guild roster and populate
  if IsInGuild() then
    GuildRoster()
  end
  self:UpdateMembers()
  self._creating = nil
end


function GuildUI:OnEvent(event, ...)
  if event == "GUILD_ROSTER_UPDATE" or event == "PLAYER_GUILD_UPDATE" then
    self:UpdateMembers()
  end
end

function GuildUI:UpdateMembers()
  -- Populate self.members from guild roster
  -- ensure members table exists to avoid ipairs(nil) errors
  if not self.members then self.members = {} end
  -- remember currently selected player's name (capture it BEFORE we wipe the members list)
  local prevSelectedNameOld = nil
  if self.selected and self.members and self.members[self.selected] and self.members[self.selected].name then
    prevSelectedNameOld = self.members[self.selected].name
  end
  if self.debug and prevSelectedNameOld then
    print("[GuildUI][DBG] Previous selection captured: " .. tostring(prevSelectedNameOld))
  end
  -- keep a lookup of previous members by name so we can preserve notes if server returns empty
  local prevByName = {}
  for _, pm in ipairs(self.members) do
    if pm and pm.name then prevByName[pm.name] = pm end
  end
  wipe(self.members)
  if not IsInGuild() then
    return self:UpdateList("")
  end
  local num = GetNumGuildMembers()
  for i = 1, num do
    -- Capture all returns from GetGuildRosterInfo into a table so we can handle
    -- different client signatures robustly (some clients return an online flag,
    -- some include lastOnline as an extra field, etc.). We then pick fields
    -- by index and try to detect an `isOnline` boolean if present.
    local info = { GetGuildRosterInfo(i) }
    local name = info[1]
    local rank = info[2]
    local rankIndex = info[3]
    local level = info[4]
    local class = info[5]
    local zone = info[6]
    local publicNote = info[7]
    local officerNote = info[8]
    local isOnline = nil
    local lastOnlineStr = nil
    local lastOnlineTS = nil
    local now = time()
    for idx = 9, #info do
      local v = info[idx]
      if type(v) == "boolean" then
        isOnline = v
      elseif type(v) == "number" then
        -- numeric 1/0 may be an online flag
        if v == 1 or v == 0 then
          isOnline = (v == 1)
        else
          -- treat large positive integers as possible epoch timestamps (seconds since 1970)
          if v > 1000000000 and v < (now + 60*60*24) then
            lastOnlineTS = v
          end
        end
      elseif type(v) == "string" then
        -- if string can be parsed as a number, apply numeric heuristics
        local num = tonumber(v)
        if num then
          if num == 1 or num == 0 then
            isOnline = (num == 1)
          elseif num > 1000000000 and num < (now + 60*60*24) then
            lastOnlineTS = num
          end
        else
          -- non-numeric string: likely server-provided human text (e.g. "4 часа", "в сети")
          if not lastOnlineStr then lastOnlineStr = tostring(v) end
        end
      end
    end
    -- Do NOT infer 'online' from zone; server may provide zone even when offline
    -- DEBUG: dump raw info array for diagnosis (temporary)
    if self and self.debug then
      print("[GuildUI][RAW_INFO] memberIndex=", i, "name=", tostring(name))
      for j = 1, #info do
        local v = info[j]
        print("[GuildUI][RAW_INFO] ", i, "slot=", j, "type=", type(v), "value=", tostring(v))
      end
    end
    if name then
      -- strip realm suffix if present (Name-Realm)
      local shortName = string.match(name, "([^%-]+)") or name
      local pub = publicNote or ""
      local off = officerNote or ""
      -- load local saved notes
      local localPub, localOff = LoadLocalNotes(shortName)
      local isLocalPub, isLocalOff = false, false
      -- Prefer server value if non-empty; otherwise try local SavedVariables; otherwise preserve previous in-memory value
      if (not pub or pub == "") then
        if localPub and localPub ~= "" then
          pub = localPub; isLocalPub = true
        elseif prevByName[shortName] and prevByName[shortName].publicNote and prevByName[shortName].publicNote ~= "" then
          pub = prevByName[shortName].publicNote
          isLocalPub = prevByName[shortName]._localPublic or false
        end
      else
        isLocalPub = false
      end
      if (not off or off == "") then
        if localOff and localOff ~= "" then
          off = localOff; isLocalOff = true
        elseif prevByName[shortName] and prevByName[shortName].officerNote and prevByName[shortName].officerNote ~= "" then
          off = prevByName[shortName].officerNote
          isLocalOff = prevByName[shortName]._localOfficer or false
        end
      else
        isLocalOff = false
      end
      -- determine client-side last-seen timestamp: prefer Blizzard UI display, then server timestamp, then server text, then local cache, then online flag
      local displayLast = nil
      local lastTS = nil
      local chosenSource = nil
      local guildUIVal = ReadGuildFrameLastSeen(i)
      if guildUIVal and guildUIVal ~= "" then
        local low = tostring(guildUIVal):lower()
        if string.find(low, "в сети") then
          displayLast = "в сети"
          lastTS = now
          chosenSource = "blizzardUI_online"
        else
          displayLast = guildUIVal
          lastTS = 0
          chosenSource = "blizzardUI_text"
        end
      else
        -- prefer server-provided numeric timestamp if present
        if lastOnlineTS and lastOnlineTS > 0 then
          lastTS = tonumber(lastOnlineTS)
          displayLast = FormatRelativeTime(lastTS)
          chosenSource = "server_timestamp"
        elseif lastOnlineStr and lastOnlineStr ~= "" then
          displayLast = tostring(lastOnlineStr)
          lastTS = 0
          chosenSource = "server_text"
        else
          -- fallback to client cache
          local clientTs = LoadLastSeen(shortName)
          if clientTs and tonumber(clientTs) and tonumber(clientTs) > 0 then
            lastTS = tonumber(clientTs)
            displayLast = FormatRelativeTime(lastTS)
            chosenSource = "local_cache"
          elseif isOnline then
            -- only mark online when we have an explicit online flag (boolean/1)
            local clientNow = now
            SaveLastSeen(shortName, clientNow)
            lastTS = clientNow
            displayLast = "в сети"
            chosenSource = "explicit_online_flag"
          end
        end
      end
      -- User requested: remove last-seen details; only show online/offline.
      if isOnline then
        displayLast = "в сети"
        lastTS = now
      else
        displayLast = "-"
        lastTS = 0
      end
      -- debug: report chosen online flag
      if self.debug then
        print("[GuildUI][SRC] ", shortName, "rosterIndex=", i, "online=", tostring(isOnline), "serverStr=", tostring(lastOnlineStr), "serverTS=", tostring(lastOnlineTS), "clientCache=", tostring(LoadLastSeen(shortName)))
      end
      -- store member: keep `lastSeen` as simple online marker for display
      tinsert(self.members, { name = shortName, rank = rank, rankIndex = rankIndex, class = class, zone = zone, lastSeen = displayLast, lastSeenTS = lastTS or 0, online = isOnline, publicNote = pub, officerNote = off, rosterIndex = i, _localPublic = isLocalPub, _localOfficer = isLocalOff })
    end
  end
  -- debug: dump first few members and note lengths
  if self.debug then
    print("[GuildUI][DBG] UpdateMembers: num="..tostring(#self.members))
    for i = 1, math.min(8, #self.members) do
      local m = self.members[i]
      print("[GuildUI][DBG] ", i, m.name, "pubLen="..tostring(string.len(m.publicNote or "")), "offLen="..tostring(string.len(m.officerNote or "")))
    end
  end
  -- Refresh visible list (preserve current search text if any)
  local searchText = ""
  if self.frame then
    local left = self.left
    if left and left:GetChildren() then
      -- try to get the EditBox as first child (we create it earlier)
      -- safer: store search on self when creating
    end
  end
  -- refresh visible list
  -- re-apply current sort (if any) so user choice persists across roster updates
  if self.ApplySort then self:ApplySort() end
  if self.UpdateHeaderSortIndicators then self:UpdateHeaderSortIndicators() end

  -- Update management button state (disabled for now)
  -- if self.manageBtn then
  --   local isGM = false
  --   local player = UnitName("player")
  --   for _, m in ipairs(self.members) do
  --     if m and m.name and string.lower(m.name) == string.lower(player) then
  --       if tonumber(m.rankIndex) == 0 then isGM = true end
  --       break
  --     end
  --   end
  --   if isGM then
  --     if self.manageBtn.Enable then pcall(function() self.manageBtn:Enable() end) end
  --     self.manageBtn:SetAlpha(1)
  --   else
  --     if self.manageBtn.Disable then pcall(function() self.manageBtn:Disable() end) end
  --     self.manageBtn:SetAlpha(0.5)
  --   end
  -- end

  -- restore selection if possible (match by name) - after sorting to get correct indices
  local prevSelectedName = nil
  if self.pendingRestore and type(self.pendingRestore) == "string" and self.pendingRestore ~= "" then
    prevSelectedName = self.pendingRestore
    -- do NOT clear pendingRestore yet: only clear when we successfully restore selection
  elseif prevSelectedNameOld and type(prevSelectedNameOld) == "string" and prevSelectedNameOld ~= "" then
    -- prefer the previously selected name captured before the roster was rebuilt
    prevSelectedName = prevSelectedNameOld
  end
  if prevSelectedName then
    if self.debug then print("[GuildUI][RESTORE] Looking for " .. tostring(prevSelectedName)) end
    local found = false
    for i, m in ipairs(self.members) do
      if m and string.lower(m.name) == string.lower(prevSelectedName) then
        self.selected = i
        -- refresh right panel to reflect restored member (notes etc.)
        self:SelectMember(i)
        found = true
        -- successfully restored, clear the pending marker so we don't try again
        if self.pendingRestore and string.lower(self.pendingRestore) == string.lower(prevSelectedName) then
          self.pendingRestore = nil
        end
        if self.debug then print("[GuildUI][RESTORE] Found at " .. i) end
        break
      end
    end
    if not found then
      self.selected = nil
      if self.debug then print("[GuildUI][RESTORE] Not found, deselected") end
    end
  end

  self:UpdateList("")

  -- debug: report where selection ended up after update
  if self.debug then
    if self.selected and self.members and self.members[self.selected] and self.members[self.selected].name then
      print("[GuildUI][DBG] Selection after UpdateMembers -> idx=" .. tostring(self.selected) .. " name=" .. tostring(self.members[self.selected].name))
    else
      print("[GuildUI][DBG] Selection after UpdateMembers -> (none)")
    end
  end

  -- Update frame title to show current guild name (if any)
  if self.title then
    -- Update online/total counter (number of members with explicit online flag)
    if self.countFS then
      local total = #self.members
      local online = 0
      for _, m in ipairs(self.members) do
        if m and m.online then online = online + 1 end
      end
      pcall(function() self.countFS:SetText("Онлайн: "..tostring(online) .. "/" .. tostring(total)) end)
    end

    local gname = nil
    if IsInGuild and IsInGuild() and GetGuildInfo then
      gname = GetGuildInfo("player")
    end
    if gname and gname ~= "" then
      self.title:SetText(gname)
    else
      self.title:SetText("GuildUI — Управление гильдией")
    end
  end
end

-- Create or open a note editor popup for public/officer notes
function GuildUI:CreateNoteEditor()
  if self.noteEditor then return end
  local ed = CreateFrame("Frame", "GuildUI_NoteEditor", UIParent)
  ed:SetSize(360, 220)
  ed:SetPoint("CENTER")
  -- Make sure the editor is topmost above the main addon frame
  ed:SetFrameStrata("DIALOG")
  ed:SetToplevel(true)
  ed:SetClampedToScreen(true)
  if self.frame then
    ed:SetFrameLevel(self.frame:GetFrameLevel() + 30)
  else
    ed:SetFrameLevel(200)
  end
  -- use a dedicated texture for the editor background (allows custom .blp)
  -- reduce outer border/inset by 5px (was 8, now 3)
  ed:SetBackdrop({ edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = { left = 3, right = 3, top = 3, bottom = 3 } })
  ed:SetBackdropColor(0,0,0,0)
  -- background image (user-provided). place behind the frame content.
  ed.bgTexture = ed:CreateTexture(nil, "BACKGROUND")
  ed.bgTexture:SetPoint("TOPLEFT", ed, "TOPLEFT", 3, -3)
  ed.bgTexture:SetPoint("BOTTOMRIGHT", ed, "BOTTOMRIGHT", -3, 3)
  ed.bgTexture:SetTexture("Interface\\AddOns\\GuildUI\\media\\background\\background2.blp")
  ed.bgTexture:SetHorizTile(false)
  ed.bgTexture:SetVertTile(false)
  ed:EnableMouse(true)
  ed:SetMovable(true)
  ed:RegisterForDrag("LeftButton")
  ed:SetScript("OnDragStart", function(self) self:StartMoving() end)
  ed:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

  ed.title = ed:CreateFontString(nil, "OVERLAY")
  ed.title:SetFont("Fonts\\FRIZQT__.TTF", 14, "OUTLINE")
  ed.title:SetPoint("TOPLEFT", ed, "TOPLEFT", 12, -10)
  ed.title:SetText("Редактировать заметку")

  local hint = ed:CreateFontString(nil, "OVERLAY")
  hint:SetFont("Fonts\\FRIZQT__.TTF", 11, "")
  hint:SetPoint("TOPLEFT", ed, "TOPLEFT", 12, -34)
  hint:SetText("Используйте Enter для новой строки.")

  -- create a framed area containing a scrollframe + multi-line editbox
  -- this provides a visible pane behind the text (backdrop + inset)
  local textFrame = CreateFrame("Frame", nil, ed, "BackdropTemplate")
  textFrame:SetSize(328, 120)
  textFrame:SetPoint("TOPLEFT", ed, "TOPLEFT", 12, -56)
  textFrame:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border", edgeSize = 16, insets = { left = 6, right = 6, top = 6, bottom = 6 } })
  textFrame:SetBackdropColor(0.06, 0.06, 0.06, 0.85)

  -- scrollframe sits inside the framed area with small inset
  local scroll = CreateFrame("ScrollFrame", "GuildUI_NoteEditorScrollFrame", textFrame, "UIPanelScrollFrameTemplate")
  scroll:SetPoint("TOPLEFT", textFrame, "TOPLEFT", 6, -6)
  scroll:SetPoint("BOTTOMRIGHT", textFrame, "BOTTOMRIGHT", -6, 6)

  local box = CreateFrame("EditBox", nil, scroll)
  box:SetMultiLine(true)
  box:SetAutoFocus(true)
  box:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
  box:SetWidth(308)
  box:SetHeight(120)
  box:SetPoint("TOPLEFT", scroll, "TOPLEFT", 6, -6)
  box:SetJustifyH("LEFT")
  box:SetJustifyV("TOP")
  box:SetTextInsets(6,6,6,6)
  -- Hide the entire editor frame on Escape (previously hid only inner frame)
  box:SetScript("OnEscapePressed", function(self) if ed then ed:Hide() end end)
  -- ensure the scroll frame scrolls with the editbox
  scroll:SetScrollChild(box)
  ed.editBox = box

  local save = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate")
  save:SetSize(100, 24)
  save:SetPoint("BOTTOMLEFT", ed, "BOTTOMLEFT", 12, 12)
  save:SetText("Сохранить")

  local cancel = CreateFrame("Button", nil, ed, "UIPanelButtonTemplate")
  cancel:SetSize(80, 24)
  cancel:SetPoint("BOTTOMLEFT", save, "BOTTOMRIGHT", 8, 0)
  cancel:SetText("Отмена")
  cancel:SetScript("OnClick", function() ed:Hide() end)

  save:SetScript("OnClick", function()
    local noteType = ed.noteType
    local idx = self.selected
    if not idx then print("[GuildUI] Выберите участника сначала.") return end
    local m = self.members[idx]
    if not m or not m.rosterIndex then print("[GuildUI] Не могу найти индекс ростера.") return end
    local text = ed.editBox:GetText() or ""
    if noteType == "public" then
      if self.debug then print("[GuildUI][DBG] Saving public note. API?", tostring(type(GuildRosterSetPublicNote) == "function"), "textLen=", tostring(string.len(text or ""))) end
      if type(GuildRosterSetPublicNote) == "function" then
        GuildRosterSetPublicNote(m.rosterIndex, text)
        -- clear any local fallback for this note since server now stores it
        ClearLocalPublic(m.name)
        m._localPublic = false
        m.publicNote = text
        if self.selected == idx then
          self:SelectMember(idx)
          if self.right and self.right.pubNoteFS then
            self.right.pubNoteFS:SetText(m.publicNote and m.publicNote ~= "" and m.publicNote or "(нет)")
            self.right.pubNoteFS:SetTextColor(1,1,1)
          end
        end
        print("[GuildUI] Заметка сохранена для: "..m.name)
        GuildRoster()
        ed:Hide()
      else
        -- save locally and mark as local fallback
        SaveLocalNotes(m.name, text, nil)
        m.publicNote = text
        m._localPublic = true
        if self.selected == idx then
          self:SelectMember(idx)
          if self.right and self.right.pubNoteFS then
            self.right.pubNoteFS:SetText(m.publicNote and m.publicNote ~= "" and m.publicNote or "(нет)")
            self.right.pubNoteFS:SetTextColor(1,1,1)
          end
        end
        print("[GuildUI] Сохранение публичной заметки недоступно в этом клиенте. (локально сохранено)")
      end
    else -- officer
      if self.debug then print("[GuildUI][DBG] Saving officer note. API?", tostring(type(GuildRosterSetOfficerNote) == "function"), "textLen=", tostring(string.len(text or ""))) end
      if type(GuildRosterSetOfficerNote) == "function" then
        GuildRosterSetOfficerNote(m.rosterIndex, text)
        -- clear any local fallback for this officer note
        ClearLocalOfficer(m.name)
        m._localOfficer = false
        m.officerNote = text
        if self.selected == idx then
          self:SelectMember(idx)
          if self.right and self.right.offNoteFS then
            self.right.offNoteFS:SetText(m.officerNote and m.officerNote ~= "" and m.officerNote or "(нет)")
            self.right.offNoteFS:SetTextColor(1,1,1)
          end
        end
        print("[GuildUI] Заметка офицера сохранена для: "..m.name)
        GuildRoster()
        ed:Hide()
      else
        SaveLocalNotes(m.name, nil, text)
        m.officerNote = text
        m._localOfficer = true
        if self.selected == idx then
          self:SelectMember(idx)
          if self.right and self.right.offNoteFS then
            self.right.offNoteFS:SetText(m.officerNote and m.officerNote ~= "" and m.officerNote or "(нет)")
            self.right.offNoteFS:SetTextColor(1,1,1)
          end
        end
        print("[GuildUI] Сохранение заметки офицера недоступно в этом клиенте. (локально сохранено)")
      end
    end
  end)

  ed:Hide()
  self.noteEditor = ed
end

function GuildUI:OpenNoteEditor(kind)
  if not self.noteEditor then self:CreateNoteEditor() end
  local ed = self.noteEditor
  local idx = self.selected
  if not idx then print("[GuildUI] Выберите участника сначала.") return end
  local m = self.members[idx]
  if not m then return end
  ed.noteType = kind
  if kind == "public" then
    ed.title:SetText("Редактировать заметку: "..m.name)
    ed.editBox:SetText(m.publicNote or "")
  else
    ed.title:SetText("Редактировать заметку офицера: "..m.name)
    ed.editBox:SetText(m.officerNote or "")
  end
  -- Ensure editor is above addon frame and focused
  if self.frame then
    ed:SetFrameLevel(self.frame:GetFrameLevel() + 30)
  end
  ed:Show()
  ed:Raise()
  ed.editBox:SetFocus()
end

-- Slash command
SLASH_GUILDUI1 = "/guildui"
SlashCmdList["GUILDUI"] = function(msg)
  if not GuildUI.frame then GuildUI:CreateUI() end
  if GuildUI.frame:IsShown() then GuildUI.frame:Hide() else GuildUI.frame:Show() end
end

-- Quick test command to open the manage panel (disabled)
-- SLASH_GUILDMANAGE1 = "/gmanage"
-- SlashCmdList["GUILDMANAGE"] = function(msg)
--   print("[GuildUI] Управление - в разработке")
-- end

-- Auto-create at load? we keep manual via slash command
_G.GuildUI = GuildUI

-- Initialization: ensure UI is created and guild roster requested on load
do
  local init = CreateFrame("Frame")
  init:RegisterEvent("ADDON_LOADED")
  init:RegisterEvent("PLAYER_LOGIN")
  init:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "GuildUI" then
      if not GuildUI.frame then GuildUI:CreateUI() end
      if IsInGuild() then GuildRoster() end
      GuildUI:UpdateMembers()
    elseif event == "PLAYER_LOGIN" then
      if not GuildUI.frame then GuildUI:CreateUI() end
      if IsInGuild() then GuildRoster() end
      GuildUI:UpdateMembers()
    end
  end)
end
