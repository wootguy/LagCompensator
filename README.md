# LagCompensator
Lag compensation "rewinds" enemies so that you don't have to aim ahead of them to get a hit. The higher your ping, the more noticeable this will be.

Type '.lagc' in console for help.

Demonstration video:  
[![Demo Video](https://img.youtube.com/vi/rAAkEDtTyOs/0.jpg)](https://www.youtube.com/watch?v=rAAkEDtTyOs)

This works only for weapons that shoot bullets or beams. Projectiles and melee weapons are not compensated. Projectiles and melee attacks don't have client-side prediction anyway (there's a delay between clicking and the gun firing, which is equal to your ping).

Custom weapons are also not lag compensated by default. I added support for a few maps (pizza_ya_san1-2, alienshooter_demo, rust), but every custom weapon will need [special logic](https://github.com/wootguy/LagCompensator/blob/master/custom_weapons.as) added to this plugin in order to be compensated.

## Installation
1. Download and extract to svencoop_addon 
1. Add this to default_plugins.txt:
```
	"plugin"
	{
		"name" "LagCompensator"
		"script" "LagCompensator/LagCompensator"
	}
```

Lag compensation is enabled for everyone by default. 

## Server impact
- 1 sprite and 1 sound is precached for the MLG hit comfirmation effect (`.lagc x`).
- Potentially heavy CPU usage when lots of players (20-30) are shooting at the same time in a map with lots of monsters (200+).
  - Type `.lagc perf` to see how much work the plugin is doing. If the info text is colored red and player pings are rising, try temporarily disabling the plugin with `.lagc pause/resume`.
