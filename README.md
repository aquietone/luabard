# luabard

A Bard bot using Lua.

## Overview
This script automates a level 120 Bard in a group setting. It expects to find all spells and AAs and such that it needs to run.

## Visuals
Depending on what you are making, it can be a good idea to include screenshots or even a video (you'll frequently see GIFs rather than actual videos). Tools like ttygif can help, but check out Asciinema for a more sophisticated method.

## Installation
Download bardbot.lua to your `mq/lua` folder.

## Usage
Start the script with `/lua run bardbot`.

## Support
Open issues on this repository.

## Roadmap
Where it stops, nobody knows.

## Contributing
Always open to suggestions.

## License
MIT

## Project status
Experimental

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
