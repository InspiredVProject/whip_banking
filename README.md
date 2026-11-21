<p align="center">
  <img src="assets/cookie_ocore_banking_banner.png" alt="Cookie OCore — WHIP Banking" width="100%" />
</p>

<h1 align="center">WHIP Banking</h1>
<p align="center"><strong>Three banks. One native WHIP economy. Fully interactive banking.</strong></p>
<p align="center">
  <code>v2.8.0</code> · <code>WHIP Core 1.2.0+</code> · <code>GTA V Legacy</code> · <code>oxmysql</code> · <code>Fleeca / Maze / Pacific</code>
</p>
<p align="center"><em>Cookie OCore branded resource documentation</em></p>

---

## Overview

**WHIP Banking** (`whip_banking`) adds a complete roleplay banking experience to FiveM using **WHIP Core's existing accounts, cash handling and transaction ledger**. No QBCore, ESX, Qbox or separate economy is required.

Customers can join **Fleeca Bank**, **Maze Bank** or **Pacific Standard** at a teller, receive a physical bank card and use themed, in-world DUI cash machines. Account services, loans, savings and transfers remain backed by WHIP Core.

> [!IMPORTANT]
> This README is updated for the **v2.8.0 resource manifest**, not the older v1.2.6 notes. It documents available code paths; it does **not** claim the resource has passed live multiplayer, banking or MLO testing on every server.

## Contents

