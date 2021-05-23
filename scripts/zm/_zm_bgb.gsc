#using scripts\codescripts\struct;

#using scripts\shared\animation_shared;
#using scripts\shared\array_shared;
#using scripts\shared\callbacks_shared;
#using scripts\shared\clientfield_shared;
#using scripts\shared\demo_shared;
#using scripts\shared\flag_shared;
#using scripts\shared\laststand_shared;
#using scripts\shared\math_shared;
#using scripts\shared\spawner_shared;
#using scripts\shared\system_shared;
#using scripts\shared\util_shared;

#insert scripts\shared\shared.gsh;

#using scripts\zm\_zm;
#using scripts\zm\_zm_audio;
#using scripts\zm\_zm_bgb;
#using scripts\zm\_zm_bgb_machine;
#using scripts\zm\_zm_bgb_token;
#using scripts\zm\_zm_equipment;
#using scripts\zm\_zm_laststand;
#using scripts\zm\_zm_perks;
#using scripts\zm\_zm_powerups;
#using scripts\zm\_zm_score;
#using scripts\zm\_zm_stats;
#using scripts\zm\_zm_unitrigger;
#using scripts\zm\_zm_utility;
#using scripts\zm\_zm_weapons;
#using scripts\zm\gametypes\_globallogic_score;

#insert scripts\zm\_zm_bgb.gsh;
#insert scripts\zm\_zm_perks.gsh;
#insert scripts\zm\_zm_utility.gsh;

#namespace bgb;


REGISTER_SYSTEM_EX( "bgb", &__init__, &__main__, undefined )

function private __init__()
{
	callback::on_spawned(&on_player_spawned);
	
	if (!IS_TRUE(level.bgb_in_use))
	{
		return;
	}
	
	level.weaponBGBGrab = GetWeapon("zombie_bgb_grab");
	level.weaponBGBUse = GetWeapon("zombie_bgb_use");

	level.bgb = []; // array for actual buffs

	clientfield::register("clientuimodel", BGB_CURRENT_CF_NAME, 1, 8, "int");
	clientfield::register("clientuimodel", BGB_DISPLAY_CF_NAME, 1, 1, "int");
	clientfield::register("clientuimodel", BGB_TIMER_CF_NAME, 1, 8, "float");
	clientfield::register("clientuimodel", BGB_ACTIVATIONS_REMAINING_CF_NAME, 1, 3, "int");
	clientfield::register("clientuimodel", BGB_INVALID_USE_CF_NAME, 1, 1, "counter");
	clientfield::register("clientuimodel", BGB_ONE_SHOT_USE_CF_NAME, 1, 1, "counter");

	clientfield::register("toplayer", BGB_BLOW_BUBBLE_CF_NAME, 1, 1, "counter");

	zm::register_vehicle_damage_callback(&vehicle_damage_override);
}

function private __main__()
{
	if (!IS_TRUE(level.bgb_in_use))
	{
		return;
	}

	bgb_finalize();

	/#
		level thread setup_devgui();
	#/

	level._effect["samantha_steal"] = "zombie/fx_monkey_lightning_zmb";
}

function private on_player_spawned()
{
	self.bgb = "none";

	if (!IS_TRUE(level.bgb_in_use))
	{
		return;
	}

	self function_52dbea8c();

	self thread bgb_player_init();
}

function private function_52dbea8c()
{
	if (!IS_TRUE(self.var_c2d95bad))
	{
		self.var_c2d95bad = 1;
		self globallogic_score::initPersStat("bgb_tokens_gained_this_game", 0);
		self.var_f191a1fc = 0;
	}
}

function private bgb_player_init()
{
	if (IsDefined(self.bgb_pack))
	{
		return;
	}

	self.bgb_pack = self GetBubbleGumPack();
	self.bgb_pack_randomized = [];

	self.bgb_stats = []; // bgb_stats will hold the player's gained/used stats, indexed by bgb name
	foreach (bgb in self.bgb_pack)
	{
		if (bgb == "weapon_null")
		{
			continue;
		}
		if (!IS_TRUE(level.bgb[bgb].consumable))
		{
			continue;
		}
		self.bgb_stats[bgb] = SpawnStruct();
		self.bgb_stats[bgb].var_e0b06b47 = self GetBGBRemaining(bgb);
		self.bgb_stats[bgb].bgb_used_this_game = 0;
	}

	self.var_85da8a33 = 0;
	self clientfield::set_to_player("zm_bgb_machine_round_buys", self.var_85da8a33);

	self init_weapon_cycling();

	self thread bgb_player_monitor();
	self thread bgb_end_game();
}

// when the game ends:
// - take any bgb that the player is carrying
// - add count of bgbs used this game to the player's stat
function private bgb_end_game()
{
	self endon("disconnect");

	if (!level flag::exists("consumables_reported"))
	{
		level flag::init("consumables_reported");
	}
	self flag::init("finished_reporting_consumables");

	self waittill("report_bgb_consumption");

	// - take any bgb that the player is carrying
	self thread take();

	self function_e1f3d6d7();
	self zm_stats::set_global_stat("bgb_tokens_gained_this_game", self.var_f191a1fc);

	// - add count of bgbs used this game to the player's stat
	foreach (bgb in self.bgb_pack)
	{
		// ignore non-consumables
		if (!IsDefined(self.bgb_stats[bgb]) || !self.bgb_stats[bgb].bgb_used_this_game)
		{
			continue;
		}

		level flag::set("consumables_reported");
		zm_utility::increment_zm_dash_counter("end_consumables_count", self.bgb_stats[bgb].bgb_used_this_game);
		self function_99b36259(bgb, self.bgb_stats[bgb].bgb_used_this_game);
	}
	self flag::set("finished_reporting_consumables");
}

