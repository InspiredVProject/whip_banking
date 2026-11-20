<div align="center">

# 🏦 MAZE BANK

### Banking, built for WHIP.

**A complete in-world banking experience for FiveM roleplay servers.**

`whip_banking` &nbsp;·&nbsp; `v1.2.6` &nbsp;·&nbsp; `GTA V Legacy` &nbsp;·&nbsp; `WHIP Core 1.2.0+`

---

### ✦ 𝘾𝙊𝙊𝙆𝙄𝙀 𝙊𝘾𝙊𝙍𝙀 ✦

<sub>CRAFTED FOR THE WHIP FRAMEWORK</sub>

</div>

> [!IMPORTANT]
> **Native WHIP integration.** This resource is a banking *front end* for WHIP Core. It uses WHIP's existing bank accounts, transfers, cash inventory and transaction ledger. It does **not** install another economy or require QB-Core, ESX, Qbox or ox_inventory.

## Overview

**WHIP Banking** brings a Maze Bank-inspired digital branch, physical debit cards, interactive ATM displays, staffed bank branches and finance features into the world. Players bank through teller conversations, their bank card or an ATM—not everyday chat commands.

The design is built around physical interaction and WHIP's native UI, map, inventory and configuration systems.

### At a glance

| System | What's included |
| :-- | :-- |
| **Bank branches** | 8 teller NPCs, native WHIP interactions and properly named WHIP map blips |
| **Digital banking** | Account overview, spending chart, statements, transfers, savings and shared accounts |
| **ATM displays** | Persistent standby screens and a private customer session on the selected ATM |
| **Debit cards** | Physical inventory item, serials, four-digit PINs, freezing, cancellation and PIN changes |
| **Cash handling** | Native WHIP cash/account operations, capacity checks and daily ATM withdrawal limits |
| **Finance** | Credit scores, three loan products, instalments, bills and recurring transfers |
| **Administration** | Live `/whip` settings, teller placement, ATM positioning and developer alignment tools |
| **Performance** | Shared standby browser, lazy-loaded private browser and distance-based idle checks |

---

## Requirements

- **FiveM / GTA V Legacy** (the target build documented for this release).
- **WHIP Core 1.2.0 or newer** and its existing **oxmysql** dependency.
- A configured, working WHIP character, inventory and banking system.
- Administrator access to `/whip` for configuration; `whip.devtools` permission for the optional alignment console.

> [!NOTE]
> This README documents the supplied **v1.2.6** release notes. The resource itself was **not provided for runtime testing with this README**, so verify compatibility and every gameplay flow on a development server before releasing it publicly.

## Installation

### 1. Add the resource

Place the `whip_banking` folder in your server's resources directory. Keep its resource name as **`whip_banking`**.

### 2. Disable WHIP's original ATM interaction

In **`whip_core/config.lua`**, replace the default ATM props list with:

```lua
Config.AtmProps = {}
```

This disables the original ATM prompt so it does not appear alongside WHIP Banking's ATM interaction. **Do not remove WHIP's internal ATM callback**; WHIP Banking deliberately calls it for cash withdrawals.

> [!WARNING]
> Edit **`whip_core/config.lua`**, not `whip_banking/config.lua`. This setting is not exposed in WHIP Core's `/whip` config editor. You must restart **`whip_core`** (or the full server) for the original prompt to disappear. Recheck this line after updating WHIP Core. If you installed the separate `whip-atmdui` reference resource, stop it to prevent competing screens.

### 3. Check your start order

In `server.cfg`, ensure WHIP Banking starts **after** WHIP Core:

```cfg
ensure oxmysql
ensure whip_core
ensure whip_banking
```

Do not duplicate `ensure` entries if `oxmysql` and `whip_core` already start elsewhere in your config.

### 4. Check the bank-card accessory slot

By default, the resource registers inventory **slot 5** as **Bank Card**, replacing the last of WHIP's three vehicle-key slots. The other two key slots remain available.

```lua
-- whip_banking/config.lua
Config.CardAccessorySlot = 5
```

This is designed to work with the WHIP and D11 inventory displays without editing their files. Existing keys in slot 5 are not deleted; move them to your pockets before equipping a bank card.

To keep all three key slots, set `Config.CardAccessorySlot = false`. You can also choose another unused accessory slot. If registration fails, check your server console for a slot conflict or accessory-row size warning.

### 5. Start the server and confirm the database

On startup, the resource is documented to create these tables in your **existing WHIP database**:

