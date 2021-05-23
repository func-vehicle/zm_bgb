#using scripts\codescripts\struct;

#using scripts\shared\callbacks_shared;
#using scripts\shared\clientfield_shared;
#using scripts\shared\system_shared;
#using scripts\shared\util_shared;

#using scripts\zm\_load;
#using scripts\zm\_zm_bgb_machine;

#insert scripts\zm\_zm_bgb.gsh

#namespace bgb;


REGISTER_SYSTEM_EX( "bgb", &__init__, &__main__, undefined )

function __init__()
{
	if (!IS_TRUE(level.bgb_in_use))
	{
		return;
	}
	
	level.weaponBGBGrab = GetWeapon("zombie_bgb_grab");

	callback::on_localclient_connect(&on_player_connect);

	level.bgb = []; // array for actual buffs
	level.bgb_pack = [];

	clientfield::register("clientuimodel", BGB_CURRENT_CF_NAME, 1, 8, "int", &bgb_store_current, 0, 0);
	clientfield::register("clientuimodel", BGB_DISPLAY_CF_NAME, 1, 1, "int", undefined, 0, 0);
	clientfield::register("clientuimodel", BGB_TIMER_CF_NAME, 1, 8, "float", undefined, 0, 0);
	clientfield::register("clientuimodel", BGB_ACTIVATIONS_REMAINING_CF_NAME, 1, 3, "int", undefined, 0, 0);
	clientfield::register("clientuimodel", BGB_INVALID_USE_CF_NAME, 1, 1, "counter", undefined, 0, 0);
	clientfield::register("clientuimodel", BGB_ONE_SHOT_USE_CF_NAME, 1, 1, "counter", undefined, 0, 0);

	clientfield::register("toplayer", BGB_BLOW_BUBBLE_CF_NAME, 1, 1, "counter", &bgb_blow_bubble, 0, 0);

	level._effect[BGB_BLOW_BUBBLE_FX_NAME] = BGB_BLOW_BUBBLE_FX;
}

function private __main__()
{
	if (!IS_TRUE(level.bgb_in_use))
	{
		return;
	}

	bgb_finalize();
}

function private on_player_connect(localClientNum)
{
	if (!IS_TRUE(level.bgb_in_use))
	{
		return;
	}

	self thread bgb_player_init(localClientNum);
}

function private bgb_player_init(localClientNum)
{
	if (IsDefined(level.bgb_pack[localClientNum]))
	{
		return;
	}

	level.bgb_pack[localClientNum] = GetBubblegumPack(localClientNum);
}

function private bgb_finalize()
{
	level.var_f3c83828 = [];
	level.var_f3c83828[0] = BGB_RARITY_CLASSIC_TAG;
	level.var_f3c83828[1] = BGB_RARITY_MEGA_TAG;
	level.var_f3c83828[2] = BGB_RARITY_RARE_TAG;
	level.var_f3c83828[3] = BGB_RARITY_ULTRA_RARE_TAG;
	level.var_f3c83828[4] = BGB_RARITY_WHIMSICAL_TAG;

	statsTableName = util::getStatsTableName();

	level.bgb_item_index_to_name = [];

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

		level.bgb[keys[i]].flying_gumball_tag = "tag_gumball_" + level.bgb[keys[i]].limit_type;
		level.bgb[keys[i]].give_gumball_tag = "tag_gumball_" + level.bgb[keys[i]].limit_type + "_" + level.var_f3c83828[level.bgb[keys[i]].rarity];

		level.bgb_item_index_to_name[level.bgb[keys[i]].item_index] = keys[i];
	}
}

function register(name, limit_type)
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

	level.bgb[name] = SpawnStruct();
	
	level.bgb[name].name = name;
	level.bgb[name].limit_type = limit_type;
}

/*
	Name: function_78c4bfa
	Namespace: bgb
	Checksum: 0x199C3CA9
	Offset: 0xAB0
	Size: 0x17B
	Parameters: 2
	Flags: Private
*/
function private function_78c4bfa(localClientNum, time)
{
	self endon("death");
	self endon("entityshutdown");

	if (IsDemoPlaying())
	{
		return;
	}
	if (!IsDefined(self.bgb) || !IsDefined(level.bgb[self.bgb]))
	{
		return;
	}
	switch(level.bgb[self.bgb].limit_type)
	{
		case "activated":
		{
			color = (25, 0, 50) / 255;
			break;
		}
		case "event":
		{
			color = (100, 50, 0) / 255;
			break;
		}
		case "rounds":
		{
			color = (1, 149, 244) / 255;
			break;
		}
		case "time":
		{
			color = (19, 244, 20) / 255;
			break;
		}
		case default:
		{
			return;
		}
	}
	self SetControllerLightbarColor(localClientNum, color);
	wait(time);
	if (IsDefined(self))
	{
		self SetControllerLightbarColor(localClientNum);
	}
}

function private bgb_store_current(localClientNum, oldVal, newVal, bNewEnt, bInitialSnap, fieldName, bWasTimeJump)
{
	self.bgb = level.bgb_item_index_to_name[newVal];
	self thread function_78c4bfa(localClientNum, 3);
}

function private bgb_play_fx_on_camera(localClientNum, FX)
{
	if (IsDefined(self.var_d7197e33))
	{
		DeleteFX(localClientNum, self.var_d7197e33, 1);
	}

	if (IsDefined(FX))
	{
		self.var_d7197e33 = PlayFXOnCamera(localClientNum, FX);
		self PlaySound(0, "zmb_bgb_blow_bubble_plr");
	}
}

function private bgb_blow_bubble(localClientNum, oldVal, newVal, bNewEnt, bInitialSnap, fieldName, bWasTimeJump)
{
	bgb_play_fx_on_camera(localClientNum, level._effect[BGB_BLOW_BUBBLE_FX_NAME]);
	self thread function_78c4bfa(localClientNum, 0.5);
}
