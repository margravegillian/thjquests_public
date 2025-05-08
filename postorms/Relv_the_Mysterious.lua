-- Constants for NPC IDs
local MEPHIT_FIRE = 1120001288
local MEPHIT_SMOKE = 1120001289
local BOSS_ID = 210245
local VFX_ID = 98207
local REQUIRED_KILLS = 8

-- Utility: Move solo player or group (no raids)
function MovePlayerGroupOrRaid(player, zone_id, x, y, z, h)
  if not player or not player:IsClient() then return end
  local client = player:CastToClient()
  local group = client:GetGroup()

  if group and group:IsGroupMember(client) then
    for i = 0, group:GroupCount() - 1 do
      local member = group:GetMember(i)
      if member and member:IsClient() then
        member:CastToClient():MovePC(zone_id, x, y, z, h)
      end
    end
  else
    client:MovePC(zone_id, x, y, z, h)
  end
end

-- Dialogue and spawn event
function event_say(e)
  if e.message:findi("hail") then
    e.self:Say("Greetings to you, small one. I see you have made great progress through our fair planar dwelling. Were it not for the dubious undertakings by someone... or something, I would be more than glad to welcome you here. Unfortunately, there have been dangerous tidings afoot. Just look at the trees around you. This [" .. eq.say_link("destruction") .. "] is the work of something altogether unseen, at least by me.")

  elseif e.message:findi("destruction") then
    e.self:Say("There was a time when all the trees were green and alive, though as you can see, that time is no more. I am unsure what it is that has caused the damage, but I do know that whatever it is has caused a great deal of damage and will continue to do so unless someone like yourself has the courage to rid us of it. [" .. eq.say_link("continue") .. "]")

  elseif e.message:findi("continue") then
    e.self:Emote("looks about him at the charred trees and sighs. 'If this destruction is not stopped, we may soon not have any forest left, which would cause a great disturbance in the balance of this land. If it were in my power, I would go forth through the brush here to try and stop whatever it is that is causing this. Unfortunately, I cannot leave, as I must protect the rest of the trees here from any beasts that may try to defile these lands further. This is why I must ask for an outsider to help, so that I may send them forth through the brush into the clearing beyond to find the menace and destroy it at the source. [" .. eq.say_link("tell me more") .. "]")

  elseif e.message:findi("tell me more") then
    e.self:Say("I have waited patiently for someone to come along to defeat this scourge on the land, and you may just be the one. If you feel you are [" .. eq.say_link("courageous") .. "] enough to go forth, please let me know and I will make preparations to assist you through the brush to end whatever suffering the forest is feeling beyond.")

  elseif e.message:findi("courageous") then
    e.self:Say("As I had hoped. I regret that I have only enough strength to send four parties through the brush to the other side, and only one party at a time. When each party is ready to move forth, tell me that [" .. eq.say_link("We are ready", false, "you are ready") .. "] and I will make a clearing for you to go through. Be wary!")

  elseif e.message:findi("we are ready") then
    local active_party = eq.get_global("forest_active_party")
    if active_party == "1" then
      e.self:Say("I’m sorry, but I’ve already sent a group through. You must wait until they return before I can send another.")
      return
    end

    e.self:Say("Then I wish you luck, brave adventurer. May the forest spirits watch over you.")
    e.self:Emote("A powerfully green aura surrounds Relv as he opens a small rift in the brushes beyond, then sends you and your party forth into the burning forest beyond.")

    eq.set_global("forest_active_party", "1", 7, "D30")
    eq.set_global("forest_mephit_kills", "0", 7, "D30")
    eq.set_global("forest_boss_spawned", "0", 7, "D30")

    MovePlayerGroupOrRaid(e.other, 0, -156.593, 5090.91, -555.29, 431)

    -- Spawn mephits
    eq.spawn2(MEPHIT_FIRE, 0, 0, -610.30, 5252.94, -492, 10)
    eq.spawn2(MEPHIT_SMOKE, 0, 0, -867.62, 5038.49, -492.10, 0)
    eq.spawn2(MEPHIT_FIRE, 0, 0, -744.74, 5269.97, -548.13, 0)
    eq.spawn2(MEPHIT_SMOKE, 0, 0, -111.31, 5095.05, -517.31, 0)
    eq.spawn2(MEPHIT_FIRE, 0, 0, -167.42, 5618.41, -541.82, 0)
    eq.spawn2(MEPHIT_SMOKE, 0, 0, -599.56, 5787.18, -587.16, 0)
    eq.spawn2(MEPHIT_FIRE, 0, 0, -108.66, 5088.07, -552.94, 0)
    eq.spawn2(MEPHIT_SMOKE, 0, 0, -890.96, 4970.50, -579.58, 0)
  end
end

-- Handle mephit and boss death
function event_death(e)
  local npc_id = e.self:GetNPCTypeID()

  if npc_id == MEPHIT_FIRE or npc_id == MEPHIT_SMOKE then
    local kill_count = tonumber(eq.get_global("forest_mephit_kills")) or 0
    local boss_spawned = eq.get_global("forest_boss_spawned") == "1"

    if not boss_spawned then
      kill_count = kill_count + 1
      eq.set_global("forest_mephit_kills", tostring(kill_count), 7, "D30")
      eq.zone_emote(15, "The forest trembles as another mephit falls! (" .. kill_count .. "/" .. REQUIRED_KILLS .. ")")

      if kill_count >= REQUIRED_KILLS then
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

function event_spawn(e)
  local x, y = e.self:GetX(), e.self:GetY()
  e.self:SetBodyType(BT.Humanoid, true);
  e.self:SetTargetable(true);
end

-- Timer event to reset party lock
function event_timer(e)
  if e.timer == "reset_party" then
    eq.stop_timer("reset_party")
    eq.set_global("forest_active_party", "0", 7, "D30")
    eq.set_global("forest_mephit_kills", "0", 7, "D30")
    eq.set_global("forest_boss_spawned", "0", 7, "D30")
  end
end

