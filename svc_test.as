
const int SVC_TIME = 7;
const int SVC_CLIENTDATA = 15;
const int SVC_PACKETENTITIES = 40;
const int SVC_DELTAPACKETENTITIES = 41;
const int SVC_SPAWNSTATIC = 20;
const int SVC_PRINT = 8;
/*
class NetDelta {
	NetDelta(string name, int type, )
}
*/

class BitField
{
	array<uint8> data;
	
	int currentBit = 0;
	
	BitField() {}

	void writeBit(uint8 value) {
		//println("Write bit " + currentBit);
		uint oldSize = data.size();
		data.resize((currentBit / 8) + 1);
		
		if (oldSize != data.size()) {
			//println("Resize to " + data.size());
		}
		
		int byteIdx = currentBit / 8;
		int bitIdx = currentBit % 8;
		data[byteIdx] |= (value & 1) << bitIdx;
		
		currentBit++;
	}
	
	void writeByte(uint8 value) {
		for (int i = 0; i < 8; i++) {
			writeBit(value);
			value >>= 1;
		}
	}
	
	void writeShort(uint16 value) {
		for (int i = 0; i < 16; i++) {
			writeBit(value);
			value >>= 1;
		}
	}
}

void svc_packetentities(edict_t@ dest=null)
{
	// as_reloadplugin lagcompensator; map svc_test
	if (true) {
		array<uint8> bytes = {
			//0x14, 0x00, 0x60, 0xff, 0x00, 0x02, 0x64, 0x18, 0x00, 0x00, 0x00, 0x00
			0x14, 0x00, 0x60, 0xff, 0x00, 0x02, 0x64, 0x18, 0x00, 0x00, 0x00, 0x00
		};
		
		
		//NetworkMessage msg(MSG_ONE_UNRELIABLE, NetworkMessages::NetworkMessageType(SVC_DELTAPACKETENTITIES), dest);
		NetworkMessage msg(MSG_ONE_UNRELIABLE, NetworkMessages::NetworkMessageType(SVC_PACKETENTITIES), dest);
		for (uint i = 0; i < bytes.size(); i++) {
			msg.WriteByte(bytes[i]);
		}
		
		for (int i = 0; i < 22; i++) {
			msg.WriteByte(0x01);
		}
		
		msg.WriteByte(SVC_PRINT);
		msg.WriteChar("B");
		msg.WriteChar("B");		
		msg.WriteByte(0x00);
		
		msg.End();
		
		return;
	}
	

	BitField data;
	
	NetworkMessage msg(MSG_ONE, NetworkMessages::NetworkMessageType(SVC_TIME), dest);
	//NetworkMessage msg(MSG_ONE, NetworkMessages::NetworkMessageType(SVC_PACKETENTITIES), dest);
	//NetworkMessage msg(MSG_ONE, NetworkMessages::NetworkMessageType(SVC_DELTAPACKETENTITIES), dest);
	//NetworkMessage msg(MSG_ONE, NetworkMessages::NetworkMessageType(0x01), dest);
	
	// svc_time
	//msg.WriteFloat(g_Engine.time);
	
	/*
	// SVC_CLIENTDATA
	data.writeByte(SVC_CLIENTDATA);
	
	data.writeBit(0); // no delta-compression
	//data.writeByte(0); 
	
	int clientdata_t_fields = 34;
	for (int i = 0; i < clientdata_t_fields; i++) {
		data.writeBit(0); // write "not changed" for all fields
	}
	
	int max_weapons = 64;
	int weapondata_t_fields = 22;
	for (int i = 0; i < max_weapons; i++) {
		
		for (int k = 0; k < weapondata_t_fields; k++) {
			data.writeBit(0); // write "not changed" for all fields
		}
	}
	
	data.writeBit(0); // end marker
	*/
	
	msg.WriteFloat(0);
	msg.WriteByte(0x07); // svc_time
	msg.WriteFloat(0);
	
	//msg.WriteByte(SVC_DELTAPACKETENTITIES);
	data.writeByte(SVC_DELTAPACKETENTITIES);
	
	int entityCount = 0;
	for ( int i = 1; i <= g_Engine.maxEntities; i++ )
	{
		bool isPlayer = i <= g_Engine.maxClients;
		CBaseEntity@ ent = g_EntityFuncs.Instance(i);
		if (ent is null or string(ent.pev.classname) == '') {
			continue;
		}
		
		entityCount++;
	}
	
	data.writeShort(entityCount); // num_entities
	data.writeShort(10); // delta sequence
	//data.writeShort(0);
	
	data.writeByte(0);
	
	for ( int i = 1; i <= g_Engine.maxEntities; i++ )
	{
		bool isPlayer = i <= g_Engine.maxClients;
		CBaseEntity@ ent = g_EntityFuncs.Instance(i);
		if (ent is null or string(ent.pev.classname) == '') {
			continue;
		}
		
		println("Write delta for " + i + " " + ent.pev.classname);
		
		//msg.WriteShort(i); // entity index
		data.writeShort(i); // entity index
		
		// 2bits = remove type:
		// 0 = keep alive, has delta update
		// 1 = remove from delta message (but keep states)
		// 2 = complete remove from server
		data.writeBit(0);
		data.writeBit(0);
		
		// entity type changes? 1 = yes, 0 = no
		data.writeBit(0);
		
		int numDeltaFields = isPlayer ? 51 : 56;
		
		numDeltaFields = ((numDeltaFields + 7) / 8) * 8; // round to byte
		println("ROUND TO " + numDeltaFields);
		
		for (int k = 0; k < numDeltaFields; k++) {
			data.writeBit(0); // 0 = unchanged
		}
	}
	
	data.writeShort(0); // end of packetentities
	
	int rounded = ((data.data.size() + 3) / 4) * 4; // round data to nearest dword
	data.data.resize(rounded);
	
	println("Write " + data.currentBit + " bits or " + data.data.size() + " bytes");
	for (uint k = 0; k < data.data.size(); k++) {
		msg.WriteByte(data.data[k]);
	}
	
	for (int i = 0; i < 16; i++) {
		msg.WriteByte(0x07); // svc_time
		msg.WriteFloat(0);
	}
	
	msg.End();
}