function private bgb_finalize()
{
	statsTableName = util::getStatsTableName();
	keys = GetArrayKeys(level.bgb);
	for (i = 0; i < keys.size; i++)
	{
		level.bgb[keys[i]].item_index = GetItemIndexFromRef(keys[i]);
		level.bgb[keys[i]].rarity = Int(TableLookup(statsTableName, 0, level.bgb[keys[i]].item_index, 16));
		if (level.bgb[keys[i]].rarity == BGB_RARITY_CLASSIC_INDEX || level.bgb[keys[i]].rarity == BGB_RARITY_WHIMSICAL_INDEX)
		{
			level.bgb[keys[i]].consumable = false;
		}
		else
		{
			level.bgb[keys[i]].consumable = true;
		}
		level.bgb[keys[i]].camo_index = Int(TableLookup(statsTableName, 0, level.bgb[keys[i]].item_index, 5));
		var_cf65a2c0 = TableLookup(statsTableName, 0, level.bgb[keys[i]].item_index, 15);
		if (IsSubStr(var_cf65a2c0, "dlc"))
		{
			level.bgb[keys[i]].dlc_index = Int(var_cf65a2c0[3]);
			continue;
		}
		level.bgb[keys[i]].dlc_index = 0;
	}
}

function private bgb_player_monitor()
{
	self endon("disconnect");

	for(;;)
	{
		str_return = level util::waittill_any_return("between_round_over", "restart_round");
		if (IsDefined(level.var_4824bb2d))
		{
			if (!IS_TRUE(self [[ level.var_4824bb2d ]]()))
			{
				continue;
			}
		}
		if (str_return === "restart_round")
		{
			level waittill("between_round_over");
		}
		else
		{
			// get your ability to grab a bubblegum buff back every round
			self.var_85da8a33 = 0;
			self clientfield::set_to_player("zm_bgb_machine_round_buys", self.var_85da8a33);
		}
	}
}

function private setup_devgui()
{
	/#
		waittillframeend;
		SetDvar("Dev Block strings are not supported", "Dev Block strings are not supported");
		SetDvar("Dev Block strings are not supported", -1);
		var_33b4e7c1 = "Dev Block strings are not supported";
		keys = GetArrayKeys(level.bgb);
		foreach (key in keys)
		{
			AddDebugCommand(var_33b4e7c1 + key + "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported" + key + "Dev Block strings are not supported");
		}
		AddDebugCommand(var_33b4e7c1 + "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported");
		AddDebugCommand(var_33b4e7c1 + "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported");
		for (i = 0; i < 4; i++)
		{
			playerNum = i + 1;
			AddDebugCommand(var_33b4e7c1 + "Dev Block strings are not supported" + playerNum + "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported" + i + "Dev Block strings are not supported");
		}
		level thread function_70fe94ae();
	#/
}

/*
	Name: function_70fe94ae
	Namespace: bgb
	Checksum: 0x286D0311
	Offset: 0x1578
	Size: 0x7F
	Parameters: 0
	Flags: Private
*/
function private function_70fe94ae()
{
	/#
		for(;;)
		{
			var_fe9a7d67 = GetDvarString("Dev Block strings are not supported");
			if (var_fe9a7d67 != "Dev Block strings are not supported")
			{
				function_dea9a9da(var_fe9a7d67);
			}
			SetDvar("Dev Block strings are not supported", "Dev Block strings are not supported");
			wait(0.5);
		}
	#/
}

/*
	Name: function_dea9a9da
	Namespace: bgb
	Checksum: 0xAB92DEAA
	Offset: 0x1600
	Size: 0x11D
	Parameters: 1
	Flags: Private
*/
function private function_dea9a9da(var_a961d470)
{
	/#
		var_a7032a9 = GetDvarInt("Dev Block strings are not supported");
		players = GetPlayers();
		for (i = 0; i < players.size; i++)
		{
			if (var_a7032a9 != -1 && var_a7032a9 != i)
			{
				continue;
			}
			if ("Dev Block strings are not supported" == var_a961d470)
			{
				players[i] thread take();
				continue;
			}
			function_594d2bdf(1);
			players[i] thread bgb_gumball_anim(var_a961d470, false);
			function_594d2bdf(0);
		}
	#/
}

/*
	Name: function_ef47b774
	Namespace: bgb
	Checksum: 0x852D87D8
	Offset: 0x1728
	Size: 0x143
	Parameters: 0
	Flags: Private
*/
function private function_ef47b774()
{
	/#
		self.var_94ee23e0 = newClientHudElem(self);
		self.var_94ee23e0.elemType = "Dev Block strings are not supported";
		self.var_94ee23e0.font = "Dev Block strings are not supported";
		self.var_94ee23e0.fontscale = 1.8;
		self.var_94ee23e0.horzAlign = "Dev Block strings are not supported";
		self.var_94ee23e0.vertAlign = "Dev Block strings are not supported";
		self.var_94ee23e0.alignX = "Dev Block strings are not supported";
		self.var_94ee23e0.alignY = "Dev Block strings are not supported";
		self.var_94ee23e0.x = 15;
		self.var_94ee23e0.y = 35;
		self.var_94ee23e0.sort = 2;
		self.var_94ee23e0.color = (1, 1, 1);
		self.var_94ee23e0.alpha = 1;
		self.var_94ee23e0.hidewheninmenu = 1;
	#/
}

function private bgb_set_debug_text(name, var_2741876d)
{
	/#
		if (!IsDefined(self.var_94ee23e0))
		{
			return;
		}
		if (IsDefined(var_2741876d))
		{
			self clientfield::set_player_uimodel("Dev Block strings are not supported", 1);
		}
		else
		{
			self clientfield::set_player_uimodel("Dev Block strings are not supported", 0);
		}
		self notify("hash_ad571a66");
		self endon("hash_ad571a66");
		self endon("disconnect");
		self.var_94ee23e0 fadeOverTime(0.05);
		self.var_94ee23e0.alpha = 1;
		prefix = "Dev Block strings are not supported";
		var_fc8642f1 = name;
		if (IsSubStr(name, prefix))
		{
			var_fc8642f1 = GetSubStr(name, prefix.size);
		}
		if (IsDefined(var_2741876d))
		{
			self.var_94ee23e0 setText("Dev Block strings are not supported" + var_fc8642f1 + "Dev Block strings are not supported" + var_2741876d + "Dev Block strings are not supported");
		}
		else
		{
			self.var_94ee23e0 setText("Dev Block strings are not supported" + var_fc8642f1);
		}
		wait(1);
		if ("Dev Block strings are not supported" == name)
		{
			self.var_94ee23e0 fadeOverTime(1);
			self.var_94ee23e0.alpha = 0;
		}
	#/
}

