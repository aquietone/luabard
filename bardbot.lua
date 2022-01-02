--[[
    BardBot 1.0 - Automate your bard

    TODO:
    - all sorts of shit

    Available modes:
    - Manual: choose your own targets to engage and let the script do the rest
    - Assist: set a camp at your current location and assist the MA on targets within your camp
    - Chase:  follow somebody around and assist the MA

    Spell Sets:
    - melee:    Use melee adps songs + insult
    - caster:   Use caster adps songs + insult
    - meleedot: Use melee adps songs + insult + dots

    Commands:
    - /brd burnnow:    activate full burns immediately
    - /brd mode 0|1|2: set your mode. 0=manual, 1=assist, 2=chase
    - /brd show|hide:  toggle the UI window
    - /brd resetcamp:  reset camp location to current position

    Other Settings:
    - Assist:         Select the main assist from one of group, raid1, raid2, raid3
    - Assist Percent: Target percent HP to assist the MA.
    - Camp Radius:    Only assist on targets within this radius of you, whether camp is set or chasing.
    - Chase Target:   Name of the PC to chase.
    - Burn Percent:   Target percent HP to engage burns. This applies to burn named and burn on proliferation proc. 0 ignores the percent check.
    - Burn Count:     Start burns if greater than or equal to this number of mobs in camp.
    - Epic:           Always, With Shaman, Burn, Never. When to use epic + fierce eye

    - Burn Always:    Engage burns as they are available.
    - Burn Named:     Engage burns on named mobs.
    - Alliance:       Use alliance if more than 1 necro in group or raid.
    - Switch with MA: Always change to the MAs current target.

    - Fade:           Toggle using Fading Memories to reduce aggro.

    What all bard bot does:
    0. Refreshes selos often when not invis or paused
    1. Keeps you in your camp if assist mode is set
    2. Keeps up with your chase target if chase mode is set
    3. Check for surrounding mobs
    4. AE mez if enabled and >= 3 mobs around
    5. Single mez if enabled and >= 2 mobs around
    6. Assist MA if assist conditions are met (mob in range, at or below assist %, target switching on or not currently engaged)
    7. Send swarm pets
    8. Find the next best song to use
        - alliance
        - insult synergy
        - regular spell set order
    9. Engage burns if burn conditions met
    10. Use mana recovery stuff if low mana/end

    Spell bar ordering can be adjusted by rearranging things in the "check_spell_set" function.

    Other things to note:
    - Drops target if MA targets themself.
    - Does not break invis in any mode.

    Burn Conditions:
    - Burn Always:  Use burns as they are available. Attempt at least some synergy for twincast -- only twincast if spire and hand of death are ready
    - Burn Named:   Burn on anything with Target.Named == true
    - Burn Count:   Burn once X # of mobs are in camp
    - Burn Pct:     Burn anything below a certain % HP

    Settings are stored in config/bardbot_server_charactername.lua

--]]


--- @type mq
local mq = require('mq')
--- @type ImGui
require 'ImGui'

local DEBUG = false
local PAUSED = true -- controls the main combat loop

local BURN_NOW = false -- toggled by /burnnow binding to burn immediately
local BURN_ALWAYS = false -- burn as burns become available
local BURN_PCT = 0 -- delay burn until mob below Pct HP, 0 ignores %.
local BURN_NAMED = false -- enable automatic burn on named mobs
local BURN_COUNT = 5 -- number of mobs to trigger burns

local SPELL_SETS = {'melee','caster','meleedot'}
local SPELL_SET = 'melee'

local MODES = {'manual','assist','chase'}
local MODE = 'manual'
local CHASE_TARGET = ''
local CHASE_DISTANCE = 15
local CAMP = nil
local CAMP_RADIUS = 60

local ASSISTS = {'group','raid1','raid2','raid3'}
local ASSIST = 'group'
local ASSIST_AT = 99
local SWITCH_WITH_MA = true

local EPIC_OPTS = {'always','with shm','burn','never'}
local USE_EPIC = 'always'
local USE_ALLIANCE = true -- enable use of alliance spell
local RALLY_GROUP = false
local USE_FADE = false
local USE_SWARM = true -- not implemented
local BYOS = false

local MIN_MANA = 15
local MIN_END = 15

local AE_MEZ_COUNT = 3
local MEZST = true
local MEZAE = true

local SPELL_SET_LOADED = nil
local I_AM_DEAD = false

local LOG_PREFIX = '\a-t[\ax\ayBardBot\ax\a-t]\ax '
local function printf(...)
    print(LOG_PREFIX..string.format(...))
end
local function debug(...)
    if DEBUG then printf(...) end
end

local function get_spellid_and_rank(spell_name)
    local spell_rank = mq.TLO.Spell(spell_name).RankName()
    return {['id']=mq.TLO.Spell(spell_rank).ID(), ['name']=spell_rank}
end

-- All spells ID + Rank name
local spells = {
    ['aura']=get_spellid_and_rank('Aura of Pli Xin Liako'), -- spell dmg, overhaste, flurry, triple atk
    ['composite']=get_spellid_and_rank('Composite Psalm'), -- DD+melee dmg bonus + small heal
    ['aria']=get_spellid_and_rank('Aria of Pli Xin Liako'), -- spell dmg, overhaste, flurry, triple atk
    ['warmarch']=get_spellid_and_rank('War March of Centien Xi Va Xakra'), -- haste, atk, ds
    ['arcane']=get_spellid_and_rank('Arcane Harmony'), -- spell dmg proc
    ['suffering']=get_spellid_and_rank('Shojralen\'s Song of Suffering'), -- melee dmg proc
    ['spiteful']=get_spellid_and_rank('Von Deek\'s Spiteful Lyric'), -- AC
    ['pulse']=get_spellid_and_rank('Pulse of Nikolas'), -- heal focus + regen
    ['sonata']=get_spellid_and_rank('Xetheg\'s Spry Sonata'), -- spell shield, AC, dmg mitigation
    ['dirge']=get_spellid_and_rank('Dirge of the Restless'), -- spell+melee dmg mitigation
    ['firenukebuff']=get_spellid_and_rank('Constance\'s Aria'), -- inc fire DD
    ['firemagicdotbuff']=get_spellid_and_rank('Fyrthek Fior\'s Psalm of Potency'), -- inc fire+mag dot
    ['crescendo']=get_spellid_and_rank('Zelinstein\'s Lively Crescendo'), -- small heal hp, mana, end
    ['insult']=get_spellid_and_rank('Yelinak\'s Insult'), -- synergy DD
    ['chantflame']=get_spellid_and_rank('Shak Dathor\'s Chant of Flame'),
    ['chantfrost']=get_spellid_and_rank('Sylra Fris\' Chant of Frost'),
    ['chantdisease']=get_spellid_and_rank('Coagulus\' Chant of Disease'),
    ['chantpoison']=get_spellid_and_rank('Cruor\'s Chant of Poison'),
    ['alliance']=get_spellid_and_rank('Coalition of Sticks and Stones'),
    ['mezst']=get_spellid_and_rank('Slumber of the Diabo'),
    ['mezae']=get_spellid_and_rank('Wave of Nocturn'),
}
for name,spell in pairs(spells) do
    printf('%s (%s)', spell['name'], spell['id'])
end

-- entries in the dots table are pairs of {spell id, spell name} in priority order
local melee = {}
table.insert(melee, spells['composite'])
table.insert(melee, spells['crescendo'])
table.insert(melee, spells['aria'])
table.insert(melee, spells['spiteful'])
table.insert(melee, spells['suffering'])
table.insert(melee, spells['warmarch'])
table.insert(melee, spells['pulse'])
table.insert(melee, spells['dirge'])
-- synergy
-- mezst
-- mezae

local caster = {}
table.insert(caster, spells['composite'])
table.insert(caster, spells['crescendo'])
table.insert(caster, spells['aria'])
table.insert(caster, spells['arcane'])
table.insert(caster, spells['firenukebuff'])
table.insert(caster, spells['suffering'])
table.insert(caster, spells['warmarch'])
table.insert(caster, spells['firemagicdotbuff'])
table.insert(caster, spells['pulse'])
table.insert(caster, spells['dirge'])
-- synergy
-- mezst
-- mezae

local meleedot = {}
table.insert(meleedot, spells['composite'])
table.insert(meleedot, spells['crescendo'])
table.insert(meleedot, spells['chantflame'])
table.insert(meleedot, spells['aria'])
table.insert(meleedot, spells['warmarch'])
table.insert(meleedot, spells['chantdisease'])
table.insert(meleedot, spells['suffering'])
table.insert(meleedot, spells['pulse'])
table.insert(meleedot, spells['dirge'])
table.insert(meleedot, spells['chantfrost'])
-- synergy
-- mezst
-- mezae

