# Maze Bank for WHIP — `whip_banking`

Version 1.2.6 · Cookie OCore · GTA V Legacy · native WHIP Core 1.2.0+

This resource builds a Maze Bank front end on **WHIP's own banking system**. It does not install QB-Core, ESX, Qbox, ox_inventory or a second bank ledger.

## Features

- Full-screen red and cream Maze Bank digital branch, modelled on the supplied banking screenshot: account dashboard, spending chart, transactions, savings, shared accounts, transfer, cards, credit, loans, bills and scheduled payments.
- Eight branch teller NPCs spawned and maintained by WHIP (not duplicated locally). Talk to them with WHIP's usual E interaction; they offer account, card, loan and transfer conversations.
- **Native WHIP map blips for every bank branch**, including Legion Square, Hawick, Alta Street, Rockford Hills, Great Ocean, Route 68, Paleto Bay and Pacific Standard. Created through **WHIP Core's server-side `ShowBlip` export**, rather than standalone GTA blips. This is essential: WHIP's pause map deliberately ignores the names of blips created by other resources and displays their sprite's default name ("Financier strand"). WHIP's own blips carry the correct **Maze Bank** label. All eight locations remain visible on the full map, while only nearby banks appear on the minimap. By default, the legend groups them under one **Maze Bank** entry (count 8); enable branch names in `/whip` to list **Maze Bank - Paleto Bay** and other branches separately. Moving/renaming a branch in `/whip` updates its WHIP blip without restarting.
- Four vanilla GTA V ATM models (`prop_atm_01`, `prop_atm_02`, `prop_atm_03`, `prop_fleeca_atm`). **Every streamed ATM gets a Maze Bank standby screen**, using `AddReplaceTexture` as in the supplied `whip-atmdui` reference plus a per-prop world-screen fallback for retextured MLO machines. A second DUI shows the private interactive screen on the customer's selected machine. Neither DUI replaces the prop model.
- Physical non-stackable debit-card inventory item (`maze_bank_card`) with per-card serial number, account link, four-digit salted PIN, card freeze, cancellation and PIN change. **Three** wrong attempts cause a 15-minute lockout.
- Dedicated **Bank Card** equipped slot in WHIP and D11 inventories: replaces the last of WHIP's three vehicle-key slots (slot 5), shows a debit-card outline when empty, and accepts only `maze_bank_card`. The two other key slots are preserved. Set `Config.CardAccessorySlot = false` to restore the third key slot.
- ATM withdrawals **using WHIP's own `whip_core:atm` callback**. It atomically moves WHIP cash inventory items and account balances together, including rollback and capacity checks. Balance and transfer use WHIP bank exports, not custom SQL balance updates. ATMs do not offer cash deposits.
- Daily ATM withdrawal limit checked against **actual WHIP `bank_transactions`** rows, rather than a simulated value. Default $5,000; `Config.AtmDailyLimit` sets it.
- Three credit-score-gated loan products, stored contracts, instalments, repayments, automatic collection every minute when due, and credit-score adjustments. Loans pay into the WHIP main account.
- Real WHIP savings accounts, including a monthly 2% APR interest payout calculated at the configured rate. Change via `Config.SavingsApr`.
- Bills: other **trusted server scripts** can issue a bill, and players can pay into a real creditor account. Recurring transfers use the same native WHIP bank transfer API.
- Auto-created SQL tables, source and account permission checks, per-operation rate limits, ownership checks, and startup reconciliation for interrupted loan repayments and bills.
- Zero chat commands for everyday banking. Use the teller, the physical debit card from inventory, or an ATM.
- Native **`/whip → Settings → Banking`** editor for ATM models and screen position, standby, calibration preview, withdrawal limits, cards, savings, loan product terms, and all eight teller positions. Changes are persisted by WHIP and synchronized to players.
- **Developer-only live ATM alignment console** under `/w → Panels → Banking - ATM Alignment`. Move the screen by keyboard or button, save per-model adjustments to your PC, select the next ATM, and export a single JSON with every ATM position for permanent integration.
- **Optimised idle client:** the standby DUI is created once; the private DUI is created on first use. ATM lookups probe by model before scanning the world object pool, while fallback-screen coordinates are cached between scans. When no ATM screen needs rendering the loop sleeps instead of ticking every frame.

## Resmon and performance (1.2.3)