/*
	Name: function_47db72b6
	Namespace: bgb
	Checksum: 0x5B63E5FA
	Offset: 0x1A70
	Size: 0xF3
	Parameters: 1
	Flags: None
*/
function function_47db72b6(bgb)
{
	/#
		PrintTopRightln(bgb + "Dev Block strings are not supported" + self.bgb_stats[bgb].var_e0b06b47, (1, 1, 1));
		PrintTopRightln(bgb + "Dev Block strings are not supported" + self.bgb_stats[bgb].bgb_used_this_game, (1, 1, 1));
		var_e4140345 = self.bgb_stats[bgb].var_e0b06b47 - self.bgb_stats[bgb].bgb_used_this_game;
		PrintTopRightln(bgb + "Dev Block strings are not supported" + var_e4140345, (1, 1, 1));
	#/
}

function private has_consumable_bgb(bgb)
{
	if (!IsDefined(self.bgb_stats[bgb]) || !IS_TRUE(level.bgb[bgb].consumable))
	{
		return false;
	}
	else
	{
		return true;
	}
}

/*
	Name: function_66a597c1
	Namespace: bgb
	Checksum: 0xA2DCCF17
	Offset: 0x1BE0
	Size: 0x153
	Parameters: 1
	Flags: None
*/
function function_66a597c1(bgb)
{
	if (!has_consumable_bgb(bgb))
	{
		return;
	}

	if (IsDefined(level.bgb[bgb].var_35e23ba2) && ![[ level.bgb[bgb].var_35e23ba2 ]]())
	{
		return;
	}

	self.bgb_stats[bgb].bgb_used_this_game++;

	self flag::set("used_consumable");
	zm_utility::increment_zm_dash_counter("consumables_used", 1);

	if (level flag::exists("first_consumables_used"))
	{
		level flag::set("first_consumables_used");
	}

	self LUINotifyEvent(&"zombie_bgb_used", 1, level.bgb[bgb].item_index);

	/#
		function_47db72b6(bgb);
	#/
}

function get_bgb_available(bgb)
{
	if (!IsDefined(self.bgb_stats[bgb]))
	{
		return true;
	}
	var_3232aae6 = self.bgb_stats[bgb].var_e0b06b47;
	var_8e01583 = self.bgb_stats[bgb].bgb_used_this_game;
	var_c6b3f8bc = var_3232aae6 - var_8e01583;
	return var_c6b3f8bc > 0;
}

/*
	Name: function_c3e0b2ba
	Namespace: bgb
	Checksum: 0xD1A78E06
	Offset: 0x1DD8
	Size: 0xC3
	Parameters: 2
	Flags: Private
*/
function private function_c3e0b2ba(bgb)
{
	if (!IS_TRUE(level.bgb[bgb].var_7ca0e2a7))
	{
		return;
	}

	var_b0106e56 = self EnableInvulnerability();

	self util::waittill_any_timeout(2, "bgb_bubble_blow_complete");

	if (IsDefined(self) && var_b0106e56)
	{
		self DisableInvulnerability();
	}
}

function bgb_gumball_anim(bgb, activating)
{
	self endon("disconnect");
	level endon("end_game");

	unlocked = function_64f7cbc3();
	if (activating)
	{
		self thread function_c3e0b2ba(bgb);
		self thread zm_audio::create_and_play_dialog("bgb", "eat");
	}
	
	while (self IsSwitchingWeapons())
	{
		self waittill("weapon_change_complete");
	}

	gun = self bgb_play_gumball_anim_begin(bgb, activating);
	evt = self util::waittill_any_return("fake_death", "death", "player_downed", "weapon_change_complete", "disconnect");

	succeeded = false;
	if (evt == "weapon_change_complete")
	{
		succeeded = true;

		if (activating)
		{
			if (IS_TRUE(level.bgb[bgb].var_7ea552f4) || self function_b616fe7a(true))
			{
				self notify("hash_83da9d01", bgb);
				self activation_start();
				self thread run_activation_func(bgb);
			}
			else
			{
				succeeded = false;
			}
		}
		else if (!IS_TRUE(unlocked))
		{
			return false;
		}

		self notify("hash_fcbbef99", bgb);
		self thread give(bgb);

		self zm_stats::increment_client_stat("bgbs_chewed");
		self zm_stats::increment_player_stat("bgbs_chewed");
		self zm_stats::increment_challenge_stat("GUM_GOBBLER_CONSUME");
		self AddDStat("ItemStats", level.bgb[bgb].item_index, "stats", "used", "statValue", 1);

		health = 0;
		if (IsDefined(self.health))
		{
			health = self.health;
		}

		self RecordMapEvent(4, GetTime(), self.origin, level.round_number, level.bgb[bgb].item_index, health);
		demo::bookmark("zm_player_bgb_grab", GetTime(), self);

		if (SessionModeIsOnlineGame())
		{
			util::function_a4c90358("zm_bgb_consumed", 1);
		}
	}
	self bgb_play_gumball_anim_end(gun, bgb, activating);
	return succeeded;
}

function private run_activation_func(bgb)
{
	self endon("disconnect");

	self set_active(true);
	self do_one_shot_use();
	self notify("hash_95b677dc");
	self [[ level.bgb[bgb].activation_func ]]();
	self set_active(false);
	self activation_complete();
}

function private bgb_get_gumball_anim_weapon(bgb, activating)
{
	if (activating)
	{
		return level.weaponBGBUse;
	}
	return level.weaponBGBGrab;
}

function private bgb_play_gumball_anim_begin(bgb, activating)
{
	self zm_utility::increment_is_drinking();

	self zm_utility::disable_player_move_states(true);

	w_original = self GetCurrentWeapon();

	weapon = bgb_get_gumball_anim_weapon(bgb, activating);

	self GiveWeapon(weapon, self CalcWeaponOptions(level.bgb[bgb].camo_index, 0, 0));
	self SwitchToWeapon(weapon);

	if (weapon == level.weaponBGBGrab)
	{
		self playsound("zmb_bgb_powerup_default");
	}

	if (weapon == level.weaponBGBUse)
	{
		self clientfield::increment_to_player(BGB_BLOW_BUBBLE_CF_NAME);
	}

	return w_original;
}