```text
whip_banking_cards
whip_banking_loans
whip_banking_loan_payments
whip_banking_credit
whip_banking_interest
whip_banking_bills
whip_banking_schedules
```

**No manual SQL import is required** according to the provided release notes. Look for:

```text
[whip_banking] Database ready; using WHIP native banking ledger
```

### 6. Complete a first-use test

Join with a fully loaded character, visit a branch, interact with a teller, issue a bank card and check that it appears in inventory. Then approach an ATM and test the physical-card/PIN workflow using a **low-value** withdrawal.

---

## How players use it

### 🏛️ Bank branch

Approach a teller and press **E** to start a WHIP conversation. The banking dashboard covers accounts, transfers, transactions, cards, savings, loans and more. **New bank cards must be issued through a teller.**

### 💳 Physical bank card

The card item is named **`maze_bank_card`**. Each card has a serial number, an account link and a salted four-digit PIN. Players can:

- Use their card from inventory to open personal digital banking.
- Drag it into the dedicated **Bank Card** equipped slot.
- Freeze or cancel a card, or change its PIN.
- Use the card at an ATM; **three incorrect PIN attempts** trigger a **15-minute lockout**.

Cancelled cards may remain as inventory items, but they no longer authorise new ATM sessions.

### 🏧 ATM

Walk up to an ATM, press **E**, then choose **Insert Card** or **Tap Here**. Select a card and enter its PIN. Available actions are:

| Input | Action |
| :-- | :-- |
| `1` | Fast Cash |
| `2` | Withdraw |
| `3` | Balance |
| `Esc` | Cancel / exit |

**ATMs are withdrawal-only.** Deposits are intentionally unavailable. The documented daily limit is **$5,000** by default, based on WHIP's actual `bank_transactions` records; adjust it through banking settings.

### 💰 Savings, loans and payments

- **Savings:** Open savings pots in Accounts and use real WHIP account numbers for transfers. The documented default savings APR is **2%**, with interest processed monthly.
- **Loans:** Choose from three products with credit-score, borrowing-limit and active-loan checks. Funds are paid into the WHIP main account; instalments are due on a **30-day** interval.
- **Bills:** Approved server resources can issue invoices payable into a real creditor account.
- **Standing orders:** Schedule recurring transfers every **7, 14 or 30 days**; an order pauses if its owner loses withdrawal permission.

---

## Bank locations & map markers

Eight built-in teller locations are documented:

| City branches | Wider map branches |
| :-- | :-- |
| Legion Square | Great Ocean |
| Hawick | Route 68 |
| Alta Street | Paleto Bay |
| Rockford Hills | Pacific Standard |

Bank markers are registered through **WHIP Core's server-side `ShowBlip` system**, not standalone GTA map blips. This is important because WHIP's pause map may replace the names of non-WHIP blips with a sprite's default label.

- **Full map:** all eight branch locations.
- **Minimap:** nearby branches only, by default.
- **Map legend:** one grouped **Maze Bank (8)** entry, by default.
- **Optional:** show individual branch names such as **Maze Bank - Paleto Bay**.

Changes made to branch positions and names in `/whip` are intended to update their WHIP blips without restarting the resource.

## Configure everything in `/whip`

For normal tuning, open **`/whip → Settings → Banking`** with the appropriate WHIP administrator access.

| Settings category | Editable options |
| :-- | :-- |
| **Bank map blips** | Visibility, icon, colour, scale, minimap range, branch names, legend name |
| **ATM screens** | Standby display, world-screen fallback, models, materials, draw distance, preview, interaction range |
| **Accounts & cards** | Display bank name, currency symbol, card limit, cash limit, savings APR, credit defaults |
| **Loan products** | Personal / vehicle / business limits, APRs, terms and minimum credit scores |
| **Individual ATM models** | Horizontal centre, depth, height, width, screen height and face tilt |
| **Bank branches** | Ped model, teller names, interaction positions, ped positions and interaction distance |

The four default ATM prop models are:

```lua
prop_atm_01
prop_atm_02
prop_atm_03
prop_fleeca_atm
```

> [!TIP]
> **Saved settings override config defaults.** If a new update appears to ignore an ATM position or blip setting, inspect the previously saved `/whip` values first.

### Place or move tellers

Within the corresponding branch setting, use **Use where I stand** for its `vec4` position. The WHIP-managed teller ped should respawn at the updated location. No banking-specific chat command is required.

