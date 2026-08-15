local api = require("api")
local default_settings = require("BetterBars/default_settings")

local settings = {}

-- ============================================================================
-- Private persistence (3.2)
--
-- BetterBars' settings no longer live in the client's shared `addon_settings`
-- file. That file is one blob for every addon, and the client rewrites it
-- non-atomically: File:Write opens with "w" - truncating the file on the
-- spot - and only THEN serializes the table. A death between those two steps
-- (an out-of-memory failure inside the serializer is exactly what a long
-- session on the 32-bit client produces) leaves a 0-byte file, and on the
-- next boot the client silently replaces it with `{enabled=true}` defaults
-- for EVERY addon and rewrites it, making the loss permanent. Diagnosed from
-- a player's crash logs (Aug 2026); power_ranger_on ships the same defense
-- for the same reason.
--
-- So BetterBars keeps its own file pair. api.SaveSettings() is called at
-- most ONCE per install - the boot-time flush that purges its legacy branch
-- from the shared file (see scrubEngineBranch) - and never on a gameplay
-- path: it can neither suffer that wipe nor put the shared file at risk
-- when it matters. The shared store is still READ once to
-- migrate a pre-3.2 save, and still owns the addon manager's `enabled` flag.
--
-- Both files live at the Addon ROOT (next to `addon_settings`, outside the
-- BetterBars folder): the File API is rooted there, the root always exists
-- (File:Write creates no directories), and root files survive addon updates
-- and even full delete-and-reinstalls.
-- ============================================================================
local SETTINGS_PATH = "BetterBars_settings.lua"
local BACKUP_PATH = "BetterBars_settings_backup.lua"

-- Read one private file defensively. File:Read RAISES on a file that exists
-- but no longer deserializes (the truncated-by-a-crash case), so the pcall is
-- load-bearing, not paranoia. Only a non-empty table counts as a usable save;
-- `next` is not in the sandbox whitelist, so emptiness is probed with pairs.
local function readPrivate(path)
    local ok, data = pcall(function() return api.File:Read(path) end)
    if not ok or type(data) ~= "table" then return nil end
    for _ in pairs(data) do return data end
    return nil
end

-- Plain deep copy, for migrating the engine's table. The migration used to
-- alias it (saved = engine), which was harmless while the engine branch was
-- left alone - but the scrub below empties that branch, and gutting a table
-- the live settings alias would take the session down with it.
local function deepCopy(tbl, seen)
    seen = seen or {}
    if seen[tbl] then return nil end
    seen[tbl] = true
    local out = {}
    for k, v in pairs(tbl) do
        if type(v) == "table" then
            out[k] = deepCopy(v, seen)
        else
            out[k] = v
        end
    end
    seen[tbl] = nil
    return out
end

-- Deep merge saved settings with defaults (nil-checks preserve false)
-- Set by the one-time forced reset so the marker persists even if the player
-- never touches a setting that session (otherwise the wipe would re-run each
-- load - same result, but noisy).
local needsPostResetSave = false