function private bgb_play_gumball_anim_end(w_original, bgb, activating)
{
	/#
		Assert(!w_original.isPerkBottle);
	#/
	/#
		Assert(w_original != level.weaponReviveTool);
	#/

	self zm_utility::enable_player_move_states();

	weapon = bgb_get_gumball_anim_weapon(bgb, activating);

	if (self laststand::player_is_in_laststand() || IS_TRUE(self.intermission))
	{
		self TakeWeapon(weapon);
		return;
	}

	self TakeWeapon(weapon);

	if (self zm_utility::is_multiple_drinking())
	{
		self zm_utility::decrement_is_drinking();
		return;
	}
	else if (w_original != level.weaponNone && !zm_utility::is_placeable_mine(w_original) && !zm_equipment::is_equipment_that_blocks_purchase(w_original))
	{
		self zm_weapons::switch_back_primary_weapon(w_original);
		if (zm_utility::is_melee_weapon(w_original))
		{
			self zm_utility::decrement_is_drinking();
			return;
		}
	}
	else
	{
		self zm_weapons::switch_back_primary_weapon();
	}

	self util::waittill_any_timeout(1, "weapon_change_complete");

	if (!self laststand::player_is_in_laststand() && (!IsDefined(self.intermission) && self.intermission))
	{
		self zm_utility::decrement_is_drinking();
	}
}

function private bgb_clear_monitors_and_clientfields()
{
	self notify("bgb_limit_monitor");
	self notify("bgb_activation_monitor");

	self clientfield::set_player_uimodel(BGB_DISPLAY_CF_NAME, 0);
	self clientfield::set_player_uimodel(BGB_ACTIVATIONS_REMAINING_CF_NAME, 0);
	self clear_timer();
}

function private bgb_limit_monitor()
{
	self endon("disconnect");
	self endon("bgb_update");

	self notify("bgb_limit_monitor");
	self endon("bgb_limit_monitor");

	self clientfield::set_player_uimodel(BGB_DISPLAY_CF_NAME, 1);
	self thread function_5fc6d844(self.bgb);

	switch(level.bgb[self.bgb].limit_type)
	{
		case "activated":
			self thread bgb_activation_monitor();

			for (i = level.bgb[self.bgb].limit; i > 0; i--)
			{
				level.bgb[self.bgb].var_32fa3cb7 = i;
				if (level.bgb[self.bgb].var_336ffc4e)
				{
					fill_timer();
				}
				else
				{
					self set_timer(i, level.bgb[self.bgb].limit);
				}
				self clientfield::set_player_uimodel(BGB_ACTIVATIONS_REMAINING_CF_NAME, i);

				self thread bgb_set_debug_text(self.bgb, i);
				self waittill("bgb_activation");
				while (IS_TRUE(self get_active())) // if we have a long, timed activation period, wait for that to end before updating the remaining-activations ui
				{
					WAIT_SERVER_FRAME;
				}
				self PlaySoundToPlayer("zmb_bgb_power_decrement", self);
			}
			level.bgb[self.bgb].var_32fa3cb7 = 0;
			self PlaySoundToPlayer("zmb_bgb_power_done_delayed", self);

			self set_timer(0, level.bgb[self.bgb].limit);
			while (IS_TRUE(self.bgb_activation_in_progress))
			{
				WAIT_SERVER_FRAME;
			}
			break;

		case "time":
			self thread bgb_set_debug_text(self.bgb);
			self thread run_timer(level.bgb[self.bgb].limit);
			wait(level.bgb[self.bgb].limit);
			self PlaySoundToPlayer("zmb_bgb_power_done", self);
			break;

		case "rounds":
			self thread bgb_set_debug_text(self.bgb);
			count = level.bgb[self.bgb].limit + 1;
			for (i = 0; i < count; i++)
			{
				self set_timer(count - i, count);
				level waittill("end_of_round");
				self PlaySoundToPlayer("zmb_bgb_power_decrement", self);
			}
			self PlaySoundToPlayer("zmb_bgb_power_done_delayed", self);
			break;

		case "event":
			self thread bgb_set_debug_text(self.bgb);
			self bgb_set_timer_clientfield(1);
			self [[ level.bgb[self.bgb].limit ]]();
			self PlaySoundToPlayer("zmb_bgb_power_done_delayed", self);
			break;

		default:
			/#
				Assert(false, "Dev Block strings are not supported" + self.bgb + "Dev Block strings are not supported" + level.bgb[self.bgb].limit_type + "Dev Block strings are not supported");
			#/
	}
	self thread take();
}

// takes the bgb on "bled_out", but sends notify ahead of time
function private bgb_bled_out_monitor()
{
	self endon("disconnect");
	self endon("bgb_update");

	self notify("bgb_bled_out_monitor");
	self endon("bgb_bled_out_monitor");

	self waittill("bled_out");

	self notify("bgb_about_to_take_on_bled_out");

	wait(0.1); // need a wait here; otherwise nothing gets a chance to respond to the "bgb_about_to_take_on_bled_out" notify before take() gets called

	self thread take();
}

function private bgb_activation_monitor()
{
	self endon("disconnect");

	self notify("bgb_activation_monitor");
	self endon("bgb_activation_monitor");

	if ("activated" != level.bgb[self.bgb].limit_type)
	{
		return;
	}

	for(;;)
	{
		self waittill("bgb_activation_request");

		if (!self function_b616fe7a(false))
		{
			continue;
		}

		if (self bgb_gumball_anim(self.bgb, true))
		{
			self notify("bgb_activation", self.bgb);
		}
	}
}

/*
	Name: function_b616fe7a
	Namespace: bgb
	Checksum: 0x17FBD8B1
	Offset: 0x2E18
	Size: 0x143
	Parameters: 1
	Flags: Private
*/
function private function_b616fe7a(b_chewing = false)
{
	var_bb1d9487 = IsDefined(level.bgb[self.bgb].validation_func) && !self [[ level.bgb[self.bgb].validation_func ]]();
	var_847ec8da = IsDefined(level.var_9cef605e) && !self [[ level.var_9cef605e ]]();
	if (!b_chewing && IS_DRINKING(self.is_drinking) || IS_TRUE(self.bgb_activation_in_progress) || self laststand::player_is_in_laststand() || var_bb1d9487 || var_847ec8da)
	{
		self clientfield::increment_uimodel(BGB_INVALID_USE_CF_NAME);
		self PlayLocalSound("zmb_bgb_deny_plr");
		return false;
	}
	return true;
}

