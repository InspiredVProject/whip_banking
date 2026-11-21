-- v2.6: The keypad is laid out from the physical ATM keypad reference image,
-- not a generic four-by-four number pad.  Positions below are proportions of
-- the whole keypad bezel. The right action buttons are wider; row three is blank.
-- The keypad rectangle is placed relative to the already-calibrated DUI screen:
-- left/top = offsets from DUI top-left (1.0 = one DUI width/height).
-- width/height = overall keypad bezel size relative to the DUI width/height.
-- Leave the screen calibration alone. Old firstX/stepX/... settings are ignored.
-- The entire keypad may be moved using ONLY left/top/width/height in /whip.
local keypad = {left=0.225, top=1.555, width=0.555, height=0.475}
Config.AtmHardware = Config.AtmHardware or {}
local models={
    default={side=0.24,out=-0.21,up=1.075},
    prop_atm_01={side=0.23,out=-0.21,up=1.065},
    prop_atm_02={side=0.24,out=-0.21,up=1.075},
    prop_atm_03={side=0.24,out=-0.21,up=1.075},
    prop_fleeca_atm={side=0.24,out=-0.21,up=1.075},
}
for model, slot in pairs(models) do
    -- Preserve the existing physical card insertion geometry and any user edits.
    local previous=Config.AtmHardware[model] or {}
    local current=previous.keypad or {}
    for k,v in pairs(keypad) do if current[k]==nil then current[k]=v end end
    previous.keypad=current
    previous.slot=previous.slot or {side=slot.side,out=slot.out,up=slot.up,width=0.085,height=0.054}
    Config.AtmHardware[model]=previous
end
