-- Forever Cleanse: one square per group member. The game itself draws the debuffs you can remove
-- (AuraContainer, filter HARMFUL|RAID_PLAYER_DISPELLABLE) and a click casts the right spell (secure button).
-- Rules found with in-game probes:
--   * in combat Lua cannot read auras at all, so it never knows who is afflicted;
--   * nothing may be anchored TO an AuraContainer (the container may be anchored to us);
--   * protected frames move, resize and change attributes only out of combat.
-- So every square has a fixed seat; layout and option changes wait for the end of combat.
local ADDON, ns = ...
local FONTS = "Interface\\AddOns\\ForeverCleanse\\Fonts\\"
local LOGO = "Interface\\AddOns\\ForeverCleanse\\Media\\logo" -- our own art (media/logo.svg → tools/logo.js)
local ICONS = "Interface\\Icons\\"
local FILTER = "HARMFUL|RAID_PLAYER_DISPELLABLE"
local PURGE_FILTER = "HELPFUL|RAID_PLAYER_DISPELLABLE"
local PER_ROW, GAP, PAD, KEY_H = 5, 2, 3, 20

local DEFAULTS = {
  theme = "shadow", mode = "only", pulse = true, sound = true, soundFile = 569200, range = true, purge = true, scale = 100, barAlpha = 82, lock = false, lang = "en",
  -- harmless debuffs nobody wants removed (spell IDs from the Classic data; more can be added in the options)
  ignore = { [15822] = "Dreamless Sleep", [24360] = "Greater Dreamless Sleep", [2096] = "Mind Vision", [10909] = "Mind Vision" },
  seen = {}, -- debuff name -> spell ID, learned out of combat, so the ignore list accepts names
}

-- spell per mouse button (first known name wins) and the debuff types each one removes
local BUTTONS = {
  MAGE = { { "Remove Lesser Curse" } },
  DRUID = { { "Remove Curse" }, { "Abolish Poison", "Cure Poison" } },
  PRIEST = { { "Dispel Magic" }, { "Abolish Disease", "Cure Disease" } },
  PALADIN = { { "Cleanse", "Purify" } },
  SHAMAN = { { "Cure Poison" }, { "Cure Disease" } },
}
local REMOVES = {
  ["Remove Lesser Curse"] = { "Curse" }, ["Remove Curse"] = { "Curse" },
  ["Abolish Poison"] = { "Poison" }, ["Cure Poison"] = { "Poison" },
  ["Dispel Magic"] = { "Magic" }, ["Abolish Disease"] = { "Disease" }, ["Cure Disease"] = { "Disease" },
  ["Cleanse"] = { "Magic", "Poison", "Disease" }, ["Purify"] = { "Poison", "Disease" },
}
local PURGE = { PRIEST = "Dispel Magic", SHAMAN = "Purge" }
local TYPE_COLOR = { Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 } }
local CLASS_COLOR = { WARRIOR = "c69b6d", PALADIN = "f48cba", HUNTER = "aad372", ROGUE = "fff468", PRIEST = "ffffff", SHAMAN = "0070dd", MAGE = "3fc7eb", WARLOCK = "8788ee", DRUID = "ff7c0a" }

-- one look: Forever Pathfinder's (black, minimal, verdigris)
local THEMES = {
  shadow = { frame = { 0, 0, 0, 0.82 }, line = { 0.227, 0.224, 0.212, 1 }, box = { 0.051, 0.051, 0.047, 1 }, boxLine = { 0.149, 0.149, 0.141, 1 },
    ink = { 0.945, 0.933, 0.91 }, soft = { 0.647, 0.631, 0.6 }, acc = { 0.498, 0.831, 0.69 } },
}
local COPPER = { 0.878, 0.627, 0.455 }

local L = {
  en = { options = "Options", grid = "Grid", everyone = "Everyone", only = "Only afflicted",
    alerts = "Alerts", pulse = "Pulsing border", sound = "Sound when a debuff lands", sFlag = "Flag", sDing = "Ding", sBell = "Bell", sReady = "Ready", range = "Fade out of range", purge = "Enemy buff box", noPurge = "(your class has no Purge)",
    ignore = "Ignore these debuffs", add = "Add", size = "Size", barAlpha = "Bar opacity", lock = "Lock position", lang = "Language", target = "Target",
    hint = "Drag to move. Right-click: options.", combat = "In combat: the change waits for the end of the fight.",
    unknown = "Unknown debuff: type its spell ID, or wait until you have seen it once out of combat.",
    noSpell = "Your character has no spell to remove debuffs yet.", noRight = "Right button: your class has no second spell.", help = "/fc options · /fc lock · /fc reset",
    preview = "Preview", pvHint = "Test squares: click them like the real ones. No spell is cast.", clear = "Clear",
    removed = "%s: %s removed.", wrong = "%s does not remove %s: use the other button.", nothing = "%s: nothing to remove.",
    cant = "%s: you cannot remove it, the square stays dark.", far = "%s is out of range.",
    info = "How it works",
    iLit = "Lit square: a debuff you can remove", iPurge = "Enemy target: click its buffs",
    browse = "Browse", reset = "Reset", clearAll = "Clear all", search = "Search", pick = "Click a debuff: it goes in the box, then Add.",
    iMove = "Drag the top bar to move", iSize = "Drag the corner to resize", iOpt = "Options: gear or /fc" },
  it = { options = "Opzioni", grid = "Griglia", everyone = "Tutti", only = "Solo chi ha un debuff",
    alerts = "Avvisi", pulse = "Bordo che pulsa", sound = "Suono quando arriva un debuff", sFlag = "Bandiera", sDing = "Ding", sBell = "Campana", sReady = "Pronti", range = "Sbiadisci fuori portata", purge = "Casella dei buff nemici", noPurge = "(la tua classe non ha Purge)",
    ignore = "Ignora questi debuff", add = "Aggiungi", size = "Dimensione", barAlpha = "Opacità della barra", lock = "Blocca la posizione", lang = "Lingua", target = "Bersaglio",
    hint = "Trascina per spostare. Clic destro: opzioni.", combat = "In combattimento: la modifica arriva a fine combattimento.",
    unknown = "Debuff sconosciuto: scrivi il suo spell ID, o aspetta di vederlo una volta fuori combattimento.",
    noSpell = "Il tuo personaggio non ha ancora spell per togliere debuff.", noRight = "Tasto destro: la tua classe non ha una seconda spell.", help = "/fc opzioni · /fc lock · /fc reset",
    preview = "Anteprima", pvHint = "Caselle di prova: cliccale come quelle vere. Nessuna spell viene lanciata.", clear = "Pulisci",
    removed = "%s: %s tolta.", wrong = "%s non toglie %s: usa l'altro tasto.", nothing = "%s: niente da togliere.",
    cant = "%s: non puoi toglierlo, la casella resta spenta.", far = "%s è fuori portata.",
    info = "Come funziona",
    iLit = "Casella accesa: un debuff che puoi togliere", iPurge = "Bersaglio nemico: clicca i suoi buff",
    browse = "Sfoglia", reset = "Ripristina", clearAll = "Togli tutti", search = "Cerca", pick = "Clicca un debuff: va nella casella, poi Aggiungi.",
    iMove = "Trascina la barra per spostare", iSize = "Trascina l'angolo per ingrandire", iOpt = "Opzioni: ingranaggio o /fc" },
}

local DB, T
local function tr(k) return L[DB and DB.lang or "en"][k] or L.en[k] end
local function say(msg) print("|cff7fd4b0Forever Cleanse|r " .. msg) end
local function hex(h) return tonumber(h:sub(1, 2), 16) / 255, tonumber(h:sub(3, 4), 16) / 255, tonumber(h:sub(5, 6), 16) / 255 end
local function paint(tex, c, a) tex:SetColorTexture(c[1], c[2], c[3], a or c[4] or 1) end

local fonts = {}
local function font(file, size)
  local key = file .. size
  if not fonts[key] then
    local fo = CreateFont("ForeverCleanseFont" .. file:gsub("%W", "") .. size)
    if fo:SetFont(FONTS .. file, size, "") == false then fo:SetFont(STANDARD_TEXT_FONT or "Fonts\\FRIZQT__.TTF", size, "") end
    fo:SetShadowOffset(0, 0)
    fonts[key] = fo
  end
  return fonts[key]
end

local function knows(name)
  local ok, info = pcall(C_Spell.GetSpellInfo, name)
  local id = ok and type(info) == "table" and info.spellID
  return id and IsPlayerSpell(id) and true or false
end

-- the spells this character can cast now: { left = name, right = name, types = { left = {...}, right = {...} } }
local spells = {}
local function resolveSpells()
  local _, class = UnitClass("player")
  local set = BUTTONS[class] or {}
  local function first(list) for _, n in ipairs(list or {}) do if knows(n) then return n end end end
  spells.left = first(set[1])
  spells.right = set[2] and first(set[2]) or nil -- one spell per button: no second spell, the right button does nothing
  spells.purge = PURGE[class] and knows(PURGE[class]) and PURGE[class] or nil
end

-- deferred work: anything touching protected frames waits for the end of combat
local pending = {}
local function later(fn)
  if InCombatLockdown() then pending[fn] = true; return true end
  fn()
end

---------------------------------------------------------------- main frame
local main, key, grid, grip, target
local tiles = {}
local toggleOptions -- defined with the options window

-- options button at the right end of a key strip: the game's own gear (by name, nothing bundled)
local GEAR_ATLAS = { "GM-icon-settings", "QuestLog-icon-setting", "OptionsIcon-Brown" }
local function atlas(tex, name) return pcall(tex.SetAtlas, tex, name) and tex.GetAtlas and tex:GetAtlas() == name end
local function setGear(tex)
  for _, a in ipairs(GEAR_ATLAS) do if atlas(tex, a) then return end end
  tex:SetTexture("Interface\\Buttons\\UI-OptionsButton")
end
local function makeCog(key)
  local b = CreateFrame("Button", nil, key)
  b:SetSize(16, 16); b:SetPoint("RIGHT", key, "RIGHT", -2, 0)
  b.icon = b:CreateTexture(nil, "ARTWORK"); b.icon:SetAllPoints()
  setGear(b.icon)
  b.icon:SetVertexColor(0.8, 0.8, 0.8)
  b:SetScript("OnClick", function() toggleOptions() end)
  b:SetScript("OnEnter", function(self)
    self.icon:SetVertexColor(1, 1, 1)
    GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tr("options")); GameTooltip:Show()
  end)
  b:SetScript("OnLeave", function(self) self.icon:SetVertexColor(0.8, 0.8, 0.8); GameTooltip:Hide() end)
  b:SetScript("OnMouseDown", function(self) self.icon:SetPoint("TOPLEFT", 1, -1); self.icon:SetPoint("BOTTOMRIGHT", 1, -1) end)
  b:SetScript("OnMouseUp", function(self) self.icon:SetAllPoints() end)
  key.cog = b
  return b
end

local function dims(n)
  n = n or (IsInRaid() and GetNumGroupMembers() or 5)
  if n > 10 then return 36, 10, 20 end
  if n > 5 then return 42, 11, 25 end
  return 48, 12, 30
end