local songs = {
    ['melee']=melee,
    ['caster']=caster,
    ['meleedot']=meleedot,
}

-- entries in the items table are MQ item datatypes
local items = {}
table.insert(items, mq.TLO.InvSlot('Chest').Item.ID())
table.insert(items, mq.TLO.FindItem('Rage of Rolfron').ID())

local function get_aaid_and_name(aa_name)
    return {['id']=mq.TLO.Me.AltAbility(aa_name).ID(), ['name']=aa_name}
end

-- entries in the AAs table are pairs of {aa name, aa id}
local burnAAs = {}
table.insert(burnAAs, get_aaid_and_name('Quick Time'))
table.insert(burnAAs, get_aaid_and_name('Funeral Dirge'))
table.insert(burnAAs, get_aaid_and_name('Spire of the Minstrels'))
table.insert(burnAAs, get_aaid_and_name('Bladed Song'))
table.insert(burnAAs, get_aaid_and_name('Dance of Blades'))
table.insert(burnAAs, get_aaid_and_name('Flurry of Notes'))
table.insert(burnAAs, get_aaid_and_name('Frenzied Kicks'))

--table.insert(burnAAs, get_aaid_and_name('Glyph of Destruction (115+)'))
--table.insert(burnAAs, get_aaid_and_name('Intensity of the Resolute'))

local mashAAs = {}
table.insert(mashAAs, get_aaid_and_name('Cacophony'))
table.insert(mashAAs, get_aaid_and_name('Boastful Bellow'))
table.insert(mashAAs, get_aaid_and_name('Lyrical Prankster'))
table.insert(mashAAs, get_aaid_and_name('Song of Stone'))
--table.insert(mashAAs, get_aaid_and_name('Vainglorious Shout'))

local selos = get_aaid_and_name('Selo\'s Sonata')
-- Mana Recovery AAs
local rallyingsolo = get_aaid_and_name('Rallying Solo')
local rallyingcall = get_aaid_and_name('Rallying Call')
-- Mana Recovery items
--local item_feather = mq.TLO.FindItem('Unified Phoenix Feather')
--local item_horn = mq.TLO.FindItem('Miniature Horn of Unity') -- 10 minute CD
-- Agro
local fade = get_aaid_and_name('Fading Memories')
-- aa mez
local dirge = get_aaid_and_name('Dirge of the Sleepwalker')

-- BEGIN lua table persistence
local write, writeIndent, writers, refCount;
local persistence =
{
	store = function (path, ...)
		local file, e = io.open(path, "w");
		if not file then
			return error(e);
		end
		local n = select("#", ...);
		-- Count references
		local objRefCount = {}; -- Stores reference that will be exported
		for i = 1, n do
			refCount(objRefCount, (select(i,...)));
		end;
		-- Export Objects with more than one ref and assign name
		-- First, create empty tables for each
		local objRefNames = {};
		local objRefIdx = 0;
		file:write("-- Persistent Data\n");
		file:write("local multiRefObjects = {\n");
		for obj, count in pairs(objRefCount) do
			if count > 1 then
				objRefIdx = objRefIdx + 1;
				objRefNames[obj] = objRefIdx;
				file:write("{};"); -- table objRefIdx
			end;
		end;
		file:write("\n} -- multiRefObjects\n");
		-- Then fill them (this requires all empty multiRefObjects to exist)
		for obj, idx in pairs(objRefNames) do
			for k, v in pairs(obj) do
				file:write("multiRefObjects["..idx.."][");
				write(file, k, 0, objRefNames);
				file:write("] = ");
				write(file, v, 0, objRefNames);
				file:write(";\n");
			end;
		end;
		-- Create the remaining objects
		for i = 1, n do
			file:write("local ".."obj"..i.." = ");
			write(file, (select(i,...)), 0, objRefNames);
			file:write("\n");
		end
		-- Return them
		if n > 0 then
			file:write("return obj1");
			for i = 2, n do
				file:write(" ,obj"..i);
			end;
			file:write("\n");
		else
			file:write("return\n");
		end;
		if type(path) == "string" then
			file:close();
		end;
	end;

	load = function (path)
		local f, e;
		if type(path) == "string" then
			f, e = loadfile(path);
		else
			f, e = path:read('*a')
		end
		if f then
			return f();
		else
			return nil, e;
		end;
	end;
}

-- Private methods

-- write thing (dispatcher)
write = function (file, item, level, objRefNames)
	writers[type(item)](file, item, level, objRefNames);
end;

-- write indent
writeIndent = function (file, level)
	for i = 1, level do
		file:write("\t");
	end;
end;

-- recursively count references
refCount = function (objRefCount, item)
	-- only count reference types (tables)
	if type(item) == "table" then
		-- Increase ref count
		if objRefCount[item] then
			objRefCount[item] = objRefCount[item] + 1;
		else
			objRefCount[item] = 1;
			-- If first encounter, traverse
			for k, v in pairs(item) do
				refCount(objRefCount, k);
				refCount(objRefCount, v);
			end;
		end;
	end;
end;

-- Format items for the purpose of restoring
writers = {
	["nil"] = function (file, item)
			file:write("nil");
		end;
	["number"] = function (file, item)
			file:write(tostring(item));
		end;
	["string"] = function (file, item)
			file:write(string.format("%q", item));
		end;
	["boolean"] = function (file, item)
			if item then
				file:write("true");
			else
				file:write("false");
			end
		end;
	["table"] = function (file, item, level, objRefNames)
			local refIdx = objRefNames[item];
			if refIdx then
				-- Table with multiple references
				file:write("multiRefObjects["..refIdx.."]");
			else
				-- Single use table
				file:write("{\n");
				for k, v in pairs(item) do
					writeIndent(file, level+1);
					file:write("[");
					write(file, k, level+1, objRefNames);
					file:write("] = ");
					write(file, v, level+1, objRefNames);
					file:write(";\n");
				end
				writeIndent(file, level);
				file:write("}");
			end;
		end;
	["function"] = function (file, item)
			-- Does only work for "normal" functions, not those
			-- with upvalues or c functions
			local dInfo = debug.getinfo(item, "uS");
			if dInfo.nups > 0 then
				file:write("nil --[[functions with upvalue not supported]]");
			elseif dInfo.what ~= "Lua" then
				file:write("nil --[[non-lua function not supported]]");
			else
				local r, s = pcall(string.dump,item);
				if r then
					file:write(string.format("loadstring(%q)", s));
				else
					file:write("nil --[[function could not be dumped]]");
				end
			end
		end;
	["thread"] = function (file, item)
			file:write("nil --[[thread]]\n");
		end;
	["userdata"] = function (file, item)
			file:write("nil --[[userdata]]\n");
		end;
}
-- END lua table persistence

local function file_exists(file_name)
    local f = io.open(file_name, "r")
    if f ~= nil then io.close(f) return true else return false end
end

local SETTINGS_FILE = ('%s/bardbot_%s_%s.lua'):format(mq.configDir, mq.TLO.EverQuest.Server(), mq.TLO.Me.CleanName())
local function load_settings()
    if not file_exists(SETTINGS_FILE) then return end
    local settings = assert(loadfile(SETTINGS_FILE))()
    if settings['MODE'] ~= nil then MODE = settings['MODE'] end
    if settings['CHASE_TARGET'] ~= nil then CHASE_TARGET = settings['CHASE_TARGET'] end
    if settings['CHASE_DISTANCE'] ~= nil then CHASE_DISTANCE = settings['CHASE_DISTANCE'] end
    if settings['CAMP_RADIUS'] ~= nil then CAMP_RADIUS = settings['CAMP_RADIUS'] end
    if settings['ASSIST'] ~= nil then ASSIST = settings['ASSIST'] end
    if settings['ASSIST_AT'] ~= nil then ASSIST_AT = settings['ASSIST_AT'] end
    if settings['SPELL_SET'] ~= nil then SPELL_SET = settings['SPELL_SET'] end
    if settings['BURN_ALWAYS'] ~= nil then BURN_ALWAYS = settings['BURN_ALWAYS'] end
    if settings['BURN_PCT'] ~= nil then BURN_PCT = settings['BURN_PCT'] end
    if settings['BURN_NAMED'] ~= nil then BURN_NAMED = settings['BURN_NAMED'] end
    if settings['BURN_COUNT'] ~= nil then BURN_COUNT = settings['BURN_COUNT'] end
    if settings['USE_ALLIANCE'] ~= nil then USE_ALLIANCE = settings['USE_ALLIANCE'] end
    if settings['SWITCH_WITH_MA'] ~= nil then SWITCH_WITH_MA = settings['SWITCH_WITH_MA'] end
    if settings['USE_SWARM'] ~= nil then USE_SWARM = settings['USE_SWARM'] end
    if settings['RALLY_GROUP'] ~= nil then RALLY_GROUP = settings['RALLY_GROUP'] end
    if settings['USE_FADE'] ~= nil then USE_FADE = settings['USE_FADE'] end
    if settings['MEZST'] ~= nil then MEZST = settings['MEZST'] end
    if settings['MEZAE'] ~= nil then MEZAE = settings['MEZAE'] end
    if settings['USE_EPIC'] ~= nil then USE_EPIC = settings['USE_EPIC'] end
    if settings['BYOS'] ~= nil then USE_EPIC = settings['BYOS'] end