/*
	Name: function_5fc6d844
	Namespace: bgb
	Checksum: 0x542A2377
	Offset: 0x2F68
	Size: 0xA3
	Parameters: 1
	Flags: Private
*/
function private function_5fc6d844(bgb)
{
	self endon("disconnect");
	self endon("bled_out");
	self endon("bgb_update");

	if (IS_TRUE(level.bgb[bgb].var_50fe45f6))
	{
		function_650ca64(N_BGB_UIMODEL_CANCEL);
	}
	else
	{
		return;
	}

	self waittill("bgb_activation_request");

	self thread take();
}

/*
	Name: function_650ca64
	Namespace: bgb
	Checksum: 0x981D146B
	Offset: 0x3018
	Size: 0x4B
	Parameters: 1
	Flags: None
*/
function function_650ca64(n_value)
{
	self SetActionSlot(1, "bgb");
	self clientfield::set_player_uimodel(BGB_ACTIVATIONS_REMAINING_CF_NAME, n_value);
}

/*
	Name: function_eabb0903
	Namespace: bgb
	Checksum: 0x5CF03FCD
	Offset: 0x3070
	Size: 0x2B
	Parameters: 1
	Flags: None
*/
function function_eabb0903(n_value)
{
	self clientfield::set_player_uimodel(BGB_ACTIVATIONS_REMAINING_CF_NAME, 0);
}

/*
	Name: function_336ffc4e
	Namespace: bgb
	Checksum: 0xEF99BB19
	Offset: 0x30A8
	Size: 0x27
	Parameters: 1
	Flags: None
*/
function function_336ffc4e(name)
{
	level.bgb[name].var_336ffc4e = true;
}

function do_one_shot_use(skip_demo_bookmark = false)
{
	self clientfield::increment_uimodel(BGB_ONE_SHOT_USE_CF_NAME);

	if (!skip_demo_bookmark)
	{
		demo::bookmark("zm_player_bgb_activate", GetTime(), self);
	}
}

function private activation_start()
{
	self.bgb_activation_in_progress = true;
}

function private activation_complete()
{
	self.bgb_activation_in_progress = false;
	self notify("activation_complete");
}

function private set_active(b_active)
{
	self.bgb_active = b_active;
}

function get_active()
{
	return IS_TRUE(self.bgb_active);
}

function is_active(name)
{
	if (!IsDefined(self.bgb))
	{
		return false;
	}

	return self.bgb == name && IS_TRUE(self.bgb_active);
}

function is_team_active(name)
{
	foreach (player in level.players)
	{
		if (player is_active(name))
		{
			return true;
		}
	}
	return false;
}

function increment_ref_count(name)
{
	if (!IsDefined(level.bgb[name]))
	{
		return 0;
	}

	var_ad8303b0 = level.bgb[name].ref_count;
	level.bgb[name].ref_count++;
	return var_ad8303b0;
}

function decrement_ref_count(name)
{
	if (!IsDefined(level.bgb[name]))
	{
		return 0;
	}

	level.bgb[name].ref_count--;
	return level.bgb[name].ref_count;
}

function private calc_remaining_duration_lerp(start_time, end_time)
{
	if (end_time - start_time <= 0)
	{
		return 0;
	}
	
	now = GetTime();
	frac = float(end_time - now) / float(end_time - start_time);
	return math::clamp(frac, 0, 1);
}

/*
	Name: function_f9fad8b3
	Namespace: bgb
	Checksum: 0xCDE8A8E
	Offset: 0x3430
	Size: 0xD7
	Parameters: 2
	Flags: Private
*/
function private function_f9fad8b3(var_eeab9300, percent)
{
	self endon("disconnect");
	self endon("hash_f9fad8b3");

	start_time = GetTime();
	end_time = start_time + BGB_TIMER_MANUAL_LERP_PERIOD;
	var_6d8b0ec7 = var_eeab9300;
	while (var_6d8b0ec7 > percent)
	{
		var_6d8b0ec7 = LerpFloat(percent, var_eeab9300, calc_remaining_duration_lerp(start_time, end_time));
		self clientfield::set_player_uimodel(BGB_TIMER_CF_NAME, var_6d8b0ec7);
		WAIT_SERVER_FRAME;
	}
}

function private bgb_set_timer_clientfield(percent)
{
	self notify("hash_f9fad8b3");

	var_eeab9300 = self clientfield::get_player_uimodel(BGB_TIMER_CF_NAME);
	if (percent < var_eeab9300 && BGB_TIMER_MANUAL_LERP_THRESHOLD <= var_eeab9300 - percent)
	{
		self thread function_f9fad8b3(var_eeab9300, percent);
	}
	else
	{
		self clientfield::set_player_uimodel(BGB_TIMER_CF_NAME, percent);
	}
}

function private fill_timer()
{
	self bgb_set_timer_clientfield(1);
}

function set_timer(current, max)
{
	self bgb_set_timer_clientfield(current / max);
}

function run_timer(max)
{
	self endon("disconnect");

	self notify("bgb_run_timer");
	self endon("bgb_run_timer");

	for (current = max; current > 0; current -= SERVER_FRAME)
	{
		self set_timer(current, max);
		WAIT_SERVER_FRAME;
	}

	self clear_timer();
}

function clear_timer()
{
	self bgb_set_timer_clientfield(0);
	self notify("bgb_run_timer");
}