- **Away from ATMs:** designed to show `0.00 ms` most of the time in client Resmon. A short proximity probe still runs occasionally, so an exact constant `0.00` cannot be guaranteed.
- **Near an ATM:** the script must draw world-space standby DUIs every frame if `Config.AtmWorldStandbyFallback = true`, including for custom MLO retextures. The optimisation removes repeated entity-transform calculations from that draw path; drawing itself still has a measurable cost.
- **Lowest possible near-ATM usage:** if *all* your ATMs already show their standby displays correctly via the native material replacement, set `Config.AtmWorldStandbyFallback = false` in `/whip → Settings → Banking` to eliminate per-frame standby quads. **Do not disable it if custom MLO ATMs go blank.** The selected ATM still gets its private session screen.
- **Measuring:** restart `whip_banking`, wait for initial DUI loading, open `resmon 1`, and test (1) away from all ATMs, (2) beside an ATM with its standby on, (3) with the ATM menu open, and (4) in the alignment editor. The active camera/NUI will naturally cost more than the idle resource. Test both ordinary and MLO machines before switching fallback off.

## Install

1. Install the official **WHIP Core 1.2.0 or newer** and its oxmysql dependency. This resource uses exports and UI conventions from the published WHIP Core 1.2.0 codebase; older WHIP versions are not verified.
2. Put the complete folder under your FiveM `resources` directory as `whip_banking` (keep its name, because DUI uses the resource URL).
   **Do not also start `whip-atmdui`**. Its own `AddReplaceTexture` calls and ATM interaction would compete with this resource's ATM screen replacements and WHIP prompts. This package uses the reference's screen-material technique inside the banking resource.
3. In `whip_core/config.lua`, replace the original built-in ATM prop list with:

   ```lua
   Config.AtmProps = {}
   ```

   **Why:** the original WHIP ATM prompt and this script's ATM action otherwise both appear on the same machines. The underlying WHIP ATM callbacks remain in place and are intentionally used here. After a WHIP Core update, recheck this one config line. No other WHIP Core edits are required.

   **Important:** this line is in **`whip_core/config.lua`**, not `whip_banking/config.lua`. WHIP's `AtmProps` is not one of the options exposed in WHIP Core's `/whip → Settings → Config` schema. After editing it, restart **`whip_core`** (or the full server); restarting only `whip_banking` does not remove the original interaction. If you also installed the reference `whip-atmdui`, stop that resource too.

4. In `server.cfg`, **after** the original WHIP resources:

   ```cfg
   ensure oxmysql
   ensure whip_core
   ensure whip_banking
   ```

   Do not add duplicate `ensure` lines for resources already started. Start `whip_banking` after Core.

   **Bank-card slot:** when `whip_banking` starts, WHIP's accessory slot 5 becomes **Bank Card** automatically, including in the D11 inventory renderer. No editing `whip_core` or D11 files is needed. Existing car keys already occupying slot 5 are not deleted; move one to your pockets before equipping a card. If you have a custom accessory-strip size below 5 or a different resource has claimed slot 5, check the server console for the registration warning. The setting is `Config.CardAccessorySlot = 5` in `whip_banking/config.lua`; set it to `false` to keep all three key slots, or pick another free slot.

5. Start or restart the server. The script automatically creates `whip_banking_cards`, `whip_banking_loans`, `whip_banking_loan_payments`, `whip_banking_credit`, `whip_banking_interest`, `whip_banking_bills` and `whip_banking_schedules` in your existing WHIP database. **No manual SQL import.**

6. Check the log for `[whip_banking] Database ready; using WHIP native banking ledger` and visit a branch with a loaded character. Use the teller to issue a card, verify it appears in WHIP inventory, then test the ATM.

## How to use

- **Branch:** walk up to a bank teller, press E, choose what you want to discuss; the dashboard opens. Issue a new card from the Cards tab. Creating a card requires the teller interaction.
- **Personal digital banking:** use your physical `maze_bank_card` item in WHIP inventory to open the complete banking interface anywhere.
- **Equipped card:** drag `maze_bank_card` from your pockets onto the rightmost **Bank Card** slot in the Equipped row. It remains usable there and is also recognised when an ATM checks your physical card. Vehicle keys still work from the two remaining key slots.
- **ATM:** press E near an ATM, then click *Insert Card* or *Tap Here*. Choose your physical card, type its four-digit PIN, and use **Fast Cash (1), Withdraw (2), Balance (3) or Cancel**. `ESC` exits. ATMs are withdrawal-only; deposit requests are refused by the banking script.
- **Savings:** create a pot in Accounts; transfers use actual WHIP account numbers. Savings interest uses native system deposits on completed months, with one ledger reference per account/month.
- **Loan:** choose a loan product, amount and personal account. Credit eligibility, borrowing cap and max active loans are all checked on the server. Instalments have a 30-day interval; collection is attempted when due.
- **Recurring transfers:** standing orders can be scheduled for 7/14/30 days; an order pauses if the owner loses withdrawal permission.
- **Cards:** freeze or cancel at any time; a cancelled card remains an inventory prop, but no longer authorises a new ATM session.