end

local function save_settings()
    local settings = {
        MODE=MODE,
        CHASE_TARGET=CHASE_TARGET,
        CHASE_DISTANCE=CHASE_DISTANCE,
        CAMP_RADIUS=CAMP_RADIUS,
        ASSIST=ASSIST,
        ASSIST_AT=ASSIST_AT,
        SPELL_SET=SPELL_SET,
        BURN_ALWAYS=BURN_ALWAYS,
        BURN_PCT=BURN_PCT,
        BURN_NAMED=BURN_NAMED,
        BURN_COUNT=BURN_COUNT,
        USE_ALLIANCE=USE_ALLIANCE,
        SWITCH_WITH_MA=SWITCH_WITH_MA,
        USE_SWARM=USE_SWARM,
        RALLY_GROUP=RALLY_GROUP,
        USE_FADE=USE_FADE,
        MEZST=MEZST,
        MEZAE=MEZAE,
        USE_EPIC=USE_EPIC,
        BYOS=BYOS,
    }
    persistence.store(SETTINGS_FILE, settings)
end

local function current_time()
    return os.time(os.date("!*t"))
end

local function timer_expired(t, expiration)
    if os.difftime(current_time(), t) > expiration then
        return true
    else
        return false
    end
end

local function time_remaining(t, less_than)
    return not timer_expired(t, less_than)
end

local function table_size(t)
    local count = 0
    for k,v in pairs(t) do
        count = count + 1
    end
    return count
end

-- Check that we are not currently casting anything
local function can_cast_weave()
    return not mq.TLO.Me.Casting()
end

-- Check whether a dot is applied to the target
local function is_target_dotted_with(spell_id, spell_name)
    if not mq.TLO.Target.MyBuff(spell_name)() then return false end
    return spell_id == mq.TLO.Target.MyBuff(spell_name).ID()
end

local function is_fighting() 
    --if mq.TLO.Target.CleanName() == 'Combat Dummy Beza' then return true end -- Dev hook for target dummy
    return (mq.TLO.Target.ID() ~= nil and (mq.TLO.Me.CombatState() ~= "ACTIVE" and mq.TLO.Me.CombatState() ~= "RESTING") and mq.TLO.Me.Standing() and not mq.TLO.Me.Feigning() and mq.TLO.Target.Type() == "NPC" and mq.TLO.Target.Type() ~= "Corpse")
end

local function check_distance(x1, y1, x2, y2)
    return math.sqrt((x2 - x1) ^ 2 + (y2 - y1) ^ 2)
end

local function am_i_dead()
    if I_AM_DEAD and (mq.TLO.Me.Buff('Resurrection Sickness').ID() or mq.TLO.SpawnCount('pccorpse '..mq.TLO.Me.CleanName())() == 0) then
        I_AM_DEAD = false
    end
    return I_AM_DEAD
end

local function check_chase()
    if MODE ~= 'chase' then return end
    if am_i_dead() or mq.TLO.Stick.Active() then return end
    local chase_spawn = mq.TLO.Spawn('pc ='..CHASE_TARGET)
    local me_x = mq.TLO.Me.X()
    local me_y = mq.TLO.Me.Y()
    local chase_x = chase_spawn.X()
    local chase_y = chase_spawn.Y()
    if not chase_x or not chase_y then return end
    if check_distance(me_x, me_y, chase_x, chase_y) > CHASE_DISTANCE then
        if not mq.TLO.Nav.Active() then
            mq.cmdf('/nav spawn pc =%s | log=off', CHASE_TARGET)
        end
    end
end

local function check_camp()
    if MODE ~= 'assist' then return end
    if am_i_dead() then return end
    if is_fighting() or not CAMP then return end
    if mq.TLO.Zone.ID() ~= CAMP.ZoneID then
        printf('Clearing camp due to zoning.')
        CAMP = nil
        return
    end
    if check_distance(mq.TLO.Me.X(), mq.TLO.Me.Y(), CAMP.X, CAMP.Y) > 15 then
        if not mq.TLO.Nav.Active() then
            mq.cmdf('/nav locyxz %d %d %d log=off', CAMP.Y, CAMP.X, CAMP.Z)
        end
    end
end

local function set_camp(reset)
    if (MODE == 'assist' and not CAMP) or reset then
        CAMP = {
            ['X']=mq.TLO.Me.X(),
            ['Y']=mq.TLO.Me.Y(),
            ['Z']=mq.TLO.Me.Z(),
            ['ZoneID']=mq.TLO.Zone.ID()
        }
        mq.cmdf('/mapf campradius %d', CAMP_RADIUS)
    elseif MODE ~= 'assist' and CAMP then
        CAMP = nil
        mq.cmd('/mapf campradius 0')
    end
end

local ASSIST_TARGET_ID = 0
local TARGETS = {}
local MOB_COUNT = 0

local xtar_corpse_count = 'xtarhater npccorpse radius %d zradius 50'
local xtar_count = 'xtarhater radius %d zradius 50'
local xtar_spawn = '%d, xtarhater radius %d zradius 50'
local function mob_radar()
    local num_corpses = 0
    num_corpses = mq.TLO.SpawnCount(xtar_corpse_count:format(CAMP_RADIUS))()
    MOB_COUNT = mq.TLO.SpawnCount(xtar_count:format(CAMP_RADIUS))() - num_corpses
    if MOB_COUNT > 0 then
        for i=1,MOB_COUNT do
            if i > 13 then break end
            local mob = mq.TLO.NearestSpawn(xtar_spawn:format(i, CAMP_RADIUS))
            local mob_id = mob.ID()
            if mob_id > 0 then
                if not mob() or mob.Type() == 'Corpse' then
                    TARGETS[mob_id] = nil
                    num_corpses = num_corpses+1
                elseif not TARGETS[mob_id] then
                    debug('Adding mob_id %d', mob_id)
                    TARGETS[mob_id] = {meztimer=0}
                end
            end
        end
        MOB_COUNT = MOB_COUNT - num_corpses
    end
end

local function clean_targets()
    for mobid,_ in pairs(TARGETS) do
        local spawn = mq.TLO.Spawn(string.format('id %s', mobid))
        if not spawn() or spawn.Type() == 'Corpse' then
            TARGETS[mobid] = nil
        --else
        --    printf('Resetting meztimer for mob_id %d', mobid)
        --    TARGETS[mobid].meztimer = 0
        end
    end
end

local function get_assist_spawn()
    local assist_target = nil
    if ASSIST == 'group' then
        assist_target = mq.TLO.Me.GroupAssistTarget
    elseif ASSIST == 'raid1' then
        assist_target = mq.TLO.Me.RaidAssistTarget(1)
    elseif ASSIST == 'raid2' then
        assist_target = mq.TLO.Me.RaidAssistTarget(2)
    elseif ASSIST == 'raid3' then
        assist_target = mq.TLO.Me.RaidAssistTarget(3)
    end
    return assist_target
end

local function should_assist(assist_target)
    if not assist_target then assist_target = get_assist_spawn() end
    if not assist_target then return false end
    local id = assist_target.ID()
    local hp = assist_target.PctHPs()
    local mob_type = assist_target.Type()
    local mob_x = assist_target.X()
    local mob_y = assist_target.Y()
    if not id or id == 0 or not hp or hp == 0 or not mob_x or not mob_y then return false end
    if mob_type == 'NPC' and hp < ASSIST_AT then
        if CAMP and check_distance(CAMP.X, CAMP.Y, mob_x, mob_y) <= CAMP_RADIUS then
            return true
        elseif not CAMP and check_distance(mq.TLO.Me.X(), mq.TLO.Me.Y(), mob_x, mob_y) <= CAMP_RADIUS then
            return true
        end
    else
        return false
    end
end