function register(name, limit_type, limit, enable_func, disable_func, validation_func, activation_func)
{
	/#
		Assert(IsDefined(name), "Dev Block strings are not supported");
	#/
	/#
		Assert("Dev Block strings are not supported" != name, "Dev Block strings are not supported" + "Dev Block strings are not supported" + "Dev Block strings are not supported");
	#/
	/#
		Assert(!IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/

	/#
		Assert(IsDefined(limit_type), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	/#
		Assert(IsDefined(limit), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/

	/#
		Assert(!IsDefined(enable_func) || IsFunctionPtr(enable_func), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	/#
		Assert(!IsDefined(disable_func) || IsFunctionPtr(disable_func), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/

	switch(limit_type)
	{
		case "activated":
			/#
				Assert(!IsDefined(validation_func) || IsFunctionPtr(validation_func), "Dev Block strings are not supported" + name + "Dev Block strings are not supported" + limit_type + "Dev Block strings are not supported");
			#/
			/#
				Assert(IsDefined(activation_func), "Dev Block strings are not supported" + name + "Dev Block strings are not supported" + limit_type + "Dev Block strings are not supported");
			#/
			/#
				Assert(IsFunctionPtr(activation_func), "Dev Block strings are not supported" + name + "Dev Block strings are not supported" + limit_type + "Dev Block strings are not supported");
			#/
		case "rounds":
		case "time":
			/#
				Assert(IsInt(limit), "Dev Block strings are not supported" + name + "Dev Block strings are not supported" + limit + "Dev Block strings are not supported" + limit_type + "Dev Block strings are not supported");
			#/
			break;
		
		case "event":
			/#
				Assert(IsFunctionPtr(limit), "Dev Block strings are not supported" + name + "Dev Block strings are not supported" + limit_type + "Dev Block strings are not supported");
			#/
			break;

		default:
			/#
				Assert(false, "Dev Block strings are not supported" + name + "Dev Block strings are not supported" + limit_type + "Dev Block strings are not supported");
			#/
	}

	level.bgb[name] = SpawnStruct();
	level.bgb[name].name = name;
	level.bgb[name].limit_type = limit_type;
	level.bgb[name].limit = limit;
	level.bgb[name].enable_func = enable_func;
	level.bgb[name].disable_func = disable_func;
	if ("activated" == limit_type)
	{
		level.bgb[name].validation_func = validation_func;
		level.bgb[name].activation_func = activation_func;
		level.bgb[name].var_336ffc4e = false;
	}
	level.bgb[name].ref_count = 0;
}

function register_actor_damage_override(name, actor_damage_override_func)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].actor_damage_override_func = actor_damage_override_func;
}

function register_vehicle_damage_override(name, vehicle_damage_override_func)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].vehicle_damage_override_func = vehicle_damage_override_func;
}

function register_actor_death_override(name, actor_death_override_func)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].actor_death_override_func = actor_death_override_func;
}

function register_lost_perk_override(name, lost_perk_override_func, lost_perk_override_func_always_run)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].lost_perk_override_func = lost_perk_override_func;
	level.bgb[name].lost_perk_override_func_always_run = lost_perk_override_func_always_run;
}

function register_add_to_player_score_override(name, add_to_player_score_override_func, add_to_player_score_override_func_always_run)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].add_to_player_score_override_func = add_to_player_score_override_func;
	level.bgb[name].add_to_player_score_override_func_always_run = add_to_player_score_override_func_always_run;
}

/*
	Name: function_4cda71bf
	Namespace: bgb
	Checksum: 0xC631F42D
	Offset: 0x3EC8
	Size: 0x67
	Parameters: 2
	Flags: None
*/
function function_4cda71bf(name, var_7ca0e2a7)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].var_7ca0e2a7 = var_7ca0e2a7;
}

/*
	Name: function_93da425
	Namespace: bgb
	Checksum: 0xE1943FD8
	Offset: 0x3F38
	Size: 0x67
	Parameters: 2
	Flags: None
*/
function function_93da425(name, var_35e23ba2)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].var_35e23ba2 = var_35e23ba2;
}

/*
	Name: function_2060b89
	Namespace: bgb
	Checksum: 0x1163C55B
	Offset: 0x3FA8
	Size: 0x5F
	Parameters: 1
	Flags: None
*/
function function_2060b89(name)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].var_50fe45f6 = true;
}

/*
	Name: function_f132da9c
	Namespace: bgb
	Checksum: 0x3F20E3AF
	Offset: 0x4010
	Size: 0x5F
	Parameters: 1
	Flags: None
*/
function function_f132da9c(name)
{
	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/
	level.bgb[name].var_7ea552f4 = true;
}

/*
	Name: function_d35f60a1
	Namespace: bgb
	Checksum: 0xA8E2EFFA
	Offset: 0x4078
	Size: 0x4B
	Parameters: 1
	Flags: None
*/
function function_d35f60a1(name)
{
	unlocked = function_64f7cbc3();
	if (unlocked)
	{
		self give(name);
	}
}

function give(name)
{
	self thread take();

	if ("none" == name)
	{
		return;
	}

	/#
		Assert(IsDefined(level.bgb[name]), "Dev Block strings are not supported" + name + "Dev Block strings are not supported");
	#/

	self notify("bgb_update", name, self.bgb);
	self notify("bgb_update_give_" + name);

	self.bgb = name;

	self clientfield::set_player_uimodel(BGB_CURRENT_CF_NAME, level.bgb[name].item_index);
	self LUINotifyEvent(&"zombie_bgb_notification", 1, level.bgb[name].item_index);

	if (IsDefined(level.bgb[name].enable_func))
	{
		self thread [[ level.bgb[name].enable_func ]]();
	}

	if (IsDefined("activated" == level.bgb[name].limit_type))
	{
		self SetActionSlot(1, "bgb");
	}

	self thread bgb_limit_monitor();
	self thread bgb_bled_out_monitor();
}

function take()
{
	if ("none" == self.bgb)
	{
		return;
	}

	self SetActionSlot(1, "");

	self thread bgb_set_debug_text("none");

	if (IsDefined(level.bgb[self.bgb].disable_func))
	{
		self thread [[ level.bgb[self.bgb].disable_func ]]();
	}

	self bgb_clear_monitors_and_clientfields();

	self notify("bgb_update", "none", self.bgb);
	self notify("bgb_update_take_" + self.bgb);

	self.bgb = "none";
}

function get_enabled()
{
	return self.bgb;
}

function is_enabled(name)
{
	/#
		Assert(IsDefined(self.bgb));
	#/
	return self.bgb == name;
}

function any_enabled()
{
	/#
		Assert(IsDefined(self.bgb));
	#/
	return self.bgb !== "none";
}

function is_team_enabled(str_name)
{
	foreach (player in level.players)
	{
		/#
			Assert(IsDefined(player.bgb));
		#/
		if (player.bgb == str_name)
		{
			return true;
		}
	}
	return false;
}

