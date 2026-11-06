-- Boss Frames 1.2.0: target plates on the monsters you name (AC:Unreal API 2
-- companion, client v146 or newer).
--
-- You enter boss names; when one is near (the client's nearby-object list, up
-- to 240 m) the client draws a target plate on it: brackets around the monster
-- and a heading with its name. Boss names are unique, so a name is matched
-- exactly (not case-sensitive).
--
-- What a plate can show depends on what the client knows about that monster.
-- The client assesses plate targets in the background (one assessment per
-- second for all plugins, each target at most every 2 s), so level, title and
-- health appear without selecting the boss:
--   - health: live on your selected target; on others, a percentage refreshed
--     every few seconds (exact numbers right after an assessment)
--   - level and title: after the first assessment
--   - debuff icons: your own confirmed casts (debuffs and damage over time),
--     with estimated timers
-- The plugin passes what is known. At most 4 plates per plugin (16 in total).
--
-- Window: "Show boss frames" (on/off: plates, minimap diamonds and alerts),
-- the Add row (name box, Add, Add selected), your boss list with Remove, and
-- Settings: plate color, plate and background opacity, health/stamina/mana
-- bars, your debuffs, level, the role line (title, creature type or none),
-- plates only on your selected target, the detection range, and two options
-- (off by default):
--   - Alert in chat when a boss is in range: one local line in the plate color,
--     "[Boss Frames] Elder Chaos Dragon is in range (85 m)", once per boss; not
--     again if it steps out and back within 60 s; a respawned boss (a new
--     object) alerts again. Only you see it; nothing is sent.
--   - Show bosses on the minimap: a diamond in the plate color on the minimap
--     for each boss in range (up to 16).
--
-- 1.2.0: the on/off toggle, the chat alert and minimap diamonds; no Nearby
-- list (the plates show the bosses); the Add box shows "Monster name" inside it,
-- so the buttons line up with it; the status line shows a client error.
--
-- Lightweight: plugin.json asks only for nearby objects and target data
-- ("snapshot_fields"); only creatures are checked, each name once (cached by
-- id); the window, plates and markers are sent only when they change. The boss
-- list and settings are saved per character.

local SIZE = 15          -- 20 px, drawn sharp (the game's basefont20)
local SMALL = 12
local COLORS = {"red", "yellow", "blue", "green", "white", "purple"}
local ROLES = {"Title", "Creature type", "None"}
local OPT_DEFAULT = {color = "red", vitals = true, effects = true, level = true, role = "Title", sel_only = false, range = 240,
  opacity = 100, back = 75, on = true, alert = false, map = false}
-- Chat colors: the plate colors (chat has no "purple" name, so its hex).
local CHAT_COLOR = {red = "red", yellow = "yellow", blue = "blue", green = "green", white = "white", purple = "#CC4DFF"}
local ALERT_GAP = 60          -- s out of range before the same boss alerts again

local st                      -- {bosses = {names}, opt = {...}} saved per character
local dirty = false
local function opt(k) local v = st.opt[k]; if v == nil then return OPT_DEFAULT[k] end; return v end

local want = {}               -- lower-case boss name -> true
local match = {}              -- object id -> boss name (or false); names checked once per object
local match_n = 0
local draft = ""              -- the Add box
local show_settings = false
local ui_key, plate_key, marker_key = nil, nil, nil
local seen = {}               -- object id -> last time it was in range (alerts)
local alerts = {}             -- alert lines waiting to be shown

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
local function build(sel_name)
  local ui = {}
  -- On/off for everything the plugin draws or says.
  ui[#ui + 1] = {id = "opt|on", type = "checkbox", size = SIZE, text = "Show boss frames", value = opt("on") ~= false, wrap = false,
    tooltip = "Plates on your bosses, minimap diamonds and alerts"}
  -- Add a boss by name (the hint sits in the box, so the buttons line up with it).
  ui[#ui + 1] = {id = "add", type = "row", children = {
    {id = "name", type = "input", size = SIZE, placeholder = "Monster name", value = draft},
    {id = "addb", type = "button", size = SIZE, text = "Add", auto_width = true},
    {id = "adds", type = "button", size = SIZE, text = "Add selected", auto_width = true, enabled = sel_name ~= nil,
      tooltip = sel_name or "Select a monster"}}}
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
    ui[#ui + 1] = {id = "opt|alert", type = "checkbox", size = SIZE, text = "Alert in chat when a boss is in range", value = opt("alert"),
      tooltip = "One line in chat, in the plate color, when a boss comes within range"}
    ui[#ui + 1] = {id = "opt|map", type = "checkbox", size = SIZE, text = "Show bosses on the minimap", value = opt("map"),
      tooltip = "A diamond in the plate color on the minimap for each boss in range"}
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
  local now = tonumber(s.time) or 0
  if next(want) and opt("on") ~= false then
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
        found[#found + 1] = {id = o.id, key = idkey(o.id), name = m, d = d}
        if #found == 16 then break end
      end
    end
  end

  -- Window: only when what it shows changes.
  local k = table.concat(st.bosses, "|") .. "#" .. draft .. "#" .. tostring(show_settings) .. "#" .. tostring(opt("on")) .. tostring(opt("alert")) .. tostring(opt("map"))
    .. "#" .. tostring(opt("color")) .. tostring(opt("vitals")) .. tostring(opt("effects")) .. tostring(opt("level"))
    .. tostring(opt("role")) .. tostring(opt("sel_only")) .. tostring(opt("range")) .. "|" .. tostring(opt("opacity")) .. "|" .. tostring(opt("back"))
  local sel_name = addable(s)
  k = k .. "#" .. tostring(sel_name)
  if k ~= ui_key then
    if not ui_key then out.status = "" end
    out.ui = build(sel_name); ui_key = k
  end

  -- Alerts: a boss that comes into range (a new object, or back after more than
  -- ALERT_GAP seconds away) gets one line in chat.
  for _, f in ipairs(found) do
    local last = seen[f.key]
    if opt("alert") and (not last or now - last > ALERT_GAP) and #alerts < 16 then
      alerts[#alerts + 1] = f.name .. " is in range (" .. math.floor(f.d + 0.5) .. " m)"
    end
    seen[f.key] = now
  end
  if #alerts > 0 then
    out.requests = {}
    while #alerts > 0 and #out.requests < 4 do
      out.requests[#out.requests + 1] = {id = "alert" .. #out.requests, service = "notice", operation = "show",
        text = table.remove(alerts, 1), color = CHAT_COLOR[opt("color")] or "red"}
    end
  end
  if next(seen) and now - (seen.__swept or 0) > 120 then
    for key, at in pairs(seen) do if key ~= "__swept" and now - at > 600 then seen[key] = nil end end
    seen.__swept = now
  end

  -- Minimap diamonds: only when they change.
  local markers = {}
  if opt("map") then
    for _, f in ipairs(found) do markers[#markers + 1] = {id = f.id, shape = "diamond", color = opt("color"), world = false, map = true} end
  end
  local mk = opt("color") .. "#"
  for _, m in ipairs(markers) do mk = mk .. idkey(m.id) .. "," end
  if mk ~= marker_key then out.markers = markers; marker_key = mk end

  -- Plates (the nearest 4): only when they change.
  local plates = {}
  for i = 1, math.min(4, #found) do plates[#plates + 1] = plate_for(found[i], s) end
  local pk = plates_key(plates, tonumber(s.time) or 0)
  if pk ~= plate_key then out.world_plates = plates; plate_key = pk end

  if dirty then out.state = {bosses = st.bosses, opt = st.opt}; dirty = false end
  return out
end