local send_pet_timer = 0
local boastful_timer = 0
local synergy_timer = 0
local stick_timer = 0
local function check_target()
    if am_i_dead() then return end
    if MODE ~= 'manual' or SWITCH_WITH_MA then
        if not mq.TLO.Group.MainAssist() then return end
        local assist_target = get_assist_spawn()
        if not assist_target() then return end
        if mq.TLO.Target() and mq.TLO.Target.Type() == 'NPC' and assist_target.ID() == mq.TLO.Group.MainAssist.ID() then
            mq.cmd('/target clear')
            mq.cmd('/pet back')
            return
        end
        if is_fighting() then
            if mq.TLO.Target.ID() == assist_target.ID() then
                ASSIST_TARGET_ID = assist_target.ID()
                return
            elseif not SWITCH_WITH_MA then return end
        end
        if ASSIST_TARGET_ID == assist_target.ID() then
            assist_target.DoTarget()
            return
        end
        if mq.TLO.Target.ID() ~= assist_target.ID() and should_assist(assist_target) then
            ASSIST_TARGET_ID = assist_target.ID()
            assist_target.DoTarget()
            if mq.TLO.Me.Sitting() then mq.cmd('/stand') end
            boastful_timer = 0
            synergy_timer = 0
            send_pet_timer = 0
            stick_timer = 0
            printf('Assisting on >>> \ay%s\ax <<<', mq.TLO.Target.CleanName())
        end
    end
end

local function get_combat_position()
    local target_id = mq.TLO.Target.ID()
    local target_distance = mq.TLO.Target.Distance3D()
    if not target_id or target_id == 0 or (target_distance and target_distance > CAMP_RADIUS) or PAUSED then
        return
    end
    mq.cmdf('/nav id %d log=off', target_id)
    local begin_time = current_time()
    while true do
        if mq.TLO.Target.LineOfSight() then
            mq.cmd('/squelch /nav stop')
            break
        end
        if os.difftime(begin_time, current_time()) > 5 then
            break
        end
        mq.delay(1)
    end
    if mq.TLO.Navigation.Active() then mq.cmd('/squelch /nav stop') end
end

local function attack()
    if ASSIST_TARGET_ID == 0 or mq.TLO.Target.ID() ~= ASSIST_TARGET_ID or not should_assist() then
        mq.cmd('/attack off')
        return
    end
    if not mq.TLO.Target.LineOfSight() then get_combat_position() end
    if mq.TLO.Navigation.Active() then
        mq.cmd('/squelch /nav stop')
    end
    if not mq.TLO.Stick.Active() and timer_expired(stick_timer, 3) then
        mq.cmd('/squelch /stick loose moveback 50% uw')
        stick_timer = current_time()
    end
    if not mq.TLO.Me.Combat() then
        mq.cmd('/attack on')
    end
end

local function in_control()
    return not mq.TLO.Me.Stunned() and not mq.TLO.Me.Silenced() and not mq.TLO.Me.Mezzed() and not mq.TLO.Me.Invulnerable() and not mq.TLO.Me.Hovering()
end

local crescendo_timer = 0
local function cast(spell_name, requires_target, requires_los)
    if not in_control() or (requires_los and not mq.TLO.Target.LineOfSight()) then return end
    if requires_target and mq.TLO.Target.ID() ~= ASSIST_TARGET_ID then return end
    printf('Casting \ar%s\ax', spell_name)
    mq.cmdf('/cast "%s"', spell_name)
    mq.delay(10)
    if not mq.TLO.Me.Casting() then mq.cmdf('/cast %s', spell_name) end
    mq.delay(10)
    if not mq.TLO.Me.Casting() then mq.cmdf('/cast %s', spell_name) end
    mq.delay(10)
    --mq.delay(200+mq.TLO.Spell(spell_name).MyCastTime(), function() return not mq.TLO.Me.Casting() end)
    mq.delay(3200, function() return not mq.TLO.Me.Casting() end)
    mq.cmd('/stopcast')
    if spell_name == spells['crescendo']['name'] then crescendo_timer = current_time() end
end

local function cast_mez(spell_name)
    if not in_control() or not mq.TLO.Target.LineOfSight() then return end
    local mez_target_id = mq.TLO.Target.ID()
    printf('Casting \ar%s\ax', spell_name)
    mq.cmdf('/cast "%s"', spell_name)
    mq.delay(10)
    if not mq.TLO.Me.Casting() then mq.cmdf('/cast %s', spell_name) end
    mq.delay(10)
    if not mq.TLO.Me.Casting() then mq.cmdf('/cast %s', spell_name) end
    mq.delay(10)
    check_target()
    if mq.TLO.Target.ID() ~= mez_target_id then
        mq.delay('1s')
        attack()
    end
    --mq.delay(200+mq.TLO.Spell(spell_name).MyCastTime(), function() return not mq.TLO.Me.Casting() end)
    mq.delay(3200, function() return not mq.TLO.Me.Casting() end)
    mq.cmd('/stopcast')
end

local MEZ_IMMUNES = {}
local MEZ_TARGET_NAME = nil
local MEZ_TARGET_ID = 0
local function check_mez()
    if MOB_COUNT >= AE_MEZ_COUNT and MEZAE then
        if mq.TLO.Me.Gem(spells['mezae']['name'])() and mq.TLO.Me.GemTimer(spells['mezae']['name'])() == 0 then
            printf('AE Mezzing (MOB_COUNT=%d)', MOB_COUNT)
            cast(spells['mezae']['name'])
            mob_radar()
            for id,_ in pairs(TARGETS) do
                local mob = mq.TLO.Spawn('id '..id)
                if mob() and not MEZ_IMMUNES[mob.CleanName()] then
                    mob.DoTarget()
                    mq.delay(50) -- allow time for target to actually change before checking buffs populated on new target
                    mq.delay('1s', function() return mq.TLO.Target.BuffsPopulated() end)
                    if mq.TLO.Target() and mq.TLO.Target.Buff(spells['mezae']['name'])() then
                        debug('AEMEZ setting meztimer mob_id %d', id)
                        TARGETS[id].meztimer = current_time()
                    end
                end
            end
        end
    end
    if not MEZST or MOB_COUNT <= 1 or not mq.TLO.Me.Gem(spells['mezst']['name'])() then return end
    for id,mobdata in pairs(TARGETS) do
        if id ~= ASSIST_TARGET_ID and (mobdata['meztimer'] == 0 or timer_expired(mobdata['meztimer'], 30)) then
            debug('[%s] meztimer: %s timer_expired: %s', id, mobdata['meztimer'], timer_expired(mobdata['meztimer'], 30))
            local mob = mq.TLO.Spawn('id '..id)
            if mob() and not MEZ_IMMUNES[mob.CleanName()] then
                if id ~= ASSIST_TARGET_ID and mob.Level() <= 123 and mob.Type() == 'NPC' then
                    mq.cmd('/attack off')
                    mq.delay(100)
                    mob.DoTarget()
                    mq.delay(50) -- allow time for target to actually change before checking buffs populated on new target
                    mq.delay('1s', function() return mq.TLO.Target.BuffsPopulated() end)
                    local pct_hp = mq.TLO.Target.PctHPs()
                    if mq.TLO.Target() and mq.TLO.Target.Type() == 'Corpse' then
                        TARGETS[id] = nil
                    elseif pct_hp and pct_hp > 85 then
                        local assist_spawn = get_assist_spawn()
                        if assist_spawn.ID() ~= id then
                            MEZ_TARGET_NAME = mob.CleanName()
                            MEZ_TARGET_ID = id
                            printf('Mezzing >>> %s (%d) <<<', mob.Name(), mob.ID())
                            cast_mez(spells['mezst']['name'])
                            debug('STMEZ setting meztimer mob_id %d', id)
                            TARGETS[id].meztimer = current_time()
                            mq.doevents('event_mezimmune')
                            mq.doevents('event_mezresist')
                            MEZ_TARGET_ID = 0
                            MEZ_TARGET_NAME = nil
                        end
                    end
                elseif mob.Type() == 'Corpse' then
                    TARGETS[id] = nil
                end
            end
        end
    end
    check_target()
    attack()
end

local function check_mez_old()
    if MOB_COUNT >= AE_MEZ_COUNT and MEZAE then
        if mq.TLO.Me.Gem(spells['mezae']['name'])() and mq.TLO.Me.GemTimer(spells['mezae']['name'])() == 0 then
            printf('AE Mezzing (MOB_COUNT=%d)', MOB_COUNT)
            cast(spells['mezae']['name'])
        end
    end
    if not MEZST or MOB_COUNT <= 1 then return end
    mq.cmd('/attack off')
    for id,_ in pairs(TARGETS) do
        local mob = mq.TLO.Spawn('id '..id)
        if mob() then
            if id ~= ASSIST_TARGET_ID and mob.Level() <= 123 and mob.Type() == 'NPC' then
                mob.DoTarget()
                if mq.TLO.Target() and mq.TLO.Target.Type() == 'Corpse' then
                    TARGETS[id] = nil
                elseif not mq.TLO.Target.Mezzed() then
                    local assist_spawn = get_assist_spawn()
                    if assist_spawn.ID() ~= id then
                        printf('Mezzing >>> %s (%d) <<<', mob.Name(), mob.ID())
                        mq.delay(5)
                        cast(spells['mezst']['name'], true, true)
                    end 
                end
            elseif mob.Type() == 'Corpse' then
                TARGETS[id] = nil
            end
        end
    end
    mq.cmd('/squelch /target clear')
    if ASSIST_TARGET_ID > 0 then
        mq.cmdf('/mqtarget id %d', ASSIST_TARGET_ID)
    end
