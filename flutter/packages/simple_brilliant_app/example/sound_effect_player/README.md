# Sound Effect Player

Plays the Halo firmware's built-in sfxr sound effect presets (pickup, laser, explosion, powerup, hit, jump, blip) through the Halo speaker using `frame.sound.play()`.

Each sound is generated from a preset name and a 32-bit seed, so the same seed always reproduces the same sound.

## Instructions

* Select a sound effect type and tap **Play**. Leave the seed field empty for a random variation, or enter a seed to reproduce a specific sound.
* Tap **Auto Play** to keep playing random variations of the selected effect until you tap **Stop Auto**.
* Every sound is logged with its seed, e.g. `jump (123456)`, so after listening for a while you can find the one you liked. Tap a history entry to load its effect and seed back into the controls, or tap the copy icon to copy the seed to the clipboard.

To play these sounds from your own frameside Lua app:

```lua
frame.sound.play('jump')                 -- random variation each call
frame.sound.play('jump', {seed=123456})  -- the same sound every call
```