-- 2nd-4th debuff on one member: the icon is cut on its centre, one piece per debuff.
-- Part k's region in the square (x, y from the top-left, width, height): 2 = right half, 3 = bottom-left, 4 = bottom-right.
local function partGeom(k, w, iconSize)
  local hb = 3 + iconSize / 2 -- from the bottom edge to the icon's centre
  if k == 2 then return w / 2, 0, w / 2, w, hb end
  return (k == 3 and 0 or w / 2), w - hb, w / 2, hb, hb
end
-- put a part's icon so that its centre sits on the whole icon's centre; the region's clip keeps only its piece
local function placePartIcon(icon, region, k, w, iconSize)
  local px, py, _, _, hb = partGeom(k, w, iconSize)
  icon:ClearAllPoints(); icon:SetSize(iconSize, iconSize)
  icon:SetPoint("CENTER", region, "TOPLEFT", w / 2 - px, -((w - hb) - py))
end

local function ignoreSet()
  local set = {}
  for id in pairs(DB.ignore) do set[id] = true end
  set[0] = true -- never empty, the native filter wants a table with content
  return set
end

-- dress one native aura button: the game's type border + symbol, icon, swipe, stacks, name, pulse
-- (the game draws the type as a border with a corner symbol; it refuses SetTexCoord in combat, so no full-square fill)
local function decorate(t, b)
  local w, nameSize, iconSize = dims()
  local part = b.fcPart -- 2nd-4th debuff: one piece of the square (partGeom), clipped
  local _, py, pw, ph = partGeom(part or 2, w, iconSize)
  if part then b:SetSize(pw, ph) else b:SetSize(w, w) end
  pcall(b.SetMouseClickEnabled, b, false) -- clicks go through to our secure square
  local th = THEMES[DB.theme]
  if part and not b.fcBg then b.fcBg = b:CreateTexture(nil, "BACKGROUND", nil, 0) end -- hides the pieces underneath (the name above stays)
  if b.fcBg then b.fcBg:ClearAllPoints(); b.fcBg:SetPoint("TOPLEFT", b, "TOPLEFT", 0, -math.max(0, nameSize + 5 - py)); b.fcBg:SetPoint("BOTTOMRIGHT", b, "BOTTOMRIGHT") end
  if b.fcBg then paint(b.fcBg, th.box) end
  if not b.fcFill then
    b.fcFill = b:CreateTexture(nil, "BACKGROUND", nil, 1)
    b.fcFill:SetAllPoints(b)
    pcall(b.AddDispelTypeTexture, b, b.fcFill, { showWhenHarmful = true, showWhenHelpful = false })
    b.fcIcon = b:CreateTexture(nil, "ARTWORK")
    b:SetIcon(b.fcIcon)
    b.fcCd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
    b.fcCd:SetReverse(true); b.fcCd:SetDrawEdge(false); b.fcCd:SetDrawBling(false); b.fcCd:SetHideCountdownNumbers(true)
    pcall(b.SetDurationCooldown, b, b.fcCd)
    b.fcCount = b:CreateFontString(nil, "OVERLAY")
    pcall(b.SetApplicationCount, b, b.fcCount, {})
    b.fcName = b:CreateFontString(nil, "OVERLAY")
    b.fcName:SetJustifyH("LEFT"); b.fcName:SetWordWrap(false)
    -- pulse: built fully before the native registration adopts it
    b.fcPulse = b:CreateAnimationGroup()
    local a = b.fcPulse:CreateAnimation("Alpha")
    a:SetTarget(b.fcFill); a:SetFromAlpha(1); a:SetToAlpha(0.3); a:SetDuration(0.55)
    b.fcPulse:SetLooping("BOUNCE")
    t.buttons[#t.buttons + 1] = b
  end
  b.fcFill:SetAlpha(1)
  if part then placePartIcon(b.fcIcon, b, part, w, iconSize)
  else b.fcIcon:ClearAllPoints(); b.fcIcon:SetSize(iconSize, iconSize); b.fcIcon:SetPoint("BOTTOM", b, "BOTTOM", 0, 3) end
  b.fcCd:ClearAllPoints(); b.fcCd:SetAllPoints(b.fcIcon)
  b.fcCount:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 10)); b.fcCount:SetTextColor(COPPER[1], COPPER[2], COPPER[3])
  b.fcCount:ClearAllPoints(); b.fcCount:SetPoint("BOTTOMRIGHT", b.fcIcon, "BOTTOMRIGHT", 1, -1)
  b.fcName:SetFontObject(font("BarlowCondensed-SemiBold.ttf", nameSize)); b.fcName:SetTextColor(th.ink[1], th.ink[2], th.ink[3])
  b.fcName:ClearAllPoints(); b.fcName:SetPoint("TOPLEFT", b, "TOPLEFT", 3, -3); b.fcName:SetPoint("RIGHT", b, "RIGHT", -14, 0) -- the game puts the type symbol in the top-right corner
  b.fcName:SetText(t.unitName or "")
  b.fcName:SetShown(DB.mode == "only" and not part)
  if DB.pulse and not b.fcPulseOn then b.fcPulseOn = pcall(b.AddAuraShownAnimation, b, b.fcPulse) end
  if not DB.pulse and b.fcPulseOn then pcall(b.RemoveAuraShownAnimation, b, b.fcPulse); b.fcPulseOn = false end
end

local function makeContainer(parent, filter, count, element, init)
  local c = CreateFrame("AuraContainer", nil, parent, "CustomAuraContainerTemplate")
  c:SetEnabled(false)
  c:Hide()
  c:SetFlowLayoutAxis(AnchorUtil.FlowLayoutAxis.Horizontal)
  c:SetFlowLayoutAnchorPoint("TOPLEFT")
  c:SetFlowLayoutGrowthDirection(AnchorUtil.FlowDirection.Right, AnchorUtil.FlowDirection.Down)
  c.fcGroup = "ForeverCleanse" .. tostring(c):gsub("%W", "")
  c:AddAuraGroup(c.fcGroup, filter, {
    maxFrameCount = count,
    sortMethod = (rawget(_G, "AuraContainerSortMethod") or { Default = 1 }).Default,
    sortDirection = (rawget(_G, "AuraContainerSortDirection") or { Normal = 1 }).Normal,
    candidateFilters = { excludeSpellIDs = ignoreSet() },
    layout = { elementWidth = element, elementHeight = element, elementSpacing = 2, lineSpacing = 2 },
    initializeFrame = init,
  })
  pcall(c.EnableMouse, c, false)
  return c
end

local function newTile(i)
  local t = CreateFrame("Button", "ForeverCleanseTile" .. i, grid, "SecureActionButtonTemplate")
  t:RegisterForClicks("AnyUp", "AnyDown") -- the secure template only acts on the one matching ActionButtonUseKeyDown
  t:SetAttribute("type1", "spell")
  t:SetAttribute("type2", "spell")
  t.buttons = {}
  t.vis = CreateFrame("Frame", nil, t)
  t.vis:SetAllPoints()
  t.edge = t.vis:CreateTexture(nil, "BACKGROUND", nil, -2); t.edge:SetAllPoints()
  t.bg = t.vis:CreateTexture(nil, "BACKGROUND", nil, -1); t.bg:SetPoint("TOPLEFT", 1, -1); t.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  t.tick = t.vis:CreateTexture(nil, "BORDER"); t.tick:SetHeight(2); t.tick:SetPoint("BOTTOMLEFT", 1, 1); t.tick:SetPoint("BOTTOMRIGHT", -1, 1)
  t.name = t.vis:CreateFontString(nil, "OVERLAY"); t.name:SetJustifyH("LEFT"); t.name:SetWordWrap(false)
  t.hl = t.vis:CreateTexture(nil, "OVERLAY", nil, 7); t.hl:SetAllPoints(); t.hl:Hide()
  t:HookScript("OnEnter", function() t.hl:Show() end)
  t:HookScript("OnLeave", function() t.hl:Hide() end)
  t.aura = makeContainer(t.vis, FILTER, 1, 48, function(b)
    local ok, err = pcall(decorate, t, b)
    if not ok then say("decorate: " .. tostring(err)) end
  end)
  t.aura:SetPoint("TOPLEFT", t, "TOPLEFT")
  -- debuffs 2-4: for part k, a native row of k slots laid so that slot k falls on its region, clipped to that region:
  -- slot k exists only when the member has k debuffs (Lua cannot count auras in combat), the game shifts them when one goes
  t.parts = {}
  for k = 2, 4 do
    local clip = CreateFrame("Frame", nil, t.vis)
    clip:SetClipsChildren(true)
    clip.aura = makeContainer(clip, FILTER, k, 24, function(b)
      b.fcPart = k
      local ok, err = pcall(decorate, t, b)
      if not ok then say("decorate: " .. tostring(err)) end
    end)
    t.parts[k] = clip
  end
  t:Hide()
  return t
end

---------------------------------------------------------------- key strip
-- the key strip is drawn on the real frame and on the preview, so it takes the strip as argument
-- the spell's own icon (by id from the game, nothing bundled) and "Curse · Poison" in the type colours
local function spellTexture(name)
  local ok, si = pcall(C_Spell.GetSpellInfo, name)
  return ok and type(si) == "table" and si.iconID or "Interface\\Icons\\INV_Misc_QuestionMark"
end
local function typeNames(spell)
  local out = {}
  for _, ty in ipairs(REMOVES[spell] or {}) do
    local c = TYPE_COLOR[ty]
    out[#out + 1] = ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, ty)
  end
  return table.concat(out, " · ")
end

local function keyPart(key, i)
  key.parts = key.parts or {}
  if key.parts[i] then return key.parts[i] end
  local p = { mouse = key:CreateTexture(nil, "ARTWORK"), icon = key:CreateTexture(nil, "ARTWORK"), text = key:CreateFontString(nil, "OVERLAY") }
  p.mouse:SetSize(12, 16)
  p.icon:SetSize(16, 16); p.icon:SetTexCoord(0.07, 0.93, 0.07, 0.93) -- trim the icon's own border
  p.letter = key:CreateFontString(nil, "OVERLAY")
  key.parts[i] = p
  return p
end

local function renderKey(key)
  local th = THEMES[DB.theme]
  local x = 22
  local list = {}
  if spells.left then list[1] = { spells.left, "L" } end
  if spells.right then list[2] = { spells.right, "R" } end
  for i = 1, 2 do
    local p = keyPart(key, i)
    local item = list[i]
    p.mouse:SetShown(item ~= nil); p.icon:SetShown(item ~= nil); p.text:SetShown(item ~= nil); p.letter:SetShown(false)
    if item then
      local atlas = item[2] == "R" and "NPE_RightClick" or "NPE_LeftClick"
      local ok = pcall(p.mouse.SetAtlas, p.mouse, atlas) and p.mouse.GetAtlas and p.mouse:GetAtlas() == atlas
      p.mouse:ClearAllPoints(); p.mouse:SetPoint("LEFT", key, "LEFT", x, 0)
      if not ok then
        p.mouse:Hide(); p.letter:Show()
        p.letter:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 12)); p.letter:SetTextColor(th.acc[1], th.acc[2], th.acc[3])
        p.letter:SetText(item[2] == "R" and "R" or "L"); p.letter:ClearAllPoints(); p.letter:SetPoint("LEFT", key, "LEFT", x + 2, 0)
      end
      x = x + 15
      p.icon:SetTexture(spellTexture(item[1])); p.icon:ClearAllPoints(); p.icon:SetPoint("LEFT", key, "LEFT", x, 0)
      x = x + 18
      p.text:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); p.text:SetTextColor(th.ink[1], th.ink[2], th.ink[3])
      p.text:SetText(typeNames(item[1])); p.text:ClearAllPoints(); p.text:SetPoint("LEFT", key, "LEFT", x + 2, 0)
      x = x + 2 + p.text:GetStringWidth() + 12
    end
  end
  if not list[1] then
    local p = keyPart(key, 1)
    p.text:Show(); p.text:SetFontObject(font("Barlow-Regular.ttf", 12)); p.text:SetTextColor(th.soft[1], th.soft[2], th.soft[3])
    p.text:SetText(tr("noSpell")); p.text:ClearAllPoints(); p.text:SetPoint("LEFT", key, "LEFT", 22, 0)
    x = 22 + p.text:GetStringWidth() + 8
  end
  key.need = x
