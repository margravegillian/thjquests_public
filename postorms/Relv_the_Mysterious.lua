-- Constants for NPC IDs
local MEPHIT_FIRE = 1120001288
local MEPHIT_SMOKE = 1120001289
local BOSS_ID = 210245
local VFX_ID = 98207
local REQUIRED_KILLS = 8
local WAVE_INTERVAL = 30 -- seconds
local WAVE_SIZE = 4
local MAX_WAVES = 3

local wave_count = 0

function event_spawn(e)
  e.self:SetBodyType(BT.Humanoid, true);
  e.self:SetTargetable(true);
end

function MovePlayerGroupOrRaid(player, zone_id, instance_id, x, y, z, h)
  if not player or not player:IsClient() then return end
  local client = player:CastToClient()
  local group = client:GetGroup()

  if group and group:IsGroupMember(client) then
    for i = 0, group:GroupCount() - 1 do
      local member = group:GetMember(i)
      if member and member:IsClient() then
        member:CastToClient():MovePCInstance(zone_id, instance_id, x, y, z, h)
      end
    end
  else
    client:MovePCInstance(zone_id, instance_id, x, y, z, h)
  end
end

function event_say(e)
  if e.message:findi("hail") then
    e.self:Say("Greetings to you, small one... [" .. eq.say_link("destruction") .. "]")
  elseif e.message:findi("destruction") then
    e.self:Say("There was a time when all the trees were green... [" .. eq.say_link("continue") .. "]")
  elseif e.message:findi("continue") then
    e.self:Emote("looks about him... [" .. eq.say_link("tell me more") .. "]")
  elseif e.message:findi("tell me more") then
    e.self:Say("I have waited patiently... [" .. eq.say_link("courageous") .. "]")
  elseif e.message:findi("courageous") then
    e.self:Say("As I had hoped... [" .. eq.say_link("We are ready", false, "you are ready") .. "]")
  elseif e.message:findi("we are ready") then
    local active_party = eq.get_global("forest_active_party")
    if active_party == "1" then
      e.self:Say("I’m sorry, but I’ve already sent a group through.")
      return
    end

    e.self:Say("Then I wish you luck...")
    e.self:Emote("A powerfully green aura surrounds Relv...")

    local client = e.other:CastToClient()
    if client then
      local zone = eq.get_zone()
      local zone_id = zone:GetZoneID()
      local instance_id = zone:GetInstanceID()
      MovePlayerGroupOrRaid(client, zone_id, instance_id, -156.593, 5090.91, -555.29, 431)
    end

    eq.set_global("forest_active_party", "1", 7, "D30")
    eq.set_global("forest_mephit_kills", "0", 7, "D30")
    eq.set_global("forest_boss_spawned", "0", 7, "D30")

    wave_count = 0
    eq.set_timer("spawn_wave", WAVE_INTERVAL * 1000)
  end
end

function event_timer(e)
  if e.timer == "spawn_wave" then
    wave_count = wave_count + 1
    if wave_count > MAX_WAVES then
      eq.stop_timer("spawn_wave")
      eq.zone_emote(15, "The last wave of enemies has been vanquished. A powerful presence approaches!")
      eq.unique_spawn(BOSS_ID, 0, 0, -740, 5150, -492, 0)
    else
      for i = 1, WAVE_SIZE do
        eq.spawn2(MEPHIT_FIRE, 0, 0, -610 + math.random(-10, 10), 5252 + math.random(-10, 10), -492, 10)
        eq.spawn2(MEPHIT_SMOKE, 0, 0, -867 + math.random(-10, 10), 5038 + math.random(-10, 10), -492 + math.random(-10, 10), 0)
      end
      eq.zone_emote(15, "A new wave of mephits has arrived! (" .. wave_count .. "/" .. MAX_WAVES .. ")")
    end
  elseif e.timer == "reset_party" then
    eq.stop_timer("reset_party")
    eq.set_global("forest_active_party", "0", 7, "D30")
    eq.set_global("forest_mephit_kills", "0", 7, "D30")
    eq.set_global("forest_boss_spawned", "0", 7, "D30")
  end
end

function event_death(e)
  local npc_id = e.self:GetNPCTypeID()

  if npc_id == MEPHIT_FIRE or npc_id == MEPHIT_SMOKE then
    local kills = tonumber(eq.get_global("forest_mephit_kills") or "0")
    local boss_spawned = eq.get_global("forest_boss_spawned") == "1"

    if not boss_spawned then
      kills = kills + 1
      eq.set_global("forest_mephit_kills", tostring(kills), 7, "D30")
      eq.zone_emote(15, "The forest trembles as another mephit falls! (" .. kills .. "/" .. REQUIRED_KILLS .. ")")

      if kills >= REQUIRED_KILLS then
        eq.set_global("forest_boss_spawned", "1", 7, "D30")
        eq.unique_spawn(BOSS_ID, 0, 0, e.self:GetX(), e.self:GetY(), e.self:GetZ(), e.self:GetHeading())
      end
    end

  elseif npc_id == BOSS_ID then
    eq.zone_emote(15, "The forest calms as the source of the destruction is silenced.")
    eq.spawn2(VFX_ID, 0, 0, e.self:GetX(), e.self:GetY(), e.self:GetZ(), e.self:GetHeading())
    eq.set_timer("reset_party", 60000)
  end
end