### Trusted billing integration

From **another server-side resource** (no public client bill-creation event):

```lua
local invoiceId, why = exports.whip_banking:CreateBill(
    source,                        -- payer's current server ID
    'Vehicle repair invoice',      -- title
    1200,                          -- amount in WHIP dollars
    garageBusinessAccountId,       -- account to receive funds, or nil to deduct
    7,                             -- due in 7 days
    'mechanic'                     -- category
)
```

Retrieve a player's score from a trusted server resource:

```lua
local score = exports.whip_banking:GetCreditScore(source)
```

## Edit everything in `/whip` — no config-file changes for normal tuning

Open **`/whip → Settings → Banking`** as a WHIP permanent administrator. Select a category from the left:

| Category | What you can edit live |
| --- | --- |
| Bank map blips | Show/hide all branch markers, sprite ID, colour, size, nearby-only minimap, grouped or individual branch names, and the bank legend title |
| ATM screens | Always-on standby, 3D fallback screens, private interactive rendering, draw distance, ATM models, native screen material mappings, calibration preview and interaction range |
| Accounts & cards | Bank name, $/£ display, card limit, daily cash limit, savings APR, starting credit score, number of loans |
| Personal / Vehicle / Business loans | Maximum loan amount, APR, number of months, minimum credit score |
| ATM 01 / ATM 02 / ATM 03 / Fleeca | Interactive-screen centre X, Y, Z, screen width and height, face tilt |
| Other ATM models | Fallback interactive-screen dimensions for models added to the ATM models list |
| Bank branches | Interaction distance, teller ped model, all eight teller names, **E interaction coordinates and ped coordinates** |

**Upgrading from 1.2.5:** bank blips have moved from the banking client's native
GTA blips into **WHIP Core's own map registry**. The resource removes its old
client blips on stop. In `/whip → Settings → Banking → Bank map blips`, make sure
**Nearby-only minimap blips** is **ON**. Set **Include branch names in blips**
**OFF** for one **Maze Bank (8)** legend group. If you saved previous overrides,
WHIP can retain the old selections. Leave **Map legend bank name** empty to
derive it automatically from the account bank name.

## Live ATM alignment: move it around in game, then send one JSON

For a proper visual alignment, you **do not need to type values in `/whip` anymore**:

1. Enter WHIP **Developer Mode** through `/w` (your account needs `whip.devtools`).
2. Stand near an ATM. Open **`/w → Panels → Banking - ATM Alignment → Align nearest ATM`**.
3. A compact editor opens on the right, while a cyan border and crosshair show the DUI panel on the selected physical screen. Move, resize and tilt it using the buttons or these keys:

   | Keys | Move |
   | --- | --- |
   | **← / →** or **A / D** | Screen left / right |
   | **↑ / ↓** or **E / Q** | Screen up / down |
   | **PgUp / PgDn** or **W / S** | Screen out towards you / back into ATM |
   | **Z / X** | Narrower / wider |
   | **C / V** | Shorter / taller |
   | **R / F** | Increase / decrease screen face tilt |
   | **Enter** | Save this model's position |
   | **Esc** | Close the alignment editor (or exit JSON view) |

4. Use the **Adjustment Step** selector for coarse positioning or millimetre-level fine tuning. You can also type an exact value in any number field. Press **⇄** in the panel header to move the whole editor between the right and left sides of your screen if it covers the ATM.
5. Press **Save This Model**; the alignment is stored on your own PC using FiveM's resource KVP. **Next ATM** selects another streamed nearby machine and automatically saves the current model first.
6. Once you're happy with each model, press **Export All JSON → Copy JSON**. If your FiveM browser permits it, **Download .JSON** also gives you a file called `whip_banking_atm_alignment.json`. Paste or upload this JSON to your developer to bake the model offsets into `Config.AtmScreens` permanently for everybody.

You can also open `/w → Panels → Banking - ATM Alignment → Export all ATM positions` from anywhere. The JSON includes the default and all configured models, plus any alignment you've saved locally. The editor is developer-only, does **not** change the live server's config or other players' displays, and retains your saved positions between game restarts. Press **Reset Model** twice to discard its local override.

**Do not start the normal WHIP ATM conversation while calibrating.** Leave the editor by clicking ✕, and test the ATM in ordinary banking mode once the cyan guide fits the physical display.

**Standby positioning:** the uploaded `whip-atmdui` script showed the native-material approach: replacing `prop_cashpoint_screen` or `prop_fleece_emis` on the machine. On some custom or retextured MLO ATMs, that replacement does not appear and the original blue screen is still visible. **v1.1.1 adds a second render path:** it finds all nearby streamed ATM models and draws the shared standby DUI in front of each display. The new fallback is enabled by default. It does not spawn a separate browser for each ATM.