void simplify_deltas() {
	//if (true) return;
	// reduce data in delta packets
	CBaseEntity@ ent2 = null;
	do {
		@ent2 = g_EntityFuncs.FindEntityByClassname(ent2, "player");
		if (ent2 !is null)
		{
			ent2.pev.animtime = 0;
			ent2.pev.frame = 0;
		}
	} while(ent2 !is null);
}

void print_delta(int idx, string name, int val) {
	print(name + " (" + idx + ") = " + val);
}

void print_delta(int idx, string name, float val) {
	print(name + " (" + idx + ") = " + val);
}

void update_delta(CBaseEntity@ ent, int idx, float fval, int ival) {

	array<edict_t@> edictChoices;
	for (int i = 0; i < g_Engine.maxEntities; i++) {
		edict_t@ ed = g_EntityFuncs.IndexEnt(ival);
		if (ed !is null) {
			edictChoices.insertLast(ed);
		}
	}
	
	if (idx == 9) {
		ival = ival == 0 ? 0 : MOVETYPE_PUSH;
	}
	
	array<string> modelChoices = {
		"*1",
		"*2"
	};

	switch(idx) {
		case 0: ent.pev.animtime = fval; print_delta(idx, "animtime", fval); break;
		case 1: ent.pev.frame = fval; print_delta(idx, "frame", fval); break;
		case 2: ent.pev.origin.x = fval; print_delta(idx, "origin[0]", fval); break;
		case 3: ent.pev.angles.x = fval; print_delta(idx, "angles[0]", fval); break;
		case 4: ent.pev.angles.y = fval; print_delta(idx, "angles[1]", fval); break;
		case 5: ent.pev.origin.y = fval; print_delta(idx, "origin[1]", fval); break;
		case 6: ent.pev.origin.z = fval; print_delta(idx, "origin[2]", fval); break;
		case 7: ent.pev.sequence = ival; print_delta(idx, "sequence", ival); break;
		case 8: g_EntityFuncs.SetModel(ent, modelChoices[ival % modelChoices.size()]); print_delta(idx, "modelidx", ent.pev.modelindex); break;
		case 9: ent.pev.movetype = ival; print_delta(idx, "movetype", ival); break;
		case 10: ent.pev.solid = ival; print_delta(idx, "solid", ival); break;
		case 11: ent.pev.mins.x = fval; print_delta(idx, "mins[0]", fval); break;
		case 12: ent.pev.mins.y = fval; print_delta(idx, "mins[1]", fval); break;
		case 13: ent.pev.mins.z = fval; print_delta(idx, "mins[2]", fval); break;
		case 14: ent.pev.maxs.x = fval; print_delta(idx, "maxs[0]", fval); break;
		case 15: ent.pev.maxs.y = fval; print_delta(idx, "maxs[1]", fval); break;
		case 16: ent.pev.maxs.z = fval; print_delta(idx, "maxs[2]", fval); break;
		case 17: ent.pev.endpos.x = fval; print_delta(idx, "endpos[0]", fval); break;
		case 18: ent.pev.endpos.y = fval; print_delta(idx, "endpos[1]", fval); break;
		case 19: ent.pev.endpos.z = fval; print_delta(idx, "endpos[2]", fval); break;
		case 20: ent.pev.startpos.x = fval; print_delta(idx, "startpos[0]", fval); break;
		case 21: ent.pev.startpos.y = fval; print_delta(idx, "startpos[1]", fval); break;
		case 22: ent.pev.startpos.z = fval; print_delta(idx, "startpos[2]", fval); break;
		case 23: ent.pev.impacttime = fval; print_delta(idx, "impacttime", fval); break;
		case 24: ent.pev.starttime = fval; print_delta(idx, "starttime", fval); break;
		case 25: ent.pev.weaponmodel = ival; print_delta(idx, "weaponmodel", ival); break;
		case 26: @ent.pev.owner = @edictChoices[ival % edictChoices.size()]; print_delta(idx, "owner", ival % edictChoices.size()); break;
		case 27: ent.pev.effects = ival; print_delta(idx, "effects", ival); break;
		case 28: ent.pev.angles.z = fval; print_delta(idx, "angles[2]", fval); break;
		case 29: ent.pev.colormap = ival; print_delta(idx, "colormap", ival); break;
		case 30: ent.pev.framerate = fval; print_delta(idx, "framerate", fval); break;
		case 31: ent.pev.skin = ival; print_delta(idx, "skin", ival); break;
		case 32: ent.pev.controller[0] = ival; print_delta(idx, "controller[0]", ival); break;
		case 33: ent.pev.controller[1] = ival; print_delta(idx, "controller[1]", ival); break;
		case 34: ent.pev.controller[2] = ival; print_delta(idx, "controller[2]", ival); break;
		case 35: ent.pev.controller[3] = ival; print_delta(idx, "controller[3]", ival); break;
		case 36: ent.pev.blending[0] = ival; print_delta(idx, "blending[0]", ival); break;
		case 37: ent.pev.blending[1] = ival; print_delta(idx, "blending[1]", ival); break;
		case 38: ent.pev.body = ival; print_delta(idx, "body", ival); break;
		case 39: ent.pev.rendermode = ival; print_delta(idx, "rendermode", ival); break;
		case 40: ent.pev.renderamt = fval; print_delta(idx, "renderamt", fval); break;
		case 41: ent.pev.renderfx = ival; print_delta(idx, "renderfx", ival); break;
		case 42: ent.pev.scale = fval; print_delta(idx, "scale", fval); break;
		case 43: ent.pev.rendercolor.x = fval; print_delta(idx, "rendercolor.r", fval); break;
		case 44: ent.pev.rendercolor.y = fval; print_delta(idx, "rendercolor.g", fval); break;
		case 45: ent.pev.rendercolor.z = fval; print_delta(idx, "rendercolor.b", fval); break;
		case 46: @ent.pev.aiment = @edictChoices[ival % edictChoices.size()]; print_delta(idx, "aiment", ival % edictChoices.size()); break;
		case 47: ent.pev.basevelocity.x = fval; print_delta(idx, "basevelocity[0]", fval); break;
		case 48: ent.pev.basevelocity.y = fval; print_delta(idx, "basevelocity[1]", fval); break;
		case 49: ent.pev.basevelocity.z = fval; print_delta(idx, "basevelocity[2]", fval); break;
		case 50: ent.pev.playerclass = ival; print_delta(idx, "playerclass", ival); break;
		case 51: ent.pev.fuser1 = fval; print_delta(idx, "fuser1", fval); break;
		case 52: ent.pev.fuser2 = fval; print_delta(idx, "fuser2", fval); break;
		case 53: ent.pev.iuser1 = ival; print_delta(idx, "iuser1", ival); break;
		case 54: ent.pev.gaitsequence = ival; print_delta(idx, "gaitsequence", ival); break;
		default: print("BAD DELTA IDX: " + idx);
	}
}