end

-- Casts alliance if we are fighting, alliance is enabled, the spell is ready, alliance isn't already on the mob, there is > 1 necro in group or raid, and we have at least a few dots on the mob.
local function try_alliance()
    if USE_ALLIANCE then
        if mq.TLO.Spell(spells['alliance']['name']).Mana() > mq.TLO.Me.CurrentMana() then
            return false
        end
        if mq.TLO.Me.Gem(spells['alliance']['name'])() and mq.TLO.Me.GemTimer(spells['alliance']['name'])() == 0  and not mq.TLO.Target.Buff(spells['alliance']['name'])() and mq.TLO.Spell(spells['alliance']['name']).StacksTarget() then
            cast(spells['alliance']['name'], true, true)
            return true
        end
    end
    return false
end

local function cast_synergy()
    if timer_expired(synergy_timer, 18) then
        if not mq.TLO.Me.Song('Troubadour\'s Synergy')() and mq.TLO.Me.Gem(spells['insult']['name'])() and mq.TLO.Me.GemTimer(spells['insult']['name'])() == 0 then
            if mq.TLO.Spell(spells['insult']['name']).Mana() > mq.TLO.Me.CurrentMana() then
                return false
            end
            cast(spells['insult']['name'], true, true)
            synergy_timer = current_time()
            return true
        end
    end
    return false
end

local function is_dot_ready(spellId, spellName)
    local songDuration = 0
    --local remainingCastTime = 0
    if not mq.TLO.Me.Gem(spellName)() or not mq.TLO.Me.GemTimer(spellName)() == 0  then
        return false
    end
    if not mq.TLO.Target() or mq.TLO.Target.ID() ~= ASSIST_TARGET_ID or mq.TLO.Target.Type() == 'Corpse' then return false end

    songDuration = mq.TLO.Target.MyBuffDuration(spellName)()
    if not is_target_dotted_with(spellId, spellName) then
        -- target does not have the dot, we are ready
        debug('song ready %s', spellName)
        return true
    else
        if not songDuration then
            debug('song ready %s', spellName)
            return true
        end
    end

    return false
end

local function is_song_ready(spellId, spellName)
    local songDuration = 0
    local remainingCastTime = 0
    if mq.TLO.Spell(spellName).Mana() > mq.TLO.Me.CurrentMana() or (mq.TLO.Spell(spellName).Mana() > 1000 and mq.TLO.Me.PctMana() < MIN_MANA) then
        return false
    end
    if mq.TLO.Spell(spellName).EnduranceCost() > mq.TLO.Me.CurrentEndurance() or (mq.TLO.Spell(spellName).EnduranceCost() > 1000 and mq.TLO.Me.PctEndurance() < MIN_END) then
        return false
    end
    if mq.TLO.Spell(spellName).TargetType() == 'Single' then
        return is_dot_ready(spellId, spellName)
    end

    if not mq.TLO.Me.Gem(spellName)() or mq.TLO.Me.GemTimer(spellName)() > 0 then
        return false
    end
    if spellName == spells['crescendo']['name'] and (mq.TLO.Me.Buff(spells['crescendo']['name'])() or not timer_expired(crescendo_timer, 50)) then
        -- buggy song that doesn't like to go on CD
        return false
    end

    songDuration = mq.TLO.Me.Song(spellName).Duration()
    if not songDuration then
        debug('song ready %s', spellName)
        return true
    else
        cast_time = mq.TLO.Spell(spellName).MyCastTime()
        if songDuration < cast_time + 3000 then
            debug('song ready %s', spellName)
        end
        return songDuration < cast_time + 3000
    end
end

local function find_next_song()
    if try_alliance() then return nil end
    if cast_synergy() then return nil end
    for _,song in ipairs(songs[SPELL_SET]) do -- iterates over the dots array. ipairs(dots) returns 2 values, an index and its value in the array. we don't care about the index, we just want the dot
        local spell_id = song['id']
        local spell_name = song['name']
        if is_song_ready(spell_id, spell_name) then
            if spell_name ~= 'Composite Psalm' or mq.TLO.Target() then
                return song
            end
        end
    end
    return nil -- we found no missing dot that was ready to cast, so return nothing
end

local function cycle_songs()
    --if is_fighting() or should_assist() then
    if not mq.TLO.Me.Invis() then
        local spell = find_next_song() -- find the first available dot to cast that is missing from the target
        if spell then -- if a dot was found
            if mq.TLO.Spell(spell['name']).TargetType() == 'Single' then
                cast(spell['name'], true, true) -- then cast the dot
            else
                cast(spell['name']) -- then cast the dot
            end
            return true
        end
    end
    return false
end

local function send_pet()
    if timer_expired(send_pet_timer, 5) and (is_fighting() or should_assist()) then
        mq.cmd('/multiline ; /pet swarm ;')
        send_pet_timer = current_time()
    end
end

local function use_item(item)
    if item.Timer() == '0' then
        if item.Clicky.Spell.TargetType() == 'Single' and not mq.TLO.Target() then return end
        if can_cast_weave() then
            printf('use_item: \ax\ar%s\ax', item)
            mq.cmdf('/useitem "%s"', item)
        end
        mq.delay(300+item.CastTime()) -- wait for cast time + some buffer so we don't skip over stuff
        -- alternatively maybe while loop until we see the buff or song is applied
    end
end

local function use_aa(aa, number)
    if mq.TLO.Me.AltAbility(aa).Spell.EnduranceCost() > 0 and mq.TLO.Me.PctEndurance() < MIN_END then return end
    if mq.TLO.Me.AltAbility(aa).Spell.TargetType() == 'Single' then
        if mq.TLO.Target() and not mq.TLO.Target.MyBuff(aa)() and mq.TLO.Me.AltAbilityReady(aa)() and can_cast_weave() and mq.TLO.Me.AltAbility(aa).Spell.EnduranceCost() < mq.TLO.Me.CurrentEndurance() then
            if aa['name'] == 'Boastful Bellow' then
                if time_remaining(boastful_timer, 30) then
                    return
                else
                    boastful_timer = current_time()
                end
            end
            printf('use_aa: \ax\ar%s\ax', aa)
            mq.cmdf('/alt activate %d', number)
            mq.delay(50+mq.TLO.Me.AltAbility(aa).Spell.CastTime()) -- wait for cast time + some buffer so we don't skip over stuff
        end
    elseif not mq.TLO.Me.Song(aa)() and not mq.TLO.Me.Buff(aa)() and mq.TLO.Me.AltAbilityReady(aa)() and can_cast_weave() then
        printf('use_aa: \ax\ar%s\ax', aa)
        mq.cmdf('/alt activate %d', number)
        -- alternatively maybe while loop until we see the buff or song is applied, but not all apply a buff or song, like pet stuff
        mq.delay(50+mq.TLO.Me.AltAbility(aa).Spell.CastTime()) -- wait for cast time + some buffer so we don't skip over stuff
    end
end

local fierceeye = get_aaid_and_name('Fierce Eye')
local function use_epic()
    local epic = mq.TLO.FindItem('=Blade of Vesagran')
    local fierceeye_rdy = mq.TLO.Me.AltAbilityReady(fierceeye['name'])()
    if epic.Timer() == '0' and fierceeye_rdy then
        use_aa(fierceeye['name'], fierceeye['id'])
        use_item(epic)
    end
end

local function mash()
    if is_fighting() or should_assist() then
        if USE_EPIC == 'always' then
            use_epic()
        elseif USE_EPIC == 'with shm' and mq.TLO.Me.Song('Prophet\'s Gift of the Ruchu')() then
            use_epic()
        end
        for _,aa in ipairs(mashAAs) do
            use_aa(aa['name'], aa['id'])
        end
    end
end

