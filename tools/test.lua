-- Fake WoW for Core.lua: unknown methods are no-ops, the ones the addon relies on keep state.
-- Run: node tools/test.js   (needs fengari in %LOCALAPPDATA%/fp-lua, same as Forever Pathfinder)
local CORE = ...
local W = { class = "DRUID", raid = false, members = 5, combat = false, known = { ["Remove Curse"] = true, ["Abolish Poison"] = true, ["Cure Poison"] = true }, printed = {} }

local METHODS
local function obj(kind)
  return setmetatable({ kind = kind, scripts = {}, attrs = {}, shown = true, w = 0, h = 0 }, { __index = function(_, k)
    if METHODS[k] then return METHODS[k] end
    if type(k) == "string" and k:find("^%u") then return function() return nil end end -- WoW methods are Capitalized
  end })
end
METHODS = {
  SetScript = function(s, n, f) s.scripts[n] = f end, HookScript = function(s, n, f) s.scripts[n] = f end,
  SetAttribute = function(s, k, v)
    if W.combat and s.kind == "Button" and s.secure then error("SetAttribute on a protected frame in combat") end
    s.attrs[k] = v
  end,
  GetAttribute = function(s, k) return s.attrs[k] end,
  Show = function(s) s.shown = true end, Hide = function(s) s.shown = false end,
  SetShown = function(s, v) s.shown = not not v end, IsShown = function(s) return s.shown end,
  SetSize = function(s, w, h) s.w, s.h = w, h end, SetWidth = function(s, w) s.w = w end, SetHeight = function(s, h) s.h = h end,
  GetFrameLevel = function() return 1 end,
  GetWidth = function(s) return s.w end, GetHeight = function(s) return s.h end,
  SetPoint = function(s, ...)
    if W.combat and s.secure then error("SetPoint on a protected frame in combat") end
    s.point = { ... }
  end,
  CreateTexture = function() return obj("Texture") end, CreateFontString = function() return obj("FontString") end,
  CreateLine = function() return obj("Line") end, CreateAnimationGroup = function() return obj("AnimationGroup") end,
  CreateAnimation = function() return obj("Animation") end,
  SetText = function(s, t) s.text = t end, GetText = function(s) return s.text end, GetStringWidth = function() return 40 end, GetStringHeight = function() return 14 end,
  SetFont = function() return true end,
  GetPoint = function() return "TOPLEFT", nil, "BOTTOMLEFT", 10, 700 end,
  GetLeft = function() return 100 end, GetTop = function() return 600 end,
  SetScale = function(s, v) s.scale = v end, GetScale = function(s) return s.scale or 1 end, GetEffectiveScale = function(s) return s.scale or 1 end,
  SetValue = function(s, v) s.value = v; if s.scripts.OnValueChanged then s.scripts.OnValueChanged(s, v, false) end end,
  AddAuraGroup = function(s, key, filter, opts)
    assert(type(opts.initializeFrame) == "function" and type(opts.candidateFilters) == "table", "aura group options")
    s.group = { key = key, filter = filter }
    for _ = 1, opts.maxFrameCount do opts.initializeFrame(obj("AuraButton")) end
  end,
  SetUnit = function(s, u) s.unit = u end,
  SetAuraGroupCandidateFilters = function(s, _, f) s.filters = f end,
}