function get_player_dropped_powerup_origin()
{
	powerup_origin = self.origin + VectorScale(AnglesToForward((0, self GetPlayerAngles()[1], 0)), 60) + VectorScale((0, 0, 1), 5);
	self zm_stats::increment_challenge_stat("GUM_GOBBLER_POWERUPS");
	return powerup_origin;
}

/*
	Name: function_dea74fb0
	Namespace: bgb
	Checksum: 0xADF187F6
	Offset: 0x4598
	Size: 0xC3
	Parameters: 2
	Flags: None
*/
function function_dea74fb0(str_powerup, v_origin)
{
	if (!IsDefined(v_origin))
	{
		v_origin = self get_player_dropped_powerup_origin();
	}

	e_powerup = zm_powerups::specific_powerup_drop(str_powerup, v_origin);

	wait(1);

	if (IsDefined(e_powerup) && (!e_powerup zm::in_enabled_playable_area() && !e_powerup zm::in_life_brush()))
	{
		level thread function_434235f9(e_powerup);
	}
}

/*
	Name: function_434235f9
	Namespace: bgb
	Checksum: 0x7EED9115
	Offset: 0x4668
	Size: 0x37B
	Parameters: 1
	Flags: None
*/
function function_434235f9(e_powerup)
{
	if (!IsDefined(e_powerup))
	{
		return;
	}

	e_powerup Ghost();
	e_powerup.clone_model = util::spawn_model(e_powerup.model, e_powerup.origin, e_powerup.angles);
	e_powerup.clone_model LinkTo(e_powerup);

	direction = e_powerup.origin;
	direction = (direction[1], direction[0], 0);

	if (direction[1] < 0 || (direction[0] > 0 && direction[1] > 0))
	{
		direction = (direction[0], direction[1] * -1, 0);
	}
	else if (direction[0] < 0)
	{
		direction = (direction[0] * -1, direction[1], 0);
	}

	if (!IS_TRUE(e_powerup.sndNoSamLaugh))
	{
		players = GetPlayers();
		for (i = 0; i < players.size; i++)
		{
			if (IsAlive(players[i]))
			{
				players[i] PlayLocalSound(level.zmb_laugh_alias);
			}
		}
	}

	PlayFXOnTag(level._effect["samantha_steal"], e_powerup, "tag_origin");
	e_powerup.clone_model Unlink();
	e_powerup.clone_model MoveZ(60, 1, 0.25, 0.25);
	e_powerup.clone_model Vibrate(direction, 1.5, 2.5, 1);
	e_powerup.clone_model waittill("movedone");

	if (IsDefined(self.damagearea))
	{
		self.damagearea Delete();
	}

	e_powerup.clone_model Delete();
	if (IsDefined(e_powerup))
	{
		if (IsDefined(e_powerup.damagearea))
		{
			e_powerup.damagearea Delete();
		}
		e_powerup zm_powerups::powerup_delete();
	}
}

function actor_damage_override(inflictor, attacker, damage, flags, meansOfDeath, weapon, vPoint, vDir, sHitLoc, psOffsetTime, boneIndex, surfaceType)
{
	if (!IS_TRUE(level.bgb_in_use))
	{
		return damage;
	}

	if (IsPlayer(attacker))
	{
		name = attacker get_enabled(); // get the name of the attacking player's bgb

		if (name !== "none" && IsDefined(level.bgb[name]) && IsDefined(level.bgb[name].actor_damage_override_func))
		{
			damage = [[ level.bgb[name].actor_damage_override_func ]](inflictor, attacker, damage, flags, meansOfDeath, weapon, vPoint, vDir, sHitLoc, psOffsetTime, boneIndex, surfaceType);
		}
	}
	return damage;
}

function vehicle_damage_override(eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, weapon, vPoint, vDir, sHitLoc, vDamageOrigin, psOffsetTime, damageFromUnderneath, modelIndex, partName, vSurfaceNormal)
{
	if (!IS_TRUE(level.bgb_in_use))
	{
		return iDamage;
	}

	if (IsPlayer(eAttacker))
	{
		name = eAttacker get_enabled(); // get the name of the attacking player's bgb

		if (name !== "none" && IsDefined(level.bgb[name]) && IsDefined(level.bgb[name].vehicle_damage_override_func))
		{
			iDamage = [[ level.bgb[name].vehicle_damage_override_func ]](eInflictor, eAttacker, iDamage, iDFlags, sMeansOfDeath, weapon, vPoint, vDir, sHitLoc, vDamageOrigin, psOffsetTime, damageFromUnderneath, modelIndex, partName, vSurfaceNormal);
		}
	}
	return iDamage;
}

function actor_death_override(attacker)
{
	if (!IS_TRUE(level.bgb_in_use))
	{
		return 0;
	}

	if (IsPlayer(attacker))
	{
		name = attacker get_enabled();
		if (name !== "none" && IsDefined(level.bgb[name]) && IsDefined(level.bgb[name].actor_death_override_func))
		{
			damage = [[ level.bgb[name].actor_death_override_func ]](attacker);
		}
	}
	return damage;
}

function lost_perk_override(perk)
{
	b_result = false; // by default, won't interfere with normal loss of the perk

	if (!IS_TRUE(level.bgb_in_use))
	{
		return b_result;
	}
	if (!IS_TRUE(self.laststand))
	{
		return b_result;
	}

	keys = GetArrayKeys(level.bgb);
	for (i = 0; i < keys.size; i++)
	{
		name = keys[i];
		if (IS_TRUE(level.bgb[name].lost_perk_override_func_always_run) && IsDefined(level.bgb[name].lost_perk_override_func))
		{
			b_result = [[ level.bgb[name].lost_perk_override_func ]](perk, self, undefined);
			if (b_result)
			{
				return b_result;
			}
		}
	}

	foreach (player in level.activePlayers)
	{
		name = player get_enabled(); // get the name of the player's bgb

		// if there's a lost perk override func associated with the player's bgb, call it, allowing it to prevent loss of the perk if desired
		if (name !== "none" && IsDefined(level.bgb[name]) && IsDefined(level.bgb[name].lost_perk_override_func))
		{
			b_result = [[ level.bgb[name].lost_perk_override_func ]](perk, self, player);
			if (b_result)
			{
				return b_result;
			}
		}
	}

	return b_result;
}