---

## ATM screen system

WHIP Banking uses two display paths:

1. **Standby screen:** a shared red Maze Bank display appears on supported ATMs using native texture replacement (`AddReplaceTexture`). A world-space fallback is available for retextured/custom MLO machines where the native material does not display.
2. **Private customer screen:** a second DUI appears **only on the ATM currently in use**, keeping neighbouring screens on standby instead of exposing account details or a PIN.

The native materials described for the reference method include `prop_cashpoint_screen` and `prop_fleece_emis`. Only add the **screen material** for a custom ATM, not a texture for its bezel or body.

### Live alignment console (developer only)

1. Enable WHIP **Developer Mode** through `/w` (requires `whip.devtools`).
2. Stand beside an ATM and open **`/w → Panels → Banking - ATM Alignment → Align nearest ATM`**.
3. Move the cyan screen guide until it precisely covers the physical ATM display.
4. Select **Save This Model**, then use **Next ATM** to move through nearby machines.
5. When finished, choose **Export All JSON → Copy JSON** (or **Download .JSON**, where supported).

The exported file is named `whip_banking_atm_alignment.json`. A developer can integrate these offsets into `Config.AtmScreens` so **all** players receive the calibrated positions.

| Keys | Effect |
| :-- | :-- |
| `←` / `→` or `A` / `D` | Move left / right |
| `↑` / `↓` or `E` / `Q` | Move up / down |
| `PgUp` / `PgDn` or `W` / `S` | Move out from / into the ATM |
| `Z` / `X` | Narrow / widen |
| `C` / `V` | Shorten / heighten |
| `R` / `F` | Increase / decrease face tilt |
| `Enter` | Save current model |
| `Esc` | Close the editor or JSON view |

The **Adjustment Step** setting supports coarse and fine movement; numeric fields allow exact values. Use **⇄** to swap the editor between screen sides. **Reset Model** requires two presses.

Local alignment data is stored using FiveM resource KVP on the developer's PC. It persists across local game restarts but **does not immediately change server settings or other players' screens**. Use **Export all ATM positions** from the `/w` panel even when no ATM is nearby.

> [!CAUTION]
> Close the alignment editor **before** using the ordinary ATM interaction. After calibration, verify the camera, touch targets and visible screen edges on each actual prop/MLO variant.

### Alternative: calibrate through `/whip`

Open **`/whip → Settings → Banking → ATM screens`**, enable **ATM screen alignment preview**, then edit the values for the relevant ATM model while observing its cyan border. **More negative depth** moves the panel towards the player; **more positive depth** moves it into the ATM. Disable the preview when finished.

For a Fleeca/LG-Zone-style ATM, the source notes suggest **horizontal −0.095 m, depth +0.045 m, height 1.180 m, width 0.285 m, screen height 0.205 m** as an initial test only. Final offsets depend on the exact streamed prop and MLO.

---

## Performance & Resmon

The source describes a shared standby DUI created once and a private ATM DUI created only when needed. Its client checks nearby ATM models before scanning broader object pools, caches fallback coordinates, and sleeps when no screen needs to be rendered.

| Situation | Expected behaviour |
| :-- | :-- |
| Away from ATMs | Designed to show **0.00 ms most of the time**, with occasional proximity probes |
| Near active world-space standby displays | Some rendering cost is normal because the fallback must draw each frame |
| ATM menu or alignment editor open | Additional rendering/UI cost is expected |

If all your machines correctly show standby screens through native texture replacement, you can disable **`Config.AtmWorldStandbyFallback`** in `/whip → Settings → Banking` to remove per-frame standby quads. **Do not disable it if custom MLO machines become blank.**

**How to measure:** restart `whip_banking`, allow DUI assets to load, then open `resmon 1`. Compare idle usage away from ATMs, next to a standby machine, while using an ATM, and during alignment. Test vanilla machines **and** custom MLOs.

> **Resmon note:** An uninterrupted `0.00 ms` is not guaranteed; real measurements depend on nearby props, camera state, the client and the chosen fallback mode.

## Developer exports

### Create a trusted bill

Call this from **another server-side resource**. Bill creation should not be exposed as a public client event.

```lua
local invoiceId, why = exports.whip_banking:CreateBill(
    source,                   -- payer's current server ID
    'Vehicle repair invoice', -- title
    1200,                     -- amount in WHIP dollars
    garageBusinessAccountId,  -- destination account; nil to deduct
    7,                        -- due in 7 days
    'mechanic'                -- category
)
```

