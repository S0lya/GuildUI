-- members.lua — modularized Left panel (Участники)
-- Contains creation of member list UI, sorting and UpdateList logic

if not GuildUI then GuildUI = {} end

function GuildUI:CreateMembersUI(parent)
  -- Left panel (member list)
  local left = CreateFrame("Frame", nil, parent)
  -- make left panel extend to match top/bottom margins inside main frame
  left:SetSize(312, 378)
  -- push left panel a bit lower to avoid overlapping top controls (invite input / title)
  left:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -68)

  left.bg = CreateFrame("Frame", nil, left)
  left.bg:SetAllPoints(left)
  left.bg:SetBackdrop({ bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background" })
  left.bg:SetBackdropColor(0.03,0.03,0.03,0.25)

  local search = CreateFrame("EditBox", nil, left, "InputBoxTemplate")
  search:SetSize(280, 22)
  search:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -8)
  search:SetText("Поиск...")
  search:SetAutoFocus(false)
  search:EnableKeyboard(true)
  search:EnableMouse(true)
  search:SetScript("OnKeyDown", function(self, key)
    if key == "ESCAPE" or key == "ESC" then
      self:ClearFocus()
    end
  end)

  -- expose search editbox so CreateUI can attach global handlers
  self.search = search
  left.search = search

  local header = CreateFont(left, 12, 1,1,1, true)
  header:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -36)
  header:SetText("Участники")

  -- Column headers under "Участники"
  local colY = -56
  local colName = CreateFont(left, 11, 1,1,1, true)
  colName:SetPoint("TOPLEFT", left, "TOPLEFT", 8, colY)
  colName:SetText("Имя")
  local colRank = CreateFont(left, 11, 0.9,0.9,0.9, true)
  colRank:SetPoint("TOPLEFT", left, "TOPLEFT", 92, colY)
  colRank:SetText("Ранг")
  local colClass = CreateFont(left, 11, 0.9,0.9,0.9, true)
  colClass:SetPoint("TOPLEFT", left, "TOPLEFT", 150, colY)
  colClass:SetText("Класс")
  local colLast = CreateFont(left, 11, 0.9,0.9,0.9, true)
  colLast:SetPoint("TOPLEFT", left, "TOPLEFT", 218, colY)
  colLast:SetText("Зона")

  -- neat arrow indicators
  colName.arrow = left:CreateFontString(nil, "OVERLAY")
  colName.arrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  colName.arrow:SetPoint("LEFT", colName, "RIGHT", 4, 0)
  colName.arrow:SetText("")
  colName.arrow:SetTextColor(0.92, 0.8, 0.36)

  colRank.arrow = left:CreateFontString(nil, "OVERLAY")
  colRank.arrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  colRank.arrow:SetPoint("LEFT", colRank, "RIGHT", 4, 0)
  colRank.arrow:SetText("")
  colRank.arrow:SetTextColor(0.92, 0.8, 0.36)

  colClass.arrow = left:CreateFontString(nil, "OVERLAY")
  colClass.arrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  colClass.arrow:SetPoint("LEFT", colClass, "RIGHT", 4, 0)
  colClass.arrow:SetText("")
  colClass.arrow:SetTextColor(0.92, 0.8, 0.36)

  colLast.arrow = left:CreateFontString(nil, "OVERLAY")
  colLast.arrow:SetFont("Fonts\\FRIZQT__.TTF", 10, "OUTLINE")
  colLast.arrow:SetPoint("LEFT", colLast, "RIGHT", 4, 0)
  colLast.arrow:SetText("")
  colLast.arrow:SetTextColor(0.92, 0.8, 0.36)

  local sep = left:CreateTexture(nil, "ARTWORK")
  sep:SetHeight(3)
  sep:SetPoint("TOPLEFT", left, "TOPLEFT", 8, colY - 16)
  sep:SetPoint("TOPRIGHT", left, "TOPRIGHT", -8, colY - 16)
  sep:SetTexture("Interface\\Buttons\\WHITE8x8")
  sep:SetVertexColor(0.62, 0.44, 0.18, 0.95)

  local sepVert = left:CreateTexture(nil, "ARTWORK")
  sepVert:SetWidth(3)
  sepVert:SetPoint("TOPRIGHT", left, "TOPRIGHT", -8, -12)
  sepVert:SetPoint("BOTTOMRIGHT", left, "BOTTOMRIGHT", -8, 12)
  sepVert:SetTexture("Interface\\Buttons\\WHITE8x8")
  sepVert:SetVertexColor(0.62, 0.44, 0.18, 0.95)

  -- Container for rows
  local rows = {}

  function GuildUI:ApplySort()
    if not self.sortKey then return end
    table.sort(self.members, function(a,b)
      if self.sortKey == "rank" then
        local ak = tonumber(a.rankIndex) or 0
        local bk = tonumber(b.rankIndex) or 0
        if ak == bk then
          return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
        end
        if self.sortDir == 1 then return ak < bk else return ak > bk end
      end
      if self.sortKey == "lastSeen" then
        local ak = tonumber(a.lastSeenTS) or 0
        local bk = tonumber(b.lastSeenTS) or 0
        if ak == bk then
          return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
        end
        if self.sortDir == 1 then return ak < bk else return ak > bk end
      end
      local ak = tostring(a[self.sortKey] or ""):lower()
      local bk = tostring(b[self.sortKey] or ""):lower()
      if ak == bk then
        return tostring(a.name or ""):lower() < tostring(b.name or ""):lower()
      end
      if self.sortDir == 1 then return ak < bk else return ak > bk end
    end)
  end

  function GuildUI:SetSort(key)
    if self.sortKey == key then
      self.sortDir = - (self.sortDir or 1)
    else
      self.sortKey = key
      self.sortDir = 1
    end
    self:ApplySort()
    if self.UpdateHeaderSortIndicators then self:UpdateHeaderSortIndicators() end
    self:UpdateList("")
  end

  -- store UI refs
  self.left = left
  self.rows = rows

  local function makeHeaderButton(x, width, onClick)
    local b = CreateFrame("Button", nil, left)
    b:SetSize(width, 18)
    b:SetPoint("TOPLEFT", left, "TOPLEFT", x, colY + 6)
    b:SetScript("OnClick", onClick)
    b:EnableMouse(true)
    return b
  end

  function GuildUI:UpdateHeaderSortIndicators()
    colName:SetText("Имя")
    colRank:SetText("Ранг")
    colClass:SetText("Класс")
    if self.showZoneColumn == nil then self.showZoneColumn = true end
    if self.showZoneColumn then
      colLast:SetText("Зона")
    else
      if not self.onlineFilter or self.onlineFilter == "all" then
        colLast:SetText("Онлайн")
      elseif self.onlineFilter == "online" then
        colLast:SetText("В сети")
      elseif self.onlineFilter == "offline" then
        colLast:SetText("Не в сети")
      else
        colLast:SetText("Онлайн")
      end
    end
    if colName.arrow then colName.arrow:SetText("") end
    if colRank.arrow then colRank.arrow:SetText("") end
    if colClass.arrow then colClass.arrow:SetText("") end
    if colLast.arrow then colLast.arrow:SetText("") end
    local up, down = "^", "v"
    if self.sortKey then
      local arrow = (self.sortDir == 1) and up or down
      if self.sortKey == "name" and colName.arrow then colName.arrow:SetText(arrow) end
      if self.sortKey == "rank" and colRank.arrow then colRank.arrow:SetText(arrow) end
      if self.sortKey == "class" and colClass.arrow then colClass.arrow:SetText(arrow) end
      if (self.sortKey == "zone" or self.sortKey == "lastSeen") and colLast.arrow then colLast.arrow:SetText(arrow) end
    end
  end

  makeHeaderButton(8, 84, function() GuildUI:SetSort("name") end)
  makeHeaderButton(92, 58, function() GuildUI:SetSort("rank") end)
  makeHeaderButton(150, 68, function() GuildUI:SetSort("class") end)

  local zoneMenu = CreateFrame("Frame", "GuildUI_ZoneMenu", UIParent, "UIDropDownMenuTemplate")
  if not GuildUI.showZoneColumn then GuildUI.showZoneColumn = true end
  if not GuildUI.onlineFilter then GuildUI.onlineFilter = "all" end
  local zoneHeaderButton = makeHeaderButton(218, 90, function() GuildUI:SetSort(GuildUI.showZoneColumn and "zone" or "lastSeen") end)
  zoneHeaderButton:EnableMouse(true)
  zoneHeaderButton:SetScript("OnMouseUp", function(_, button)
    if button == "RightButton" then
      local menuList = {
        { text = "Онлайн", notCheckable = false, func = function()
            GuildUI.showZoneColumn = false; GuildUI.onlineFilter = "all"; GuildUI:UpdateHeaderSortIndicators(); GuildUI:UpdateList("")
          end, checked = function() return not GuildUI.showZoneColumn and GuildUI.onlineFilter == "all" end },
        { text = "В сети", notCheckable = false, func = function()
            GuildUI.showZoneColumn = false; GuildUI.onlineFilter = "online"; GuildUI:UpdateHeaderSortIndicators(); GuildUI:UpdateList("")
          end, checked = function() return not GuildUI.showZoneColumn and GuildUI.onlineFilter == "online" end },
        { text = "Не в сети", notCheckable = false, func = function()
            GuildUI.showZoneColumn = false; GuildUI.onlineFilter = "offline"; GuildUI:UpdateHeaderSortIndicators(); GuildUI:UpdateList("")
          end, checked = function() return not GuildUI.showZoneColumn and GuildUI.onlineFilter == "offline" end },
        { text = "Показать зону", notCheckable = false, func = function()
            GuildUI.showZoneColumn = true; GuildUI.onlineFilter = "all"; GuildUI:UpdateHeaderSortIndicators(); GuildUI:UpdateList("")
          end, checked = function() return GuildUI.showZoneColumn end },
      }
      EasyMenu(menuList, zoneMenu, zoneHeaderButton, 0, 0, "MENU")
    end
  end)

  if not self.sortKey then self.sortKey = "name"; self.sortDir = 1 end
  self:UpdateHeaderSortIndicators()

  function GuildUI:UpdateList(filter)
    local left = self.left
    local rows = self.rows
    for i, row in ipairs(rows) do
      row:Hide()
    end
    local idx = 1
    local rowSpacing = 28 * 0.75
    for i, m in ipairs(self.members) do
      if not filter or filter == "" or string.find(string.lower(m.name), string.lower(filter), 1, true) then
        local row = rows[idx]
        if not row then
          row = CreateFrame("Button", "GuildUI_MemberRow"..idx, left)
          row:SetSize(280, 24)
          row.nameFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormal")
          row.nameFS:SetPoint("LEFT", row, "LEFT", 0, 0)
          row.nameFS:SetWidth(80)
          row.rankFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          row.rankFS:SetPoint("LEFT", row, "LEFT", 84, 0)
          row.rankFS:SetWidth(60)
          row.classFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          row.classFS:SetPoint("LEFT", row, "LEFT", 142, 0)
          row.classFS:SetWidth(44)
          row.classIcon = row:CreateTexture(nil, "OVERLAY")
          row.classIcon:SetSize(14, 14)
          local classColLeft = 142
          local classColWidth = 44
          local iconW = 14
          local iconOffset = classColLeft + (classColWidth - iconW) / 2
          row.classIcon:SetPoint("LEFT", row, "LEFT", iconOffset, 0)
          row.lastFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          row.lastFS:SetPoint("LEFT", row, "LEFT", 210, 0)
          row.lastFS:SetWidth(70)
          if row.nameFS.SetJustifyH then row.nameFS:SetJustifyH("LEFT") end
          if row.rankFS.SetJustifyH then row.rankFS:SetJustifyH("LEFT") end
          if row.classFS.SetJustifyH then row.classFS:SetJustifyH("LEFT") end
          if row.lastFS.SetJustifyH then row.lastFS:SetJustifyH("LEFT") end
          row.hl = row:CreateTexture(nil, "BACKGROUND")
          row.hl:SetTexture("Interface\\Buttons\\UI-Listbox-Highlight")
          row.hl:SetPoint("TOPLEFT", row, "TOPLEFT", 0, 0)
          row.hl:SetPoint("BOTTOMLEFT", row, "BOTTOMLEFT", 0, 0)
          row.hl:SetWidth(294)
          row.hl:SetAlpha(0)
          row.hl:Show()
          row:SetScript("OnEnter", function(self)
            if self.hl and UIFrameFadeIn then
              UIFrameFadeIn(self.hl, 0.15, self.hl:GetAlpha() or 0, 1)
            elseif self.hl then
              self.hl:SetAlpha(1)
            end
            if self.nameFS then self.nameFS:SetTextColor(1,1,0) end
            if self.rankFS then self.rankFS:SetTextColor(1,1,0) end
            if self.classIcon then self.classIcon:SetVertexColor(1,1,0) end
            if self.lastFS then self.lastFS:SetTextColor(1,1,0) end
          end)
          row:SetScript("OnLeave", function(self)
            -- keep selection highlight if this row is currently selected
            if GuildUI and GuildUI.selected and self._memberIndex == GuildUI.selected then
              if self.hl then
                if UIFrameFadeIn then UIFrameFadeIn(self.hl, 0.15, self.hl:GetAlpha() or 0, 1) else self.hl:SetAlpha(1) end
              end
              if self.nameFS then self.nameFS:SetTextColor(1,1,0) end
              if self.rankFS then self.rankFS:SetTextColor(1,1,0) end
              if self.classIcon then self.classIcon:SetVertexColor(1,1,0) end
              if self.lastFS then self.lastFS:SetTextColor(1,1,0) end
            else
              if self.hl and UIFrameFadeOut then
                UIFrameFadeOut(self.hl, 0.15, self.hl:GetAlpha() or 1, 0)
              elseif self.hl then
                self.hl:SetAlpha(0)
              end
              if self.nameFS and self.nameColor then pcall(function() self.nameFS:SetTextColor(self.nameColor[1], self.nameColor[2], self.nameColor[3]) end) end
              if self.rankFS and self.rankColor then pcall(function() self.rankFS:SetTextColor(self.rankColor[1], self.rankColor[2], self.rankColor[3]) end) end
              if self.classIcon then pcall(function() self.classIcon:SetVertexColor(1,1,1) end) end
              if self.lastFS and self.lastColor then pcall(function() self.lastFS:SetTextColor(self.lastColor[1], self.lastColor[2], self.lastColor[3]) end) end
            end
          end)
          row:SetScript("OnClick", function(self)
            GuildUI:SelectMember(self._memberIndex)
          end)
          rows[idx] = row
        end
        row._memberIndex = i
        row:SetPoint("TOPLEFT", left, "TOPLEFT", 8, -74 - (idx-1)*rowSpacing)
        row.nameFS:SetText(m.name or "")
        row.rankFS:SetText(m.rank or "")
        row.classFS:SetText("")
        local cr, cg, cb = GetClassColorByName(m.class)
        do
          local token = ResolveClassToken(m.class)
          local iconFile = nil
          if token then
            iconFile = "ClassIcon_"..string.lower(token)
          elseif m.class then
            iconFile = "ClassIcon_"..string.lower((m.class:gsub("%s+", "")))
          end
          if iconFile then
            local path = "Interface\\AddOns\\GuildUI\\media\\icons\\"..iconFile..".blp"
            if GuildUI and GuildUI.debug then
              print("[GuildUI][ICON] row=", tostring(m.name), "class=", tostring(m.class), "token=", tostring(token), "iconFile=", tostring(iconFile), "path=", path)
            end
            row.classIcon:SetTexture(path)
            row.classIcon:Show()
          else
            if GuildUI and GuildUI.debug then
              print("[GuildUI][ICON] row=", tostring(m.name), "class=", tostring(m.class), "no iconFile")
            end
            row.classIcon:Hide()
          end
        end
        row.nameColor = {1,1,1}
        row.rankColor = {1,1,1}
        row.classColor = {cr, cg, cb}
        row.lastColor = {1,1,1}
        if row.nameFS and row.nameFS.SetTextColor and row.nameColor then pcall(function() row.nameFS:SetTextColor(unpack(row.nameColor)) end) end
        if row.rankFS and row.rankFS.SetTextColor and row.rankColor then pcall(function() row.rankFS:SetTextColor(unpack(row.rankColor)) end) end
        if row.lastFS and row.lastFS.SetTextColor and row.lastColor then pcall(function() row.lastFS:SetTextColor(unpack(row.lastColor)) end) end
        if row.classIcon then row.classIcon:SetVertexColor(1,1,1) end
        if row.hl then row.hl:SetAlpha(0) end
        if self.showZoneColumn == nil then self.showZoneColumn = true end
        local skipMember = false
        if not self.showZoneColumn and self.onlineFilter and self.onlineFilter ~= "all" then
          if self.onlineFilter == "online" and not m.online then
            skipMember = true
          elseif self.onlineFilter == "offline" and m.online then
            skipMember = true
          end
        end
        if not skipMember then
          local lastText = "-"
          if self.showZoneColumn then
            lastText = m.zone or "-"
          else
            if m.online then lastText = "В сети" else lastText = "Не в сети" end
          end
          row.lastFS:SetText(lastText)
          row:Show()
          idx = idx + 1
        end
      end
    end
  end

  -- exposed members UI ready
  return left
end
