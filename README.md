# EasyPoisons

Plan a batch of rogue poisons and buy the missing reagents at the vendor in one
click. For World of Warcraft 1.12.1.

**Version 1.0.0: stable.** Tested in play. No changes are planned until the
server changes its poisons, vendors or client.

## Requirements

- [ClassicAPI](https://github.com/brues-code/ClassicAPI) 1.16.0 or newer. Without
  it the addon stays switched off and says so.
- A rogue. The addon does nothing on other classes.

## Install

Put the `EasyPoisons` folder in `Interface\AddOns` and restart the game.

## How to use

1. Talk to a poison vendor. The window opens beside the vendor window when the
   vendor sells Crystal Vials and at least one other poison reagent.
2. Set how many of each poison you want with `+`, `-` or by typing a number.
3. The window shows the total cost, or why you can't buy yet: not enough money,
   not enough bag space, or a reagent this vendor doesn't sell or has too few of.
4. Press **Buy**. It buys only what your bags don't already hold, one stack at
   a time. Each stack is checked in your bags before the next one, so anything
   the server drops is bought again. Chat says "Purchase complete." at the end.

Closing the window or the vendor clears the quantities and stops a purchase
that is still running.

**Keep 20 Flash Powder:** switch it on in the window, and every vendor that
sells Flash Powder tops your bags up to 20 when you open it, even vendors where
the window does not open. It is off until you switch it on.

`/ep` or `/easypoisons` opens or closes the window by hand, at any vendor.

## Poisons

The highest rank of each poison today: Instant Poison VI,
Dissolvent Poison II, Crippling Poison II, Mind-numbing Poison III, Deadly
Poison IV, Corrosive Poison, Wound Poison and Agitating Poison.

**New ranks are picked up by themselves.** When you learn a higher rank, such
as a new poison from AQ20, open your Poisons window and the row switches to it,
recipe and all. Each character keeps its own ranks.

Opening your Poisons window also refreshes the recipes from the game, so they
stay right even if the server changes them.

## Credits

Based on EasyPoisons by **Horyoshi**. Modernized and maintained by Fostercare5988.
