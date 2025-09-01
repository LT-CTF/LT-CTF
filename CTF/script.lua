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

--------------
-- Settings --
--------------

ctf_flag_delivered_score = 1000
ctf_final_turn = 100

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

function flag_unit_team(flag_unit)
  local team_name = string.match(flag_unit.utype:rule_name(), "^(%S+) Flag$")
  if not team_name then return nil end
  return find.team(team_name)
end

-- Since granting techs in the .serv file doesn't seem to work, we'll do it 
-- when the first city is built instead.
function first_city_built(city)
  -- Only on first city
  if not city:has_building(find.building_type("Palace")) then return false end
  local team_name = city.owner.team.name
  local flag_tech = find.tech_type(team_name .. " Flag-making")
  assert(flag_tech, "Missing %s Flag-making tech", team_name)
  city.owner:give_tech(flag_tech, 0, false, "team_start_tech")
  return false
end

signal.connect("city_built", "first_city_built")

-----------------
-- CTF Scoring --
-----------------

function team_flag_score(team)
  return tonumber(_G[string.format("score_%s", team.name)] or 0)
end

function team_civ_score(team)
  local civ_score = 0
  for player in team:members_iterate() do
    civ_score = civ_score + player:civilization_score()
  end
  return civ_score
end

function team_flag_score_add(team, amount)
  local score = team_flag_score(team) + amount
  _G[string.format("score_%s", team.name)] = score
end

function team_leaderboard()
  local team_scores = {}
  for team in find.teams_iterate() do
    table.insert(team_scores, {
      name = team.name,
      flag_score = team_flag_score(team),
      civ_score = team_civ_score(team)
    })
  end
  table.sort(team_scores, function(a, b)
    if a.flag_score == b.flag_score then
      return a.civ_score > b.civ_score
    else
      return a.flag_score > b.flag_score
    end
  end)
  return team_scores
end

function notify_leaderboard()
  local team_scores = team_leaderboard()
  notify.event(nil, nil, E.SCRIPT, "Leaderboard:")
  for i, team in ipairs(team_scores) do
    notify.event(nil, nil, E.SCRIPT, "- %s: %d flag points (%d civ score)",
      team.name, team.flag_score, team.civ_score)
  end
end

function check_scores(turn, year)
  notify_leaderboard()
  if turn >= ctf_final_turn then
    local winning_team = find.team(team_leaderboard()[1].name)
    notify.event(nil, nil, E.SCRIPT, "The %s team has won!", winning_team.name)
    local winner = nil
    local highscore = 0
    for player in winning_team:members_iterate() do
      if player:civilization_score() > highscore then
        highscore = player:civilization_score()
        winner = player
      end
    end
    winner:victory()
  end
end

signal.connect("turn_begin", "check_scores")

------------------------------------
-- Capture the Flag custom action --
------------------------------------

function flag_captured_bonus_on(flag_team)
  for player in flag_team:members_iterate() do
    for city in player:cities_iterate() do
      city.tile:create_extra("Flag Captured")
    end
  end
end

function flag_captured_bonus_off(flag_team)
  for player in flag_team:members_iterate() do
    for city in player:cities_iterate() do
      city.tile:remove_extra("Flag Captured")
    end
  end
end

function capture_the_flag(action, actor, target)
  if action:rule_name() ~= "User Action 1" then return false end
  local flag_team = target.owner.team
  local flag_utype = find.unit_type(flag_team.name .. " Flag")
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
  local city = dst_tile:city()
  if not city then return false end
  local flag_team = flag_unit_team(unit)
  if not flag_team then return false end
  local holder_team = unit.owner.team
  local flagpole = find.building_type(holder_team.name .. " Flagpole")
  if not city:has_building(flagpole) then return false end
  flag_captured_bonus_off(flag_team)
  team_flag_score_add(unit.owner.team, ctf_flag_delivered_score)
  unit.owner:add_history(ctf_flag_delivered_score)
  notify.event(nil, unit.tile, E.SCRIPT, 
    "%s has delivered the %s flag to the %s team base!", 
    unit.owner.name, flag_team.name, holder_team.name)
  notify_leaderboard()
  unit:kill("used", nil)
  return false
end

signal.connect("unit_moved", "flag_delivered")

--------------------
-- Flag destroyed --
--------------------

function flag_destroyed(unit, loser, reason, killer)
  local flag_team = flag_unit_team(unit)
  if not flag_team then return false end
  flag_captured_bonus_off(flag_team)
  if killer then
    notify.event(nil, unit.tile, E.SCRIPT, 
      "%s has recovered the %s flag!", 
      killer.name, flag_team.name)
  else
    notify.event(nil, unit.tile, E.SCRIPT, 
      "The %s flag has been recovered.", 
      flag_team.name)
  end
  return false
end

signal.connect("unit_lost", "flag_destroyed")

-------------
-- Logging --
-------------

function log_flagpole_built(building, city)
  local team_name = string.match(building:rule_name(), "^(%S+) Flagpole$")
  if not team_name then return false end
  log.normal("The %s flag wonder has been built in %s", team_name, city.name)
end

signal.connect("building_built", "log_flagpole_built")