**Interactive positioning:** a second DUI is drawn on *only the machine a customer uses*, so the neighbouring ATM stays in standby rather than displaying their balance and PIN. In 1.1.2 the default freestanding ATM panels have been moved **back towards the physical screen** compared with 1.1.1, and slightly right/up. The previous visible red panel was floating in front of and below the blue display; an angled view exaggerates this through parallax. These model defaults still need an in-game visual check on your exact MLO/prop variants.

**How to calibrate the interactive screen:**

1. Stand in front of the ATM you want to align and open `/whip → Settings → Banking → ATM screens`.
2. Enable **ATM screen alignment preview** and close the admin menu. A bright cyan border and yellow crosshairs appear on the nearest machine, along with its actual prop model name (for example `prop_atm_03`).
3. Reopen `/whip → Settings → Banking`, pick the corresponding ATM model category, and adjust **horizontal centre, depth, height, width, height and face tilt**. Press Apply and inspect the border until it matches the built-in screen. **More negative Depth brings the panel towards you; more positive moves it back towards/into the ATM.**
4. Turn **ATM screen alignment preview** off once finished. WHIP saves your values server-side and applies them to connected clients automatically.

If a custom ATM prop does not light up, add its **model name** and **screen material mapping** in Banking → ATM screens. Each model's native texture dictionary and screen-only texture name can be managed there; the vanilla set is already configured. Do not use a hardware or bezel texture as the screen material.

You can reposition tellers with **Use where I stand** on their `vec4` setting, and the WHIP-native networked NPC respawns at the new position. There is no new banking admin command.

> **Existing saved settings:** WHIP gives saved `/whip` values priority over new `config.lua` defaults. If you already changed an ATM model's position, those saved values are retained. For the LG Zone/Fleeca-style ATM in the supplied screenshot, try **horizontal -0.095 m, depth +0.045 m, height 1.180 m, width 0.285 m and screen height 0.205 m**, then fine-tune with the alignment preview. Use the same numbers for both relevant freestanding models if you cannot tell which variant is streamed.

## Test before public launch

Static JavaScript syntax checks and Lua compile checks pass, but this package has not been executed on a live WHIP/FiveM server or database. Please test with a development character and a low balance:

1. Verify each teller is inside its branch behind the counter, facing the player; no duplicate ped after a restart.
2. Verify that **two or more nearby ATMs show the red standby screen simultaneously** before anyone uses them; test each of the four vanilla prop models.
3. Enable preview to align the private interactive quad for each model, then turn preview off and check that using one machine leaves the other in standby. Check the camera position and button/menu alignment.
4. Issue a card, check inventory, verify 3 wrong PINs trigger lockout, then change PIN and test freeze/cancel.
5. Deposit/withdraw cash repeatedly and restart the resource. Confirm no inventory money is gained or lost on a failed action.
6. Confirm transfers, savings account creation, loan disbursal and next-due repayments on a staging database.
7. Issue a test bill from a trusted script and confirm the payer and creditor statement both update.
8. Test after a **full server restart**, not just a resource restart, because this checks persistence and loan/bill reconciliation.

## Important limits

- The normal ATM workflow requires a card and PIN and checks a daily withdrawal limit from WHIP's ledger, but other resources could still call the **public WHIP Core** ATM callbacks without this UI. The original WHIP Core exposes those callbacks for its own ATM; this satellite does not patch their internal security checks.
- WHIP's native bank account numbers are retained exactly. They do not change to the screenshot's example `MZ 4821 0937` because altering display numbers would break server transfers.
- Loan funding and repayment run through WHIP Core exports, with an interruption ledger. After an ambiguous disbursement crash, the loan is marked `review` rather than issuing the funds twice. Staff should review the bank ledger before resolving it.
- Physical interactive ATM layout and ped positions still require visual checks on your exact Legacy build/MLO. The idle material replacement is based on the supplied `whip-atmdui` screen texture mapping; those names cannot be validated on your custom MLO without an in-game test. A literal pixel-perfect screenshot claim is not justified until that test passes.

## Attribution

Uses WHIP Core's documented satellite API, `WorldQuad` module and atomic ATM callbacks from [WHIPFX/whip_core](https://github.com/WHIPFX/whip_core). The ATM screen material mapping and native replacement technique were adapted from the user's provided `whip-atmdui-1.1.0` script; its original bundled art or source files have not been incorporated into the release. Barlow and Barlow Condensed fonts are from WHIP's font assets and distributed under the SIL Open Font License; license texts are provided in `html/fonts/`. Maze Bank and GTA V are fictional trademarks/assets of Rockstar Games. This resource contains no original GTA model files.
