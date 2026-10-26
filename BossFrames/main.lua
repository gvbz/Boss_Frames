-- Boss Frames 1.1.1: target plates on the monsters you name (AC:Unreal API 2
-- companion, client build 137 or newer; plate opacity needs 138).
--
-- You enter boss names; when one is near (the client's nearby-object list,
-- 240 m), it is listed under Nearby with a Select button, and the client draws
-- a target plate on it: brackets around the monster and a heading with its
-- name. Boss names are unique, so a name is matched exactly (not case-sensitive).
--
-- What a plate can show depends on what the client knows about that monster.
-- The client assesses plate targets in the background (one assessment per
-- second for all plugins, each target at most every 2 s), so level, title and
-- health appear without selecting the boss:
--   - health: live on your selected target; on others, a percentage refreshed
--     every few seconds (exact numbers right after an assessment)
--   - level and title: after the first assessment
--   - debuff icons: your own confirmed casts, with estimated timers
-- The plugin passes what is known. At most 4 plates per plugin (16 in total).
--
-- Settings: plate color, plate and background opacity, health/stamina/mana
-- bars, your debuffs, level, the role line (title, creature type or none),
-- plates only on your selected target, and the detection range.
--
-- 1.1.0 (client 138): background assessments fill in plates on bosses you have
-- not selected; plate and background opacity; "Add selected"; only creatures
-- are checked (object_type).
-- 1.1.1: back to a callback every 0.5 s (1 s felt slow to respond).
--
-- Lightweight: plugin.json asks only for nearby objects and target data
-- ("snapshot_fields"); only creatures are checked, each name once (cached by
-- id); the
-- window and the plates are sent only when they change. The boss list and
-- settings are saved per character.

