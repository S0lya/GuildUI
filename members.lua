
if not GuildUI then GuildUI = {} end

function GuildUI:CreateMembersUI(parent)
  -- Left panel (member list)
  local left = CreateFrame("Frame", nil, parent)
  -- make left panel extend to match top/bottom margins inside main frame
  left:SetSize(312, 378)
  left:SetPoint("TOPLEFT", parent, "TOPLEFT", 16, -46)

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
    -- preserve selected member name so visual selection survives sorting
    local selName = nil
    if self.selected and self.members and self.members[self.selected] and self.members[self.selected].name then
      selName = self.selectedName or self.members[self.selected].name
    end
    if self.sortKey == key then
      self.sortDir = - (self.sortDir or 1)
    else
      self.sortKey = key
      self.sortDir = 1
    end
    self:ApplySort()
    if self.UpdateHeaderSortIndicators then self:UpdateHeaderSortIndicators() end
    -- rebuild the list then restore selection by name
    self:UpdateList("")
    if selName then
      for i, m in ipairs(self.members) do
        if m and m.name and string.lower(m.name) == string.lower(selName) then
          self.selected = i
          self.selectedName = m.name
          self:SelectMember(i)
          break
        end
      end
    end
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
          -- keep only the class icon; hide textual class column
          row.classFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          row.classFS:SetPoint("LEFT", row, "LEFT", 142, 0)
          row.classFS:SetWidth(44)
          row.classFS:Hide()
          row.classIcon = row:CreateTexture(nil, "OVERLAY")
          row.classIcon:SetSize(14, 14)
          local classColLeft = 142
          local classColWidth = 44
          local iconW = 14
          local iconOffset = classColLeft + (classColWidth - iconW) / 2
          row.classIcon:SetPoint("LEFT", row, "LEFT", iconOffset, 0)
          -- draw class icon above the highlight so it stays visually unchanged
          row.classIcon:SetDrawLayer("OVERLAY", 2)
          row.lastFS = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
          row.lastFS:SetPoint("LEFT", row, "LEFT", 210, 0)
          row.lastFS:SetWidth(70)
          if row.nameFS.SetJustifyH then row.nameFS:SetJustifyH("LEFT") end
          if row.rankFS.SetJustifyH then row.rankFS:SetJustifyH("LEFT") end
          if row.classFS.SetJustifyH then row.classFS:SetJustifyH("LEFT") end
          if row.lastFS.SetJustifyH then row.lastFS:SetJustifyH("LEFT") end
          -- subtle center-only highlight (no side stripes)
          row.hl = CreateFrame("Frame", nil, row)
          row.hl:SetAllPoints(row)
          -- put highlight behind row contents
          local rl = row:GetFrameLevel()
          if rl and rl > 0 then row.hl:SetFrameLevel(rl - 1) end
          -- center band only
          row.hl.center = row.hl:CreateTexture(nil, "BACKGROUND")
          row.hl.center:SetTexture("Interface\\Buttons\\WHITE8x8")
          row.hl.center:SetVertexColor(0.85, 0.65, 0.18, 1)
          -- tighter inset so it never reaches text/icons
          row.hl.center:SetPoint("TOPLEFT", row.hl, "TOPLEFT", 0, -2)
          row.hl.center:SetPoint("BOTTOMRIGHT", row.hl, "BOTTOMRIGHT", 12, 2)
          row.hl.center:SetAlpha(0)
          row.hl:Show()

          row:SetScript("OnEnter", function(self)
            if self.hl and self.hl.center then
              if UIFrameFadeIn then UIFrameFadeIn(self.hl.center, 0.15, self.hl.center:GetAlpha() or 0, 0.18) else self.hl.center:SetAlpha(0.18) end
            end
            if self.nameFS then self.nameFS:SetTextColor(1,1,1) end
            if self.rankFS then self.rankFS:SetTextColor(1,1,1) end
            if self.lastFS then self.lastFS:SetTextColor(1,1,1) end
          end)

          row:SetScript("OnLeave", function(self)
            if GuildUI and GuildUI.selected and self._memberIndex == GuildUI.selected then
              if self.hl and self.hl.center then
                if UIFrameFadeIn then UIFrameFadeIn(self.hl.center, 0.12, self.hl.center:GetAlpha() or 0, 0.18) else self.hl.center:SetAlpha(0.18) end
              end
              if self.nameFS then self.nameFS:SetTextColor(1,1,1) end
              if self.rankFS then self.rankFS:SetTextColor(1,1,1) end
              if self.lastFS then self.lastFS:SetTextColor(1,1,1) end
            else
              if self.hl and self.hl.center then
                if UIFrameFadeOut then UIFrameFadeOut(self.hl.center, 0.15, self.hl.center:GetAlpha() or 0.18, 0) else self.hl.center:SetAlpha(0) end
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
        -- resolve class icon (robust: try token mapping, fallback to sanitized class name)
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
        -- set displayed texts
        if row.nameFS and row.nameFS.SetText then row.nameFS:SetText(m.name or "") end
        if row.rankFS and row.rankFS.SetText then row.rankFS:SetText(m.rank or "") end
        -- do not show class text (icons only)
        if row.classFS and row.classFS.SetText then row.classFS:SetText("") end
        -- class color for potential use elsewhere
        local cr, cg, cb = GetClassColorByName(m.class)
        row.nameColor = {1,1,1}
        row.rankColor = {1,1,1}
        row.classColor = {cr, cg, cb}
        row.lastColor = {1,1,1}
        if row.nameFS and row.nameFS.SetTextColor and row.nameColor then pcall(function() row.nameFS:SetTextColor(unpack(row.nameColor)) end) end
        if row.rankFS and row.rankFS.SetTextColor and row.rankColor then pcall(function() row.rankFS:SetTextColor(unpack(row.rankColor)) end) end
        if row.lastFS and row.lastFS.SetTextColor and row.lastColor then pcall(function() row.lastFS:SetTextColor(unpack(row.lastColor)) end) end
        if row.classIcon then row.classIcon:SetVertexColor(1,1,1) end
        if row.hl and row.hl.center then
          local isSelected = false
          if self.selected and self.members and self.members[self.selected] and self.members[self.selected].name then
            -- prefer name comparison because indices may change after sorting
            local selName = self.selectedName or self.members[self.selected].name
            if selName and m.name and string.lower(selName) == string.lower(m.name) then
              isSelected = true
            end
          elseif self.selected and self.selected == i then
            isSelected = true
          end
          if isSelected then
            if UIFrameFadeIn then UIFrameFadeIn(row.hl.center, 0.15, row.hl.center:GetAlpha() or 0, 0.18) else row.hl.center:SetAlpha(0.18) end
            if row.nameFS then pcall(function() row.nameFS:SetTextColor(1,1,1) end) end
            if row.rankFS then pcall(function() row.rankFS:SetTextColor(1,1,1) end) end
            if row.lastFS then pcall(function() row.lastFS:SetTextColor(1,1,1) end) end
          else
            if UIFrameFadeOut then UIFrameFadeOut(row.hl.center, 0.15, row.hl.center:GetAlpha() or 0.18, 0) else row.hl.center:SetAlpha(0) end
            if row.nameFS and row.nameColor then pcall(function() row.nameFS:SetTextColor(row.nameColor[1], row.nameColor[2], row.nameColor[3]) end) end
            if row.rankFS and row.rankColor then pcall(function() row.rankFS:SetTextColor(row.rankColor[1], row.rankColor[2], row.rankColor[3]) end) end
            if row.lastFS and row.lastColor then pcall(function() row.lastFS:SetTextColor(row.lastColor[1], row.lastColor[2], row.lastColor[3]) end) end
          end
        end
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