local burn_active_timer = 0
local burn_active = false
local function is_burn_condition_met()
    -- activating a burn condition is good for 60 seconds, don't do check again if 60 seconds hasn't passed yet and burn is active.
    if time_remaining(burn_active_timer, 30) and burn_active then
        return true
    else
        burn_active = false
    end
    if BURN_NOW then
        printf('\arActivating Burns (on demand)\ax')
        burn_active_timer = current_time()
        burn_active = true
        BURN_NOW = false
        return true
    elseif is_fighting() then
        if BURN_ALWAYS then
            -- With burn always, save twincast for when hand of death is ready, otherwise let other burns fire
            if mq.TLO.Me.AltAbilityReady('Heretic\'s Twincast')() and not mq.TLO.Me.AltAbilityReady('Hand of Death')() then
                return false
            elseif not mq.TLO.Me.AltAbilityReady('Heretic\'s Twincast')() and mq.TLO.Me.AltAbilityReady('Hand of Death')() then
                return false
            else
                return true
            end
        elseif BURN_NAMED and mq.TLO.Target.Named() then
            printf('\arActivating Burns (named)\ax')
            burn_active_timer = current_time()
            burn_active = true
            return true
        elseif mq.TLO.SpawnCount(string.format('xtarhater radius %d zradius 50', CAMP_RADIUS))() >= BURN_COUNT then
            printf('\arActivating Burns (mob count > %d)\ax', BURN_COUNT)
            burn_active_timer = current_time()
            burn_active = true
            return true
        elseif BURN_PCT ~= 0 and mq.TLO.Target.PctHPs() < BURN_PCT then
            printf('\arActivating Burns (percent HP)\ax')
            burn_active_timer = current_time()
            burn_active = true
            return true
        end
    end
    burn_active_timer = 0
    burn_active = false
    return false
end

local function try_burn()
    -- Some items use Timer() and some use IsItemReady(), this seems to be mixed bag.
    -- Test them both for each item, and see which one(s) actually work.
    if is_burn_condition_met() then

        if USE_EPIC == 'burn' then
            use_epic()
        end

        --[[
        |===========================================================================================
        |Item Burn
        |===========================================================================================
        ]]--

        for _,item_id in ipairs(items) do
            local item = mq.TLO.FindItem(item_id)
            use_item(item)
        end

        --[[
        |===========================================================================================
        |Spell Burn
        |===========================================================================================
        ]]--

        for _,aa in ipairs(burnAAs) do
            use_aa(aa['name'], aa['id'])
        end
    end
end

local function check_mana()
    -- modrods
    local pct_mana = mq.TLO.Me.PctMana()
    local pct_end = mq.TLO.Me.PctEndurance()
    if pct_mana < 75 then
        -- Find ModRods in check_mana since they poof when out of charges, can't just find once at startup.
        local item_aa_modrod = mq.TLO.FindItem('Summoned: Dazzling Modulation Shard') or mq.TLO.FindItem('Summoned: Radiant Modulation Shard')
        use_item(item_aa_modrod)
        local item_wand_modrod = mq.TLO.FindItem('Wand of Restless Modulation')
        use_item(item_wand_modrod)
        local item_wand_old = mq.TLO.FindItem('Wand of Phantasmal Transvergence')
        use_item(item_wand_old)
    end
    if not is_fighting() and (pct_mana < 20 or pct_end < 20) then
        -- death bloom at some %
        use_aa(rallyingsolo['name'], rallyingsolo['id'])
    end
    -- unified phoenix feather
end

local check_aggro_timer = 0
local function check_aggro()
    if USE_FADE and is_fighting() and mq.TLO.Target() then
        if mq.TLO.Me.TargetOfTarget.ID() == mq.TLO.Me.ID() or timer_expired(check_aggro_timer, 10) then
            if mq.TLO.Me.PctAggro() >= 70 then
                use_aa(fade['name'], fade['id'])
                check_aggro_timer = current_time()
                mq.delay('1s')
                mq.cmd('/makemevis')
            end
        end
    end
end

local function swap_gem_ready(spell_name, gem)
    return mq.TLO.Me.Gem(gem)() and mq.TLO.Me.Gem(gem).Name() == spell_name
end

local function swap_spell(spell_name, gem)
    if not gem or am_i_dead() then return end
    mq.cmdf('/memspell %d "%s"', gem, spell_name)
    mq.delay('3s', swap_gem_ready(spell_name, gem))
    mq.TLO.Window('SpellBookWnd').DoClose()
end

local function check_buffs()
    if am_i_dead() then return end
    if is_fighting() then return end
    if mq.TLO.SpawnCount(string.format('xtarhater radius %d zradius 50', CAMP_RADIUS))() > 0 then return end
    if not mq.TLO.Me.Aura(spells['aura']['name'])() then
        local restore_gem = nil
        if not mq.TLO.Me.Gem(spells['aura']['name'])() then
            restore_gem = mq.TLO.Me.Gem(1)()
            swap_spell(spells['aura']['name'], 1)
        end
        mq.delay('3s', function() return mq.TLO.Me.Gem(spells['aura']['name'])() and mq.TLO.Me.GemTimer(spells['aura']['name'])() == 0  end)
        cast(spells['aura']['name'])
        if restore_gem then
            swap_spell(restore_gem, 1)
        end
    end
end

local function rest()
    if not is_fighting() and not mq.TLO.Me.Sitting() and not mq.TLO.Me.Moving() and (mq.TLO.Me.PctMana() < 60 or mq.TLO.Me.PctEndurance() < 60) and not mq.TLO.Me.Casting() and mq.TLO.SpawnCount(string.format('xtarhater radius %d zradius 50', CAMP_RADIUS))() == 0 then
        mq.cmd('/sit')
    end
end

local function pause_for_rally()
    if mq.TLO.Me.Song(rallyingsolo['name'])() or mq.TLO.Me.Buff(rallyingsolo['name'])() then
        if MOB_COUNT >= 3 then
            return true
        elseif mq.TLO.Target() and mq.TLO.Target.Named() then
            return true
        else
            return false
        end
    else
        return false
    end
end