function add_to_player_score_override(n_points, str_awarded_by)
{
	if (!IS_TRUE(level.bgb_in_use))
	{
		return n_points;
	}

	str_enabled = self get_enabled(); // get the name of the attacking player's bgb

	keys = GetArrayKeys(level.bgb);
	for (i = 0; i < keys.size; i++)
	{
		str_bgb = keys[i];
		if (str_bgb === str_enabled)
		{
			continue;
		}
		if (IS_TRUE(level.bgb[str_bgb].add_to_player_score_override_func_always_run) && IsDefined(level.bgb[str_bgb].add_to_player_score_override_func))
		{
			n_points = [[ level.bgb[str_bgb].add_to_player_score_override_func ]](n_points, str_awarded_by, false);
		}
	}
	if (str_enabled !== "none" && IsDefined(level.bgb[str_enabled]) && IsDefined(level.bgb[str_enabled].add_to_player_score_override_func))
	{
		n_points = [[ level.bgb[str_enabled].add_to_player_score_override_func ]](n_points, str_awarded_by, true);
	}
	return n_points;
}

/*
	Name: function_d51db887
	Namespace: bgb
	Checksum: 0x5FCF4FAE
	Offset: 0x51D8
	Size: 0xC3
	Parameters: 0
	Flags: None
*/
function function_d51db887()
{
	keys = array::randomize(GetArrayKeys(level.bgb));
	for (i = 0; i < keys.size; i++)
	{
		if (level.bgb[keys[i]].rarity != BGB_RARITY_MEGA_INDEX)
		{
			continue;
		}
		if (level.bgb[keys[i]].dlc_index > 0)
		{
			continue;
		}
		return keys[i];
	}
}

/*
	Name: function_4ed517b9
	Namespace: bgb
	Checksum: 0x23D70B86
	Offset: 0x52A8
	Size: 0x20B
	Parameters: 3
	Flags: None
*/
function function_4ed517b9(n_max_distance, var_98a3e738, var_287a7adb)
{
	self endon("disconnect");
	self endon("bled_out");
	self endon("bgb_update");

	self.var_6638f10b = [];

	for(;;)
	{
		foreach (e_player in level.players)
		{
			if (e_player == self)
			{
				continue;
			}

			array::remove_undefined(self.var_6638f10b);
			var_368e2240 = array::contains(self.var_6638f10b, e_player);
			var_50fd5a04 = zm_utility::is_player_valid(e_player, false, true) && function_2469cfe8(n_max_distance, self, e_player);
			if (!var_368e2240 && var_50fd5a04)
			{
				array::add(self.var_6638f10b, e_player, false);
				if (IsDefined(var_98a3e738))
				{
					self thread [[ var_98a3e738 ]](e_player);
				}
				continue;
			}
			if (var_368e2240 && !var_50fd5a04)
			{
				ArrayRemoveValue(self.var_6638f10b, e_player);
				if (IsDefined(var_287a7adb))
				{
					self thread [[ var_287a7adb ]](e_player);
				}
			}
		}
		WAIT_SERVER_FRAME;
	}
}

/*
	Name: function_2469cfe8
	Namespace: bgb
	Checksum: 0x6C2A4F72
	Offset: 0x54C0
	Size: 0x7D
	Parameters: 3
	Flags: Private
*/
function private function_2469cfe8(n_distance, var_d21815c4, var_441f84ff)
{
	var_31dc18aa = SQR(n_distance);
	var_2931dc75 = DistanceSquared(var_d21815c4.origin, var_441f84ff.origin);
	if (var_2931dc75 <= var_31dc18aa)
	{
		return true;
	}
	return false;
}

/*
	Name: function_ca189700
	Namespace: bgb
	Checksum: 0x194165CC
	Offset: 0x5548
	Size: 0x43
	Parameters: 0
	Flags: None
*/
function function_ca189700()
{
	self clientfield::increment_uimodel(BGB_INVALID_USE_CF_NAME);
	self PlayLocalSound("zmb_bgb_deny_plr");
}

function suspend_weapon_cycling()
{
	self flag::clear("bgb_weapon_cycling");
}

function resume_weapon_cycling()
{
	self flag::set("bgb_weapon_cycling");
}

function init_weapon_cycling()
{
	if (!self flag::exists("bgb_weapon_cycling"))
	{
		self flag::init("bgb_weapon_cycling");
	}
	self flag::set("bgb_weapon_cycling");
}

function weapon_cycling_waittill_active()
{
	self flag::wait_till("bgb_weapon_cycling");
}

function revive_and_return_perk_on_bgb_activation(perk)
{
	self endon("disconnect");
	self endon("bled_out");
	
	self notify("revive_and_return_perk_on_bgb_activation" + perk);
	self endon("revive_and_return_perk_on_bgb_activation" + perk);
	
	if (perk == PERK_WIDOWS_WINE)
	{
		var_376ad33c = self GetWeaponAmmoClip(self.current_lethal_grenade);
	}

	self waittill("player_revived", e_reviver);

	if (IS_TRUE(self.var_df0decf1) || (IsDefined(e_reviver) && (IsDefined(self.bgb) && self is_enabled("zm_bgb_near_death_experience")) || (IsDefined(e_reviver.bgb) && e_reviver is_enabled("zm_bgb_near_death_experience"))))
	{
		if (zm_perks::use_solo_revive() && perk == PERK_QUICK_REVIVE)
		{
			level.solo_game_free_player_quickrevive = 1;
		}

		WAIT_SERVER_FRAME;

		self thread zm_perks::give_perk(perk, false);

		if (perk == PERK_WIDOWS_WINE && IsDefined(var_376ad33c))
		{
			self SetWeaponAmmoClip(self.current_lethal_grenade, var_376ad33c);
		}
	}
}

/*
	Name: function_7d63d2eb
	Namespace: bgb
	Checksum: 0x37E45910
	Offset: 0x5848
	Size: 0x71
	Parameters: 0
	Flags: None
*/
function function_7d63d2eb()
{
	self endon("disconnect");
	self endon("death");

	self.var_df0decf1 = true;

	self waittill("player_revived", e_reviver);

	WAIT_SERVER_FRAME;

	if (IS_TRUE(self.var_df0decf1))
	{
		self notify("bgb_revive");
		self.var_df0decf1 = undefined;
	}
}
