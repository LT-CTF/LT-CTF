-- Copyright (c) 2007-2020 Freeciv21 and Freeciv contributors. This file is
--   part of Freeciv21. Freeciv21 is free software: you can redistribute it
--   and/or modify it under the terms of the GNU General Public License
--   as published by the Free Software Foundation, either version 3
--   of the License,  or (at your option) any later version.
--   You should have received a copy of the GNU General Public License
--   along with Freeciv21. If not, see https://www.gnu.org/licenses/.

-- This file is for lua-functionality that is specific to a given
-- ruleset. When freeciv loads a ruleset, it also loads script
-- file called 'default.lua'. The one loaded if your ruleset
-- does not provide an override is default/default.lua.

---------------
-- Utilities --
---------------

function find_player(player_name)
  for player in players_iterate() do
    if player.name == player_name then
      return player
    end
  end
  return nil
end

----------------
-- City Ruins --
----------------

-- Place Ruins at the location of the destroyed city.
function city_destroyed_callback(city, loser, destroyer)
  city.tile:create_extra("Ruins", NIL)
  -- continue processing
  return false
end

signal.connect("city_destroyed", "city_destroyed_callback")

----------------------------------
-- Nuke bombards adjacent units --
----------------------------------

function nuke_terrain_defence(terrain)
  if terrain == "Lake" then return 1.10 end
  if terrain == "Ocean" then return 1.10 end
  if terrain == "Deep Ocean" then return 1.0 end
  if terrain == "Glacier" then return 1.0 end
  if terrain == "Desert" then return 1.0 end
  if terrain == "Forest" then return 1.25 end
  if terrain == "Grassland" then return 1.0 end
  if terrain == "Hills" then return 1.50 end
  if terrain == "Jungle" then return 1.40 end
  if terrain == "Mountains" then return 2.0 end
  if terrain == "Plains" then return 1.0 end
  if terrain == "Swamp" then return 1.25 end
  if terrain == "Tundra" then return 1.0 end
  return 1.0
end

function nuke_min_hp(unit)
  if not unit.tile.city then return 0 end
  if unit.tile.city:has_building(find.building_type("City Walls")) then 
    return unit.utype.hp * 0.5
  end
  return unit.utype.hp * 0.25
end

function nuke_bombard_unit(unit, player, epicentre)
  local defence = 400 * nuke_terrain_defence(unit.tile.terrain:rule_name())
  if epicentre then
    defence = defence * 0.5
  end
  local min_hp = nuke_min_hp(unit)
  local damage = 0
  for i = 1, 200 do
    if random(0, defence) < 80 then
      damage = damage + 1
    end
  end
  local hp = math.min(unit.hp - damage, min_hp)
  if hp <= 0 then
    notify.event(unit.owner, unit.tile, E.UNIT_LOST_MISC, 
      "Your %s was nuked by %s.", 
      unit:tile_link_text(), player.name)
    unit:kill("nuke", player)
  else
    notify.event(unit.owner, unit.tile, E.UNIT_BOMB_DEF, 
      "Your %s suffered %d damage from %s's nuke.", 
      unit:link_text(), damage, player.name)
    unit:set_hp(hp)
  end
end

function nuke_bombard_area(tile, player)
  for adj in tile:square_iterate(1) do
    for unit in adj:units_iterate() do
      nuke_bombard_unit(unit, player, tile == adj)
    end
  end
  return false
end

signal.connect("nuke_exploded", "nuke_bombard_area")

---------------
-- CTF Teams --
---------------

function register_team_member(player_name, team_name)
  local player = find_player(player_name)
  assert(player, "%s is a not a player", player_name)
  assert(team_name == "Red" or team_name == "Blue", "Team must be Red or Blue")
  _G[string.format("player_team_%s", player_name)] = team_name
end

function player_team_name(player)
  return _G[string.format("player_team_%s", player.name)]
end

function team_iterate(team_name)
  if not team_name then return nil end
  local get_next_player = players_iterate()
  return function()
    local player = get_next_player()
    while player do
      if player_team_name(player) == team_name then
        return player
      end
      player = get_next_player()
    end
    return nil
  end
end

function flag_team_name(flag_unit)
  if flag_unit.utype:rule_name() == "Red Flag" then
    return "Red"
  elseif flag_unit.utype:rule_name() == "Blue Flag" then
    return "Blue"
  end
  return nil
end

-- Since granting techs in the .serv file doesn't seem to work, we'll do it 
-- when the first city is built instead.
function first_city_built(city)
  -- Only on first city
  if not city:has_building(find.building_type("Palace")) then return false end
  local team_name = player_team_name(city.owner)
  if not team_name then return false end -- Not on a flag team
  local flag_tech = find.tech_type(team_name .. " Flag-making")
  assert(flag_tech, "Missing %s Flag-making tech", team_name)
  city.owner:give_tech(flag_tech, 0, false, "team_start_tech")
end

signal.connect("city_built", "first_city_built")

------------------------------------
-- Capture the Flag custom action --
------------------------------------

function flag_captured_bonus_on(flag_team)
  for player in team_iterate(flag_team) do
    for city in player:cities_iterate() do
      city.tile:create_extra("Flag Captured")
    end
  end
end

function flag_captured_bonus_off(flag_team)
  for player in team_iterate(flag_team) do
    for city in player:cities_iterate() do
      city.tile:remove_extra("Flag Captured")
    end
  end
end

function capture_the_flag(action, actor, target)
  if action:rule_name() ~= "User Action 1" then return false end
  local flag_team = player_team_name(target.owner)
  local flag_utype = find.utype(flag_team .. " Flag")
  local flag = actor.owner:create_unit(actor.tile, flag_utype, 0, nil, -1)
  flag_captured_bonus_on(flag_team)
  notify.event(nil, target.tile, E.SCRIPT, 
    "%s has captured the %s!", 
    actor.owner.name, flag:link_text())
  return false
end

signal.connect("action_started_unit_city", "capture_the_flag")

-------------------
-- Flag returned --
-------------------

function flag_delivered(unit, src_tile, dst_tile)
  local city = dst_tile.city
  if not city then return false end
  local flag_team = flag_team_name(unit)
  if not flag_team then return false end
  local holder_team = player_team_name(flag.owner)
  if not city:has_building(holder_team .. " Flagpole") then return false end
  flag_captured_bonus_off(flag_team)
  unit.owner:add_history(1000000)
  notify.event(nil, unit.tile, E.SCRIPT, 
    "%s has delivered the %s flag to the %s team base!", 
    unit.owner.name, flag_team, holder_team)
  unit:kill("used", nil)
  return false
end

signal.connect("unit_moved", "flag_delivered")

--------------------
-- Flag destroyed --
--------------------

function flag_destroyed(unit, loser, reason, killer)
  local flag_team = flag_team_name(unit)
  if not flag_team then return false end
  flag_captured_bonus_off(flag_team)
  if killer then
    notify.event(nil, unit.tile, E.SCRIPT, 
      "%s has recovered the %s flag!", 
      killer.name, flag_team)
  else
    notify.event(nil, unit.tile, E.SCRIPT, 
      "The %s flag has been recovered.", 
      flag_team)
  end
  return false
end

signal.connect("unit_lost", "flag_destroyed")