local check_spell_timer = 0
local function check_spell_set()
    if is_fighting() or mq.TLO.Me.Moving() or am_i_dead() or BYOS then return end
    if SPELL_SET_LOADED ~= SPELL_SET or timer_expired(check_spell_timer, 30) then
        if SPELL_SET == 'melee' then
            if mq.TLO.Me.Gem(1)() ~= spells['aria']['name'] then swap_spell(spells['aria']['name'], 1) end
            if mq.TLO.Me.Gem(2)() ~= spells['arcane']['name'] then swap_spell(spells['arcane']['name'], 2) end
            if mq.TLO.Me.Gem(3)() ~= spells['spiteful']['name'] then swap_spell(spells['spiteful']['name'], 3) end
            if mq.TLO.Me.Gem(4)() ~= spells['suffering']['name'] then swap_spell(spells['suffering']['name'], 4) end
            if mq.TLO.Me.Gem(5)() ~= spells['insult']['name'] then swap_spell(spells['insult']['name'], 5) end
            if mq.TLO.Me.Gem(6)() ~= spells['warmarch']['name'] then swap_spell(spells['warmarch']['name'], 6) end
            if mq.TLO.Me.Gem(7)() ~= spells['sonata']['name'] then swap_spell(spells['sonata']['name'], 7) end
            if mq.TLO.Me.Gem(8)() ~= spells['mezst']['name'] then swap_spell(spells['mezst']['name'], 8) end
            if mq.TLO.Me.Gem(9)() ~= spells['mezae']['name'] then swap_spell(spells['mezae']['name'], 9) end
            if mq.TLO.Me.Gem(10)() ~= spells['crescendo']['name'] then swap_spell(spells['crescendo']['name'], 10) end
            if mq.TLO.Me.Gem(11)() ~= spells['pulse']['name'] then swap_spell(spells['pulse']['name'], 11) end
            if mq.TLO.Me.Gem(12)() ~= 'Composite Psalm' then swap_spell(spells['composite']['name'], 12) end
            if mq.TLO.Me.Gem(13)() ~= spells['dirge']['name'] then swap_spell(spells['dirge']['name'], 13) end
            SPELL_SET_LOADED = SPELL_SET
        elseif SPELL_SET == 'caster' then
            if mq.TLO.Me.Gem(1)() ~= spells['aria']['name'] then swap_spell(spells['aria']['name'], 1) end
            if mq.TLO.Me.Gem(2)() ~= spells['arcane']['name'] then swap_spell(spells['arcane']['name'], 2) end
            if mq.TLO.Me.Gem(3)() ~= spells['firenukebuff']['name'] then swap_spell(spells['firenukebuff']['name'], 3) end
            if mq.TLO.Me.Gem(4)() ~= spells['suffering']['name'] then swap_spell(spells['suffering']['name'], 4) end
            if mq.TLO.Me.Gem(5)() ~= spells['insult']['name'] then swap_spell(spells['insult']['name'], 5) end
            if mq.TLO.Me.Gem(6)() ~= spells['warmarch']['name'] then swap_spell(spells['warmarch']['name'], 6) end
            if mq.TLO.Me.Gem(7)() ~= spells['firemagicdotbuff']['name'] then swap_spell(spells['firemagicdotbuff']['name'], 7) end
            if mq.TLO.Me.Gem(8)() ~= spells['mezst']['name'] then swap_spell(spells['mezst']['name'], 8) end
            if mq.TLO.Me.Gem(9)() ~= spells['mezae']['name'] then swap_spell(spells['mezae']['name'], 9) end
            if mq.TLO.Me.Gem(10)() ~= spells['crescendo']['name'] then swap_spell(spells['crescendo']['name'], 10) end
            if mq.TLO.Me.Gem(11)() ~= spells['pulse']['name'] then swap_spell(spells['pulse']['name'], 11) end
            if mq.TLO.Me.Gem(12)() ~= 'Composite Psalm' then swap_spell(spells['composite']['name'], 12) end
            if mq.TLO.Me.Gem(13)() ~= spells['dirge']['name'] then swap_spell(spells['dirge']['name'], 13) end
            SPELL_SET_LOADED = SPELL_SET
        elseif SPELL_SET == 'meleedot' then
            if mq.TLO.Me.Gem(1)() ~= spells['aria']['name'] then swap_spell(spells['aria']['name'], 1) end
            if mq.TLO.Me.Gem(2)() ~= spells['chantflame']['name'] then swap_spell(spells['chantflame']['name'], 2) end
            if mq.TLO.Me.Gem(3)() ~= spells['chantfrost']['name'] then swap_spell(spells['chantfrost']['name'], 3) end
            if mq.TLO.Me.Gem(4)() ~= spells['suffering']['name'] then swap_spell(spells['suffering']['name'], 4) end
            if mq.TLO.Me.Gem(5)() ~= spells['insult']['name'] then swap_spell(spells['insult']['name'], 5) end
            if mq.TLO.Me.Gem(6)() ~= spells['warmarch']['name'] then swap_spell(spells['warmarch']['name'], 6) end
            if mq.TLO.Me.Gem(7)() ~= spells['chantdisease']['name'] then swap_spell(spells['chantdisease']['name'], 7) end
            if mq.TLO.Me.Gem(8)() ~= spells['mezst']['name'] then swap_spell(spells['mezst']['name'], 8) end
            if mq.TLO.Me.Gem(9)() ~= spells['mezae']['name'] then swap_spell(spells['mezae']['name'], 9) end
            if mq.TLO.Me.Gem(10)() ~= spells['crescendo']['name'] then swap_spell(spells['crescendo']['name'], 10) end
            if mq.TLO.Me.Gem(11)() ~= spells['pulse']['name'] then swap_spell(spells['pulse']['name'], 11) end
            if mq.TLO.Me.Gem(12)() ~= 'Composite Psalm' then swap_spell(spells['composite']['name'], 12) end
            if mq.TLO.Me.Gem(13)() ~= spells['dirge']['name'] then swap_spell(spells['dirge']['name'], 13) end
            SPELL_SET_LOADED = SPELL_SET
        end
        check_spell_timer = current_time()
    end
end

-- BEGIN UI IMPLEMENTATION

-- GUI Control variables
local open_gui = true
local should_draw_gui = true

local base_left_pane_size = 190
local left_pane_size = 190

local function draw_splitter(thickness, size0, min_size0)
    local x,y = ImGui.GetCursorPos()
    local delta = 0
    ImGui.SetCursorPosX(x + size0)

    ImGui.PushStyleColor(ImGuiCol.Button, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonActive, 0, 0, 0, 0)
    ImGui.PushStyleColor(ImGuiCol.ButtonHovered, 0.6, 0.6, 0.6, 0.1)
    ImGui.Button('##splitter', thickness, -1)
    ImGui.PopStyleColor(3)

    ImGui.SetItemAllowOverlap()

    if ImGui.IsItemActive() then
        delta,_ = ImGui.GetMouseDragDelta()

        if delta < min_size0 - size0 then
            delta = min_size0 - size0
        end
        if delta > 275 - size0 then
            delta = 275 - size0
        end

        size0 = size0 + delta
        left_pane_size = size0
    else
        base_left_pane_size = left_pane_size
    end
    ImGui.SetCursorPosX(x)
    ImGui.SetCursorPosY(y)
end

local function help_marker(desc)
    ImGui.TextDisabled('(?)')
    if ImGui.IsItemHovered() then
        ImGui.BeginTooltip()
        ImGui.PushTextWrapPos(ImGui.GetFontSize() * 35.0)
        ImGui.Text(desc)
        ImGui.PopTextWrapPos()
        ImGui.EndTooltip()
    end
end

local function draw_combo_box(label, resultvar, options, bykey)
    ImGui.Text(label)
    if ImGui.BeginCombo('##'..label, resultvar) then
        for i,j in pairs(options) do
            if bykey then
                if ImGui.Selectable(i, i == resultvar) then
                    resultvar = i
                end
            else
                if ImGui.Selectable(j, j == resultvar) then
                    resultvar = j
                end
            end
        end
        ImGui.EndCombo()
    end
    return resultvar
end

local function draw_check_box(labelText, idText, resultVar, helpText)
    resultVar,_ = ImGui.Checkbox(idText, resultVar)
    ImGui.SameLine()
    ImGui.Text(labelText)
    ImGui.SameLine()
    help_marker(helpText)
    return resultVar
end

local function draw_input_int(labelText, idText, resultVar, helpText)
    ImGui.Text(labelText)
    ImGui.SameLine()
    help_marker(helpText)
    resultVar = ImGui.InputInt(idText, resultVar)
    return resultVar
end

local function draw_input_text(labelText, idText, resultVar, helpText)
    ImGui.Text(labelText)
    ImGui.SameLine()
    help_marker(helpText)
    resultVar = ImGui.InputText(idText, resultVar)
    return resultVar
end

local function draw_left_pane_window()
    local _,y = ImGui.GetContentRegionAvail()
    if ImGui.BeginChild("left", left_pane_size, y-1, true) then
        MODE = draw_combo_box('Mode', MODE, MODES)
        set_camp()
        SPELL_SET = draw_combo_box('Spell Set', SPELL_SET, SPELL_SETS)
        ASSIST = draw_combo_box('Assist', ASSIST, ASSISTS)
        ASSIST_AT = draw_input_int('Assist %', '##assistat', ASSIST_AT, 'Percent HP to assist at')
        CAMP_RADIUS = draw_input_int('Camp Radius', '##campradius', CAMP_RADIUS, 'Camp radius to assist within')
        CHASE_TARGET = draw_input_text('Chase Target', '##chasetarget', CHASE_TARGET, 'Chase Target')
        CHASE_DISTANCE = draw_input_int('Chase Distance', '##chasedist', CHASE_DISTANCE, 'Distance to follow chase target')
        USE_EPIC = draw_combo_box('Epic', USE_EPIC, EPIC_OPTS)
        BURN_PCT = draw_input_int('Burn Percent', '##burnpct', BURN_PCT, 'Percent health to begin burns')
        BURN_COUNT = draw_input_int('Burn Count', '##burncnt', BURN_COUNT, 'Trigger burns if this many mobs are on aggro')
    end
    ImGui.EndChild()
end

local function draw_right_pane_window()
    local x,y = ImGui.GetContentRegionAvail()
    if ImGui.BeginChild("right", x, y-1, true) then
        BURN_ALWAYS = draw_check_box('Burn Always', '##burnalways', BURN_ALWAYS, 'Always be burning')
        BURN_NAMED = draw_check_box('Burn Named', '##burnnamed', BURN_NAMED, 'Burn all named')
        USE_ALLIANCE = draw_check_box('Alliance', '##alliance', USE_ALLIANCE, 'Use alliance spell')
        SWITCH_WITH_MA = draw_check_box('Switch With MA', '##switchwithma', SWITCH_WITH_MA, 'Switch targets with MA')
        RALLY_GROUP = draw_check_box('Rallying Group', '##rallygroup', RALLY_GROUP, 'Use Rallying Group AA')
        MEZST = draw_check_box('Mez ST', '##mezst', MEZST, 'Mez single target')
        MEZAE = draw_check_box('Mez AE', '##mezae', MEZAE, 'Mez AOE')
        BYOS = draw_check_box('BYOS', '##byos', BYOS, 'Bring your own spells')
    end
    ImGui.EndChild()
end

