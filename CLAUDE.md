# EasyPoisons

Rogue helper: plan a batch of poisons and buy the missing reagents at the
vendor in one click. Fostercare5988's addon, based on Horyoshi's EasyPoisons 1.3
(GitHub starts at 1.0.0; the earlier history, 1.3 included, is only in the
local branches `backup/pre-2.0.0` and `backup/pre-1.0.0`); keep crediting him in the TOC (`X-Credits`) and README.
Public repo, listed on the Fostercare-Addons hub.
**Stable at 1.0.0 (2026-10-22), confirmed in play.** Leave it as it is until
the server changes its poisons, vendors or client, or the user asks.
Regression tests: `regressions/EasyPoisons` in VanillaForge (34 tests).

| File | Job |
| --- | --- |
| `ClassicAPIRequirement.lua` | ClassicAPI 1.16.0+ guard; sets `ns.unsupported` so the addon stays inert |
| `ForgeUI.lua` | The shared settings kit (ForgeUI, Ember) |
| `EasyPoisons.lua` | Poison table, vendor scan, order plan, buying, recipe learning, window, `/ep` |

Things to know:

- Opens only for rogues, beside the vendor window, at a poison vendor: one
  that sells every reagent of at least one poison. (Vials plus one reagent was
  not enough: a trade goods vendor with Crystal and Leaded Vials opened it.) `/ep` opens it by hand
  at any vendor. Closing it by any route clears the quantities (kept from 1.3).
- Vendor data comes from the client per visit: `GetMerchantItemID` and
  `C_MerchantFrame.GetItemInfo` (price per purchase, items per purchase, stock).
  Nothing about prices or purchase sizes is hardcoded.
- Buying goes one purchase at a time, at most one full stack each, as the stock
  vendor window does. Each purchase waits until its items are in the bags,
  then the plan is made again, so anything lost is bought again. Measured in
  play (2026-10-21): a burst of 20 purchases in one frame lost one. A purchase
  that does not arrive in 2 seconds is retried; after 3 misses in a row the
  order stops with a message. Closing the window or the vendor stops it.
- Poisons: the highest rank a level 60 rogue knows on the server, item IDs read
  in game from the Poisons window (2026-10-21), in the order the user wants:
  Instant VI 8928, Dissolvent II 54010, Crippling II 3776, Mind-numbing III
  9186, Deadly IV 8985, Corrosive 47408, Wound 10918, Agitating 65032 (custom). Deadly V (20844) and Corrosive II
  (47409) need content that is not open yet. Item 8928 is Instant Poison VI
  (1.3 called it IV).
- New ranks need no update: opening the Poisons window moves each row to the
  highest rank of its poison listed there (name split into poison and roman
  numeral, `SplitRank`), with that rank's item ID and recipe. Stored per
  character in `EasyPoisonsDB.Ranks["Name-Realm"]`, keyed by the table's item
  ID; rows only move up, since the window's search and filters can hide ranks.
  No new IDs are hardcoded for AQ20 (never take them from Turtle WoW).
- Recipes: the table holds all eight as the Poisons window reported them in
  play (2026-10-22; Wound and Agitating use Leaded Vial 3372, Wound Essence of
  Pain 2930). Opening the window saves every poison recipe it shows in
  `EasyPoisonsDB.Recipes` (by poison item ID), and those replace the table. A
  new rank whose recipe was never read asks for the Poisons window.
- Flash Powder (item 5140): with the switch on (`EasyPoisonsDB.KeepFlashPowder`,
  off by default) any vendor that sells it tops the bags up to 20 on opening,
  in one purchase. Works at vendors where the window does not open (a repair
  bot), and never opens it: Flash Powder is not part of the poison-vendor test.
- While a purchase is on its way, bag events only check whether it landed; the
  order is planned again once it has.
- Bag space counts general-purpose bags only
  (`C_Container.CalculateTotalNumberOfFreeBagSlots`).