local SIZE = 15          -- 20 px, drawn sharp (the game's basefont20)
local SMALL = 12
local COLORS = {"red", "yellow", "blue", "green", "white", "purple"}
local ROLES = {"Title", "Creature type", "None"}
local OPT_DEFAULT = {color = "red", vitals = true, effects = true, level = true, role = "Title", sel_only = false, range = 240,
  opacity = 100, back = 75}

local st                      -- {bosses = {names}, opt = {...}} saved per character
local dirty = false
local function opt(k) local v = st.opt[k]; if v == nil then return OPT_DEFAULT[k] end; return v end

local want = {}               -- lower-case boss name -> true
local match = {}              -- object id -> boss name (or false); names checked once per object
local match_n = 0
local draft = ""              -- the Add box
local show_settings = false
local ui_key, plate_key = nil, nil

local function trim(s)
  local a, b = 1, #s
  while a <= b and string.byte(s, a) == 32 do a = a + 1 end
  while b >= a and string.byte(s, b) == 32 do b = b - 1 end
  return string.sub(s, a, b)
end
local function refresh_want()
  want = {}
  for _, n in ipairs(st.bosses) do want[string.lower(n)] = true end
  match, match_n = {}, 0
end

-- The selected monster, if it can be added (a living creature not on the list).
local function addable(s)
  local t = type(s.selection) == "table" and s.selection or nil
  if not t or t.dead or type(t.name) ~= "string" or #t.name == 0 or t.id == s.player then return nil end
  if t.object_type ~= nil and t.object_type ~= "creature" then return nil end
  if t.object_type == nil and not t.monster then return nil end
  if want[string.lower(t.name)] then return nil end
  return t.name
end

-- Window -----------------------------------------------------------------------
local function build(found, sel_name)
  local ui = {}
  -- Add a boss by name.
  ui[#ui + 1] = {id = "add", type = "row", children = {
    {id = "name", type = "input", size = SIZE, text = "Monster name", value = draft},
    {id = "addb", type = "button", size = SIZE, text = "Add", auto_width = true},
    {id = "adds", type = "button", size = SIZE, text = "Add selected", auto_width = true, enabled = sel_name ~= nil,
      tooltip = sel_name or "Select a monster"}}}
  -- Bosses near you, each with a Select button (handled by the client itself).
  ui[#ui + 1] = {id = "nh", type = "text", size = SIZE, text = "Nearby", bold = true}
  for _, f in ipairs(found) do
    ui[#ui + 1] = {id = "n|" .. f.key, type = "row", children = {
      {id = "nt|" .. f.key, type = "text", size = SIZE, text = f.name, wrap = false, tooltip = f.name},
      {id = "ns|" .. f.key, type = "button", size = SIZE, text = "Select", auto_width = true, action = "select", target = f.id}}}
  end
  if #found == 0 then ui[#ui + 1] = {id = "none", type = "text", size = SMALL, text = "None nearby", wrap = false} end
  -- Your boss list.
  ui[#ui + 1] = {id = "bh", type = "text", size = SIZE, text = "Bosses", bold = true}
  for i, n in ipairs(st.bosses) do
    ui[#ui + 1] = {id = "b|" .. i, type = "row", children = {
      {id = "bt|" .. i, type = "text", size = SIZE, text = n, wrap = false, tooltip = n},
      {id = "rm|" .. i, type = "button", size = SIZE, text = "Remove", auto_width = true}}}
  end
  if #st.bosses == 0 then ui[#ui + 1] = {id = "empty", type = "text", size = SMALL, text = "Add a monster name above", wrap = false} end

  -- Settings: what the client's target plates can adjust.
  ui[#ui + 1] = {id = "settings", type = "button", size = SIZE, text = "Settings"}
  if show_settings then
    ui[#ui + 1] = {id = "opt|color", type = "select", size = SIZE, text = "Plate color", value = opt("color"), options = COLORS}
    ui[#ui + 1] = {id = "opt|opacity", type = "slider", size = SIZE, text = "Plate opacity (%)", min = 10, max = 100, step = 5, value = tonumber(opt("opacity")) or 100}
    ui[#ui + 1] = {id = "opt|back", type = "slider", size = SIZE, text = "Background opacity (%)", min = 0, max = 100, step = 5, value = tonumber(opt("back")) or 75}
    ui[#ui + 1] = {id = "opt|vitals", type = "checkbox", size = SIZE, text = "Health, stamina and mana", value = opt("vitals"),
      tooltip = "Live on your selected target; refreshed every few seconds on others"}
    ui[#ui + 1] = {id = "opt|effects", type = "checkbox", size = SIZE, text = "My debuffs", value = opt("effects"),
      tooltip = "Your own confirmed casts, with estimated timers"}
    ui[#ui + 1] = {id = "opt|level", type = "checkbox", size = SIZE, text = "Level", value = opt("level")}
    ui[#ui + 1] = {id = "opt|role", type = "select", size = SIZE, text = "Role line", value = opt("role"), options = ROLES}
    ui[#ui + 1] = {id = "opt|sel_only", type = "checkbox", size = SIZE, text = "Only on my selected target", value = opt("sel_only")}
    ui[#ui + 1] = {id = "opt|range", type = "slider", size = SIZE, text = "Range (m)", min = 20, max = 240, step = 10, value = tonumber(opt("range")) or 240}
  end
  return ui
end

-- Plates -------------------------------------------------------------------------
local function idkey(id) return string.format("%.0f", id) end
local function plate_for(f, s)
  local t = (type(s.tracked_targets) == "table" and s.tracked_targets[f.key])
    or (type(s.selection) == "table" and s.selection.id == f.id and s.selection) or nil
  local p = {id = f.id, name = string.sub(f.name, 1, 128), color = opt("color"), selection_only = opt("sel_only"),
    opacity = (tonumber(opt("opacity")) or 100) / 100, background_opacity = (tonumber(opt("back")) or 75) / 100}
  if t then
    local r = opt("role")
    local role = (r == "Title" and (t.title or t.creature_class)) or (r == "Creature type" and (t.creature_class or t.title)) or nil
    if role then p.role = string.sub(role, 1, 80) end
    if opt("level") and tonumber(t.level) and t.level >= 0 then p.level = math.floor(t.level) end
    if opt("vitals") and type(t.vitals) == "table" and next(t.vitals) then p.vitals = t.vitals end
  end
  if opt("effects") and type(s.target_effects) == "table" then
    local fx = {}
    for _, e in ipairs(s.target_effects[f.key] or {}) do
      if #fx == 16 then break end
      local rem = tonumber(e.remaining) or 0
      if rem > 0 and rem <= 86400 and tonumber(e.icon) then fx[#fx + 1] = {spell = e.spell, icon = e.icon, remaining = rem} end
    end
    if #fx > 0 then p.effects = fx end
  end
  return p
end
-- What makes the plates look different (not the timers, which count down on
-- their own between callbacks).
local function plates_key(plates, now)
  local k = {}
  for _, p in ipairs(plates) do
    k[#k + 1] = p.id .. "|" .. p.name .. "|" .. tostring(p.role) .. "|" .. tostring(p.level) .. "|" .. p.color .. "|" .. tostring(p.selection_only) .. "|" .. p.opacity .. "|" .. p.background_opacity
    for _, v in pairs(p.vitals or {}) do k[#k + 1] = tostring(v.current) .. "/" .. tostring(v.max) .. "/" .. tostring(v.fraction) end
    -- An effect's end time (whole seconds) changes only when it is recast.
    for _, e in ipairs(p.effects or {}) do k[#k + 1] = tostring(e.spell) .. ":" .. tostring(e.icon) .. ":" .. math.floor(now + e.remaining + 0.5) end
  end
  return table.concat(k, ";")
end

-- Callback -------------------------------------------------------------------------
return function(s, p)
  local out = {}
  if not st then
    local saved = type(s.state) == "table" and s.state or {}
    st = {bosses = {}, opt = type(saved.opt) == "table" and saved.opt or {}}
    for _, n in ipairs(type(saved.bosses) == "table" and saved.bosses or {}) do
      if type(n) == "string" and #n > 0 then st.bosses[#st.bosses + 1] = n end
    end
    refresh_want()
  end

  -- Clicks and settings
  for _, e in ipairs(s.events or {}) do
    local id = type(e.id) == "string" and e.id or ""
    if e.type == "change" and id == "name" then draft = string.sub(tostring(e.value or ""), 1, 128)
    elseif e.type == "click" and id == "addb" then
      local n = trim(draft)
      if #n > 0 and not want[string.lower(n)] and #st.bosses < 50 then
        st.bosses[#st.bosses + 1] = n; refresh_want(); dirty = true
      end
      draft = ""
    elseif e.type == "click" and id == "adds" then
      local n = addable(s)
      if n and #st.bosses < 50 then st.bosses[#st.bosses + 1] = n; refresh_want(); dirty = true end
    elseif e.type == "click" and string.sub(id, 1, 3) == "rm|" then
      local i = tonumber(string.sub(id, 4))
      if i and st.bosses[i] then table.remove(st.bosses, i); refresh_want(); dirty = true end
    elseif e.type == "click" and id == "settings" then show_settings = not show_settings
    elseif e.type == "change" and string.sub(id, 1, 4) == "opt|" then
      local k = string.sub(id, 5)
      if k == "range" then st.opt.range = math.max(20, math.min(240, math.floor(tonumber(e.value) or 240)))
      elseif k == "opacity" then st.opt.opacity = math.max(10, math.min(100, math.floor(tonumber(e.value) or 100)))
      elseif k == "back" then st.opt.back = math.max(0, math.min(100, math.floor(tonumber(e.value) or 75)))
      elseif k == "color" or k == "role" then st.opt[k] = tostring(e.value)
      else st.opt[k] = e.value == true end
      dirty = true
    end
  end

  -- Nearby bosses (objects arrive nearest first); only creatures, each name checked once.
  local found = {}
  if next(want) then
    local range = tonumber(opt("range")) or 240
    for _, o in ipairs(s.objects or {}) do
      local d = o.distance or 1e9
      if d > range then break end
      local m = match[o.id]
      if m == nil and o.object_type ~= nil and o.object_type ~= "creature" then m = false end
      if m == nil then
        m = (type(o.name) == "string" and not o.player and want[string.lower(o.name)]) and o.name or false
        if match_n > 4000 then match, match_n = {}, 0 end
        match[o.id] = m; match_n = match_n + 1
      end
      if m and not o.dead and not o.corpse then
        found[#found + 1] = {id = o.id, key = idkey(o.id), name = m}
        if #found == 4 then break end
      end
    end
  end

  -- Window: only when what it shows changes.
  local keys = {}
  for _, f in ipairs(found) do keys[#keys + 1] = f.key end
  local k = table.concat(keys, ",") .. "#" .. table.concat(st.bosses, "|") .. "#" .. draft .. "#" .. tostring(show_settings)
    .. "#" .. tostring(opt("color")) .. tostring(opt("vitals")) .. tostring(opt("effects")) .. tostring(opt("level"))
    .. tostring(opt("role")) .. tostring(opt("sel_only")) .. tostring(opt("range")) .. "|" .. tostring(opt("opacity")) .. "|" .. tostring(opt("back"))
  local sel_name = addable(s)
  k = k .. "#" .. tostring(sel_name)
  if k ~= ui_key then
    if not ui_key then out.status = "" end
    out.ui = build(found, sel_name); ui_key = k
  end

  -- Plates: only when they change.
  local plates = {}
  for _, f in ipairs(found) do plates[#plates + 1] = plate_for(f, s) end
  local pk = plates_key(plates, tonumber(s.time) or 0)
  if pk ~= plate_key then out.world_plates = plates; plate_key = pk end

  if dirty then out.state = {bosses = st.bosses, opt = st.opt}; dirty = false end
  return out
end