local function mergeSettings(saved)
    saved = saved or {}

    -- One-time forced reset for 3.0: the defaults were rebuilt around new
    -- anchor bases and layouts, and older customised saves sit badly on top
    -- of them. Guarded by its own marker exactly like bbOpacityRebased, so
    -- it runs once per install and never again - after that the player
    -- customises freely. The shown-once welcome-card marker and the addon
    -- manager's enabled flag are the only survivors; the wipe lands on
    -- current semantics, so the opacity migration below is marked done too.
    if not saved.bbForcedReset30 then
        -- `next` is not in the addon sandbox whitelist - emptiness has to be
        -- probed with pairs
        local isEmpty = true
        for _ in pairs(saved) do isEmpty = false break end
        if isEmpty then
            -- Fresh install, or a too-early read before the engine store
            -- loaded (that read is a detached table - anything written to it
            -- vanishes). Nothing to wipe either way: mark and move on. When
            -- loadSettings runs again from OnLoad against the real store,
            -- this re-evaluates with the real contents.
            saved.bbOpacityRebased = true
            saved.bbForcedReset30 = true
        else
            local keepSeen = saved.infoCardSeen
            local keepEnabled = saved.enabled
            for k in pairs(saved) do saved[k] = nil end
            saved.infoCardSeen = keepSeen
            if keepEnabled ~= nil then saved.enabled = keepEnabled end
            saved.bbOpacityRebased = true
            saved.bbForcedReset30 = true
            needsPostResetSave = true
        end
    end


    -- colors.abyssal is GONE as of 3.1 - the pips are plain authored artwork
    -- and nothing reads a tint any more. This migration stays to scrub the key
    -- out of old saves (it shipped as violet in the drawn-disc era, then white
    -- in the tint era); with "abyssal" removed from the merge list below,
    -- nothing refills it and saves come out clean.
    if not saved.bbAbyssalArt then
        saved.bbAbyssalArt = true
        if saved.colors and saved.colors.abyssal ~= nil then
            saved.colors.abyssal = nil
            needsPostResetSave = true
        end
    end

    -- The five generated fill styles (flat, gloss, sheen, striped, tube) are
    -- gone as of 3.1 - the extracted retail sprite is the only fill that ships.
    -- A save still naming one of them would point the drawable at a PNG that no
    -- longer exists, so the key is dropped and the merge below refills it from
    -- the defaults. "none" and any file the player put in textures/ themselves
    -- are left alone; only the names this addon deleted are rewritten. Guarded
    -- by its own marker like the migrations above, so a later hand-set value is
    -- never second-guessed.
    if not saved.bbFillRetailOnly then
        saved.bbFillRetailOnly = true
        local gone = {
            bar_flat = true, bar_gloss = true, bar_sheen = true,
            bar_striped = true, bar_tube = true,
        }
        if saved.barTexture and gone[saved.barTexture] then
            saved.barTexture = nil
            needsPostResetSave = true
        end
    end

    -- Colors. Copied field by field rather than assigned: handing out the
    -- default table itself made the live settings and the defaults the same
    -- object, so anything editing a colour in place would have destroyed the
    -- fallback for the rest of the session.
    if not saved.colors then saved.colors = {} end
    for _, key in ipairs({"hp", "mp", "ehp", "cast"}) do
        if not saved.colors[key] then
            local d = default_settings.colors[key]
            saved.colors[key] = { r = d.r, g = d.g, b = d.b, a = d.a }
        else
            for _, comp in ipairs({"r", "g", "b", "a"}) do
                if saved.colors[key][comp] == nil then
                    saved.colors[key][comp] = default_settings.colors[key][comp]
                end
            end
        end
    end
    
    -- NOTE: this runs BEFORE the defaults are filled in below, so a fresh
    -- install (where backgroundOpacity is still nil) is left alone. Running it
    -- after would rescale the shipped default and undo it.
    -- backgroundOpacity changed meaning: it used to be normalised against 0.6,
    -- so 0.6 was "draw the reference cell at its own alphas". It is now a plain
    -- multiplier where 1.0 means that. Without rescaling, every existing install
    -- would suddenly render its bar backgrounds at 60% and look washed out.
    --
    -- Guarded by its own marker rather than the schema version, so it runs once
    -- regardless of what else has migrated.
    if not saved.bbOpacityRebased then
        saved.bbOpacityRebased = true
        local v = tonumber(saved.backgroundOpacity)
        if v then
            v = v / 0.6
            if v > 1.1 then v = 1.1 end
            saved.backgroundOpacity = v
        end
    end

    -- barHeight changed meaning, so saved values have to be re-based.
    --
    -- It used to be the FILL height, with the wrapper drawn 4px larger to leave
    -- room for a border inset inside it. The bar is vanilla geometry now - the
    -- setting IS the wrapper height, applied straight to SetHeight, and the
    -- border is drawn outside the bar instead. A save carrying the old 17 would
    -- render a 17px wrapper where it used to produce 21, and 2px under AAC's
    -- native 19.
    --
    -- Dropping the key lets the merge below refill it from the new defaults
    -- (19/13, the client's own heights). Guarded by its own marker like the
    -- migrations above, so it runs exactly once and the player is free to
    -- re-tune afterwards.
    -- Only flags a save when there was actually something to drop. The
    -- parse-time read can hand back a detached empty table, and marking that
    -- dirty would write the marker to a table nothing keeps - after which the
    -- real load would re-run the migration and wipe a height the player had
    -- since set.
    if not saved.bbHeightsVanilla then
        saved.bbHeightsVanilla = true
        if saved.barHeight ~= nil then
            saved.barHeight = nil
            needsPostResetSave = true
        end
    end

    -- Every non-table default (label format and size, background opacity, the
    -- show* toggles, info font size, bar texture...). Driven off the defaults
    -- table so adding a setting there is enough - the old version repeated an
    -- `if saved.X == nil` block per field, and a field missing from that list
    -- would arrive nil at the point of use.
    for key, value in pairs(default_settings) do
        if type(value) ~= "table" and saved[key] == nil then
            saved[key] = value
        end
    end

    -- Bar height
    if not saved.barHeight then
        saved.barHeight = { hp = default_settings.barHeight.hp, mp = default_settings.barHeight.mp }
    else
        if saved.barHeight.hp == nil then saved.barHeight.hp = default_settings.barHeight.hp end
        if saved.barHeight.mp == nil then saved.barHeight.mp = default_settings.barHeight.mp end
    end

    -- Info label offsets and sizes (nested like barHeight, so partial saves
    -- heal). A missing per-item size inherits the old global infoFontSize,
    -- so pre-split saves keep their look.
    if not saved.infoOffsets then saved.infoOffsets = {} end
    for _, k in ipairs({"class", "gs", "guild"}) do
        local d = default_settings.infoOffsets[k]
        if not saved.infoOffsets[k] then
            saved.infoOffsets[k] = { x = d.x, y = d.y, size = d.size }
        else
            if saved.infoOffsets[k].x == nil then saved.infoOffsets[k].x = d.x end
            if saved.infoOffsets[k].y == nil then saved.infoOffsets[k].y = d.y end
            if saved.infoOffsets[k].size == nil then
                saved.infoOffsets[k].size = saved.infoFontSize or d.size
            end
        end
    end
    
    return saved
end

-- Scrub the engine's branch down to the bare `enabled` flag the addon
-- manager owns. power_ranger_on's stance, adopted here too (user call):
-- once the private pair is the source of truth, nothing of ours belongs in
-- the shared file - no replica, and no stale copy from earlier builds
-- lingering there. The accepted trade: if BOTH private files are ever lost
-- at once, the migration path finds nothing and the addon starts from
-- defaults. Runs after every load and save, so a branch populated by an
-- older build empties on the first boot of this one. One session-state
-- exception rides along: bbWatchToken, the abyssal watchdog's staleness
-- token, lives on this table precisely BECAUSE it is the one object every
-- load can reach - scrubbing it would un-gate dead sessions' handlers.
local function scrubEngineBranch()
    local engineTable = api.GetSettings("BetterBars")
    if type(engineTable) ~= "table" then return end
    local removed = 0
    for key in pairs(engineTable) do
        if key ~= "enabled" and key ~= "bbWatchToken" then
            engineTable[key] = nil
            removed = removed + 1
        end
    end
    -- One-shot flush. Scrubbing only empties the IN-MEMORY table; the file
    -- is rewritten by the client at boot BEFORE addons load, so it keeps
    -- copying the stale branch back, and if no other addon ever saves
    -- mid-session the stale keys would sit on disk forever. When the scrub
    -- actually removed something - which after the transition boot it never
    -- does again, the branch arrives bare - flush the file once. A single
    -- boot-time write per install, when memory is fresh; gated on a REAL
    -- engine read (`enabled` stamp) so it can never fire from the parse-time
    -- detached table, where a save would serialize a half-built store.
    if removed > 0 and engineTable.enabled ~= nil then
        pcall(function() api.SaveSettings() end)
    end
end

-- Forward declaration: loadSettings persists the forced-reset marker and the
-- migration/heal writes through saveSettings, which is defined below it.
local saveSettings

-- Load settings: primary file, then backup, then the shared store (a pre-3.2
-- save, or a fresh install's bare `{enabled=true}`), then defaults.
local function loadSettings()
    local saved = readPrivate(SETTINGS_PATH)
    local needsSave = false
    if saved == nil then
        saved = readPrivate(BACKUP_PATH)
        if saved ~= nil then
            -- Primary lost or corrupt but the mirror survived: heal it back.
            needsSave = true
        end
    end
    if saved == nil then
        local engine = api.GetSettings("BetterBars")
        -- `enabled` is how a REAL engine read is told apart from the
        -- parse-time one: the client stamps `{enabled=true}` on every entry
        -- when its store initializes, while a require at chunk time gets a
        -- detached empty table (the store isn't loaded yet). Migrating THAT
        -- would freeze defaults into the private file, shadowing the
        -- player's real save forever - so only a real read migrates; the
        -- OnLoad re-run of loadSettings does it against the ready store.
        if engine ~= nil and engine.enabled ~= nil then
            saved = deepCopy(engine)
            needsSave = true
        else
            -- Copied even on the parse-time detached read: settings must
            -- never alias the engine table now that scrubEngineBranch
            -- empties it - the scrub would gut the defaults just merged in.
            saved = (engine ~= nil and deepCopy(engine)) or {}
        end
    end
    settings = mergeSettings(saved)
    if needsSave or needsPostResetSave then
        needsPostResetSave = false
        pcall(saveSettings)
    end
    -- Ordinary boots save nothing, so the cleanup runs here too. The
    -- migration copy above happened BEFORE this (deepCopy, never an alias),
    -- so emptying the engine branch cannot touch the live settings.
    pcall(scrubEngineBranch)
    return settings
end

-- Save current settings to the private pair. Backup FIRST: if the process
-- dies mid-write (the crash that motivated all this), dying during the
-- backup write leaves the previous primary intact, and dying during the
-- primary write leaves a fresh backup to heal from on the next boot. Either
-- order keeps one good copy; backup-first just makes the surviving copy the
-- fresher one.
saveSettings = function()
    pcall(function() api.File:Write(BACKUP_PATH, settings) end)
    pcall(function() api.File:Write(SETTINGS_PATH, settings) end)
    pcall(scrubEngineBranch)
    -- api:Emit, not api.Emit. The API declares it as `function ADDON_API:Emit`,
    -- so a dot call passes the event name as self and leaves the event nil -
    -- this never fired, which is why every settings change needed a reload
    -- before it showed up. GetSettings/SaveSettings/On really are dot-declared.
    api:Emit("BETTERBARS_SETTINGS_UPDATED")
end

-- Get full settings table
local function getSettings()
    return settings
end

-- Get colors only (backward compat)
local function getColors()
    if not settings.colors then
        -- Copied, not aliased - see the note in mergeSettings
        settings.colors = {}
        for key, d in pairs(default_settings.colors) do
            settings.colors[key] = { r = d.r, g = d.g, b = d.b, a = d.a }
        end
    end
    return settings.colors
end

-- Update colors from given values
local function updateColors(newColors)
    if not settings.colors then
        settings.colors = {}
    end
    for _, key in ipairs({"hp", "mp", "ehp", "cast"}) do
        if newColors[key] then
            settings.colors[key] = {
                r = newColors[key].r,
                g = newColors[key].g,
                b = newColors[key].b,
                a = newColors[key].a or 1
            }
        end
    end
end

-- Update a single non-color setting
local function updateSetting(key, value)
    settings[key] = value
end

-- Reset all settings to defaults. infoCardSeen is deliberately carried over:
-- it is a "shown once ever" marker, not a preference - resetting used to
-- re-arm the welcome card, which then greeted the player on every reload
-- after a Reset until dismissed again.
local function resetToDefaults()
    local seen = settings.infoCardSeen
    settings = mergeSettings({})
    settings.infoCardSeen = seen or false
    saveSettings()
end

-- Initialize settings. Once the private file exists this parse-time read
-- already returns the player's real save (File:Read works at chunk time; the
-- Addon-root baseDir is set before chunks run). On the one boot where it
-- doesn't exist yet - first run after the 3.2 update, or a fresh install -
-- this read comes up short and the OnLoad re-run migrates from the engine
-- store once it is ready.
loadSettings()

return {
    loadSettings = loadSettings,
    saveSettings = saveSettings,
    getSettings = getSettings,
    getColors = getColors,
    updateColors = updateColors,
    updateSetting = updateSetting,
    resetToDefaults = resetToDefaults
}