- [Highlights](#highlights)
- [Bank choices](#bank-choices)
- [Requirements](#requirements)
- [Installation](#installation)
- [Player guide](#player-guide)
- [Admin settings](#admin-settings)
- [ATM calibration](#atm-calibration)
- [Phone banking integration](#phone-banking-integration)
- [Developer integrations](#developer-integrations)
- [Performance](#performance)
- [Troubleshooting](#troubleshooting)
- [Pre-release checklist](#pre-release-checklist)
- [Credits and usage notes](#credits-and-usage-notes)

## Highlights

| System | Included functionality |
| :-- | :-- |
| **Three banking brands** | Fleeca (green), Maze Bank (red), Pacific Standard (blue); saved per character |
| **Bank tellers** | Eight WHIP networked NPC locations; first-time enrolment, switching and account services |
| **Bank cards** | Nine branded card items across Everyday, Cash+ and Metal finishes, plus legacy Maze card support |
| **Card preview** | Use the inventory card to display its front, flip to the back and close with ESC; no full-screen dark menu |
| **ATM DUI** | Always-on standby, private card/PIN session, fast cash, custom withdrawal and balance enquiry |
| **Physical ATM input** | Clickable number keys, side buttons, Enter, Clear and Cancel; optional keyboard/controller fallback |
| **Card insertion** | Animated, bank-matched visual card face moving toward the ATM's physical card reader |
| **Financial services** | Account dashboard, transfers, history, savings, shared accounts, bills, schedules, credit and loans |
| **WHIP administration** | Native `/whip → Settings → Banking` controls and WHIP-native map blips |
| **Calibration tools** | In-game DUI alignment, live physical-keypad editor, Save & Test Live and JSON export |
| **Optimisation** | Lazy DUI creation, cached ATM geometry, proximity-aware searches and adaptive loops |

## Bank choices

First-time customers choose a bank at a branch teller. The character's bank profile is stored in `whip_banking_profiles` and controls the banking dashboard, teller popup, card designs and ATM theme.

| Bank | Identity | Savings APR (default) | Daily ATM limit (default) |
| :-- | :-- | --: | --: |
| **Fleeca Bank** | Green | 3.0% | $2,500 |
| **Maze Bank** | Red | 2.0% | $5,000 |
| **Pacific Standard** | Blue | 4.5% | $5,000 |

These values come from `Config.Banks` in v2.8.0 and are editable in `/whip`. They are **server gameplay settings**, not real-world rates. The resource's global currency symbol defaults to `$` and can be changed to `£`.

Bank switching is enabled by default. When switching at a teller, old cards are cancelled and a new card is issued. **The underlying WHIP account balance, account number and prior loan records are not reset.** Existing legacy Maze cardholders are migrated to a Maze profile without deleting their existing cards or PIN hashes.

## Requirements

- **WHIP Core 1.2.0 or newer**, with a loaded WHIP character.
- **oxmysql**, configured with the server's working database.
- **FiveM / GTA V Legacy**, the build targeted by this release.
- The resource folder must be named **`whip_banking`**. Changing the name can break DUI and asset URLs.
- **Optional:** the matching WHIP Phone bank-theme sync update for themed mobile banking.

> [!CAUTION]
> Back up your **database, `whip_banking`, `whip_phone` and saved ATM alignment JSON** before replacing an installed build. Avoid replacing your custom phone resource with an older full phone ZIP; merge only its bank-app changes if you have other apps or DUI pose modifications.

## Installation

### 1. Install the resource

Place the complete `whip_banking` folder inside your FiveM resources directory. Keep `config.lua`, `shared/`, `client/`, `server/` and `html/` together.

### 2. Disable the duplicate built-in WHIP ATM interaction

If the ATM shows both the default WHIP prompt and **Use cash machine**, open **`whip_core/config.lua`** and set:

```lua
Config.AtmProps = {}
```

This disables the *original interaction registration*, not WHIP's underlying banking APIs. Restart **WHIP Core or the full server** for this edit to take effect. Also stop any separate `whip-atmdui` script that attempts to replace the same ATM textures.

### 3. Set the startup order

```cfg
ensure oxmysql
ensure whip_core
ensure whip_banking
ensure whip_phone   # only if installed; start it after whip_banking
```

Only add `ensure` lines that are not already present in `server.cfg`. If your existing WHIP setup starts these elsewhere, keep the same dependency order.

### 4. Start and verify

The banking resource creates its supporting SQL tables automatically, including profiles, cards, loans, credit history, interest payouts, invoices and recurring payments. Ensure your database account has the permissions needed for table creation/migration.

Look for this server console line:

```text
[whip_banking] Database ready; using WHIP native banking ledger
```

Visit a bank teller, select a bank on a test character, issue a card, and verify the card appears in WHIP inventory before testing a withdrawal.

## Player guide

### Visiting a bank

1. Walk to any supported banking branch and interact with the **bank teller**.
2. First-time customers choose **Fleeca**, **Maze** or **Pacific** and select a card finish and four-digit PIN.
3. Returning customers can open the bank's themed dashboard to view accounts, send transfers, manage cards, use savings and discuss loans.
4. To change banks, use the banking dashboard's **Bank** tab and the bank-switching option (if enabled by your server).

Supported branches: **Legion Square, Hawick, Alta Street, Rockford Hills, Great Ocean, Route 68, Paleto Bay and Pacific Standard**. Branch positions and tellers are editable in WHIP settings.

### Physical bank cards

- **Everyday**, **Cash+** and **Metal** finishes are available for each bank, with corresponding inventory item images.
- Using a valid card in inventory displays the **physical card preview**, with a front/back **Flip** control. This does not open the full bank dashboard.
- The front shows a masked card number, cardholder name and validity; the reverse does not expose the PIN or a usable CVV.
- A teller can issue, freeze, cancel and change the PIN of an eligible card.
- Three incorrect PIN attempts trigger the configured temporary lockout (the supplied implementation uses 15 minutes).

By default, `Config.CardAccessorySlot = 5` reserves WHIP equipped slot 5 for a bank card. Set it to `false` if you need to retain the third vehicle-key slot. New items use `whip_banking_*` prefixes; existing `maze_bank_card` items remain supported.

### Using a cash machine

1. Approach an ATM and choose **Use cash machine**.
2. Insert/tap an active debit card; a bank-branded card insertion effect is displayed.
3. Enter the **four-digit PIN using the physical machine keypad** (or supported input fallback).
4. Select **Fast Cash**, **Withdraw** or **Balance**, using the screen-side buttons and ATM keys.
5. Exit using **Cancel / ESC**.

**ATM cash deposits are disabled.** Deposits and other full banking services are carried out through bank tellers. The active ATM screen follows the **player's selected bank**, even when the physical machine displays another bank's signage.

## Admin settings

Open **`/whip → Settings → Banking`** as a WHIP administrator. The current release exposes these groups:

| Settings category | Controls |
| :-- | :-- |
| Banks & customer choice | Bank switching, savings APR and daily withdrawal limits |
| ATM standby brands | Fallback bank theme for each supported ATM prop model |
| ATM screens | Idle screens, material replacement, MLO fallback, draw distances and world-screen offsets |
| ATM card slot & keypad | Per-model card-slot coordinates and physical keypad layout |
| Bank map blips | Visibility, sprite, colour, scale, grouped branch legend and nearby-only minimap |
| Accounts & cards | Card count, shared currency settings, default limits and credit settings |
| Personal / vehicle / business loans | Amount caps, APR, terms and eligibility thresholds |
| Bank branches | Teller coordinates, NPCs and interaction positions |

**Map blips:** WHIP Banking uses WHIP's server-side `ShowBlip` registry, so the custom WHIP pause map displays bank names instead of GTA's default *Financier strand* sprite label. All branches remain visible on the full map; short-range minimap visibility can be enabled.

**Saved settings override packaged defaults.** If you have already calibrated an ATM in `/whip`, a newer ZIP won't automatically replace your saved position.

## ATM calibration

### Display alignment

Use **`/w → Developer Mode → Panels → Banking - ATM Alignment → Align nearest ATM`** to position the live DUI over the actual screen glass. Move, resize and tilt the panel while looking at the real ATM. Save the model locally, then **Export All JSON** when satisfied.

### Physical keypad alignment (v2.8.0)

1. Stand directly in front of the ATM.
2. Open **`/w → Developer Mode → Panels → Banking - ATM Alignment`**.
3. Choose **LIVE: Align physical ATM keypad**.
4. Adjust the coloured outlines until they match **1–9**, `− / 0 / +`, **Cancel**, **Clear** and **Enter**.
5. Choose **Save & Test Live**. The editor opens a real ATM session using the same camera/projected coordinates so you can verify the hitboxes.
6. Export the keypad JSON for permanent inclusion in `shared/atm_hardware.lua` / the live model settings.

The editor stores local working overrides in the developer's FiveM resource KVP. It does **not** automatically deploy those values to other players; the exported JSON must be integrated into the server resource or its saved settings.

> [!TIP]
> If clicks move after saving, confirm the model matches the editor selection and use **Save & Test Live** to compare the actual hitboxes. The v2.8.0 update specifically aligned the live/editor camera paths, but custom prop geometry still needs an in-game check.

## Phone banking integration

The matching `whip_phone` banking module obtains the character's selected bank from this trusted server export:

```lua
local profile = exports.whip_banking:GetBankProfile(source)
-- e.g. { key = 'fleeca', name = 'Fleeca Bank', ... }
```

This is a **server-side export**; do not trust a client-submitted bank name. The companion phone update supports red, green and blue branding, real WHIP account balances, transfers and transaction history, and a refresh when the player switches banks at a teller.

To keep your custom 3D phone positioning and other apps, install the **banking-only phone patch** rather than overwriting the entire `whip_phone` resource with an older copy.

## Developer integrations

### Create a trusted bill

Call this from another **server-side resource** only:

```lua
local billId, err = exports.whip_banking:CreateBill(
    source,                    -- payer's server ID
    'Vehicle repair invoice', -- title
    1200,                      -- amount
    garageBusinessAccountId,   -- receiving account, or nil
    7,                         -- due in days
    'mechanic'                 -- bill category
)
```

### Retrieve a credit score

```lua
local score = exports.whip_banking:GetCreditScore(source)
```

The resource intentionally does not publish a client event for arbitrary invoice creation. Money movements and ATM authorisation are checked server-side against WHIP's account system, card ownership and status.

## Performance

- Standby DUIs are shared, and the private ATM browser is created only when required.
- Nearby ATM searches use model proximity checks and cached world geometry rather than a constant full-world scan.
- Loops sleep when no ATM surfaces need drawing.
- The optional `AtmWorldStandbyFallback` draws screen surfaces for custom MLOs whose original textures are not replaced correctly.

**0.00 ms idle Resmon is a target, not a guarantee.** Rendering an active ATM or world-space standby surfaces costs measurable time. Check `resmon 1` away from ATMs, near idle ATMs, during an active session and in the calibration editor before changing performance settings.

## Troubleshooting

| Symptom | Check |
| :-- | :-- |
| Two **Use ATM** prompts | Set `Config.AtmProps = {}` in `whip_core/config.lua`, then restart Core/server; disable separate ATM scripts |
| Bank app stays red after switching | Install the matching `whip_phone` bank sync patch and ensure `whip_banking` starts before the phone |
| An ATM is blank | Verify the model and texture mapping; enable the MLO 3D standby fallback if native replacement fails |
| ATM screen is offset | Align the correct model in the DUI editor; check saved `/whip` overrides |
| Clickable keypad differs after saving | Use v2.8.0 **Save & Test Live**, recheck the model and export its aligned keypad JSON |
| Map legend shows *Financier strand* | Check that bank blips use WHIP `ShowBlip` and remove old client-created duplicates |
| Can't withdraw | Verify card ownership, status, PIN lockout, daily withdrawal cap, bank balance and inventory cash capacity |
| SQL migration fails | Verify oxmysql starts first and the database user can `CREATE` / `ALTER` tables |

## Pre-release checklist

- [ ] Confirm each teller appears at the correct counter, without duplicates after restarting.
- [ ] Choose and switch between all three banks; verify balances and card transitions.
- [ ] View and flip a card; confirm PINs are never revealed by the preview.
- [ ] Test card insertion, physical keypad mapping, PIN rejection and PIN lockout.
- [ ] Check standby and active DUIs on all four supported ATM prop models.
- [ ] Confirm ATM deposits are not available.
- [ ] Test phone branding refresh after switching banks.
- [ ] Verify full-map blips and short-range minimap behaviour.
- [ ] Test transfers, loans, bills and scheduled payments against a staging database.
- [ ] Check Resmon and server logs following a **full server restart**.

## Credits and usage notes

<p align="center">
  <img src="assets/cookie_ocore_developer_mark.svg" alt="Cookie OCore developer mark" width="420" />
</p>

**Cookie OCore** mark and README presentation were created for this documentation package. The provided v2.8.0 resource manifest currently identifies **Lunny Dev** as its author; this README does not silently overwrite that metadata or assert transfer of ownership.

WHIP integration uses the [WHIP Core repository](https://github.com/WHIPFX/whip_core) APIs. The ATM rendering approach follows the supplied `whip-atmdui` reference. Barlow font files supplied with the existing resource retain their own licence terms. GTA V, Fleeca Bank, Maze Bank and Pacific Standard are fictional game-world assets/names associated with Rockstar Games.

**Licence:** This README does not grant redistribution, resale or sublicensing rights. Check the actual resource licence and the rights of every bundled dependency and asset before distribution.

---

<p align="center"><strong>COOKIE OCORE</strong> · Crafted for FiveM communities · <code>whip_banking v2.8.0</code></p>
