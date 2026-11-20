-- Native WHIP /whip -> Settings -> Banking page. WHIP validates, persists and replicates changes.
-- No extra dashboard resource, admin command, or config-editing restart is required.

local groups = {
    { label = 'Bank map blips', settings = {
        { key='Blips.Enabled', type='bool', label='Show all bank branches',
          help='Adds a map blip for every branch in the Banks list. Turn off to remove all of them.' },
        { key='Blips.Sprite', type='int', min=1, max=900, label='Bank blip icon ID',
          help='GTA map sprite number. Default 108 (red dollar icon). Its built-in name is replaced by the bank legend below.' },
        { key='Blips.Colour', type='int', min=0, max=85, label='Bank blip colour',
          help='GTA blip colour number. Default 1 (red).' },
        { key='Blips.Scale', type='number', min=0.3, max=1.5, step=0.05, label='Bank blip size' },
        { key='Blips.ShortRange', type='bool', label='Nearby-only minimap blips',
          help='Recommended ON: all branches remain on the full map, but only nearby banks appear on the minimap. Applies immediately.' },
        { key='Blips.BranchNames', type='bool', label='Include branch names in blips',
          help='OFF: one Maze Bank legend entry with a count of all banks. ON: individual names such as Maze Bank - Legion Square.' },
        { key='Blips.LegendName', type='string', maxLen=40, label='Map legend bank name',
          help='Leave empty to use the bank display name, such as Maze Bank. WHIP owns the blips and uses this text in its pause-map legend.' },
    } },
    { label = 'ATM screens', settings = {
        { key='AtmStandbyEnabled', type='bool', label='Always-on ATM standby screens',
          help='Places the Maze Bank welcome screen on the ATM model’s real display material. No 3D positioning needed.' },
        { key='AtmWorldStandbyFallback', type='bool', label='3D standby screen fallback',
          help='Also renders the standby screen over every nearby ATM prop. Leave on for custom/MLO ATM textures that ignore material replacement.' },
        { key='AtmInteractiveOverlay', type='bool', label='Private interactive ATM screen',
          help='Shows a customer’s transaction on their machine only. Leave on to prevent nearby identical ATMs showing their PIN/balance.' },
        { key='AtmDrawDistance', type='number', min=4, max=45, step=1, unit='m', label='Interactive display distance',
          help='Draw distance of the private on-machine overlay. Idle displays use the actual ATM texture.' },
        { key='AtmOverlayPreview', type='bool', label='ATM screen alignment preview',
          help='Temporarily displays an alignment guide on the closest ATM for tuning its model offsets. Turn off when finished.' },
        { key='ATMs', type='list', label='ATM prop models',
          item={type='string',maxLen=80}, minItems=1, maxItems=30,
          help='Vanilla ATM models are preloaded. Add any extra streamed custom prop model names here; unfamiliar models use the default overlay placement.' },
        { key='AtmScreenMaterials', type='map', label='ATM native screen textures', maxItems=30,
          fields={
              {key='dict',type='string',maxLen=80,label='Texture dictionary'},
              {key='name',type='string',maxLen=80,label='Screen texture name'},
          },
          help='Physical screen texture for each ATM prop model. Add entries for custom ATM YTD models here; use screen-only textures, not the hardware or bezel.' },
        { key='AtmRange', type='number', min=1, max=8, step=0.1, unit='m', label='ATM interaction distance' },
    } },
    { label = 'Accounts & cards', settings = {
        { key='Brand', type='string', maxLen=30, label='Bank display name' },
        { key='Currency', type='enum', label='Currency symbol', options={{value='$',label='Dollar ($)'},{value='£',label='Pound (£)'}} },
        { key='MaxCards', type='int', min=1, max=15, label='Maximum cards per character' },
        { key='AtmDailyLimit', type='int', min=100, max=1000000, step=100, label='Daily ATM withdrawal limit', unit='$' },
        { key='SavingsApr', type='number', min=0, max=30, step=0.1, label='Savings annual interest', unit='%' },
        { key='DefaultCredit', type='int', min=300, max=850, label='Starting credit score',
          help='Changes the baseline for all existing and new characters. Stored credit events are still included.' },
        { key='MaxActiveLoans', type='int', min=1, max=8, label='Concurrent loans per character' },
    } },
}

local loanGroups = {
    {label='Personal loans', idx=1},
    {label='Vehicle finance', idx=2},
    {label='Business loans', idx=3},
}

for _, loan in ipairs(loanGroups) do
    local key = 'Loans.' .. loan.idx .. '.'
    groups[#groups+1] = {label=loan.label, settings={
        {key=key..'max', type='int', min=100, max=10000000, step=100, unit='$', label='Maximum loan amount'},
        {key=key..'rate', type='number', min=0, max=100, step=0.1, unit='%', label='Annual interest rate'},
        {key=key..'months', type='int', min=1, max=120, label='Repayment term', unit='months'},
        {key=key..'minScore', type='int', min=300, max=850, label='Minimum credit score'},
    }}
end

local models = {
    {label='ATM 01 / Wall', key='prop_atm_01'},
    {label='ATM 02 / Freestanding', key='prop_atm_02'},
    {label='ATM 03 / Freestanding', key='prop_atm_03'},
    {label='Fleeca ATM', key='prop_fleeca_atm'},
    {label='Other ATM models', key='default'},
}

for _, model in ipairs(models) do
    local key = 'AtmScreens.' .. model.key .. '.'
    local guide = 'Local metres relative to ATM origin, using the physical screen. Changes update the live interactive DUI placement.'
    groups[#groups+1] = {label=model.label..' screen',settings={
        {key=key..'side',type='number',min=-1,max=1,step=0.005,unit='m',label='Horizontal screen centre',help=guide},
        {key=key..'out',type='number',min=-1,max=1,step=0.005,unit='m',label='Depth (front / back)',help='More negative moves the DUI out towards the player. If the original blue screen shows, bring this forward.'},
        {key=key..'up',type='number',min=0,max=3,step=0.005,unit='m',label='Height above ATM base'},
        {key=key..'width',type='number',min=0.05,max=1.5,step=0.005,unit='m',label='Screen width'},
        {key=key..'height',type='number',min=0.05,max=1.5,step=0.005,unit='m',label='Screen height'},
        {key=key..'tilt',type='number',min=-1,max=1,step=0.01,label='Screen face tilt',help='How far the screen moves in local Y for each 1m upwards. Allows tilted ATM displays to sit flush.'},
    }}
end

local branches = { 'Legion Square', 'Hawick', 'Alta Street', 'Rockford Hills',
                   'Great Ocean', 'Route 68', 'Paleto Bay', 'Pacific Standard' }

groups[#groups+1] = {label='Bank branches',settings={
    {key='BranchRange',type='number',min=1,max=8,step=0.1,unit='m',label='Teller interaction range'},
    {key='TellerModel',type='string',maxLen=70,label='Teller ped model',
     help='Changing the model updates existing bank tellers.'},
}}

for i, label in ipairs(branches) do
    local key = 'Branches.'..i..'.'
    groups[#groups+1] = {label=label,settings={
        {key=key..'name',type='string',maxLen=60,label='Branch name'},
        {key=key..'coords',type='vec4',here=true,label='Teller interaction position',
         help='The E interaction position. Use where I stand to set it.'},
        {key=key..'teller',type='vec4',here=true,label='Teller ped position',
         help='Moving this position respawns the bank employee at the new counter.'},
    }}
end

Whip.configPage({label='Banking',groups=groups})