-- ImGui main function for rendering the UI window
local function bardbot_ui()
    if not open_gui then return end
    open_gui, should_draw_gui = ImGui.Begin('Bard Bot 1.0', open_gui)
    if should_draw_gui then
        if ImGui.GetWindowHeight() == 500 and ImGui.GetWindowWidth() == 500 then
            ImGui.SetWindowSize(400, 200)
        end
        if PAUSED then
            if ImGui.Button('RESUME') then
                PAUSED = false
            end
        else
            if ImGui.Button('PAUSE') then
                PAUSED = true
            end
        end
        ImGui.SameLine()
        if ImGui.Button('Save Settings') then
            save_settings()
        end
        ImGui.SameLine()
        if DEBUG then
            if ImGui.Button('Debug OFF') then
                DEBUG = false
            end
        else
            if ImGui.Button('Debug ON') then
                DEBUG = true
            end
        end
        if ImGui.BeginTabBar('##tabbar') then
            if ImGui.BeginTabItem('Settings') then
                draw_splitter(8, base_left_pane_size, 190)
                ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 6, 6)
                draw_left_pane_window()
                ImGui.PopStyleVar()
                ImGui.SameLine()
                ImGui.PushStyleVar(ImGuiStyleVar.WindowPadding, 6, 6)
                draw_right_pane_window()
                ImGui.PopStyleVar()
                ImGui.EndTabItem()
            end
            if ImGui.BeginTabItem('Status') then
                ImGui.TextColored(1, 1, 0, 1, 'Status:')
                ImGui.SameLine()
                local x,_ = ImGui.GetCursorPos()
                ImGui.SetCursorPosX(90)
                if PAUSED then
                    ImGui.TextColored(1, 0, 0, 1, 'PAUSED')
                else
                    ImGui.TextColored(0, 1, 0, 1, 'RUNNING')
                end
                ImGui.TextColored(1, 1, 0, 1, 'Mode:')
                ImGui.SameLine()
                x,_ = ImGui.GetCursorPos()
                ImGui.SetCursorPosX(90)
                ImGui.TextColored(1, 1, 1, 1, MODE)

                ImGui.TextColored(1, 1, 0, 1, 'Camp:')
                ImGui.SameLine()
                x,_ = ImGui.GetCursorPos()
                ImGui.SetCursorPosX(90)
                if CAMP then
                    ImGui.TextColored(1, 1, 0, 1, string.format('X: %.02f  Y: %.02f  Z: %.02f  Rad: %d', CAMP.X, CAMP.Y, CAMP.Z, CAMP_RADIUS))
                else
                    ImGui.TextColored(1, 0, 0, 1, '--')
                end

                ImGui.TextColored(1, 1, 0, 1, 'Target:')
                ImGui.SameLine()
                x,_ = ImGui.GetCursorPos()
                ImGui.SetCursorPosX(90)
                ImGui.TextColored(1, 0, 0, 1, string.format('%s', mq.TLO.Target()))

                ImGui.TextColored(1, 1, 0, 1, 'AM_I_DEAD:')
                ImGui.SameLine()
                x,_ = ImGui.GetCursorPos()
                ImGui.SetCursorPosX(90)
                ImGui.TextColored(1, 0, 0, 1, string.format('%s', I_AM_DEAD))

                ImGui.TextColored(1, 1, 0, 1, 'Burning:')
                ImGui.SameLine()
                x,_ = ImGui.GetCursorPos()
                ImGui.SetCursorPosX(90)
                ImGui.TextColored(1, 0, 0, 1, string.format('%s', burn_active))
                ImGui.EndTabItem()
            end
        end
        ImGui.EndTabBar()
    end
    ImGui.End()
end

-- END UI IMPLEMENTATION

local function show_help()
    printf('BardBot 1.0')
    printf('Commands:\n- /brd burnnow\n- /brd pause on|1|off|0\n- /brd show|hide\n- /brd mode 0|1|2\n- /brd resetcamp\n- /brd help')
end

local function brd_bind(...)
    local args = {...}
    if not args[1] or args[1] == 'help' then
        show_help()
    elseif args[1]:lower() == 'burnnow' then
        BURN_NOW = true
    elseif args[1] == 'pause' then
        if not args[2] then
            PAUSED = not PAUSED
        else
            if args[2] == 'on' or args[2] == '1' then
                PAUSED = true
            elseif args[2] == 'off' or args[2] == '0' then
                PAUSED = false
            end
        end
    elseif args[1] == 'show' then
        open_gui = true
    elseif args[1] == 'hide' then
        open_gui = false
    elseif args[1] == 'mode' then
        if args[2] == '0' then
            MODE = MODES[1]
            set_camp()
        elseif args[2] == '1' then
            MODE = MODES[2]
            set_camp()
        elseif args[2] == '2' then
            MODE = MODES[3]
            set_camp()
        end
    elseif args[1] == 'resetcamp' then
        set_camp(true)
    else
        -- some other argument, show or modify a setting
    end
end
mq.bind('/brd', brd_bind)

local function event_dead()
    printf('bard down!')
    I_AM_DEAD = true
end
local function event_mezbreak(line, mob, breaker)
    printf('\ay%s\ax mez broken by \ag%s\ax', mob, breaker)
    --TARGETS={}
end
local function event_mezimmune(line)
    if MEZ_TARGET_NAME then
        printf('Added to MEZ_IMMUNE: \ay%s', MEZ_TARGET_NAME)
        MEZ_IMMUNES[MEZ_TARGET_NAME] = 1
    end
end
local function event_mezresist(line, mob)
    if MEZ_TARGET_NAME and mob == MEZ_TARGET_NAME then
        printf('MEZ RESIST >>> %s <<<', MEZ_TARGET_NAME)
        TARGETS[MEZ_TARGET_ID].meztimer = 0
    end
end
mq.event('event_dead_released', '#*#Returning to Bind Location#*#', event_dead)
mq.event('event_dead', 'You died.', event_dead)
mq.event('event_dead_slain', 'You have been slain by#*#', event_dead)
mq.event('event_mezbreak', '#1# has been awakened by #2#.', event_mezbreak)
mq.event('event_mezimmune', 'Your target cannot be mesmerized#*#', event_mezimmune)
mq.event('event_mezimmune', '#1# resisted your#*#slumber of the diabo#*#', event_mezresist)

mq.imgui.init('Bard Bot 1.0', bardbot_ui)

load_settings()

mq.TLO.Lua.Turbo(500)
mq.cmd('/squelch /stick set verbosity off')
mq.cmd('/squelch /plugin melee unload noauto')

local debug_timer = 0
local selos_timer = 0
-- Main Loop
while true do
    if DEBUG and timer_expired(debug_timer, 3) then
        debug('main loop: PAUSED=%s, Me.Invis=%s', PAUSED, mq.TLO.Me.Invis())
        debug('#TARGETS: %d, MOB_COUNT: %d', table_size(TARGETS), MOB_COUNT)
        debug_timer = current_time()
    end

    clean_targets()
    if not mq.TLO.Target() and mq.TLO.Me.Combat() then
        ASSIST_TARGET_ID = 0
        mq.cmd('/attack off')
    end
    if mq.TLO.Target() and mq.TLO.Target.Type() == 'Corpse' then
        ASSIST_TARGET_ID = 0
        mq.cmd('/squelch /mqtarget clear')
    end
    -- Process death events
    mq.doevents()
    -- do active combat assist things when not paused and not invis
    if not PAUSED and not mq.TLO.Me.Invis() then
        -- keep cursor clear for spell swaps and such
        if mq.TLO.Cursor() then mq.cmd('/autoinventory') end
        if timer_expired(selos_timer, 30) then
            use_aa(selos['name'], selos['id'])
            selos_timer = current_time()
        end
        -- ensure correct spells are loaded based on selected spell set
        check_spell_set()
        -- check whether we need to return to camp
        check_camp()
        -- check whether we need to go chasing after the chase target
        check_chase()
        check_target()
        -- check our surroundings for mobs to deal with
        mob_radar()
        if not pause_for_rally() then
            -- check we have the correct target to attack
            check_mez()
            -- if we should be assisting but aren't in los, try to be?
            attack()
            -- begin actual combat stuff
            send_pet()
            if mq.TLO.Me.CombatState() ~= 'ACTIVE' and mq.TLO.Me.CombatState() ~= 'RESTING' then
                cycle_songs()
            end
            mash()
            -- pop a bunch of burn stuff if burn conditions are met
            try_burn()
            -- try not to run OOM
            check_aggro()
        end
        check_mana()
        check_buffs()
        rest()
        mq.delay(1)
    elseif not PAUSED and mq.TLO.Me.Invis() then
        -- stay in camp or stay chasing chase target if not paused but invis
        if MODE == 'assist' and should_assist() then mq.cmd('/makemevis') end
        check_camp()
        check_chase()
        mq.delay(50)
    else
        -- paused, spin
        mq.delay(500)
    end
end