end

---------------------------------------------------------------- layout (out of combat only)
local function units()
  local list = {}
  if IsInRaid() then
    local groups = {}
    for i = 1, GetNumGroupMembers() do
      local _, _, sub = GetRaidRosterInfo(i)
      sub = sub or 1
      groups[sub] = groups[sub] or {}
      table.insert(groups[sub], "raid" .. i)
    end
    for g = 1, 8 do
      if groups[g] then
        for _, u in ipairs(groups[g]) do list[#list + 1] = u end
        while #list % PER_ROW ~= 0 do list[#list + 1] = false end -- each group starts a new row
      end
    end
  else
    list[1] = "player"
    for i = 1, GetNumSubgroupMembers() do list[#list + 1] = "party" .. i end
  end
  return list
end

local function paintTile(t)
  local th = THEMES[DB.theme]
  local only = DB.mode == "only"
  paint(t.edge, th.boxLine); paint(t.bg, th.box)
  t.edge:SetShown(not only); t.bg:SetShown(not only); t.tick:SetShown(not only); t.name:SetShown(not only)
  t.hl:SetColorTexture(th.acc[1], th.acc[2], th.acc[3], 0.18)
  t.name:SetTextColor(th.ink[1], th.ink[2], th.ink[3])
end

-- sound: in combat Lua cannot see auras, so the game itself plays it when a debuff you can remove lands.
-- C_UnitAuras.AddAuraSound(trigger, info), trigger 0 = aura added (format as in DBM): one registration per unit and spell ID.
-- ponytail: a raid Paladin means ~1100 IDs x 40 units; and an AoE curse on 20 people plays 20 overlapping sounds (each registration throttles alone).
-- the game's own sound files (IDs as used by DBM): PvP flag taken, ding, night elf bell, ready check
local SOUNDS = { { 569200, "sFlag" }, { 567458, "sDing" }, { 566558, "sBell" }, { 567478, "sReady" } }
local soundIds, soundKey = {}, nil
local function syncSounds(list)
  local add = C_UnitAuras and C_UnitAuras.AddAuraSound
  local remove = C_UnitAuras and (C_UnitAuras.RemoveAuraSound or C_UnitAuras.RemovePrivateAuraAppliedSound)
  if not add then return end
  local types, us, ign = {}, {}, {}
  for _, s in ipairs({ spells.left or "", spells.right or "" }) do for _, ty in ipairs(REMOVES[s] or {}) do types[ty] = true end end
  for _, u in ipairs(list) do if u then us[#us + 1] = u end end
  for id in pairs(DB.ignore) do ign[#ign + 1] = id end
  table.sort(ign)
  local k = tostring(DB.sound) .. DB.soundFile .. table.concat(us, ",") .. tostring(types.Curse) .. tostring(types.Poison) .. tostring(types.Disease) .. tostring(types.Magic) .. table.concat(ign, ",")
  if k == soundKey then return end
  soundKey = k
  for _, id in ipairs(soundIds) do if remove then pcall(remove, id) end end
  soundIds = {}
  if not DB.sound then return end
  for _, ty in ipairs({ "Curse", "Poison", "Disease", "Magic" }) do
    for _, row in ipairs(types[ty] and ns.DEBUFFS[ty] or {}) do
      for i = 2, #row do
        if not DB.ignore[row[i]] then
          for _, u in ipairs(us) do
            local ok, id = pcall(add, 0, { unitToken = u, spellID = row[i], soundFileID = DB.soundFile, outputChannel = "Master", throttleSeconds = 2 })
            if ok and id then soundIds[#soundIds + 1] = id end
          end
        end
      end
    end
  end
end

local function layout()
  if not main then return end
  resolveSpells()
  local w, nameSize = dims()
  local list = units()
  syncSounds(list)
  local used = 0
  for i, unit in ipairs(list) do
    if unit then
      used = used + 1
      local t = tiles[used] or newTile(used)
      tiles[used] = t
      local col, row = (i - 1) % PER_ROW, math.floor((i - 1) / PER_ROW)
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", grid, "TOPLEFT", col * (w + GAP), -row * (w + GAP))
      t:SetSize(w, w)
      t:SetAttribute("unit", unit)
      t:SetAttribute("spell1", spells.left)
      t:SetAttribute("type2", spells.right and "spell" or nil)
      t:SetAttribute("spell2", spells.right)
      t.unit = unit
      t.unitName = UnitName(unit)
      local _, class = UnitClass(unit)
      t.tick:SetColorTexture(hex(CLASS_COLOR[class] or "7b7770")); t.tick:SetAlpha(0.75)
      t.name:SetFontObject(font("BarlowCondensed-SemiBold.ttf", nameSize))
      t.name:ClearAllPoints(); t.name:SetPoint("TOPLEFT", t, "TOPLEFT", 3, -3); t.name:SetPoint("RIGHT", t, "RIGHT", -14, 0)
      t.name:SetText(t.unitName or unit)
      paintTile(t)
      t.aura:SetSize(w, w)
      t.aura:SetUnit(unit)
      t.aura:SetFlowLayoutMaximumLineSize(w)
      t.aura:SetAuraGroupLayout(t.aura.fcGroup, { elementWidth = w, elementHeight = w, elementSpacing = 0, lineSpacing = 0 })
      t.aura:SetAuraGroupCandidateFilters(t.aura.fcGroup, { excludeSpellIDs = ignoreSet() })
      for _, b in ipairs(t.buttons) do pcall(decorate, t, b) end
      t.aura:Show(); t.aura:SetEnabled(true)
      for k = 2, 4 do
        local clip, c = t.parts[k], t.parts[k].aura
        local px, py, pw, ph = partGeom(k, w, select(3, dims()))
        local x0 = k == 2 and 0 or -w -- slot k starts at x0 + (k - 1) * w / 2 = px
        clip:ClearAllPoints(); clip:SetPoint("TOPLEFT", t, "TOPLEFT", px, -py); clip:SetSize(pw, ph)
        clip:SetFrameLevel(t.aura:GetFrameLevel() + 10 * k)
        c:ClearAllPoints(); c:SetPoint("TOPLEFT", t, "TOPLEFT", x0, -py)
        c:SetSize(k * w / 2, ph)
        c:SetUnit(unit)
        c:SetFlowLayoutMaximumLineSize(k * w / 2)
        c:SetAuraGroupLayout(c.fcGroup, { elementWidth = w / 2, elementHeight = ph, elementSpacing = 0, lineSpacing = 0 })
        c:SetAuraGroupCandidateFilters(c.fcGroup, { excludeSpellIDs = ignoreSet() })
        c:Show(); c:SetEnabled(true)
      end
      t:Show()
    end
  end
  for i = used + 1, #tiles do tiles[i]:Hide(); tiles[i].aura:SetEnabled(false); for k = 2, 4 do tiles[i].parts[k].aura:SetEnabled(false) end; tiles[i].unit = nil end
  local rows = math.max(1, math.ceil(#list / PER_ROW))
  local cols = math.min(math.max(#list, 1), PER_ROW) -- solo or small party: no empty columns
  local gw, gh = cols * w + (cols - 1) * GAP, rows * w + (rows - 1) * GAP
  grid:SetSize(gw, gh)

  -- enemy buffs (Purge / Dispel Magic on the target)
  local showTarget = spells.purge and DB.purge
  target:SetShown(showTarget and true or false)
  local th = THEMES[DB.theme]
  if showTarget then
    target:SetAttribute("type1", "spell"); target:SetAttribute("spell1", spells.purge); target:SetAttribute("unit", "target")
    target:SetSize(gw, 24)
    paint(target.edge, th.boxLine); paint(target.bg, th.box)
    target.label:SetFontObject(font("BarlowCondensed-Medium.ttf", 12)); target.label:SetTextColor(th.soft[1], th.soft[2], th.soft[3])
    target.label:SetText(tr("target") .. " · " .. spells.purge)
    target.aura:SetAuraGroupCandidateFilters(target.aura.fcGroup, { excludeSpellIDs = ignoreSet() })
    target.aura:Show(); target.aura:SetEnabled(true)
  else
    target.aura:SetEnabled(false)
  end

  renderKey(key)
  local width = math.max(gw, key.need + 22)
  main:SetSize(width + PAD * 2, PAD + KEY_H + GAP + gh + (showTarget and (GAP + 24) or 0) + PAD)
  key:SetWidth(width)
  local only = DB.mode == "only"
  paint(main.bg, th.frame, DB.barAlpha / 100); main.bg:SetShown(not only)
  paint(main.edge, th.line); main.edge:SetShown(not only)
  paint(key.bg, th.frame, DB.barAlpha / 100); key.bg:SetShown(only)
  main:SetScale(DB.scale / 100)
  grip:SetShown(not DB.lock)
end

---------------------------------------------------------------- preview: shown while the options are open, fake squares, no spell is cast
local PV_NAMES = { "Nimra","Grumok", "Elyra", "Thadrin", "Vessa", "Korgan", "Lirael", "Brannoc", "Syla", "Durnik", "Meriel", "Oswin", "Tazrik",
  "Ilsa", "Fennick", "Rowan", "Zuhra", "Kael", "Mirth", "Gorrin", "Anwen", "Bolt", "Cerys", "Dagna", "Eamon", "Freya", "Gideon", "Hesk",
  "Iona", "Jorvik", "Kestra", "Lugh", "Maeve", "Nox", "Orla", "Pike", "Quill", "Rusk", "Sable" }
local PV_CLASSES = { "WARRIOR", "PRIEST", "HUNTER", "ROGUE", "WARLOCK", "DRUID", "SHAMAN", "PALADIN", "MAGE" }
local PV_DEBUFF = { Curse = { "Curse of Tongues", "Spell_Shadow_CurseOfTounges" }, Poison = { "Corrosive Poison", "Spell_Nature_CorrosiveBreath" },
  Disease = { "Creeping Plague", "Spell_Shadow_CreepingPlague" }, Magic = { "Slow", "Spell_Nature_Slow" } }
local TYPE_ORDER = { "Curse", "Poison", "Disease", "Magic" }
local pv
local pvState = { size = 5, deb = {} } -- deb[i] = { type, type }: up to two debuffs per member

local function removes(spell, ty) for _, x in ipairs(REMOVES[spell] or {}) do if x == ty then return true end end return false end
-- a few icons per type, so the pieces of a square with several debuffs look different
local PV_ICONS = {
  Curse = { "Spell_Shadow_CurseOfTounges", "Spell_Shadow_CurseOfSargeras", "Spell_Shadow_CurseOfMannoroth", "Spell_Shadow_UnholyStrength", "Spell_Shadow_ChillTouch", "Spell_Shadow_CurseOfAchimonde", "Spell_Shadow_GrimWard", "Spell_Shadow_AuraOfDarkness" },
  Poison = { "Spell_Nature_CorrosiveBreath", "Ability_Creature_Poison_02", "Ability_PoisonSting", "Ability_Creature_Poison_05", "Ability_Creature_Poison_03" },
  Disease = { "Spell_Shadow_CreepingPlague", "Spell_Shadow_CallofBone", "Ability_Creature_Disease_02", "Ability_Creature_Disease_03" },
  Magic = { "Spell_Nature_Slow", "Spell_Frost_FrostNova", "Spell_Shadow_Possession", "Spell_Nature_Polymorph", "Spell_Shadow_ShadowWordPain", "Spell_Frost_FrostBolt02" },
}
local function canRemove(ty) return removes(spells.left, ty) or removes(spells.right, ty) end
local function pvName(i) return i == 1 and (UnitName("player") or "You") or PV_NAMES[i - 1] end
local function pvFar(i) return DB.range and i > 1 and i % 4 == 0 end

local function pvButton(parent, w, text)
  local b = CreateFrame("Button", nil, parent)
  b:SetSize(w, 20)
  b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.102, 0.102, 0.094, 1)
  b.t = b:CreateFontString(nil, "OVERLAY"); b.t:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 12)); b.t:SetPoint("CENTER"); b.t:SetTextColor(0.945, 0.933, 0.91)
  b.t:SetText(text or "")
  b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.227, 0.224, 0.212, 1) end)
  b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.102, 0.102, 0.094, 1) end)
  return b
end

-- what the real square shows: only the debuffs you can remove, up to four, the icon cut in one piece each
local function pvVisible(i)
  local out = {}
  for _, ty in ipairs(pvState.deb[i] or {}) do if canRemove(ty) and #out < 4 then out[#out + 1] = ty end end
  return out
end

local pvRender
local function pvTile(i)
  local t = CreateFrame("Button", nil, pv.grid)
  t:RegisterForClicks("AnyUp")
  t.edge = t:CreateTexture(nil, "BACKGROUND", nil, -2); t.edge:SetAllPoints()
  t.bg = t:CreateTexture(nil, "BACKGROUND", nil, -1); t.bg:SetPoint("TOPLEFT", 1, -1); t.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  t.mark = t:CreateTexture(nil, "ARTWORK", nil, 2); t.mark:SetSize(8, 8); t.mark:SetPoint("TOPRIGHT", -2, -2) -- stands in for the game's type symbol
  t.tick = t:CreateTexture(nil, "ARTWORK"); t.tick:SetHeight(2); t.tick:SetPoint("BOTTOMLEFT", 1, 1); t.tick:SetPoint("BOTTOMRIGHT", -1, 1)
  t.icon = t:CreateTexture(nil, "ARTWORK", nil, 1)
  t.name = t:CreateFontString(nil, "OVERLAY"); t.name:SetJustifyH("LEFT"); t.name:SetWordWrap(false)
  t.hl = t:CreateTexture(nil, "HIGHLIGHT"); t.hl:SetAllPoints()
  -- debuffs 2-4: one clipped piece each with its own border and its icon on the whole icon's centre, like the real square
  t.parts = {}
  for k = 2, 4 do
    local p = CreateFrame("Frame", nil, t); p:SetClipsChildren(true); p:SetFrameLevel(t:GetFrameLevel() + k)
    p.bg = p:CreateTexture(nil, "BACKGROUND", nil, 1); p.bg:SetPoint("BOTTOMRIGHT")
    p.icon = p:CreateTexture(nil, "ARTWORK", nil, 1)
    p.lines = {}
    for n, pts in ipairs({ { "TOPLEFT", "TOPRIGHT" }, { "BOTTOMLEFT", "BOTTOMRIGHT" }, { "TOPLEFT", "BOTTOMLEFT" }, { "TOPRIGHT", "BOTTOMRIGHT" } }) do
      local l = p:CreateTexture(nil, "ARTWORK", nil, 3); l:SetPoint(pts[1]); l:SetPoint(pts[2])
      if n <= 2 then l:SetHeight(1) else l:SetWidth(1) end
      p.lines[n] = l
    end
    if k == 2 then p.mark = p:CreateTexture(nil, "ARTWORK", nil, 4); p.mark:SetSize(8, 8); p.mark:SetPoint("TOPRIGHT", -2, -2) end
    t.parts[k] = p
  end
  t.pulse = t:CreateAnimationGroup()
  t.pulseA = t.pulse:CreateAnimation("Alpha"); t.pulseA:SetTarget(t.edge); t.pulseA:SetDuration(0.55)
  t.pulse:SetLooping("BOUNCE")
  t:SetScript("OnClick", function(_, button)
    local spell = spells.left
    if button == "RightButton" then spell = spells.right end
    local vis, list = pvVisible(i), pvState.deb[i] or {}
    local hit -- index in the member's list of the first visible debuff this spell removes
    for k, ty in ipairs(list) do if not hit and canRemove(ty) and removes(spell or "", ty) then hit = k end end
    if not spell then pv.msg:SetText(tr(spells.left and "noRight" or "noSpell"))
    elseif pvFar(i) then pv.msg:SetText(tr("far"):format(pvName(i)))
    elseif not vis[1] then pv.msg:SetText(tr("nothing"):format(spell))
    elseif not hit then pv.msg:SetText(tr("wrong"):format(spell, vis[1]))
    else
      local ty = table.remove(list, hit)
      if not list[1] then pvState.deb[i] = nil end
      pv.msg:SetText(tr("removed"):format(spell, PV_DEBUFF[ty][1])); pvRender()
    end
  end)
  pv.tiles[i] = t
  return t
end

-- put a debuff of this type on a random member (no limit: past the fourth they wait their turn, as in the game)
local function pvAdd(ty)
  local i = math.random(pvState.size)
  pvState.deb[i] = pvState.deb[i] or {}
  table.insert(pvState.deb[i], ty)
  if DB.sound and canRemove(ty) then PlaySoundFile(DB.soundFile, "Master") end
  pv.msg:SetText(canRemove(ty) and (pvName(i) .. ": " .. PV_DEBUFF[ty][1]) or tr("cant"):format(pvName(i) .. ", " .. ty))
  pvRender()
end

local function makePreview()
  pv = CreateFrame("Frame", "ForeverCleansePreview", UIParent)
  pv:SetFrameStrata("FULLSCREEN_DIALOG")
  pv:SetClampedToScreen(true)
  pv.tiles, pv.sizeB, pv.typeB = {}, {}, {}
  pv.edge = pv:CreateTexture(nil, "BACKGROUND", nil, -2); pv.edge:SetPoint("TOPLEFT", -1, 1); pv.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  pv.bg = pv:CreateTexture(nil, "BACKGROUND", nil, -1); pv.bg:SetAllPoints()
  pv.key = CreateFrame("Frame", nil, pv); pv.key:SetPoint("TOPLEFT", PAD, -PAD); pv.key:SetHeight(KEY_H)
  pv.key.bg = pv.key:CreateTexture(nil, "BACKGROUND"); pv.key.bg:SetAllPoints()
  pv.key.mark = pv.key:CreateTexture(nil, "ARTWORK"); pv.key.mark:SetSize(16, 16); pv.key.mark:SetPoint("LEFT", 2, 0); pv.key.mark:SetTexture(LOGO)
  makeCog(pv.key)
  -- dragging the preview moves the real frame underneath (out of combat)
  pv.key:EnableMouse(true); pv.key:RegisterForDrag("LeftButton")
  pv.key:SetScript("OnDragStart", function() if main and not DB.lock and not InCombatLockdown() then main:StartMoving() end end)
  pv.key:SetScript("OnDragStop", function()
    if not main then return end
    main:StopMovingOrSizing()
    local a, _, b, x, y = main:GetPoint()
    DB.point = { a, nil, b, x, y }
  end)
  pv.grid = CreateFrame("Frame", nil, pv); pv.grid:SetPoint("TOPLEFT", pv.key, "BOTTOMLEFT", 0, -GAP)

  -- test bench under the squares
  pv.bar = CreateFrame("Frame", nil, pv); pv.bar:SetSize(262, 98)
  pv.bar.bg = pv.bar:CreateTexture(nil, "BACKGROUND"); pv.bar.bg:SetAllPoints(); pv.bar.bg:SetColorTexture(0, 0, 0, 0.92)
  pv.title = pv.bar:CreateFontString(nil, "OVERLAY"); pv.title:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); pv.title:SetTextColor(0.663, 0.847, 0.773)
  pv.title:SetPoint("TOPLEFT", 6, -5)
  for n, ty in ipairs(TYPE_ORDER) do
    local b = pvButton(pv.bar, 61, ty)
    b:SetPoint("TOPLEFT", 6 + (n - 1) * 63, -22)
    b.sw = b:CreateTexture(nil, "ARTWORK"); b.sw:SetSize(8, 8); b.sw:SetPoint("LEFT", 5, 0)
    local c = TYPE_COLOR[ty]; b.sw:SetColorTexture(c[1], c[2], c[3], 1)
    b.t:ClearAllPoints(); b.t:SetPoint("LEFT", b.sw, "RIGHT", 4, 0)
    b:SetScript("OnClick", function() pvAdd(ty) end)
    pv.typeB[n] = b
  end
  pv.clear = pvButton(pv.bar, 61)
  pv.clear:SetPoint("TOPLEFT", 6, -44)
  pv.clear:SetScript("OnClick", function() pvState.deb = {}; pv.msg:SetText(""); pvRender() end)
  for n, size in ipairs({ 5, 10, 40 }) do
    local b = pvButton(pv.bar, 40, tostring(size))
    b:SetPoint("TOPLEFT", 132 + (n - 1) * 42, -44)
    b:SetScript("OnClick", function() pvState.size = size; pvRender() end)
    b.size = size
    pv.sizeB[n] = b
  end
  pv.msg = pv.bar:CreateFontString(nil, "OVERLAY"); pv.msg:SetFontObject(font("Barlow-Regular.ttf", 12)); pv.msg:SetTextColor(0.945, 0.933, 0.91)
  pv.msg:SetPoint("TOPLEFT", 6, -70); pv.msg:SetWidth(250); pv.msg:SetJustifyH("LEFT")
  pv.hint = pv.bar:CreateFontString(nil, "OVERLAY"); pv.hint:SetFontObject(font("Barlow-Regular.ttf", 11)); pv.hint:SetTextColor(0.482, 0.467, 0.439)
  pv.hint:SetPoint("TOPLEFT", pv.msg, "BOTTOMLEFT", 0, -3); pv.hint:SetWidth(250); pv.hint:SetJustifyH("LEFT")
  pv:Hide()
end

pvRender = function()
  if not pv or not pv:IsShown() then return end
  local th = THEMES[DB.theme]
  local only = DB.mode == "only"
  local n = pvState.size
  local w, nameSize, iconSize = dims(n)
  renderKey(pv.key)
  local rows = math.ceil(n / PER_ROW)
  local gw, gh = PER_ROW * w + (PER_ROW - 1) * GAP, rows * w + (rows - 1) * GAP
  pv.grid:SetSize(gw, gh)
  for i = 1, 40 do
    local t = pv.tiles[i] or (i <= n and pvTile(i))
    if t and i <= n then
      local vis = pvVisible(i)
      local ty = vis[1]
      local lit = ty ~= nil
      t:ClearAllPoints()
      t:SetPoint("TOPLEFT", pv.grid, "TOPLEFT", ((i - 1) % PER_ROW) * (w + GAP), -math.floor((i - 1) / PER_ROW) * (w + GAP))
      t:SetSize(w, w)
      local show = lit or not only
      if lit then local c = TYPE_COLOR[ty]; t.edge:SetColorTexture(c[1], c[2], c[3], 1); t.mark:SetColorTexture(c[1], c[2], c[3], 1)
      else paint(t.edge, th.boxLine) end
      paint(t.bg, th.box)
      t.edge:SetShown(show); t.bg:SetShown(show); t.name:SetShown(show); t.tick:SetShown(show and not only)
      t.mark:SetShown(lit and true or false)
      t.icon:SetShown(lit and true or false)
      if lit then t.icon:SetTexture("Interface\\Icons\\" .. PV_ICONS[ty][(i - 1) % #PV_ICONS[ty] + 1]) end
      t.icon:ClearAllPoints(); t.icon:SetSize(iconSize, iconSize); t.icon:SetPoint("BOTTOM", 0, 3)
      for k = 2, 4 do
        local p, tyk = t.parts[k], vis[k]
        p:SetShown(tyk ~= nil)
        if tyk then
          local c = TYPE_COLOR[tyk]
          local px, py, pw, ph = partGeom(k, w, iconSize)
          p:ClearAllPoints(); p:SetPoint("TOPLEFT", t, "TOPLEFT", px, -py); p:SetSize(pw, ph)
          p.bg:SetPoint("TOPLEFT", 0, -math.max(0, nameSize + 5 - py)); paint(p.bg, th.box)
          for _, l in ipairs(p.lines) do l:SetColorTexture(c[1], c[2], c[3], 1) end
          if p.mark then p.mark:SetColorTexture(c[1], c[2], c[3], 1) end
          placePartIcon(p.icon, p, k, w, iconSize)
          p.icon:SetTexture(ICONS .. PV_ICONS[tyk][(i + k) % #PV_ICONS[tyk] + 1])
        end
      end
      t.name:SetFontObject(font("BarlowCondensed-SemiBold.ttf", nameSize)); t.name:SetTextColor(th.ink[1], th.ink[2], th.ink[3])
      t.name:ClearAllPoints(); t.name:SetPoint("TOPLEFT", 3, -3); t.name:SetPoint("RIGHT", -12, 0)
      t.name:SetText(pvName(i))
      local class = i == 1 and select(2, UnitClass("player")) or PV_CLASSES[(i * 7) % #PV_CLASSES + 1]
      t.tick:SetColorTexture(hex(CLASS_COLOR[class] or "7b7770")); t.tick:SetAlpha(0.75)
      t.hl:SetColorTexture(th.acc[1], th.acc[2], th.acc[3], 0.18)
      t:SetAlpha(pvFar(i) and 0.35 or 1)
      t.pulseA:SetFromAlpha(1); t.pulseA:SetToAlpha(0.3)
      if lit and DB.pulse then if not t.pulse:IsPlaying() then t.pulse:Play() end else t.pulse:Stop() end
      t:Show()
    elseif t then
      t:Hide()
    end
  end
  local width = math.max(gw, pv.key.need + 22)
  pv.key:SetWidth(width)
  paint(pv.bg, th.frame, DB.barAlpha / 100); pv.bg:SetShown(not only)
  paint(pv.edge, th.line); pv.edge:SetShown(not only)
  paint(pv.key.bg, th.frame, DB.barAlpha / 100); pv.key.bg:SetShown(only)
  pv.bar:ClearAllPoints(); pv.bar:SetPoint("TOPLEFT", pv.grid, "BOTTOMLEFT", 0, -6)
  pv:SetSize(width + PAD * 2, PAD + KEY_H + GAP + gh + PAD)
  pv:SetScale(DB.scale / 100)
  pv.title:SetText(tr("preview"))
  pv.clear.t:SetText(tr("clear"))
  pv.hint:SetText(tr("pvHint"))
  for _, b in ipairs(pv.sizeB) do
    if b.size == n then b.bg:SetColorTexture(th.acc[1], th.acc[2], th.acc[3], 1); b.t:SetTextColor(0, 0, 0)
    else b.bg:SetColorTexture(0.102, 0.102, 0.094, 1); b.t:SetTextColor(0.945, 0.933, 0.91) end
  end
end

local function pvShow()
  if not pv then makePreview() end
  pv:ClearAllPoints()
  if main then pv:SetPoint("TOPLEFT", main, "TOPLEFT") else pv:SetPoint("CENTER", UIParent, "CENTER", -300, 120) end
  -- start with something to click: the first two debuff types this class can remove
  if not next(pvState.deb) then
    local slot = 2
    for _, ty in ipairs(TYPE_ORDER) do
      if canRemove(ty) and slot <= 4 then pvState.deb[slot] = { ty }; slot = slot + 2 end
    end
  end
  pv.msg:SetText("")
  pv:Show()
  if main then pcall(main.SetAlpha, main, 0) end
  pvRender()
end

local function pvHide()
  if pv then pv:Hide() end
  if main then pcall(main.SetAlpha, main, 1) end
end

-- debuff name (lower case) → { name, id, id, ... } from Debuffs.lua
local BYNAME = {}
for _, list in pairs(ns and ns.DEBUFFS or {}) do
  for _, e in ipairs(list) do BYNAME[e[1]:lower()] = e end
end

---------------------------------------------------------------- options window
local opt
local function refreshOptions() if opt and opt:IsShown() then opt.refresh() end; pvRender() end
local function apply() if later(layout) then say(tr("combat")) end; refreshOptions() end

local function makeOptions()
  opt = CreateFrame("Frame", "ForeverCleanseOptions", UIParent)
  opt:SetSize(300, 470); opt:SetPoint("CENTER", 220, 40)
  opt:SetFrameStrata("DIALOG"); opt:SetMovable(true); opt:EnableMouse(true); opt:SetClampedToScreen(true)
  opt:RegisterForDrag("LeftButton")
  opt:SetScript("OnDragStart", opt.StartMoving); opt:SetScript("OnDragStop", opt.StopMovingOrSizing)
  tinsert(UISpecialFrames, "ForeverCleanseOptions")
  local bg = opt:CreateTexture(nil, "BACKGROUND", nil, -1); bg:SetAllPoints(); bg:SetColorTexture(0, 0, 0, 0.94)
  local edge = opt:CreateTexture(nil, "BACKGROUND", nil, -2); edge:SetPoint("TOPLEFT", -1, 1); edge:SetPoint("BOTTOMRIGHT", 1, -1); edge:SetColorTexture(0.227, 0.224, 0.212, 1)
  local acc, ink, soft, line = THEMES.shadow.acc, THEMES.shadow.ink, THEMES.shadow.soft, THEMES.shadow.line
  local widgets, y = {}, -12

  local mark = opt:CreateTexture(nil, "ARTWORK"); mark:SetSize(20, 20); mark:SetPoint("TOPLEFT", 12, -11); mark:SetTexture(LOGO)
  local title = opt:CreateFontString(nil, "OVERLAY"); title:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 16)); title:SetTextColor(ink[1], ink[2], ink[3])
  title:SetPoint("LEFT", mark, "RIGHT", 8, 0)
  local close = CreateFrame("Button", nil, opt); close:SetSize(20, 20); close:SetPoint("TOPRIGHT", -8, -10)
  close.t = close:CreateFontString(nil, "OVERLAY"); close.t:SetFontObject(font("Barlow-SemiBold.ttf", 14)); close.t:SetPoint("CENTER"); close.t:SetText("x"); close.t:SetTextColor(soft[1], soft[2], soft[3])
  close:SetScript("OnClick", function() opt:Hide() end)

  -- "i": how the addon works, in a panel beside the options
  local infoB = CreateFrame("Button", nil, opt); infoB:SetSize(20, 20); infoB:SetPoint("RIGHT", close, "LEFT", -4, 0)
  infoB.bg = infoB:CreateTexture(nil, "BACKGROUND"); infoB.bg:SetAllPoints()
  infoB.t = infoB:CreateFontString(nil, "OVERLAY"); infoB.t:SetFontObject(font("Barlow-SemiBold.ttf", 13)); infoB.t:SetPoint("CENTER"); infoB.t:SetText("i")
  local info = CreateFrame("Frame", "ForeverCleanseInfo", opt)
  info:SetWidth(290); info:SetPoint("TOPLEFT", opt, "TOPRIGHT", 8, 0); info:EnableMouse(true)
  local ibg = info:CreateTexture(nil, "BACKGROUND", nil, -1); ibg:SetAllPoints(); ibg:SetColorTexture(0, 0, 0, 0.94)
  local iedge = info:CreateTexture(nil, "BACKGROUND", nil, -2); iedge:SetPoint("TOPLEFT", -1, 1); iedge:SetPoint("BOTTOMRIGHT", 1, -1); iedge:SetColorTexture(0.227, 0.224, 0.212, 1)
  local ititle = info:CreateFontString(nil, "OVERLAY"); ititle:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 16)); ititle:SetTextColor(ink[1], ink[2], ink[3])
  ititle:SetPoint("TOPLEFT", 14, -12)
  info:Hide()
  -- one row = a picture on the left, a few words on the right
  info.rows = {}
  local function row()
    local r = CreateFrame("Frame", nil, info); r:SetSize(262, 30)
    r.t = r:CreateFontString(nil, "OVERLAY"); r.t:SetFontObject(font("Barlow-Regular.ttf", 13)); r.t:SetTextColor(0.843, 0.827, 0.796)
    r.t:SetPoint("LEFT", 50, 0); r.t:SetWidth(212); r.t:SetJustifyH("LEFT")
    info.rows[#info.rows + 1] = r
    return r
  end
  local function mouse(r, side)
    r.m = r:CreateTexture(nil, "ARTWORK"); r.m:SetSize(13, 18); r.m:SetPoint("LEFT", 2, 0)
    if not atlas(r.m, side == "R" and "NPE_RightClick" or "NPE_LeftClick") then
      r.m:Hide()
      r.l = r:CreateFontString(nil, "OVERLAY"); r.l:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); r.l:SetTextColor(acc[1], acc[2], acc[3])
      r.l:SetPoint("LEFT", 4, 0); r.l:SetText(side)
    end
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(24, 24); r.ic:SetPoint("LEFT", 18, 0)
  end
  local lit = row() -- a lit square, as in the grid
  lit.edge = lit:CreateTexture(nil, "BACKGROUND", nil, -2); lit.edge:SetSize(28, 28); lit.edge:SetPoint("LEFT", 8, 0)
  lit.bg = lit:CreateTexture(nil, "BACKGROUND", nil, -1); lit.bg:SetPoint("TOPLEFT", lit.edge, 1, -1); lit.bg:SetPoint("BOTTOMRIGHT", lit.edge, -1, 1); lit.bg:SetColorTexture(0.051, 0.051, 0.047, 1)
  lit.ic = lit:CreateTexture(nil, "ARTWORK"); lit.ic:SetSize(18, 18); lit.ic:SetPoint("BOTTOM", lit.edge, "BOTTOM", 0, 3)
  lit.mark = lit:CreateTexture(nil, "ARTWORK", nil, 2); lit.mark:SetSize(6, 6); lit.mark:SetPoint("TOPRIGHT", lit.edge, -2, -2)
  local left, right, purge = row(), row(), row()
  mouse(left, "L"); mouse(right, "R"); mouse(purge, "L")
  local move = row()
  move.ic = move:CreateTexture(nil, "ARTWORK"); move.ic:SetSize(22, 22); move.ic:SetPoint("LEFT", 11, 0); move.ic:SetTexture("Interface\\CURSOR\\UI-Cursor-Move")
  local size = row()
  for _, len in ipairs({ 14, 9, 4 }) do
    local l = size:CreateLine(nil, "OVERLAY"); l:SetThickness(1.5); l:SetColorTexture(soft[1], soft[2], soft[3], 1)
    l:SetStartPoint("LEFT", 34, -9 + len); l:SetEndPoint("LEFT", 34 - len, -9)
  end
  local gear = row()
  gear.ic = gear:CreateTexture(nil, "ARTWORK"); gear.ic:SetSize(20, 20); gear.ic:SetPoint("LEFT", 12, 0); setGear(gear.ic)
  local function spellIcon(tex, name)
    local ok, si = pcall(C_Spell.GetSpellInfo, name)
    tex:SetTexture(ok and type(si) == "table" and si.iconID or "Interface\\Icons\\INV_Misc_QuestionMark")
  end
  local function colours(spell) -- "Curse · Poison" in their own colours
    local out = {}
    for _, ty in ipairs(REMOVES[spell] or {}) do
      local c = TYPE_COLOR[ty]
      out[#out + 1] = ("|cff%02x%02x%02x%s|r"):format(c[1] * 255, c[2] * 255, c[3] * 255, ty)
    end
    return table.concat(out, " · ")
  end
  local function paintInfo()
    local on = info:IsShown()
    if on then infoB.bg:SetColorTexture(acc[1], acc[2], acc[3], 1); infoB.t:SetTextColor(0, 0, 0)
    else infoB.bg:SetColorTexture(line[1], line[2], line[3], 0.45); infoB.t:SetTextColor(soft[1], soft[2], soft[3]) end
    if not on then return end
    ititle:SetText(tr("info"))
    local ty = spells.left and (REMOVES[spells.left] or {})[1] or "Curse"
    local c = TYPE_COLOR[ty]
    lit.edge:SetColorTexture(c[1], c[2], c[3], 1); lit.mark:SetColorTexture(c[1], c[2], c[3], 1)
    lit.ic:SetTexture("Interface\\Icons\\" .. PV_DEBUFF[ty][2])
    lit.t:SetText(tr("iLit"))
    if spells.left then spellIcon(left.ic, spells.left); left.t:SetText(spells.left .. "\n" .. colours(spells.left))
    else left.ic:SetTexture("Interface\\Icons\\INV_Misc_QuestionMark"); left.t:SetText(tr("noSpell")) end
    right:SetShown(spells.right ~= nil)
    if spells.right then spellIcon(right.ic, spells.right); right.t:SetText(spells.right .. "\n" .. colours(spells.right)) end
    purge:SetShown(spells.purge ~= nil)
    if spells.purge then spellIcon(purge.ic, spells.purge); purge.t:SetText(tr("iPurge")) end
    move.t:SetText(tr("iMove")); size.t:SetText(tr("iSize")); gear.t:SetText(tr("iOpt"))
    local iy = -40
    for _, r in ipairs(info.rows) do
      if r:IsShown() then r:ClearAllPoints(); r:SetPoint("TOPLEFT", 14, iy); iy = iy - 34 end
    end
    info:SetHeight(-iy + 8)
  end
  infoB:SetScript("OnClick", function() if opt.browse then opt.browse:Hide() end; info:SetShown(not info:IsShown()); paintInfo() end)
  infoB:SetScript("OnEnter", function(self) GameTooltip:SetOwner(self, "ANCHOR_TOP"); GameTooltip:AddLine(tr("info")); GameTooltip:Show() end)
  infoB:SetScript("OnLeave", function() GameTooltip:Hide() end)
  y = -40

  local function label(key)
    local fs = opt:CreateFontString(nil, "OVERLAY"); fs:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); fs:SetTextColor(0.663, 0.847, 0.773)
    fs:SetPoint("TOPLEFT", 14, y); y = y - 18
    widgets[#widgets + 1] = function() fs:SetText(tr(key)) end
  end
  local function seg(field, choices)
    local w = 272 / #choices
    local bs = {}
    for i, c in ipairs(choices) do
      local b = CreateFrame("Button", nil, opt); b:SetSize(w - (i < #choices and 1 or 0), 24); b:SetPoint("TOPLEFT", 14 + (i - 1) * w, y)
      b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
      b.t = b:CreateFontString(nil, "OVERLAY"); b.t:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); b.t:SetPoint("CENTER")
      b:SetScript("OnClick", function() DB[field] = c[1]; if field == "soundFile" then PlaySoundFile(c[1], "Master") end; apply() end)
      bs[i] = b
    end
    y = y - 32
    widgets[#widgets + 1] = function()
      for i, c in ipairs(choices) do
        local on = DB[field] == c[1]
        if on then bs[i].bg:SetColorTexture(acc[1], acc[2], acc[3], 1); bs[i].t:SetTextColor(0, 0, 0)
        else bs[i].bg:SetColorTexture(line[1], line[2], line[3], 0.45); bs[i].t:SetTextColor(soft[1], soft[2], soft[3]) end
        bs[i].t:SetText(c[2] and tr(c[2]) or c[3])
      end
    end
  end
  local function check(field, key, enabled)
    local b = CreateFrame("Button", nil, opt); b:SetSize(272, 20); b:SetPoint("TOPLEFT", 14, y); y = y - 22
    b.box = b:CreateTexture(nil, "BACKGROUND"); b.box:SetSize(14, 14); b.box:SetPoint("LEFT")
    b.tick = b:CreateTexture(nil, "ARTWORK"); b.tick:SetSize(6, 6); b.tick:SetPoint("CENTER", b.box)
    b.t = b:CreateFontString(nil, "OVERLAY"); b.t:SetFontObject(font("Barlow-Regular.ttf", 13)); b.t:SetPoint("LEFT", b.box, "RIGHT", 8, 0)
    b:SetScript("OnClick", function() if enabled and not enabled() then return end; DB[field] = not DB[field]
      if field == "sound" and DB.sound then PlaySoundFile(DB.soundFile, "Master") end
      apply() end)
    widgets[#widgets + 1] = function()
      local can = not enabled or enabled()
      local on = DB[field] and can
      if on then b.box:SetColorTexture(acc[1], acc[2], acc[3]) else b.box:SetColorTexture(line[1], line[2], line[3]) end
      b.tick:SetColorTexture(0, 0, 0, on and 1 or 0)
      b.t:SetText(tr(key) .. (can and "" or "  " .. tr("noPurge")))
      if can then b.t:SetTextColor(0.843, 0.827, 0.796) else b.t:SetTextColor(0.482, 0.467, 0.439) end
    end
  end

  label("grid"); seg("mode", { { "everyone", "everyone" }, { "only", "only" } })
  label("alerts")
  check("pulse", "pulse"); check("sound", "sound"); seg("soundFile", SOUNDS); check("range", "range")
  check("purge", "purge", function() return spells.purge ~= nil end)
  y = y - 6

  -- ignore list: names with a remove button, an edit box to add by name or spell ID
  label("ignore")
  local rows, listTop = {}, y
  rows.count = opt:CreateFontString(nil, "OVERLAY"); rows.count:SetFontObject(font("Barlow-Regular.ttf", 11)); rows.count:SetTextColor(0.482, 0.467, 0.439)
  rows.count:SetPoint("BOTTOMRIGHT", opt, "TOPLEFT", 286, y + 4)
  for i = 1, 6 do
    local r = CreateFrame("Button", nil, opt); r:SetSize(272, 18); r:SetPoint("TOPLEFT", 14, listTop - (i - 1) * 19)
    r.t = r:CreateFontString(nil, "OVERLAY"); r.t:SetFontObject(font("Barlow-Regular.ttf", 12)); r.t:SetPoint("LEFT", 6, 0); r.t:SetTextColor(0.843, 0.827, 0.796)
    r.x = r:CreateFontString(nil, "OVERLAY"); r.x:SetFontObject(font("Barlow-SemiBold.ttf", 12)); r.x:SetPoint("RIGHT", -6, 0); r.x:SetText("x"); r.x:SetTextColor(soft[1], soft[2], soft[3])
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.102, 0.102, 0.094, 1)
    r:SetScript("OnClick", function(self)
      if not self.name then return end
      for id, n in pairs(DB.ignore) do if n == self.name then DB.ignore[id] = nil end end
      GameTooltip:Hide()
      apply()
    end)
    r:SetScript("OnEnter", function(self)
      self.bg:SetColorTexture(0.18, 0.18, 0.165, 1)
      if not self.firstId then return end
      GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
      if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.firstId) then GameTooltip:AddLine(self.name) end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.102, 0.102, 0.094, 1); GameTooltip:Hide() end)
    r:EnableMouseWheel(true)
    r:SetScript("OnMouseWheel", function(_, delta) rows.off = math.max(0, (rows.off or 0) - delta); opt.refresh() end)
    rows[i] = r
  end
  y = listTop - 6 * 19 - 4
  -- Reset = the addon's own list back, Clear all = empty, Browse = every debuff of the game
  local function smallButton(x, w)
    local b = CreateFrame("Button", nil, opt); b:SetSize(w, 22); b:SetPoint("TOPLEFT", x, y)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints(); b.bg:SetColorTexture(0.102, 0.102, 0.094, 1)
    b.t = b:CreateFontString(nil, "OVERLAY"); b.t:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); b.t:SetPoint("CENTER"); b.t:SetTextColor(ink[1], ink[2], ink[3])
    return b
  end
  local resetB, clearB = smallButton(14, 66), smallButton(84, 80)
  resetB:SetScript("OnClick", function() DB.ignore = CopyTable(DEFAULTS.ignore); rows.off = 0; apply() end)
  clearB:SetScript("OnClick", function() DB.ignore = {}; rows.off = 0; apply() end)
  local browseB = smallButton(220, 66)
  y = y - 26
  local edit = CreateFrame("EditBox", nil, opt); edit:SetSize(200, 22); edit:SetPoint("TOPLEFT", 14, y); edit:SetAutoFocus(false)
  edit:SetFontObject(font("Barlow-Regular.ttf", 13)); edit:SetTextColor(ink[1], ink[2], ink[3]); edit:SetTextInsets(6, 6, 0, 0)
  local ebg = edit:CreateTexture(nil, "BACKGROUND"); ebg:SetAllPoints(); ebg:SetColorTexture(0.051, 0.051, 0.047, 1)
  local addB = CreateFrame("Button", nil, opt); addB:SetSize(66, 22); addB:SetPoint("LEFT", edit, "RIGHT", 6, 0)
  addB.bg = addB:CreateTexture(nil, "BACKGROUND"); addB.bg:SetAllPoints(); addB.bg:SetColorTexture(0.102, 0.102, 0.094, 1)
  addB.t = addB:CreateFontString(nil, "OVERLAY"); addB.t:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); addB.t:SetPoint("CENTER"); addB.t:SetTextColor(ink[1], ink[2], ink[3])
  -- "Name 1234", "Name" or "1234"; a known debuff name brings every id (rank) it has
  local function add()
    local text = strtrim(edit:GetText() or "")
    if text == "" then return end
    local name, id = text:match("^(.-)%s+(%d+)$")
    if name and name ~= "" then id = tonumber(id) else name, id = text, tonumber(text) end
    if id and name == text then
      local ok, si = pcall(C_Spell.GetSpellInfo, id)
      name = ok and type(si) == "table" and si.name or text
    end
    local known = BYNAME[name:lower()]
    if known then
      for i = 2, #known do DB.ignore[known[i]] = known[1] end
    else
      if not id then for n, sid in pairs(DB.seen) do if n:lower() == name:lower() then id, name = sid, n end end end
      if not id then say(tr("unknown")); return end
      DB.ignore[id] = name
    end
    edit:SetText(""); edit:ClearFocus()
    apply()
  end
  addB:SetScript("OnClick", add); edit:SetScript("OnEnterPressed", add); edit:SetScript("OnEscapePressed", edit.ClearFocus)

  -- browse: every debuff of the game by type; a click puts "Name id" in the box above Add
  local br = CreateFrame("Frame", "ForeverCleanseBrowse", opt)
  opt.browse = br
  local BR_ROWS = 14
  br:SetSize(290, 112 + BR_ROWS * 20); br:SetPoint("TOPLEFT", opt, "TOPRIGHT", 8, 0); br:EnableMouse(true); br:EnableMouseWheel(true); br:Hide()
  local bbg = br:CreateTexture(nil, "BACKGROUND", nil, -1); bbg:SetAllPoints(); bbg:SetColorTexture(0, 0, 0, 0.94)
  local bedge = br:CreateTexture(nil, "BACKGROUND", nil, -2); bedge:SetPoint("TOPLEFT", -1, 1); bedge:SetPoint("BOTTOMRIGHT", 1, -1); bedge:SetColorTexture(0.227, 0.224, 0.212, 1)
  br.state = { type = "Curse", off = 0, q = "" }
  br.tabs = {}
  for n, ty in ipairs(TYPE_ORDER) do
    local b = CreateFrame("Button", nil, br); b:SetSize(64, 22); b:SetPoint("TOPLEFT", 14 + (n - 1) * 66, -12)
    b.bg = b:CreateTexture(nil, "BACKGROUND"); b.bg:SetAllPoints()
    b.sw = b:CreateTexture(nil, "ARTWORK"); b.sw:SetSize(8, 8); b.sw:SetPoint("LEFT", 6, 0)
    local c = TYPE_COLOR[ty]; b.sw:SetColorTexture(c[1], c[2], c[3], 1)
    b.t = b:CreateFontString(nil, "OVERLAY"); b.t:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); b.t:SetPoint("LEFT", b.sw, "RIGHT", 4, 0); b.t:SetText(ty)
    b:SetScript("OnClick", function() br.state.type, br.state.off = ty, 0; br.paint() end)
    b.ty = ty
    br.tabs[n] = b
  end
  local find = CreateFrame("EditBox", nil, br); find:SetSize(262, 22); find:SetPoint("TOPLEFT", 14, -40); find:SetAutoFocus(false)
  find:SetFontObject(font("Barlow-Regular.ttf", 13)); find:SetTextColor(ink[1], ink[2], ink[3]); find:SetTextInsets(6, 6, 0, 0)
  local fbg = find:CreateTexture(nil, "BACKGROUND"); fbg:SetAllPoints(); fbg:SetColorTexture(0.051, 0.051, 0.047, 1)
  find.hint = find:CreateFontString(nil, "OVERLAY"); find.hint:SetFontObject(font("Barlow-Regular.ttf", 13)); find.hint:SetTextColor(0.482, 0.467, 0.439); find.hint:SetPoint("LEFT", 6, 0)
  find:SetScript("OnTextChanged", function(self) br.state.q, br.state.off = strtrim(self:GetText() or ""):lower(), 0; br.paint() end)
  find:SetScript("OnEscapePressed", find.ClearFocus); find:SetScript("OnEnterPressed", find.ClearFocus)
  br.list = {}
  for i = 1, BR_ROWS do
    local r = CreateFrame("Button", nil, br); r:SetSize(262, 19); r:SetPoint("TOPLEFT", 14, -68 - (i - 1) * 20)
    r.bg = r:CreateTexture(nil, "BACKGROUND"); r.bg:SetAllPoints(); r.bg:SetColorTexture(0.102, 0.102, 0.094, 1)
    r.ic = r:CreateTexture(nil, "ARTWORK"); r.ic:SetSize(16, 16); r.ic:SetPoint("LEFT", 2, 0)
    r.t = r:CreateFontString(nil, "OVERLAY"); r.t:SetFontObject(font("Barlow-Regular.ttf", 12)); r.t:SetPoint("LEFT", 24, 0); r.t:SetPoint("RIGHT", -50, 0)
    r.t:SetJustifyH("LEFT"); r.t:SetWordWrap(false); r.t:SetTextColor(0.843, 0.827, 0.796)
    r.id = r:CreateFontString(nil, "OVERLAY"); r.id:SetFontObject(font("BarlowCondensed-Medium.ttf", 12)); r.id:SetPoint("RIGHT", -6, 0); r.id:SetTextColor(0.482, 0.467, 0.439)
    r:SetScript("OnEnter", function(self)
      self.bg:SetColorTexture(0.18, 0.18, 0.165, 1)
      if not self.entry then return end
      GameTooltip:SetOwner(br, "ANCHOR_NONE"); GameTooltip:SetPoint("TOPLEFT", br, "TOPRIGHT", 8, 0) -- the game's own spell tooltip
      if not pcall(GameTooltip.SetSpellByID, GameTooltip, self.entry[2]) then GameTooltip:AddLine(self.entry[1]) end
      GameTooltip:Show()
    end)
    r:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.102, 0.102, 0.094, 1); GameTooltip:Hide() end)
    r:SetScript("OnClick", function(self) if self.entry then edit:SetText(self.entry[1] .. " " .. self.entry[2]) end end)
    br.list[i] = r
  end
  br.foot = br:CreateFontString(nil, "OVERLAY"); br.foot:SetFontObject(font("Barlow-Regular.ttf", 11)); br.foot:SetTextColor(0.482, 0.467, 0.439)
  br.foot:SetPoint("BOTTOMLEFT", 14, 12); br.foot:SetWidth(262); br.foot:SetJustifyH("LEFT")
  br:SetScript("OnMouseWheel", function(_, delta)
    br.state.off = math.max(0, br.state.off - delta * 3); br.paint()
  end)
  br.paint = function()
    local st = br.state
    for _, b in ipairs(br.tabs) do
      if b.ty == st.type then b.bg:SetColorTexture(acc[1], acc[2], acc[3], 1); b.t:SetTextColor(0, 0, 0)
      else b.bg:SetColorTexture(line[1], line[2], line[3], 0.45); b.t:SetTextColor(soft[1], soft[2], soft[3]) end
    end
    find.hint:SetText(tr("search")); find.hint:SetShown((find:GetText() or "") == "")
    local all = (ns.DEBUFFS or {})[st.type] or {}
    local shown = {}
    for _, e in ipairs(all) do if st.q == "" or e[1]:lower():find(st.q, 1, true) then shown[#shown + 1] = e end end
    st.off = math.min(st.off, math.max(0, #shown - BR_ROWS))
    for i, r in ipairs(br.list) do
      local e = shown[st.off + i]
      r.entry = e; r:SetShown(e ~= nil)
      if e then
        r.t:SetText(e[1]); r.id:SetText(e[2])
        local ok, tex = pcall(C_Spell.GetSpellTexture, e[2])
        r.ic:SetTexture(ok and tex or "Interface\\Icons\\INV_Misc_QuestionMark")
      end
    end
    local range = #shown == 0 and "0" or ((st.off + 1) .. "–" .. math.min(st.off + BR_ROWS, #shown) .. " / " .. #shown)
    br.foot:SetText(range .. "  ·  " .. tr("pick"))
  end
  browseB:SetScript("OnClick", function()
    local info = _G.ForeverCleanseInfo
    if info and info:IsShown() then info:Hide() end
    br:SetShown(not br:IsShown())
    opt.refresh()
  end)
  y = y - 34
  widgets[#widgets + 1] = function()
    local first, count, names = {}, {}, {}
    for id, n in pairs(DB.ignore) do
      if not first[n] then names[#names + 1] = n; first[n], count[n] = id, 0 end
      first[n] = math.min(first[n], id); count[n] = count[n] + 1
    end
    table.sort(names)
    rows.off = math.min(rows.off or 0, math.max(0, #names - #rows)) -- the wheel scrolls a long list
    for i, r in ipairs(rows) do
      local n = names[rows.off + i]
      r.name, r.firstId = n, n and first[n]; r:SetShown(n ~= nil)
      if n then r.t:SetText(n .. "  |cff7b7770" .. first[n] .. (count[n] > 1 and (" +" .. (count[n] - 1)) or "") .. "|r") end
    end
    rows.count:SetText(#names > #rows and ((rows.off + 1) .. "–" .. (rows.off + #rows) .. " / " .. #names) or "")
    addB.t:SetText(tr("add")); browseB.t:SetText(tr("browse")); resetB.t:SetText(tr("reset")); clearB.t:SetText(tr("clearAll"))
    local on = opt.browse and opt.browse:IsShown()
    if on then browseB.bg:SetColorTexture(acc[1], acc[2], acc[3], 1); browseB.t:SetTextColor(0, 0, 0)
    else browseB.bg:SetColorTexture(0.102, 0.102, 0.094, 1); browseB.t:SetTextColor(ink[1], ink[2], ink[3]) end
    if on then opt.browse.paint() end
  end

  -- sliders (size, bar opacity) and lock
  local function slider(field, text, lo, hi, step)
    label(text)
    local s = CreateFrame("Slider", nil, opt); s:SetSize(220, 14); s:SetPoint("TOPLEFT", 14, y - 2); s:SetOrientation("HORIZONTAL")
    s:SetMinMaxValues(lo, hi); s:SetValueStep(step); s:SetObeyStepOnDrag(true)
    local track = s:CreateTexture(nil, "BACKGROUND"); track:SetHeight(4); track:SetPoint("LEFT"); track:SetPoint("RIGHT"); track:SetColorTexture(line[1], line[2], line[3])
    local thumb = s:CreateTexture(nil, "ARTWORK"); thumb:SetSize(10, 14); thumb:SetColorTexture(acc[1], acc[2], acc[3]); s:SetThumbTexture(thumb)
    local val = opt:CreateFontString(nil, "OVERLAY"); val:SetFontObject(font("BarlowCondensed-SemiBold.ttf", 13)); val:SetTextColor(COPPER[1], COPPER[2], COPPER[3])
    val:SetPoint("LEFT", s, "RIGHT", 10, 0)
    s:SetScript("OnValueChanged", function(_, v, user)
      v = math.floor(v + 0.5)
      val:SetText(v .. "%")
      if user then DB[field] = v; apply() end
    end)
    y = y - 26
    widgets[#widgets + 1] = function() s:SetValue(DB[field]); val:SetText(DB[field] .. "%") end
    return s
  end
  slider("scale", "size", 60, 200, 5)
  slider("barAlpha", "barAlpha", 0, 100, 5)
  check("lock", "lock")
  y = y - 4
  label("lang"); seg("lang", { { "en", nil, "English" }, { "it", nil, "Italiano" } })
  widgets[#widgets + 1] = function() title:SetText("Forever Cleanse · " .. tr("options")) end
  widgets[#widgets + 1] = paintInfo -- follows the language switch

  opt:SetHeight(-y + 6)
  opt.refresh = function() for _, f in ipairs(widgets) do f() end end
  opt:Hide()
  opt:SetScript("OnShow", function() opt.refresh(); pvShow() end)
  opt:SetScript("OnHide", pvHide)
end

toggleOptions = function()
  if not opt then makeOptions() end
  opt:SetShown(not opt:IsShown())
end

---------------------------------------------------------------- build (out of combat)
local function build()
  if main then return end
  if C_AddOns and not C_AddOns.IsAddOnLoaded("Blizzard_AuraContainer") then pcall(C_AddOns.LoadAddOn, "Blizzard_AuraContainer") end
  main = CreateFrame("Frame", "ForeverCleanseFrame", UIParent)
  main:SetMovable(true); main:SetClampedToScreen(true)
  main.edge = main:CreateTexture(nil, "BACKGROUND", nil, -2); main.edge:SetPoint("TOPLEFT", -1, 1); main.edge:SetPoint("BOTTOMRIGHT", 1, -1)
  main.bg = main:CreateTexture(nil, "BACKGROUND", nil, -1); main.bg:SetAllPoints()
  local p = DB.point
  if p then main:SetPoint(p[1], UIParent, p[3], p[4], p[5]) else main:SetPoint("CENTER", UIParent, "CENTER", -300, 120) end

  key = CreateFrame("Frame", nil, main)
  key:SetPoint("TOPLEFT", PAD, -PAD); key:SetHeight(KEY_H)
  key.bg = key:CreateTexture(nil, "BACKGROUND"); key.bg:SetAllPoints()
  key.mark = key:CreateTexture(nil, "ARTWORK"); key.mark:SetSize(16, 16); key.mark:SetPoint("LEFT", 2, 0); key.mark:SetTexture(LOGO)
  key:EnableMouse(true); key:RegisterForDrag("LeftButton")
  key:SetScript("OnDragStart", function() if not DB.lock and not InCombatLockdown() then main:StartMoving() end end)
  key:SetScript("OnDragStop", function()
    main:StopMovingOrSizing()
    local a, _, b, x, y = main:GetPoint()
    DB.point = { a, nil, b, x, y }
  end)
  key:SetScript("OnMouseUp", function(_, btn) if btn == "RightButton" then toggleOptions() end end)
  makeCog(key)
  key:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_TOP")
    GameTooltip:AddLine("Forever Cleanse")
    if spells.left then GameTooltip:AddLine("Left: " .. spells.left, 1, 1, 1) end
    if spells.right then GameTooltip:AddLine("Right: " .. spells.right, 1, 1, 1) end
    GameTooltip:AddLine(tr("hint"), 0.65, 0.63, 0.6)
    GameTooltip:Show()
  end)
  key:SetScript("OnLeave", function() GameTooltip:Hide() end)

  grid = CreateFrame("Frame", nil, main)
  grid:SetPoint("TOPLEFT", key, "BOTTOMLEFT", 0, -GAP)

  target = CreateFrame("Button", "ForeverCleanseTarget", main, "SecureActionButtonTemplate")
  target:RegisterForClicks("AnyUp", "AnyDown")
  target:SetPoint("TOPLEFT", grid, "BOTTOMLEFT", 0, -GAP)
  target.edge = target:CreateTexture(nil, "BACKGROUND", nil, -2); target.edge:SetAllPoints()
  target.bg = target:CreateTexture(nil, "BACKGROUND", nil, -1); target.bg:SetPoint("TOPLEFT", 1, -1); target.bg:SetPoint("BOTTOMRIGHT", -1, 1)
  target.label = target:CreateFontString(nil, "OVERLAY"); target.label:SetPoint("LEFT", 5, 0)
  target.aura = makeContainer(target, PURGE_FILTER, 5, 18, function(b)
    pcall(function()
      b:SetSize(18, 18)
      pcall(b.SetMouseClickEnabled, b, false)
      local icon = b:CreateTexture(nil, "ARTWORK"); icon:SetAllPoints(b); b:SetIcon(icon)
    end)
  end)
  target.aura:SetSize(5 * 20, 18)
  target.aura:SetPoint("RIGHT", target, "RIGHT", -3, 0)
  target.aura:SetUnit("target")
  target.aura:SetFlowLayoutMaximumLineSize(5 * 20)
  target:Hide()

  -- corner grip: scale the whole frame (out of combat)
  grip = CreateFrame("Button", nil, main)
  grip:SetSize(12, 12); grip:SetPoint("BOTTOMRIGHT", main, "BOTTOMRIGHT", 0, 0)
  for i, len in ipairs({ 10, 6, 2 }) do
    local l = grip:CreateLine(nil, "OVERLAY"); l:SetThickness(1)
    l:SetStartPoint("BOTTOMRIGHT", -1, len + 1); l:SetEndPoint("BOTTOMRIGHT", -(len + 1), 1)
    l:SetColorTexture(0.482, 0.467, 0.439, 1)
    grip["l" .. i] = l
  end
  -- the grip moves while the frame scales, so the release can land elsewhere and OnMouseUp never comes:
  -- stop as soon as the button is no longer held
  local function stopScaling(self)
    self:SetScript("OnUpdate", nil)
    local a, _, b, x, y = main:GetPoint()
    DB.point = { a, nil, b, x, y }
  end
  grip:SetScript("OnMouseDown", function(self)
    if DB.lock or InCombatLockdown() then return end
    self.x0, self.s0, self.w0 = GetCursorPosition(), DB.scale, main:GetWidth() * main:GetEffectiveScale()
    self:SetScript("OnUpdate", function()
      if InCombatLockdown() or not IsMouseButtonDown("LeftButton") then return stopScaling(self) end
      local x = GetCursorPosition()
      local v = math.floor(math.max(60, math.min(200, self.s0 * (self.w0 + x - self.x0) / self.w0)) / 5 + 0.5) * 5
      if v ~= DB.scale then
        -- keep the top-left corner still while scaling
        local left, top = main:GetLeft() * main:GetScale(), main:GetTop() * main:GetScale()
        DB.scale = v
        main:SetScale(v / 100)
        main:ClearAllPoints(); main:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", left / main:GetScale(), top / main:GetScale())
        refreshOptions()
      end
    end)
  end)
  grip:SetScript("OnMouseUp", stopScaling)

  layout()
end

---------------------------------------------------------------- out of range: the game hands us a secret boolean, the frame applies it
local function rangeTick()
  for _, t in ipairs(tiles) do
    if t:IsShown() and t.unit then
      if DB.range and t.unit ~= "player" then
        if not pcall(t.vis.SetAlphaFromBoolean, t.vis, UnitInRange(t.unit), 1, 0.35) then pcall(t.vis.SetAlpha, t.vis, 1) end
      else
        pcall(t.vis.SetAlpha, t.vis, 1)
      end
    end
  end
end

-- learn debuff names out of combat, so the ignore list can take names
local function learn(unit)
  if InCombatLockdown() or (C_Secrets and C_Secrets.ShouldAurasBeSecret and C_Secrets.ShouldAurasBeSecret()) then return end
  for i = 1, 40 do
    local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, "HARMFUL")
    if not ok or type(a) ~= "table" then return end
    if type(a.name) == "string" and type(a.spellId) == "number" then DB.seen[a.name] = a.spellId end
  end
end

---------------------------------------------------------------- events
local ev = CreateFrame("Frame")
ev:RegisterEvent("ADDON_LOADED")
ev:RegisterEvent("PLAYER_LOGIN")
ev:RegisterEvent("PLAYER_REGEN_ENABLED")
ev:RegisterEvent("GROUP_ROSTER_UPDATE")
ev:RegisterEvent("PLAYER_ENTERING_WORLD")
ev:RegisterEvent("SPELLS_CHANGED")
ev:RegisterEvent("UNIT_NAME_UPDATE")
ev:RegisterEvent("UNIT_AURA")
ev:SetScript("OnEvent", function(_, e, arg)
  if e == "ADDON_LOADED" then
    if arg ~= ADDON then return end
    ForeverCleanseDB = type(ForeverCleanseDB) == "table" and ForeverCleanseDB or {}
    DB = ForeverCleanseDB
    for k, v in pairs(DEFAULTS) do if DB[k] == nil then DB[k] = type(v) == "table" and CopyTable(v) or v end end
    DB.theme = "shadow" -- the light theme was dropped
    if not L[DB.lang] then DB.lang = "en" end
    return
  end
  if not DB then return end
  if e == "PLAYER_LOGIN" then
    resolveSpells()
    later(build)
    C_Timer.NewTicker(0.25, rangeTick)
  elseif e == "PLAYER_REGEN_ENABLED" then
    if not main then build() end
    for fn in pairs(pending) do pending[fn] = nil; fn() end
  elseif e == "UNIT_AURA" then
    if type(arg) == "string" and not (issecretvalue and issecretvalue(arg)) and (arg == "player" or arg:find("^party") or arg:find("^raid")) then learn(arg) end
  elseif main then
    later(layout)
  end
end)

SLASH_FOREVERCLEANSE1 = "/fc"
SLASH_FOREVERCLEANSE2 = "/fcleanse"
SlashCmdList.FOREVERCLEANSE = function(msg)
  msg = strtrim((msg or ""):lower())
  if msg == "lock" then DB.lock = not DB.lock; apply()
  elseif msg == "reset" then
    later(function() DB.point, DB.scale = nil, 100; main:ClearAllPoints(); main:SetPoint("CENTER", UIParent, "CENTER", -300, 120); layout() end)
  elseif msg == "help" then say(tr("help"))
  else toggleOptions() end
end