### Read a credit score

```lua
local score = exports.whip_banking:GetCreditScore(source)
```

According to the provided notes, the resource applies server-side ownership checks, account permissions, per-operation rate limits and startup reconciliation for interrupted finance operations.

---

## Troubleshooting

<details>
<summary><strong>Two ATM prompts appear on the same machine</strong></summary>

Set `Config.AtmProps = {}` in **`whip_core/config.lua`**, restart **`whip_core`** or the full server, and stop any separate `whip-atmdui` resource.

</details>

<details>
<summary><strong>ATM standby screen is blank on a custom MLO</strong></summary>

Re-enable the world-space standby fallback in `/whip`. Check that the custom model is listed and that its screen-only texture mapping is correct. Use the in-game alignment tools to correct its position.

</details>

<details>
<summary><strong>Interactive ATM screen floats above or inside the prop</strong></summary>

Run the developer alignment console for the actual prop model, save its local offset and export the JSON for permanent integration. Test from a side angle because perspective can exaggerate small offsets.

</details>

<details>
<summary><strong>Bank blips show a generic or incorrect name</strong></summary>

Confirm you are running the resource's WHIP-native blip implementation. In `/whip → Settings → Banking → Bank map blips`, use **Nearby-only minimap blips = ON**. Set **Include branch names in blips = OFF** for one grouped **Maze Bank (8)** legend entry. Clear the **Map legend bank name** override to inherit the bank name. Previously saved settings may persist after upgrading.

</details>

<details>
<summary><strong>Bank card slot is unavailable</strong></summary>

Check `Config.CardAccessorySlot` and the server log for registration warnings. Make sure the accessory strip supports the chosen slot and another resource has not claimed it. Set the option to `false` to restore the original three key slots.

</details>

<details>
<summary><strong>Setting a new default does not change the screen</strong></summary>

WHIP's saved `/whip` values take precedence over new file defaults. Inspect the saved ATM model and screen settings, including any local alignment overrides.

</details>

## Pre-launch checklist

- [ ] All eight tellers appear at the correct desks, facing players; no duplicates after restart.
- [ ] Multiple nearby ATMs show standby screens at the same time.
- [ ] All four default ATM models render correctly; custom MLO machines have been tested.
- [ ] Using one ATM changes only that ATM to the private customer display.
- [ ] ATM screen guides, camera position, keypad and buttons align with each machine.
- [ ] Card issuance, inventory, equipped slot, PIN retry limit, PIN change, freeze and cancellation work.
- [ ] Cash withdrawal and failed-capacity handling never create or lose money.
- [ ] Account transfers, savings, loan funding, instalments and bill payments reconcile correctly.
- [ ] Grouped/individual bank map names and nearby-only minimap behaviour are correct.
- [ ] All gameplay and finance state survives a **full server restart**.
- [ ] `resmon 1` has been checked both near and away from ATMs.

> [!WARNING]
> **Known boundaries:** The normal ATM UI applies card/PIN and withdrawal-limit checks, but WHIP Core's public ATM callbacks may still be callable by other resources. WHIP's real account numbers are retained instead of replacing them with decorative example numbers. Ambiguous loan disbursements can enter a `review` state, requiring staff to inspect the bank ledger before resolving them. Validate these flows against your installed WHIP version.

---

## Credits & attribution

<div align="center">

### ✦ 𝘾𝙊𝙊𝙆𝙄𝙀 𝙊𝘾𝙊𝙍𝙀 ✦

**Development & integration**

<sub>MADE FOR THE WORLD OF WHIP • BUILT FOR ROLEPLAY</sub>

</div>

- Built for the [WHIP Core framework](https://github.com/WHIPFX/whip_core) and its banking, UI, inventory and map APIs.
- The ATM screen replacement approach was informed by the supplied `whip-atmdui-1.1.0` reference; the source notes state its bundled art and code were **not** copied into this release.
- Barlow and Barlow Condensed fonts originate from WHIP's font assets. Consult the SIL Open Font License notices distributed with the resource in `html/fonts/`.
- **Maze Bank, Grand Theft Auto V and related fictional branding** are the property of their respective owners, including Rockstar Games. This is an independent FiveM resource, not an official Rockstar product.

<div align="center">

---

**MAZE BANK** · `whip_banking` · **v1.2.6**

<sub>✦ COOKIE OCORE ✦</sub>

</div>