float lastSwitch = 0;
int lastIdx = 0;
CScheduledFunction@ svc_interval = null;
uint16 iTest = 0;
float fTest = 0;
int deltaIdx = 0;
void testo(CBaseEntity@ ent) {

	/*
	ent.pev.sequence += frame++ % 2 == 0 ? -1 : 2;
	if (ent.pev.sequence >= 255) {
		ent.pev.sequence = 0;
	}
	ent.pev.frame = 0;
	ent.pev.animtime = 0;
	println("SEQ " + ent.pev.sequence);
	*/
	//ent.pev.rendermode = ent.pev.rendermode == 0 ? 1 : 0;

	
	fTest += 32.0*g_Engine.frametime;
	if (fTest > 256) {
		fTest = 0;
	}
	//iTest += 1;
	
	
	//iTest = iTest != 0 ? 0 : 1;
	//fTest = fTest != 0 ? 0 : 1;
	
	//iTest = Math.RandomLong(0, 256);
	//fTest = Math.RandomFloat(0, 256);
	
	if (false && g_Engine.time - lastSwitch > 1.5f) {
		lastSwitch = g_Engine.time;
		deltaIdx = (deltaIdx + 1) % 55;
		if (deltaIdx == 0) 
			deltaIdx = 1;
			
		while (deltaIdx == 8 || deltaIdx == 23 || deltaIdx == 24 || deltaIdx == 25 || deltaIdx == 46 || deltaIdx == 48 || deltaIdx == 49) {
			println("SKIP");
			deltaIdx++;
		}
	}
	
	//update_delta(ent, deltaIdx, fTest, iTest);
	//println("");
}

