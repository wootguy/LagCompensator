#define ACT_RESET 	0 	// Set m_Activity to this invalid value to force a reset to m_IdealActivity
#define ACT_IDLE 	1
#define ACT_GUARD 	2 	
#define ACT_WALK 	3 	
#define ACT_RUN 	4 	
#define ACT_FLY 	5 	// Fly (and flap if appropriate)
#define ACT_SWIM 	6 	
#define ACT_HOP 	7 	// vertical jump
#define ACT_LEAP 	8 	// long forward jump
#define ACT_FALL 	9 	
#define ACT_LAND 	10 	
#define ACT_STRAFE_LEFT 	11 	
#define ACT_STRAFE_RIGHT 	12 	
#define ACT_ROLL_LEFT 	13 	// tuck and roll, left
#define ACT_ROLL_RIGHT 	14 	// tuck and roll, right
#define ACT_TURN_LEFT 	15 	// turn quickly left (stationary)
#define ACT_TURN_RIGHT 	16 	// turn quickly right (stationary)
#define ACT_CROUCH 	17 	// the act of crouching down from a standing position
#define ACT_CROUCHIDLE 	18 	// holding body in crouched position (loops)
#define ACT_STAND 	19 	// the act of standing from a crouched position
#define ACT_USE 	20 	
#define ACT_SIGNAL1 	21 	
#define ACT_SIGNAL2 	22 	
#define ACT_SIGNAL3 	23 	
#define ACT_TWITCH 	24 	
#define ACT_COWER 	25 	
#define ACT_SMALL_FLINCH 	26 	
#define ACT_BIG_FLINCH 	27 	
#define ACT_RANGE_ATTACK1 	28 	
#define ACT_RANGE_ATTACK2 	29 	
#define ACT_MELEE_ATTACK1 	30 	
#define ACT_MELEE_ATTACK2 	31 	
#define ACT_RELOAD 	32 	
#define ACT_ARM 	33 	// pull out gun, for instance
#define ACT_DISARM 	34 	// reholster gun
#define ACT_EAT 	35 	// monster chowing on a large food item (loop)
#define ACT_DIESIMPLE 	36 	
#define ACT_DIEBACKWARD 	37 	
#define ACT_DIEFORWARD 	38 	
#define ACT_DIEVIOLENT 	39 	
#define ACT_BARNACLE_HIT 	40 	// barnacle tongue hits a monster
#define ACT_BARNACLE_PULL 	41 	// barnacle is lifting the monster ( loop )
#define ACT_BARNACLE_CHOMP 	42 	// barnacle latches on to the monster
#define ACT_BARNACLE_CHEW 	43 	// barnacle is holding the monster in its mouth ( loop )
#define ACT_SLEEP 	44 	
#define ACT_INSPECT_FLOOR 	45 	// for active idles, look at something on or near the floor
#define ACT_INSPECT_WALL 	46 	// for active idles, look at something directly ahead of you ( doesn't HAVE to be a wall or on a wall )
#define ACT_IDLE_ANGRY 	47 	// alternate idle animation in which the monster is clearly agitated. (loop)
#define ACT_WALK_HURT 	48 	// limp (loop)
#define ACT_RUN_HURT 	49 	// limp (loop)
#define ACT_HOVER 	50 	// Idle while in flight
#define ACT_GLIDE 	51 	// Fly (don't flap)
#define ACT_FLY_LEFT 	52 	// Turn left in flight
#define ACT_FLY_RIGHT 	53 	// Turn right in flight
#define ACT_DETECT_SCENT 	54 	// this means the monster smells a scent carried by the air
#define ACT_SNIFF 	55 	// this is the act of actually sniffing an item in front of the monster
#define ACT_BITE 	56 	// some large monsters can eat small things in one bite. This plays one time, EAT loops.
#define ACT_THREAT_DISPLAY 	57 	// without attacking, monster demonstrates that it is angry. (Yell, stick out chest, etc )
#define ACT_FEAR_DISPLAY 	58 	// monster just saw something that it is afraid of
#define ACT_EXCITED 	59 	// for some reason, monster is excited. Sees something he really likes to eat, or whatever.
#define ACT_SPECIAL_ATTACK1 	60 	// very monster specific special attacks.
#define ACT_SPECIAL_ATTACK2 	61 	
#define ACT_COMBAT_IDLE 	62 	// agitated idle.
#define ACT_WALK_SCARED 	63 	
#define ACT_RUN_SCARED 	64 	
#define ACT_VICTORY_DANCE 	65 	// killed a player, do a victory dance.
#define ACT_DIE_HEADSHOT 	66 	// die, hit in head.
#define ACT_DIE_CHESTSHOT 	67 	// die, hit in chest
#define ACT_DIE_GUTSHOT 	68 	// die, hit in gut
#define ACT_DIE_BACKSHOT 	69 	// die, hit in back
#define ACT_FLINCH_HEAD 	70 	
#define ACT_FLINCH_CHEST 	71 	
#define ACT_FLINCH_STOMACH 	72 	
#define ACT_FLINCH_LEFTARM 	73 	
#define ACT_FLINCH_RIGHTARM 	74 	
#define ACT_FLINCH_LEFTLEG 	75 	
#define ACT_FLINCH_RIGHTLEG 	76 	