function CreateFrame(kind, name, parent, template)
  local o = obj(kind)
  o.secure = template == "SecureActionButtonTemplate"
  o.parent = parent
  if name then _G[name] = o end
  W.frames = W.frames or {}
  W.frames[#W.frames + 1] = o
  return o
end
function CreateFont() return obj("Font") end
function CreateFontFamily(_, members) -- names in other alphabets: Barlow for Latin, the game's fonts for the rest
  for _, m in ipairs(members) do if m.alphabet == "russian" and m.file:find("CYR") then W.cyrillic = true end end
  return obj("Font")
end
UIParent, GameTooltip = obj("Frame"), obj("GameTooltip")
UISpecialFrames, SlashCmdList = {}, {}
tinsert = table.insert
function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
function CopyTable(t) local c = {} for k, v in pairs(t) do c[k] = type(v) == "table" and CopyTable(v) or v end return c end
function print(...) W.printed[#W.printed + 1] = table.concat({ ... }, " ") end
function UnitClass(u) if u == "player" then return "Druid", W.class end return "Warrior", "WARRIOR" end
function UnitName(u) return "N-" .. u end
function IsInRaid() return W.raid end
function GetNumGroupMembers() return W.members end
function GetNumSubgroupMembers() return W.raid and 0 or (W.members - 1) end
function GetRaidRosterInfo(i) return "N" .. i, 0, math.floor((i - 1) / 5) + 1 end
function IsPlayerSpell(id) return W.knownIds[id] == true end
function InCombatLockdown() return W.combat end
function UnitInRange() return true end
date = os.date
function GetTime() return W.now or 100 end
function IsMouseButtonDown() return W.held end
function GetCursorPosition() return W.cursor or 0, 0 end
issecretvalue = function() return false end
STANDARD_TEXT_FONT = "font"
AnchorUtil = { FlowLayoutAxis = { Horizontal = 1 }, FlowDirection = { Right = 1, Down = 2 } }
C_AddOns = { IsAddOnLoaded = function() return true end, LoadAddOn = function() end }
C_Timer = { NewTicker = function(_, f) W.tick = f end }
C_Secrets = { ShouldAurasBeSecret = function() return W.combat end }
W.sounds, W.played, W.soundN = {}, {}, 0
C_UnitAuras = { GetAuraDataByIndex = function(_, i) if i == 1 then return { name = "Curse of Tongues", spellId = 12889 } end end,
  AddAuraSound = function(trigger, info) assert(trigger == 0, "trigger: aura added"); W.soundN = W.soundN + 1; W.sounds[W.soundN] = info; return W.soundN end,
  RemoveAuraSound = function(id) W.sounds[id] = nil end }
function PlaySoundFile(f) W.played[#W.played + 1] = f end
W.knownIds = {}
local ids = {}
C_Spell = { GetSpellInfo = function(n)
  local byId = { [475] = "Remove Lesser Curse", [2782] = "Remove Curse", [2893] = "Abolish Poison", [526] = "Cure Poison", [527] = "Dispel Magic",
    [552] = "Abolish Disease", [528] = "Cure Disease", [4987] = "Cleanse", [1152] = "Purify", [1714] = "Curse of Tongues", [13526] = "Corrosive Poison" }
  if type(n) == "number" then return { spellID = n, name = (W.lang == "de" and byId[n] and ("DE " .. byId[n])) or byId[n] or ("Spell" .. n) } end
  ids[n] = ids[n] or (#ids + 1000 + n:len())
  if W.known[n] then W.knownIds[ids[n]] = true end
  return { spellID = ids[n], name = n }
end }

local NS = {}
assert(loadfile((CORE:gsub("Core%.lua$", "Debuffs.lua"))))("ForeverCleanse", NS)
assert(loadfile((CORE:gsub("Core%.lua$", "Locales.lua"))))("ForeverCleanse", NS)
assert(loadfile(CORE))("ForeverCleanse", NS)
local evf
for _, f in ipairs(W.frames) do if f.scripts.OnEvent then evf = f end end
local function fire(e, ...) evf.scripts.OnEvent(evf, e, ...) end
local function shownTiles()
  local n = 0
  for i = 1, 40 do local t = _G["ForeverCleanseTile" .. i]; if t and t.shown then n = n + 1 end end
  return n
end

-- party of 5, Druid
fire("ADDON_LOADED", "ForeverCleanse")
fire("PLAYER_LOGIN")
local t1 = assert(_G.ForeverCleanseTile1, "tile 1 built")
assert(shownTiles() == 5, "party: 5 squares, got " .. shownTiles())
assert(t1.attrs.unit == "player" and t1.attrs.spell1 == "Remove Curse" and t1.attrs.spell2 == "Abolish Poison", "druid spells on the buttons")
assert(_G.ForeverCleanseTile5.attrs.unit == "party4", "fifth square is party4")
assert(t1.w == 48 and t1.h == 48, "party squares are 48x48")
W.members = 1; fire("GROUP_ROSTER_UPDATE")
assert(_G.ForeverCleanseTile1.parent.w == 48, "solo: grid one column wide, got " .. _G.ForeverCleanseTile1.parent.w)
W.members = 5; fire("GROUP_ROSTER_UPDATE")

-- raid of 23: rows by group, 36px squares
W.raid, W.members = true, 23
fire("GROUP_ROSTER_UPDATE")
assert(shownTiles() == 23, "raid 23: 23 squares, got " .. shownTiles())
assert(_G.ForeverCleanseTile6.attrs.unit == "raid6" and _G.ForeverCleanseTile6.point[4] == 0, "group 2 starts a new row at x=0")
assert(_G.ForeverCleanseTile1.w == 36, "raid squares are 36")
local parts = { 0, 0, 0, 0 }
for _, b in ipairs(_G.ForeverCleanseTile1.buttons) do
  if b.fcPart then parts[b.fcPart] = parts[b.fcPart] + 1; assert(b.w == 18 and b.h == (b.fcPart == 2 and 36 or 13), "debuff piece " .. b.fcPart .. ": " .. b.w .. "x" .. b.h) end
end
assert(parts[2] == 2 and parts[3] == 3 and parts[4] == 4, "pieces 2-4: rows of 2, 3 and 4 slots")
local P = _G.ForeverCleanseTile1.parts
assert(P[2].w == 18 and P[2].h == 36 and P[3].h == 13 and P[4].point[4] == 18, "clips: right half, bottom-left, bottom-right")
assert(P[3].aura.point[4] == -36 and P[4].aura.point[4] == -36 and P[2].aura.point[4] == 0, "slot k lands on its clip")

-- in combat nothing protected may change: roster change is deferred, then applied
W.combat = true
W.members = 7
fire("GROUP_ROSTER_UPDATE")
W.tick() -- range fade runs in combat without errors
assert(shownTiles() == 23, "no layout change in combat")
W.combat = false
fire("PLAYER_REGEN_ENABLED")
assert(shownTiles() == 7, "deferred layout applied after combat, got " .. shownTiles())

-- options: open, theme and mode, ignore list by id and by learned name, slash commands
SlashCmdList.FOREVERCLEANSE("")
assert(_G.ForeverCleanseOptions and _G.ForeverCleanseOptions.shown, "options open")
local db = ForeverCleanseDB
assert(db.mode == "only" and db.theme == "shadow", "defaults")

-- preview: opens with the options, seeded with the druid's two types, clicks remove with the right button only
_G.ForeverCleanseOptions.scripts.OnShow()
local pv = assert(_G.ForeverCleansePreview, "preview built")
assert(pv.shown, "preview shown with the options")
local curse, poison
for i, t in pairs(pv.tiles) do if t.icon.shown then if i == 2 then curse = t elseif i == 4 then poison = t end end end
assert(curse and poison, "preview seeded: curse on 2, poison on 4")
curse.scripts.OnClick(curse, "RightButton")
assert(pv.msg.text:find("does not remove"), "wrong button explained: " .. tostring(pv.msg.text))
curse.scripts.OnClick(curse, "LeftButton")
assert(pv.msg.text:find("removed") and not curse.icon.shown, "left click removes the curse")
for _, b in ipairs(pv.sizeB) do if b.size == 40 then b.scripts.OnClick(b) end end
local visible = 0
for _, t in pairs(pv.tiles) do if t.shown then visible = visible + 1 end end
assert(visible == 40, "preview 40 squares, got " .. visible)
pv.typeB[4].scripts.OnClick(pv.typeB[4]) -- Magic: a druid cannot remove it
assert(pv.msg.text:find("cannot remove"), "magic explained for druid")
pv.clear.scripts.OnClick(pv.clear)
-- two debuffs on one member: the second takes the right half; a click removes the one the button can remove
for _, b in ipairs(pv.sizeB) do if b.size == 5 then b.scripts.OnClick(b) end end
local rnd = math.random
math.random = function() return 2 end -- every test debuff goes to member 2
for _, ty in ipairs({ 1, 2, 1, 2, 1 }) do pv.typeB[ty].scripts.OnClick(pv.typeB[ty]) end -- curse, poison, curse, poison, curse
math.random = rnd
local t2 = pv.tiles[2]
assert(t2.icon.shown and t2.parts[2].shown and t2.parts[3].shown and t2.parts[4].shown, "five debuffs: four pieces shown")
t2.scripts.OnClick(t2, "LeftButton")
assert(pv.msg.text:find("removed") and t2.parts[4].shown, "one curse gone: the fifth slides in, still four")
t2.scripts.OnClick(t2, "RightButton")
assert(pv.msg.text:find("Corrosive Poison") and t2.parts[3].shown and not t2.parts[4].shown, "a poison gone: three pieces")
math.random = function() return 2 end
pv.typeB[4].scripts.OnClick(pv.typeB[4]) -- magic: a druid cannot remove it, it takes no piece
math.random = rnd
assert(not t2.parts[4].shown, "a debuff you cannot remove never takes a piece")
pv.clear.scripts.OnClick(pv.clear)
_G.ForeverCleanseOptions.scripts.OnHide()
assert(not pv.shown, "preview hides with the options")
fire("UNIT_AURA", "player")
assert(db.seen["Curse of Tongues"] == 12889, "learned a debuff name out of combat")
SlashCmdList.FOREVERCLEANSE("lock")
assert(db.lock == true, "lock toggles")
SlashCmdList.FOREVERCLEANSE("reset")
assert(db.scale == 100 and db.point == nil, "reset")

-- shaman: two buttons, no enemy buff box (dropped: the game has its own)
W.class, W.known = "SHAMAN", { ["Cure Poison"] = true, ["Cure Disease"] = true, ["Purge"] = true }
W.raid, W.members = false, 3
fire("SPELLS_CHANGED")
assert(_G.ForeverCleanseTarget == nil, "no enemy buff box")
assert(t1.attrs.spell1 == "Cure Poison" and t1.attrs.spell2 == "Cure Disease", "shaman spells")

-- paladin before Cleanse: Purify on the left button, right does nothing
W.class, W.known = "PALADIN", { ["Purify"] = true }
fire("SPELLS_CHANGED")
assert(t1.attrs.spell1 == "Purify" and t1.attrs.spell2 == nil and t1.attrs.type2 == nil, "paladin: one spell, left button only")

-- preview: with one spell the right button explains it has nothing
_G.ForeverCleanseOptions.scripts.OnShow()
local pal = pv.tiles[2]
pal.scripts.OnClick(pal, "RightButton")
assert(pv.msg.text:find("no second spell"), "right button without a spell: " .. tostring(pv.msg.text))
_G.ForeverCleanseOptions.scripts.OnHide()
-- info panel: opens from the "i" button, follows the language
local info = assert(_G.ForeverCleanseInfo, "info panel built")
local infoB
for _, f in ipairs(W.frames) do if f.parent == _G.ForeverCleanseOptions and f.t and f.t.text == "i" then infoB = f end end
assert(infoB and not info.shown, "info button, panel closed")
infoB.scripts.OnClick(infoB)
assert(info.shown and info.rows[1].t.text:find("Lit square") and info.rows[2].t.text:find("Purify") and not info.rows[3].shown and info.h > 100, "info open in english, paladin: one spell row")
ForeverCleanseDB.lang = "it"; _G.ForeverCleanseOptions.refresh()
assert(info.rows[1].t.text:find("Casella accesa"), "info follows the language")
ForeverCleanseDB.lang = "en"
infoB.scripts.OnClick(infoB)
assert(not info.shown, "info closes")
-- browse: every debuff by type, search, a click fills the box, Add brings every rank, a row click removes them all
local opt = _G.ForeverCleanseOptions
if not opt.shown then SlashCmdList.FOREVERCLEANSE("") end
opt.refresh()
local editBox, addBtn, browseBtn
for _, f in ipairs(W.frames) do
  if f.parent == opt and f.kind == "EditBox" then editBox = f end
  if f.parent == opt and f.t and f.t.text == "Add" then addBtn = f end
  if f.parent == opt and f.t and f.t.text == "Browse" then browseBtn = f end
end
assert(editBox and addBtn and browseBtn, "browse, add and the box exist")
local br = _G.ForeverCleanseBrowse
browseBtn.scripts.OnClick(browseBtn)
assert(br.shown and br.list[1].entry, "browse opens on Curse with entries")
local search
for _, f in ipairs(W.frames) do if f.parent == br and f.kind == "EditBox" then search = f end end
search.text = "tongues"; search.scripts.OnTextChanged(search)
assert(br.list[1].entry[1] == "Curse of Tongues" and not br.list[2].shown, "search finds Curse of Tongues only")
br.list[1].scripts.OnEnter(br.list[1]); br.list[1].scripts.OnLeave(br.list[1]) -- spell tooltip on hover
br.list[1].scripts.OnClick(br.list[1])
assert(editBox.text == "Curse of Tongues 1714", "click fills the box: " .. tostring(editBox.text))
addBtn.scripts.OnClick(addBtn)
local n = 0
for _, name in pairs(ForeverCleanseDB.ignore) do if name == "Curse of Tongues" then n = n + 1 end end
assert(n >= 5, "every rank of Curse of Tongues ignored, got " .. n)
local tongueRow
for _, f in ipairs(W.frames) do if f.parent == opt and f.name == "Curse of Tongues" then tongueRow = f end end
assert(tongueRow and tongueRow.t.text:find("%+"), "one row for the name, with the other ranks counted")
tongueRow.scripts.OnClick(tongueRow)
for _, name in pairs(ForeverCleanseDB.ignore) do assert(name ~= "Curse of Tongues", "row click removes every rank") end
search.text = ""; search.scripts.OnTextChanged(search)
br.tabs[4].scripts.OnClick(br.tabs[4])
assert(br.state.type == "Magic" and br.list[1].entry, "Magic tab")
-- ignore list: Clear all empties it, Reset brings the addon's own list back, rows show the spell on hover, the wheel scrolls
local resetBtn, clearBtn
for _, f in ipairs(W.frames) do
  if f.parent == opt and f.t and f.t.text == "Reset" then resetBtn = f end
  if f.parent == opt and f.t and f.t.text == "Clear all" then clearBtn = f end
end
assert(resetBtn and clearBtn, "reset and clear all exist")
clearBtn.scripts.OnClick(clearBtn)
assert(next(ForeverCleanseDB.ignore) == nil, "clear all empties the list")
for _, e in ipairs(NS.DEBUFFS.Curse) do for i = 2, #e do ForeverCleanseDB.ignore[e[i]] = e[1] end end
opt.refresh()
local irows = {}
for _, f in ipairs(W.frames) do if f.parent == opt and f.scripts.OnMouseWheel and f.kind == "Button" then irows[#irows + 1] = f end end
local before = irows[1].name
irows[1].scripts.OnEnter(irows[1]); irows[1].scripts.OnLeave(irows[1])
irows[1].scripts.OnMouseWheel(irows[1], -1)
assert(irows[1].name ~= before, "the wheel scrolls the ignore list")
resetBtn.scripts.OnClick(resetBtn)
assert(ForeverCleanseDB.ignore[15822] == "Dreamless Sleep" and ForeverCleanseDB.ignore[12889] == nil, "reset brings the default list back")
assert(ForeverCleanseDB.ignore[1229451] == nil, "the XP auras are not in the list")
local ex = _G.ForeverCleanseTile1.aura.filters
assert(ex and ex.excludeSpellIDs[1229451], "the XP auras are always hidden from the squares")
assert(W.cyrillic, "fonts carry a Cyrillic member for Russian names")
-- key strip: the spell's own icon and its types; bar opacity slider
local sliders = {}
for _, f in ipairs(W.frames) do if f.kind == "Slider" and f.parent == opt then sliders[#sliders + 1] = f end end
assert(#sliders == 2, "size and bar opacity sliders, got " .. #sliders)
sliders[2].scripts.OnValueChanged(sliders[2], 40, true)
assert(ForeverCleanseDB.barAlpha == 40, "bar opacity saved")
sliders[1].scripts.OnValueChanged(sliders[1], 120, true)
assert(ForeverCleanseDB.scale == 120, "size slider still works")
local keyText
for _, f in ipairs(W.frames) do if f.parts and f.parts[1] and f.parts[1].icon then keyText = f.parts[1].text.text end end
assert(keyText and keyText:find("Poison"), "key strip names the types: " .. tostring(keyText))
-- grip: scaling stops when the button is released, even if OnMouseUp never reaches the grip
local grip
for _, f in ipairs(W.frames) do if f.scripts.OnMouseDown and f.scripts.OnMouseUp and f.parent == ForeverCleanseFrame then grip = f end end
assert(grip, "grip found")
W.held, W.cursor, ForeverCleanseDB.lock = true, 0, false
grip.scripts.OnMouseDown(grip)
W.cursor = 200; grip.scripts.OnUpdate(grip)
assert(ForeverCleanseDB.scale > 100 and grip.scripts.OnUpdate, "grip scales while held, scale " .. ForeverCleanseDB.scale)
W.held = false; grip.scripts.OnUpdate(grip)
assert(grip.scripts.OnUpdate == nil, "grip lets go when the button is released")
-- sound: one native registration per unit and removable spell ID, none for types the class cannot remove; off removes them all
local live, curse = 0, false
for _, info in pairs(W.sounds) do live = live + 1; if info.spellID == 14868 then curse = true end; assert(info.unitToken and info.soundFileID, "sound info") end
assert(live > 100 and not curse, "paladin: poison/disease/magic sounds, no curses, got " .. live)
local soundBtn
for _, f in ipairs(W.frames) do if f.parent == opt and f.t and f.t.text == "Sound when a debuff lands" then soundBtn = f end end
assert(soundBtn, "sound option exists")
soundBtn.scripts.OnClick(soundBtn)
assert(not ForeverCleanseDB.sound and next(W.sounds) == nil, "sound off removes every registration")
soundBtn.scripts.OnClick(soundBtn)
assert(ForeverCleanseDB.sound and next(W.sounds) and #W.played >= 1, "sound back on: registered again, plays once")
local dingBtn
for _, f in ipairs(W.frames) do if f.parent == opt and f.t and f.t.text == "Ding" then dingBtn = f end end
assert(dingBtn, "sound choices exist")
dingBtn.scripts.OnClick(dingBtn)
assert(ForeverCleanseDB.soundFile == 567458 and W.played[#W.played] == 567458, "picking a sound saves it and plays it")
for _, info in pairs(W.sounds) do assert(info.soundFileID == 567458, "registrations use the picked sound") end
-- other languages: the texts follow the language, the spells are cast by the client's own names (German client here)
ForeverCleanseDB.lang = "de"; _G.ForeverCleanseOptions.refresh()
local de
for _, f in ipairs(W.frames) do if f.parent == _G.ForeverCleanseOptions and f.t and f.t.text == "Hinzufügen" then de = f end end
assert(de, "options in German")
W.lang, W.class, W.known = "de", "DRUID", { ["DE Remove Curse"] = true, ["DE Abolish Poison"] = true }
fire("SPELLS_CHANGED")
assert(t1.attrs.spell1 == "DE Remove Curse" and t1.attrs.spell2 == "DE Abolish Poison", "German client: German spell names on the buttons, got " .. tostring(t1.attrs.spell1))
ForeverCleanseDB.lang, W.lang = "en", nil
for _, p in ipairs(W.printed) do assert(not p:find("decorate:"), "decorate failed: " .. p) end
print_real("addon: tutte le prove ok")