void delete_test_ents() {
	array<CBaseEntity@> toDelete;
	CBaseEntity@ ent = null;
	do {
		@ent = g_EntityFuncs.FindEntityByTargetname(ent, "svc_delete_me");
		if (ent !is null)
		{
			toDelete.insertLast(ent);
		}
	} while(ent !is null);
	
	for (uint i = 0; i < toDelete.size(); i++) {
		g_EntityFuncs.Remove(toDelete[i]);
	}
	println("Deleted " + toDelete.size() + " test ents");
}

CBaseEntity@ create_test_ents() {
	

	dictionary keys;
	keys["targetname"] = "svc_delete_me";
	keys["origin"] = "0 0 0";
	
	for (int i = 0; i < 0; i++) {
		CBaseEntity@ newEnt = @g_EntityFuncs.CreateEntity("info_target", keys, true);
		newEnt.pev.effects |= EF_NODRAW;
	}
	
	keys["model"] = string(g_EntityFuncs.FindEntityByTargetname(null, "test_wall").pev.model);
	
	CBaseEntity@ ret = null;
	for (int i = 0; i < 16; i++) {
		keys["origin"] = Vector(100, i, -50).ToString();
		@ret = @g_EntityFuncs.CreateEntity("func_illusionary", keys, true);
	}
	
	return ret;
}

bool createdTestEnts = false;

void svc_test(CBasePlayer@ plr, int val) {
	int entCount = 0;
	
	// say "y 90" "y 154" (26, 90, 54)
	CBaseEntity@ wall = g_EntityFuncs.FindEntityByTargetname(null, "test_wall");
	if (wall !is null) {
		println("YES HLELO");
		//svc_packetentities(plr.edict());
		
		if (!createdTestEnts) {
			create_test_ents();
			createdTestEnts = true;
		}
		
		int i = 0;
		CBaseEntity@ ent2 = null;
		do {
			@ent2 = g_EntityFuncs.FindEntityByTargetname(ent2, "svc_delete_me");
			if (ent2 !is null && ent2.pev.effects & EF_NODRAW == 0)
			{
				if (i++ == val || true) {
					println("FOUND IT");
					ent2.pev.solid = SOLID_NOT;
					break;
				}
			}
		} while(ent2 !is null);
		
		
		deltaIdx = val;
		println("DELTA IS " + deltaIdx);
		@svc_interval = @g_Scheduler.SetInterval("testo", 0.0f, -1, @ent2);
	}
	
	
}
