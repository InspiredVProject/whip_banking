Config = {}

Config.Brand = 'MAZE BANK'
Config.Currency = '$' -- Screenshot-accurate; change to '£' for a UK economy.
Config.CardItem = 'maze_bank_card'
-- Replace WHIP's third vehicle-key slot with a dedicated Maze Bank card slot.
-- The accessory strip defaults to 1=Phone, 2=Money, 3/4/5=Vehicle Keys.
-- Set false to leave all three vehicle-key slots unchanged.
Config.CardAccessorySlot = 5
Config.MaxCards = 4
Config.AtmDailyLimit = 5000
Config.AtmRange = 2.6
Config.AtmStandbyEnabled = true -- Replace the ATM model's real display texture, including on idle machines.
Config.AtmInteractiveOverlay = true -- Keep one customer's session on their ATM, not every identical model.
Config.AtmWorldStandbyFallback = true -- Draw each streamed ATM screen if a custom YTD ignores native replacement.
Config.AtmDrawDistance = 23.0 -- Maximum distance for world-space screen surfaces.
Config.AtmOverlayPreview = false -- Temporary calibration aid: show the quad on the nearest ATM while idle.
Config.BranchRange = 3.2
-- WHIP owns these markers via its ShowBlip API, so the custom pause-map legend
-- actually reads the bank name (unlike native blips, which show "Financier strand").
-- Every branch stays visible on the full map; only nearby ones appear on the minimap.
-- Edit icon, colour, size, label and visibility in /whip -> Banking.
Config.Blips = {
    Enabled = true,
    Sprite = 108,          -- GTA's red financier/dollar marker.
    Colour = 1,            -- Maze Bank red.
    Scale = 0.78,
    ShortRange = true,     -- Only close branches appear on the minimap.
    BranchNames = false,   -- One "Maze Bank" map legend group with all 8 banks.
    LegendName = '',       -- Blank uses the Bank display name in title case.
}
Config.DefaultCredit = 650
Config.MinCredit = 300
Config.MaxCredit = 850
Config.MaxActiveLoans = 2
Config.SavingsApr = 2.0 -- Annual percentage, credited monthly for qualifying WHIP savings accounts.

Config.Loans = {
    { key = 'personal', label = 'Personal loan', max = 15000, rate = 8.5, months = 6, minScore = 540 },
    { key = 'vehicle', label = 'Vehicle finance', max = 50000, rate = 6.2, months = 12, minScore = 620 },
    { key = 'business', label = 'Business loan', max = 100000, rate = 9.8, months = 18, minScore = 710 }
}

-- These are the public vanilla GTA V branch counters; adapt locations for a custom bank MLO.
-- Each entry spawns one persistent, synchronized WHIP NPC, not a duplicated local ped.
Config.Branches = {
    { name = 'Legion Square', coords = vector4(149.11, -1042.07, 29.37, 340.0), teller = vector4(149.37, -1042.19, 29.37, 160.0) },
    { name = 'Hawick', coords = vector4(313.28, -280.59, 54.16, 340.0), teller = vector4(313.53, -280.32, 54.16, 160.0) },
    { name = 'Alta Street', coords = vector4(-351.02, -51.25, 49.04, 337.0), teller = vector4(-351.26, -50.92, 49.04, 158.0) },
    { name = 'Rockford Hills', coords = vector4(-1212.35, -331.98, 37.78, 28.0), teller = vector4(-1211.67, -331.40, 37.78, 207.0) },
    { name = 'Great Ocean', coords = vector4(-2962.53, 482.96, 15.70, 90.0), teller = vector4(-2961.94, 482.90, 15.70, 270.0) },
    { name = 'Route 68', coords = vector4(1175.01, 2706.67, 38.09, 0.0), teller = vector4(1175.03, 2707.23, 38.09, 180.0) },
    { name = 'Paleto Bay', coords = vector4(-112.20, 6471.06, 31.63, 310.0), teller = vector4(-112.51, 6470.77, 31.63, 130.0) },
    { name = 'Pacific Standard', coords = vector4(236.78, 219.39, 106.29, 155.0), teller = vector4(236.53, 219.16, 106.29, 335.0) }
}

Config.TellerModel = 'u_m_m_bankman'

Config.ATMs = {
    -- These model names are also registered with WHIP AddAction, so MLO ATMs work automatically.
    'prop_atm_01', 'prop_atm_02', 'prop_atm_03', 'prop_fleeca_atm'
}

-- Interactive session overlays are model-local metres and calibrated against the physical keypad.
-- Standby tries the model's native screen material AND has a world-space fallback for
-- custom MLO textures. These offsets control both the private and fallback quads.
-- tilt is the local-Y change per metre of height: most ATM faces lean backwards near the top.
Config.AtmScreens = {
    default = { side = -0.095, out = 0.045, up = 1.18, width = 0.285, height = 0.205, tilt = 0.17 },
    prop_atm_01 = { side = -0.038, out = -0.125, up = 1.11, width = 0.22, height = 0.16, tilt = 0.15 },
    prop_atm_02 = { side = -0.095, out = 0.045, up = 1.18, width = 0.285, height = 0.205, tilt = 0.17 },
    prop_atm_03 = { side = -0.095, out = 0.045, up = 1.18, width = 0.285, height = 0.205, tilt = 0.26 },
    prop_fleeca_atm = { side = -0.095, out = 0.045, up = 1.18, width = 0.285, height = 0.205, tilt = 0.17 }
}

-- Screen-material names from the user's whip-atmdui 1.1.0 reference. Never replace an ATM's
-- whole hardware texture as a fallback: that would colour its bezel, keypad and cash slot.
Config.AtmScreenMaterials = {
    prop_atm_01 = {dict='prop_atm_01', name='prop_cashpoint_screen'},
    prop_atm_02 = {dict='prop_atm_02', name='prop_cashpoint_screen'},
    prop_atm_03 = {dict='prop_atm_03', name='prop_cashpoint_screen'},
    prop_fleeca_atm = {dict='prop_fleeca_atm', name='prop_fleece_emis'}
}
