local CORE = exports.whip_core
local visible = false
local mode = nil
local activeAtm = nil
local terminalBankKey = nil -- Active session is branded to the character's registered bank.
local personalBankKey = nil -- Cached server-authoritative WHIP bank membership for standby displays.
local previewCardNumber = nil -- Card number accepted by server only after using the physical inventory item.
local atmCamera = nil
local activeDui = nil
local cardDui = nil
local atmOverviewCards = nil -- Only rows returned by WHIP Core for this character.
local atmCardOwnerName = nil
local cardAnimationNonce = 0
local keypadLastSent = nil
local keypadActive = false
local keypadTestMode = false -- dev-only verification of the actual live ATM hotspots
local keypadEditorReadyAt = 0 -- camera must finish blending before calibration
local keypadAlignState = nil   -- Developer-only visual keypad editor (not the DUI-screen editor).
local keypadAlignKvp = 'whip_banking_keypad_alignment_v1'
local savedKeypadAlignments = {}
local keypadEditable = {
    left={-0.3,1.2}, top={0.75,3.0}, width={0.2,1.5}, height={0.2,1.5}
}
local function boundedKeypad(input,base)
    local result={}
    for field,range in pairs(keypadEditable) do
        local n=type(input)=='table' and tonumber(input[field]) or nil
        if not n or n~=n or math.abs(n)>10000 then n=tonumber(base and base[field]) or (field=='left' and 0.225 or field=='top' and 1.555 or field=='width' and 0.555 or 0.475) end
        result[field]=math.floor(math.max(range[1],math.min(range[2],n))*10000+0.5)/10000
    end
    return result
end
-- These are client-side editing previews. Apply the exported JSON in the resource
-- for server-wide positions; no untrusted client event changes shared WHIP settings.
do
    local raw=GetResourceKvpString(keypadAlignKvp)
    if raw and #raw<20000 then
        local ok,values=pcall(json.decode,raw)
        if ok and type(values)=='table' then
            for model,pad in pairs(values) do
                if type(model)=='string' and #model<=80 and type(pad)=='table' then
                    savedKeypadAlignments[model]=boundedKeypad(pad)
                end
            end
        end
    end
end
local standbyDuis = {}
local function atmBankKey(model)
    local mapping = (Config.AtmModelBanks or {})[model]
    local key = type(mapping)=='table' and mapping.bank or mapping
    return Config.Banks and Config.Banks[key] and key or 'maze'
end
local function shownBankKey(model)
    return (personalBankKey and Config.Banks[personalBankKey]) and personalBankKey or atmBankKey(model)
end
local function idleFrame(bankKey)
    local b=Config.Banks[bankKey] or Config.Banks.maze
    return {screen='idle',bankKey=bankKey,brand=b.name,currency=Config.Currency}
end
local duiState = {screen='idle'}
local cachedAtms = {}
local geometryEpoch = 0
local remainingLimit = Config.AtmDailyLimit
local objectHashes = {}
local modelHashes = {}
local nativeReplacements = {}
local actionsRegistered = false
local alignState = nil
local savedAlignments = {}
local alignKvp = 'whip_banking_atm_alignment_v1'

local alignFields = {
    side={-1.0,1.0},out={-1.0,1.0},up={0.0,3.0},
    width={0.05,1.5},height={0.05,1.5},tilt={-1.0,1.0}
}

local function copyAlignment(input, fallback)
    local result = {}
    fallback = fallback or Config.AtmScreens.default
    for key, bounds in pairs(alignFields) do
        local val = type(input)=='table' and tonumber(input[key]) or nil
        if not val or val ~= val or val == math.huge or val == -math.huge then
            val = tonumber(fallback[key]) or 0.0
        end
        result[key] = math.floor(math.max(bounds[1],math.min(bounds[2],val))*10000+0.5)/10000
    end
    return result
end

do
    local raw = GetResourceKvpString(alignKvp)
    if raw and #raw <= 25000 then
        local ok, parsed = pcall(json.decode,raw)
        if ok and type(parsed)=='table' then
            for model, entry in pairs(parsed) do
                if type(model)=='string' and #model <= 80 and type(entry)=='table' then
                    savedAlignments[model] = copyAlignment(entry,Config.AtmScreens[model])
                end
            end
        end
    end
end

local function rebuildModelHashes()
    objectHashes = {}
    modelHashes = {}
    for _, name in ipairs(Config.ATMs) do
        if type(name) == 'string' and #name > 0 then
            local hash = GetHashKey(name)
            objectHashes[hash] = name
            modelHashes[#modelHashes+1] = {hash=hash,name=name}
        end
    end
end
rebuildModelHashes()

local function notify(message, kind)
    CORE:Notify(message, kind or 'info')
end

local function request(name, ...)
    return CORE:Callback('whip_banking:' .. name, ...)
end

local function status(data)
    if activeDui and activeDui.ready then SendDuiMessage(activeDui.browser, json.encode(data)) end
end

-- Replacing the ATM screen material is the accurate positioning method from the user's
-- whip-atmdui reference. One shared idle browser lights EVERY matching streamed ATM,
-- without scanning or drawing a polygon for each one.
local function createDui(dict, width, height)
    local browser = CreateDui(('nui://%s/html/dui.html'):format(GetCurrentResourceName()), width, height)
    if not browser then
        print('[whip_banking] Could not create ATM screen ' .. dict)
        return nil
    end
    local result = {browser=browser,dict=dict,tex='screen',ready=false}
    CreateThread(function()
        -- The supplied whip-atmdui reference allows the Chromium handle to initialise
        -- before building its runtime texture. Keep this wait out of WHIP config callbacks.
        Wait(250)
        if not result.browser then return end
        local txd = CreateRuntimeTxd(dict)
        CreateRuntimeTextureFromDuiHandle(txd, 'screen', GetDuiHandle(result.browser))
        local deadline = GetGameTimer() + 10000
        while result.browser and not IsDuiAvailable(result.browser) and GetGameTimer() < deadline do Wait(100) end
        if result.browser and IsDuiAvailable(result.browser) then
            result.ready = true
            local idleKey=dict:match('^whip_banking_idle_(%w+)$')
            SendDuiMessage(result.browser,json.encode(idleKey and idleFrame(idleKey) or duiState))
            if idleKey then
                -- The material replacement must be installed even when the player has never used an ATM.
                TriggerEvent('whip_banking:standbyReady')
            else
                TriggerEvent('whip_banking:activeReady')
            end
        else
            print('[whip_banking] ATM DUI page did not become available: ' .. dict)
            if result.browser then DestroyDui(result.browser); result.browser = nil end
            if activeDui == result then activeDui = nil end
            for key,dui in pairs(standbyDuis) do
                if dui==result then standbyDuis[key]=nil end
            end
        end
    end)
    return result
end

local function materialKey(material)
    return material.dict .. '/' .. material.name
end

local function refreshNativeScreens()
    local wanted={}
    if Config.AtmStandbyEnabled then
        for model,material in pairs(Config.AtmScreenMaterials or {}) do
            if objectHashes[GetHashKey(model)] and type(material)=='table'
               and material.dict and material.name then
                local key=shownBankKey(model)
                local standby=standbyDuis[key]
                if standby and standby.ready then
                    local active=mode=='atm' and not Config.AtmInteractiveOverlay
                      and activeAtm and DoesEntityExist(activeAtm)
                      and objectHashes[GetEntityModel(activeAtm)]==model
                      and activeDui and activeDui.ready
                    local target=active and activeDui or standby
                    wanted[materialKey(material)]={material=material,dict=target.dict}
                end
            end
        end
    end
    for key,old in pairs(nativeReplacements) do
        if not wanted[key] or old.dict~=wanted[key].dict then
            RemoveReplaceTexture(old.material.dict,old.material.name)
            nativeReplacements[key]=nil
        end
    end
    for key,nextOne in pairs(wanted) do
        if not nativeReplacements[key] then
            AddReplaceTexture(nextOne.material.dict,nextOne.material.name,nextOne.dict,'screen')
            nativeReplacements[key]=nextOne
        end
    end
end

AddEventHandler('whip_banking:standbyReady', refreshNativeScreens)
AddEventHandler('whip_banking:activeReady', refreshNativeScreens)

-- Keep the standby DUI alive for all ATM material replacements. The private
-- session browser is allocated only when an ATM (or calibration) actually needs
-- it; an idle player no longer pays for two Chromium pages from login.
local function ensureDuis(needsPrivate)
    for _,key in ipairs({'maze','fleeca','pacific'}) do
        if not standbyDuis[key] then
            standbyDuis[key]=createDui('whip_banking_idle_'..key,1024,768)
        end
    end
    if needsPrivate and not activeDui then activeDui = createDui('maze_bank_private', 1024, 768) end
end

local function setScreen(frame)
    duiState = frame
    ensureDuis(mode == 'atm' or alignState ~= nil or Config.AtmOverlayPreview)
    status(frame)
end

local function findClosestAtm(range)
    local pos = GetEntityCoords(PlayerPedId())
    local result, chosen, best = nil, nil, range or 18.0
    for _, item in ipairs(modelHashes) do
        local entity = GetClosestObjectOfType(pos.x, pos.y, pos.z, best, item.hash, false, false, false)
        if entity ~= 0 and DoesEntityExist(entity) then
            local d = #(pos - GetEntityCoords(entity))
            if d < best then result, chosen, best = entity, item.name, d end
        end
    end
    return result, chosen, best
end

local function screenOffset(entity, name)
    local spec = (alignState and alignState.entity == entity and alignState.spec)
        or savedAlignments[name] or Config.AtmScreens[name] or Config.AtmScreens.default
    local center = GetOffsetFromEntityInWorldCoords(entity, spec.side, spec.out, spec.up)
    -- Derive the local right basis from the object's actual matrix; the screen stays aligned on a rotated ATM.
    local rightTip = GetOffsetFromEntityInWorldCoords(entity, 1.0, 0.0, 0.0)
    local origin = GetEntityCoords(entity)
    local r = rightTip - origin
    local m = #r
    if m < 0.001 then return nil end
    -- Match the slope of the ATM's physical face, not a flat vertical billboard.
    local upTip = GetOffsetFromEntityInWorldCoords(entity, 0.0, spec.tilt or 0.0, 1.0)
    local up = upTip - origin
    local um = #up
    if um < 0.001 then return nil end
    return center, r / m, up / um, spec
end

-- Both the live editor and real banking must use precisely the same camera.
-- Previously the editor used a 55-degree FOV at 1.55m, but banking used
-- 51 degrees at 1.05m and a different aim height. That made any screen-space
-- keypad calibration shift after saving, even though KVP values were correct.
local function createBankAtmCamera(entity, center, spec)
    local view=GetOffsetFromEntityInWorldCoords(entity, spec.side, spec.out-1.05, spec.up+0.12)
    local cam=CreateCam('DEFAULT_SCRIPTED_CAMERA',true)
    SetCamCoord(cam,view.x,view.y,view.z)
    PointCamAtCoord(cam,center.x,center.y,center.z)
    SetCamFov(cam,51.0)
    SetCamActive(cam,true)
    RenderScriptCams(true,true,450,true,false)
    return cam
end

local function closeUI()
    if mode == 'atm' then CORE:Callback('whip_banking:atmEnd') end
    visible = false
    mode = nil
    activeAtm = nil
    terminalBankKey = nil
    previewCardNumber = nil
    keypadActive = false
    keypadTestMode = false
    SendNUIMessage({type='atmKeypadDebug',active=false})
    atmOverviewCards = nil
    atmCardOwnerName = nil
    cardAnimationNonce = cardAnimationNonce + 1
    keypadLastSent = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({type='close'})
    if atmCamera then
        RenderScriptCams(false, true, 350, true, false)
        DestroyCam(atmCamera, false)
        atmCamera = nil
    end
    FreezeEntityPosition(PlayerPedId(), false)
    setScreen(idleFrame('maze'))
    refreshNativeScreens()
end

local function openBank(isTeller)
    if visible then closeUI() end
    local result, why = request('overview')
    if not result then return notify(why or 'Bank unavailable', 'error') end
    visible = true
    mode = 'bank'
    if result.bankKey and Config.Banks[result.bankKey] then
        personalBankKey=result.bankKey
        refreshNativeScreens()
    end
    SetNuiFocus(true, true)
    SendNUIMessage({type='openBank', teller=isTeller, data=result})
end

local function openAtm(contextEntity, insertedCardNumber)
    if visible then closeUI() end
    local entity = (contextEntity and DoesEntityExist(contextEntity)) and contextEntity or nil
    local model
    if entity then model = objectHashes[GetEntityModel(entity)] end
    if not model then entity, model = findClosestAtm(Config.AtmRange) end
    if not entity or not model then return notify('Move closer to the cash machine', 'error') end
    local center, _, _, spec = screenOffset(entity, model)
    if not center then return end

    local overview, why = request('overview')
    if not overview then return notify(why or 'ATM unavailable', 'error') end
    atmOverviewCards = overview.cards or {}
    atmCardOwnerName = overview.name or 'CARDHOLDER'

    -- View is from the actual screen face (the ATM's local negative Y). No fake ATM photograph or shell.
    atmCamera=createBankAtmCamera(entity,center,spec)

    activeAtm = entity
    mode = 'atm'
    visible = true
    FreezeEntityPosition(PlayerPedId(), true)
    SetNuiFocus(true, true)
    -- The ATM screen is private to this player. Its theme is the account bank,
    -- never the machine's prop model or the player's untrusted NUI message.
    -- Someone banking with Pacific Standard sees Pacific Standard even on a Fleeca shell.
    local bankKey=(overview.bankKey and Config.Banks[overview.bankKey])
        and overview.bankKey or atmBankKey(model)
    if overview.bankKey and Config.Banks[overview.bankKey] then
        personalBankKey=overview.bankKey
    end
    terminalBankKey=bankKey
    local bank=(Config.Banks or {})[bankKey] or Config.Banks.maze
    setScreen(idleFrame(bankKey))
    refreshNativeScreens()
    SendNUIMessage({type='openAtm', data={cards=overview.cards, cash=overview.cash,
      currency=Config.Currency, brand=bank.name, bankKey=bankKey,
      terminalBankKey=bankKey, customerBankKey=overview.bankKey,
      bankOptions=overview.bankOptions, dailyLimit=bank.atmDailyLimit or Config.AtmDailyLimit,
      selectedNumber=insertedCardNumber}})
end

-- Project the *visible ATM screen* into NUI coordinates, then extend its
-- perspective basis onto the physical keypad and the surrounding side keys.
-- This is more reliable than assuming the prop origin / 3D hardware axes are
-- identical across GTA and MLO ATM meshes. The DUI screen remains the reference
-- that players have already aligned in /whip. All hit targets are transparent.
local function hardwareFor(entity)
    local model=entity and objectHashes[GetEntityModel(entity)]
    return (Config.AtmHardware and (Config.AtmHardware[model] or Config.AtmHardware.default)) or nil
end
local function projectKeypad(entity)
    local model=entity and objectHashes[GetEntityModel(entity)]
    local center,right,up,spec=screenOffset(entity,model)
    if not center or not spec then return nil end
    local hw=hardwareFor(entity)
    local pad=hw and hw.keypad or {}
    local modelEdit=keypadAlignState and keypadAlignState.entity==entity and keypadAlignState.spec
    local override=modelEdit or (model and savedKeypadAlignments[model])
    if override then
        -- Keep side-button positions from WHIP config; override only four pad fields.
        local merged={}
        for key,value in pairs(pad) do merged[key]=value end
        for key,value in pairs(override) do merged[key]=value end
        pad=merged
    end
    local function at(x,y)
        local w=center + right*(x*spec.width) + up*(y*spec.height)
        local ok,sx,sy=GetScreenCoordFromWorldCoord(w.x,w.y,w.z)
        if ok and type(sx)=='number' and type(sy)=='number' and sx==sx and sy==sy then
            return vector2(sx,sy)
        end
        return nil
    end
    -- top-left, top-right and bottom-left are exactly on the calibrated DUI
    -- display, not guessed 3D locations on the ATM plastic.
    local tl=at(-0.5,0.5)
    local tr=at(0.5,0.5)
    local bl=at(-0.5,-0.5)
    if not tl or not tr or not bl then return nil end
    local rx=tr.x-tl.x;local ry=tr.y-tl.y
    local dx=bl.x-tl.x;local dy=bl.y-tl.y
    local w=math.sqrt(rx*rx+ry*ry);local h=math.sqrt(dx*dx+dy*dy)
    if w<0.025 or h<0.02 or w>0.85 or h>0.9 then return nil end
    local function loc(u,v)
        local x=tl.x+rx*u+dx*v
        local y=tl.y+ry*u+dy*v
        if x<0.0 or y<0.0 or x>1.0 or y>1.0 then return nil end
        return x,y
    end
    local function safe(v,default,min,max)
        v=tonumber(v)
        if not v or v~=v then return default end
        return math.max(min,math.min(max,v))
    end
    -- Exact key centres and physical click areas measured on the supplied
    -- 218x153 reference photograph, normalized to its keypad bezel:
    -- x 13..201, y 3..144. The third action-row button is EMPTY.
    local geometry={
        {key='1',      x=32, y=18,  width=28,height=25},
        {key='2',      x=65, y=18,  width=29,height=25},
        {key='3',      x=99, y=18,  width=29,height=25},
        {key='CANCEL', x=167,y=18,  width=62,height=26},
        {key='4',      x=32, y=52,  width=28,height=26},
        {key='5',      x=65, y=52,  width=29,height=26},
        {key='6',      x=99, y=52,  width=29,height=26},
        {key='CLEAR',  x=167,y=52,  width=62,height=27},
        {key='7',      x=32, y=87,  width=28,height=27},
        {key='8',      x=65, y=87,  width=29,height=27},
        {key='9',      x=99, y=87,  width=29,height=27},
        {key='MINUS',  x=32, y=126, width=28,height=28},
        {key='0',      x=65, y=126, width=29,height=28},
        {key='PLUS',   x=99, y=126, width=29,height=28},
        {key='ENTER',  x=167,y=126, width=62,height=28},
    }
    local bezel={left=13,top=3,width=188,height=141}
    local padLeft=safe(pad.left,0.225,-0.3,1.2)
    local padTop=safe(pad.top,1.555,0.75,3.0)
    local padWidth=safe(pad.width,0.555,0.2,1.5)
    local padHeight=safe(pad.height,0.475,0.2,1.5)
    local sideOffset=safe(pad.sideOffset,0.075,0.01,0.25)
    local sideTop=safe(pad.sideTop,0.17,0.01,0.6)
    local sideStep=safe(pad.sideStep,0.235,0.1,0.35)
    local function round(v)return math.floor(v*10000+0.5)/10000 end
    local keys={}
    -- Project every button centre through the calibrated ATM DUI surface. The
    -- screenshot's non-uniform row spacing and the wider coloured keys survive.
    for _,item in ipairs(geometry) do
        local cx=(item.x-bezel.left)/bezel.width
        local cy=(item.y-bezel.top)/bezel.height
        local u=padLeft+cx*padWidth
        local v=padTop+cy*padHeight
        local x,y=loc(u,v)
        if x then
            local buttonWidth=math.sqrt((rx*(padWidth*item.width/bezel.width))^2 + (ry*(padWidth*item.width/bezel.width))^2)
            local buttonHeight=math.sqrt((dx*(padHeight*item.height/bezel.height))^2 + (dy*(padHeight*item.height/bezel.height))^2)
            keys[#keys+1]={key=item.key,x=round(x),y=round(y),w=round(buttonWidth),h=round(buttonHeight)}
        end
    end
    local sides={}
    for i=1,4 do
        local leftX,leftY=loc(-sideOffset,sideTop+(i-1)*sideStep)
        local rightX,rightY=loc(1+sideOffset,sideTop+(i-1)*sideStep)
        if leftX then sides[#sides+1]={key='L'..i,x=round(leftX),y=round(leftY),w=round(w*0.13),h=round(h*0.15)} end
        if rightX then sides[#sides+1]={key='R'..i,x=round(rightX),y=round(rightY),w=round(w*0.13),h=round(h*0.15)} end
    end
    return #keys>0 and {keys=keys,sides=sides,model=model,screenRight={rx,ry},screenDown={dx,dy},screenW=w,screenH=h} or nil
end

RegisterNUICallback('atmKeypadMode',function(req,cb)
    keypadActive=(visible and mode=='atm' and ((type(req)=='table' and req.active==true) or keypadTestMode))
    if not keypadActive then SendNUIMessage({type='atmKeypadLayout',data={keys={}}}) end
    cb({ok=true})
end)

CreateThread(function()
    while true do
        if visible and mode=='atm' and keypadActive and activeAtm and DoesEntityExist(activeAtm) then
            local layout=projectKeypad(activeAtm)
            if layout then
                SendNUIMessage({type='atmKeypadLayout',data=layout})
            else
                SendNUIMessage({type='atmKeypadLayout',data={keys={}}})
            end
            Wait(280) -- camera is stationary, 3.5 checks/second, 0 ms when idle
        else
            Wait(650)
        end
    end
end)

local function ensureCardTexture()
    if cardDui then return cardDui end
    local browser=CreateDui(('nui://%s/html/card_insert.html'):format(GetCurrentResourceName()),800,500)
    if not browser then return nil end
    local result={browser=browser,dict='whip_banking_card_face',tex='card',ready=false}
    cardDui=result
    CreateThread(function()
        Wait(250)
        if cardDui~=result or not result.browser then return end
        local txd=CreateRuntimeTxd(result.dict)
        CreateRuntimeTextureFromDuiHandle(txd,result.tex,GetDuiHandle(result.browser))
        local deadline=GetGameTimer()+4500
        while result.browser and not IsDuiAvailable(result.browser) and GetGameTimer()<deadline do Wait(100) end
        result.ready=result.browser and IsDuiAvailable(result.browser) or false
    end)
    return result
end

local function cardIntoSlot(entity,card,owner)
    if not entity or not DoesEntityExist(entity) then return false end
    cardAnimationNonce=cardAnimationNonce+1
    local nonce=cardAnimationNonce
    local texture=ensureCardTexture()
    if not texture then return false end
    CreateThread(function()
        local expires=GetGameTimer()+2500
        while texture and not texture.ready and GetGameTimer()<expires do Wait(50) end
        if cardAnimationNonce~=nonce or not texture.ready or not DoesEntityExist(entity) or mode~='atm' then return end
        SendDuiMessage(texture.browser,json.encode({type='cardFace',
            bankKey=card.bankKey,cardStyle=card.cardStyle,last4=card.last4,
            expires=card.expires,holder=owner}))
        Wait(80) -- Allow Chromium to paint the requested branded card face.
        local hw=hardwareFor(entity)
        local slot=hw and hw.slot
        if not slot then return end
        local origin=GetEntityCoords(entity)
        local rightWorld=GetOffsetFromEntityInWorldCoords(entity,1.0,0.0,0.0)-origin
        local upWorld=GetOffsetFromEntityInWorldCoords(entity,0.0,0.0,1.0)-origin
        local right=rightWorld/(#rightWorld>0.001 and #rightWorld or 1.0)
        local up=upWorld/(#upWorld>0.001 and #upWorld or 1.0)
        local began=GetGameTimer()
        local duration=950
        while cardAnimationNonce==nonce and mode=='atm' and DoesEntityExist(entity) and GetGameTimer()-began<duration do
            local t=math.min(1.0,(GetGameTimer()-began)/duration)
            local ease=t*t*(3.0-2.0*t)
            local x=slot.side+0.17*(1.0-ease)
            local y=slot.out-0.18*(1.0-ease)
            local z=slot.up+0.045*(1.0-ease)
            local pos=GetOffsetFromEntityInWorldCoords(entity,x,y,z)
            local shrink=1.0-0.22*ease
            WorldQuad.draw(texture.dict,texture.tex,
                pos.x,pos.y,pos.z,right.x,right.y,right.z,up.x,up.y,up.z,
                slot.width*shrink,slot.height*shrink,0.0,0.0,1.0,1.0,
                255,255,255,255)
            Wait(0)
        end
    end)
    return true
end

RegisterNUICallback('atmInsertCard',function(req,cb)
    if mode~='atm' or not activeAtm or not DoesEntityExist(activeAtm) then
        cb({ok=false,error='ATM session is closed'});return
    end
    local id=type(req)=='table' and tonumber(req.cardId) or nil
    local picked
    for _,card in ipairs(atmOverviewCards or {}) do
        if tonumber(card.id)==id and card.status=='active' then picked=card;break end
    end
    if not picked then cb({ok=false,error='This bank card is not available'});return end
    -- This is purely a visual preview. WHIP performs the actual ownership,
    -- inventory, PIN, expiry and lockout checks in the atmAuth secure callback.
    local started=cardIntoSlot(activeAtm,picked,atmCardOwnerName)
    cb({ok=started,duration=1350,error=not started and 'ATM card display unavailable' or nil})
end)

Whip.register(function()
    for i, branch in ipairs(Config.Branches) do
        local entry = branch
        Whip.core:AddAction({
            id='branch_'..i,
            at={coords=vector3(entry.coords.x,entry.coords.y,entry.coords.z)},
            label='Speak to bank teller', icon='bank',
            onSelect=function()
                CreateThread(function()
                    local allowed, why = request('teller')
                    if not allowed then return notify(why or 'Please approach the teller', 'error') end
                    openBank(true)
                end)
            end
        })
    end
    Whip.core:AddAction({
        id='world_atms', at={model=Config.ATMs},
        label='Use cash machine', icon='bank',
        onSelect=function(ctx)
            CreateThread(function() openAtm(ctx and ctx.entity) end)
        end
    })
    actionsRegistered = true
    CreateThread(function()
        for attempt=1,3 do
            Wait(attempt==1 and 1200 or 2500)
            local ok,info=request('bankIdentity')
            if ok==true and type(info)=='table' then
                local key=info.bankKey
                personalBankKey=key and Config.Banks[key] and key or nil
                refreshNativeScreens()
                break
            end
        end
    end)
end)

Whip.onConfigChanged('ATMs', function()
    rebuildModelHashes()
    refreshNativeScreens()
    if actionsRegistered then
        Whip.core:UpdateAction('world_atms', {at={model=Config.ATMs}})
    end
end)

Whip.onConfigChanged('Branches', function(_, _, path)
    if not actionsRegistered then return end
    -- Changing a branch's position in /whip moves its live E prompt immediately.
    if type(path)=='string' and not path:find('coords',1,true) then return end
    for i, branch in ipairs(Config.Branches) do
        Whip.core:UpdateAction('branch_'..i, {
            at={coords=vector3(branch.coords.x,branch.coords.y,branch.coords.z)}
        })
    end
end)

Whip.onConfigChanged('AtmStandbyEnabled', refreshNativeScreens)
Whip.onConfigChanged('AtmInteractiveOverlay', refreshNativeScreens)
Whip.onConfigChanged('AtmScreenMaterials', refreshNativeScreens)
Whip.onConfigChanged('AtmScreens', function() geometryEpoch = geometryEpoch + 1 end)
local function refreshIdleDuis()
    for key,dui in pairs(standbyDuis) do
        if dui and dui.ready then SendDuiMessage(dui.browser,json.encode(idleFrame(key))) end
    end
end
Whip.onConfigChanged('Brand', refreshIdleDuis)
Whip.onConfigChanged('Currency',refreshIdleDuis)
Whip.onConfigChanged('Banks',function() refreshIdleDuis(); refreshNativeScreens() end)
Whip.onConfigChanged('AtmModelBanks',refreshNativeScreens)
Whip.onConfigChanged('AtmOverlayPreview', function()
    if mode ~= 'atm' then setScreen({screen=Config.AtmOverlayPreview and 'calibration' or 'idle',bankKey='maze',brand=Config.Brand}) end
end)

-- Local developer-only live alignment. Does not change Config or everybody else's screens.
-- Saving stores model offsets in the developer's client KVP until they export one JSON bundle
-- for the server owner to review and merge into Config.AtmScreens.
local function alignmentCount()
    local n=0
    for _ in pairs(savedAlignments) do n=n+1 end
    return n
end

local function alignmentSnapshot()
    return {model=alignState and alignState.model or nil,
            spec=alignState and alignState.spec or nil,
            saved=alignmentCount()}
end

local function alignmentNotify()
    SendNUIMessage({type='alignUpdate',data=alignmentSnapshot()})
end

local function alignmentSave()
    if not alignState or not alignState.model or not alignState.spec then return false end
    savedAlignments[alignState.model] = copyAlignment(alignState.spec)
    geometryEpoch = geometryEpoch + 1
    SetResourceKvp(alignKvp,json.encode(savedAlignments))
    alignmentNotify()
    return true
end

local function alignmentExport()
    local all={}
    for model, spec in pairs(Config.AtmScreens) do
        all[model]=copyAlignment(savedAlignments[model] or spec)
    end
    for model, spec in pairs(savedAlignments) do
        all[model]=copyAlignment(spec)
    end
    return json.encode({format='whip_banking_atm_alignment_v1',AtmScreens=all})
end

local function alignmentClose()
    if not alignState then return end
    alignState=nil
    SetNuiFocus(false,false)
    SetNuiFocusKeepInput(false)
    Whip.core:SetScreenOpen(false,'bank_align')
    FreezeEntityPosition(PlayerPedId(),false)
    SendNUIMessage({type='alignClose'})
    setScreen({screen='idle',brand=Config.Brand,currency=Config.Currency})
end

local function alignmentOpen(entity)
    if not CORE:HasDevTools() then return notify('Enable WHIP developer mode first','error') end
    if visible then closeUI() end
    if alignState then alignmentClose() end
    if entity and DoesEntityExist(entity) then
        local model = objectHashes[GetEntityModel(entity)]
        if not model then return notify('Unrecognised ATM model','error') end
        alignState={entity=entity,model=model,
                    spec=copyAlignment(savedAlignments[model] or Config.AtmScreens[model])}
        FreezeEntityPosition(PlayerPedId(),true)
        setScreen({screen='calibration',brand=Config.Brand,model=model})
    else
        alignState={entity=nil,model=nil,spec=nil}
    end
    Whip.core:SetScreenOpen(true,'bank_align')
    SetNuiFocus(true,true)
    SendNUIMessage({type='alignOpen',data=alignmentSnapshot()})
end

local function alignmentNearest()
    local entity = findClosestAtm(6.0)
    if not entity then return notify('Stand beside an ATM, then choose Align nearest ATM','error') end
    alignmentOpen(entity)
end

local function alignmentNext()
    if not alignState then return false end
    if alignState.model then alignmentSave() end
    local pos=GetEntityCoords(PlayerPedId())
    local nearby={}
    for _, entity in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(entity) and objectHashes[GetEntityModel(entity)] then
            local distance=#(GetEntityCoords(entity)-pos)
            if distance<10.0 then nearby[#nearby+1]={entity=entity,d=distance} end
        end
    end
    table.sort(nearby,function(a,b) return a.d<b.d end)
    if #nearby==0 then return false end
    local nextIndex=1
    for i, item in ipairs(nearby) do
        if item.entity==alignState.entity then nextIndex=i%#nearby+1; break end
    end
    local nextEntity=nearby[nextIndex].entity
    local model=objectHashes[GetEntityModel(nextEntity)]
    alignState.entity=nextEntity
    alignState.model=model
    alignState.spec=copyAlignment(savedAlignments[model] or Config.AtmScreens[model])
    setScreen({screen='calibration',brand=Config.Brand,model=model})
    alignmentNotify()
    return true
end

RegisterNUICallback('alignAction',function(req,cb)
    if not alignState or not CORE:HasDevTools() or type(req)~='table' then
        cb({ok=false,error='Alignment mode is not active'});return
    end
    local action=req.action
    if action=='close' then
        alignmentClose()
        cb({ok=true});return
    elseif action=='next' then
        cb({ok=alignmentNext(),data=alignmentSnapshot()});return
    elseif action=='save' then
        cb({ok=alignmentSave(),data=alignmentSnapshot()});return
    elseif action=='reset' then
        if alignState.model then
            savedAlignments[alignState.model]=nil
            alignState.spec=copyAlignment(Config.AtmScreens[alignState.model])
            geometryEpoch = geometryEpoch + 1
            SetResourceKvp(alignKvp,json.encode(savedAlignments))
            alignmentNotify()
        end
        cb({ok=true,data=alignmentSnapshot()});return
    elseif action=='export' then
        if alignState.model then alignmentSave() end
        cb({ok=true,json=alignmentExport(),data=alignmentSnapshot()});return
    elseif action=='adjust' or action=='set' then
        local key=req.field
        local bounds=alignFields[key]
        if not bounds or not alignState.spec then cb({ok=false,error='Select an ATM first'});return end
        local numeric=tonumber(req.value)
        if not numeric or numeric~=numeric or math.abs(numeric)>1000 then
            cb({ok=false,error='Invalid adjustment'});return
        end
        local current=alignState.spec[key]
        local value=action=='adjust' and (current+numeric) or numeric
        value=math.max(bounds[1],math.min(bounds[2],value))
        alignState.spec[key]=math.floor(value*10000+0.5)/10000
        alignmentNotify()
        cb({ok=true,data=alignmentSnapshot()});return
    end
    cb({ok=false,error='Unknown alignment action'})
end)

-- Live, in-world keypad alignment. All outlines use projectKeypad(), the SAME
-- math as the real click hotspots, so the green/yellow boxes genuinely represent
-- what a player can click. No permanent render loop while the editor is closed.
local function keypadSnapshot()
    return {model=keypadAlignState and keypadAlignState.model or nil,
            spec=keypadAlignState and keypadAlignState.spec or nil,
            saved=(function()local count=0;for _ in pairs(savedKeypadAlignments) do count=count+1 end;return count end)()}
end

local function keypadEditorLayout()
    if not keypadAlignState or not keypadAlignState.entity or not DoesEntityExist(keypadAlignState.entity) then return end
    -- Don't calibrate against an interpolating camera. It would move the key
    -- outlines even with unchanged settings, producing an unreliable save.
    if GetGameTimer()<keypadEditorReadyAt then
        SendNUIMessage({type='keypadAlignLayout',data={keys={},sides={}}})
        return
    end
    local data=projectKeypad(keypadAlignState.entity)
    SendNUIMessage({type='keypadAlignLayout',data=data or {keys={},sides={}}})
end

local function keypadEditorNotify()
    SendNUIMessage({type='keypadAlignUpdate',data=keypadSnapshot()})
    keypadEditorLayout()
end

local function keypadEditorSave()
    if not keypadAlignState or not keypadAlignState.model or not keypadAlignState.spec then return false end
    savedKeypadAlignments[keypadAlignState.model]=boundedKeypad(keypadAlignState.spec)
    SetResourceKvp(keypadAlignKvp,json.encode(savedKeypadAlignments))
    keypadEditorNotify()
    return true
end

local function keypadEditorExport()
    local models={}
    for model,data in pairs(Config.AtmHardware or {}) do
        if type(model)=='string' and type(data)=='table' and type(data.keypad)=='table' then
            models[model]={keypad=boundedKeypad(savedKeypadAlignments[model] or data.keypad)}
        end
    end
    -- Include any user-calibrated custom ATM models not in the default config.
    for model,spec in pairs(savedKeypadAlignments) do models[model]={keypad=boundedKeypad(spec)} end
    if keypadAlignState and keypadAlignState.model then
        models[keypadAlignState.model]={keypad=boundedKeypad(keypadAlignState.spec)}
    end
    return json.encode({format='whip_banking_keypad_alignment_v1',AtmHardware=models})
end

local function keypadEditorClose()
    if not keypadAlignState then return end
    keypadAlignState=nil
    SetNuiFocus(false,false)
    SetNuiFocusKeepInput(false)
    Whip.core:SetScreenOpen(false,'bank_keypad_align')
    SendNUIMessage({type='keypadAlignClose'})
    if atmCamera then
        RenderScriptCams(false,true,300,true,false)
        DestroyCam(atmCamera,false)
        atmCamera=nil
    end
    FreezeEntityPosition(PlayerPedId(),false)
end

local function keypadEditorOpen(entity)
    if not CORE:HasDevTools() then return notify('Enable WHIP developer mode first','error') end
    if visible then closeUI() end
    if alignState then alignmentClose() end
    if keypadAlignState then keypadEditorClose() end
    local model=entity and DoesEntityExist(entity) and objectHashes[GetEntityModel(entity)]
    if not model then return notify('Stand beside an ATM with a recognised model','error') end
    local center,_,_,screenSpec=screenOffset(entity,model)
    if not center then return notify('This ATM has no calibrated display','error') end
    local hw=(Config.AtmHardware and (Config.AtmHardware[model] or Config.AtmHardware.default)) or {}
    local base=hw.keypad or {}
    keypadAlignState={entity=entity,model=model,spec=boundedKeypad(savedKeypadAlignments[model] or base,base)}
    -- EXACT SAME 3D camera transform used by openAtm(), not a second approximation.
    atmCamera=createBankAtmCamera(entity,center,screenSpec)
    keypadEditorReadyAt=GetGameTimer()+550
    FreezeEntityPosition(PlayerPedId(),true)
    Whip.core:SetScreenOpen(true,'bank_keypad_align')
    SetNuiFocus(true,true)
    SendNUIMessage({type='keypadAlignOpen',data=keypadSnapshot()})
    keypadEditorLayout()
end

local function keypadEditorNearest()
    local entity=findClosestAtm(6.0)
    if not entity then return notify('Stand beside an ATM, then select live keypad alignment','error') end
    keypadEditorOpen(entity)
end

RegisterNUICallback('keypadAlignAction',function(req,cb)
    if not keypadAlignState or not CORE:HasDevTools() or type(req)~='table' then
        cb({ok=false,error='Live keypad editor is not active'});return
    end
    local action=req.action
    if action=='close' then
        keypadEditorClose();cb({ok=true});return
    elseif action=='save' then
        cb({ok=keypadEditorSave(),data=keypadSnapshot()});return
    elseif action=='test' then
        -- Save first, then open the actual banking session with developer outlines
        -- enabled. This validates what is *really clickable*, not an editor mock-up.
        local selected=keypadAlignState.entity
        if not keypadEditorSave() then cb({ok=false,error='Could not save this ATM'});return end
        keypadEditorClose()
        cb({ok=true})
        CreateThread(function()
            keypadTestMode=true
            openAtm(selected)
            if visible and mode=='atm' then
                SendNUIMessage({type='atmKeypadDebug',active=true})
                keypadActive=true
            else
                keypadTestMode=false
            end
        end)
        return
    elseif action=='export' then
        cb({ok=true,json=keypadEditorExport(),data=keypadSnapshot()});return
    elseif action=='reset' then
        local model=keypadAlignState.model
        savedKeypadAlignments[model]=nil
        SetResourceKvp(keypadAlignKvp,json.encode(savedKeypadAlignments))
        local hw=(Config.AtmHardware and (Config.AtmHardware[model] or Config.AtmHardware.default)) or {}
        keypadAlignState.spec=boundedKeypad(hw.keypad)
        keypadEditorNotify()
        cb({ok=true,data=keypadSnapshot()});return
    elseif action=='adjust' or action=='set' or action=='drag' then
        local spec=keypadAlignState.spec
        if action=='drag' then
            local left=tonumber(req.left);local top=tonumber(req.top)
            if not left or not top or left~=left or top~=top or math.abs(left)>3 or math.abs(top)>3 then
                cb({ok=false,error='Invalid drag'});return
            end
            spec.left=boundedKeypad({left=spec.left+left},spec).left
            spec.top=boundedKeypad({top=spec.top+top},spec).top
        else
            local field=req.field
            if not keypadEditable[field] then cb({ok=false,error='Unknown keypad field'});return end
            local value=tonumber(req.value)
            if not value or value~=value or math.abs(value)>10 then cb({ok=false,error='Invalid adjustment'});return end
            local old=spec[field]
            spec[field]=boundedKeypad({[field]=action=='adjust' and old+value or value},spec)[field]
        end
        keypadEditorNotify()
        cb({ok=true,data=keypadSnapshot()});return
    end
    cb({ok=false,error='Unknown keypad editor action'})
end)

CreateThread(function()
    while true do
        if keypadAlignState then
            if not keypadAlignState.entity or not DoesEntityExist(keypadAlignState.entity) then
                keypadEditorClose()
            else keypadEditorLayout() end
            Wait(200) -- Only while the visual editor is open.
        else Wait(850) end
    end
end)

-- Uses WHIP's own developer page in /w, not a player-facing chat command.
Whip.register(function()
    Whip.core:RegisterDevPage('banking_atm_alignment',{
        label='Banking - ATM Alignment',
        desc='Visually align ATM screens and physical keypad buttons; export the positions as JSON.',
        rows=function()
            return {rows={
                {id='nearest',label='Align nearest ATM',desc='Stand in front of the model you want to tune.',close=true},
                {id='keypad',label='LIVE: Align physical ATM keypad',desc='Opens the real ATM camera and draws the clickable keys in colour; adjust visually and save.',close=true},
                {id='export',label='Export all ATM positions',desc='Copy a JSON file for your developer.',close=true},
                {sep='Saved on this PC'},
                {kind='note',label=alignmentCount()..' model(s) calibrated locally'},
            }}
        end,
        onSelect=function(id)
            CreateThread(function()
                Wait(170) -- let /w close before this resource takes NUI focus
                if id=='nearest' then alignmentNearest()
                elseif id=='keypad' then keypadEditorNearest()
                elseif id=='export' then alignmentOpen(nil) end
            end)
        end,
    })
end)

RegisterNetEvent('whip_core:devtools:modeChanged',function(evt)
    if alignState and (not evt or evt.on==false) then alignmentClose() end
    if keypadAlignState and (not evt or evt.on==false) then keypadEditorClose() end
end)

-- Inventory use opens the card viewer anywhere. The server confirms the
-- card belongs to this character AND still physically exists in their inventory.
RegisterNetEvent('whip_banking:client:cardUsed', function(metadata)
    if visible or alignState or keypadAlignState then return end
    local number = type(metadata)=='table' and type(metadata.number)=='string'
        and metadata.number or nil
    if not number then return notify('This card has no valid banking details', 'error') end
    CreateThread(function()
        local ok, card = request('cardPreview', number)
        if ok ~= true or type(card) ~= 'table' then
            notify(type(card)=='string' and card or 'Could not verify this card', 'error')
            return
        end
        if visible or alignState or keypadAlignState then return end
        previewCardNumber = number
        visible = true
        mode = 'cardPreview'
        SetNuiFocus(true, true)
        SendNUIMessage({type='openCardPreview', data=card})
    end)
end)

RegisterNUICallback('previewInsertAtm', function(_, cb)
    if not visible or mode ~= 'cardPreview' or not previewCardNumber then
        cb({ok=false,error='No bank card selected'}); return
    end
    local entity=findClosestAtm(Config.AtmRange)
    if not entity or not DoesEntityExist(entity) then
        cb({ok=false,error='Move closer to an ATM to insert your card'}); return
    end
    local number=previewCardNumber -- never accept a client-supplied card number here
    cb({ok=true})
    CreateThread(function() openAtm(entity,number) end)
end)

RegisterNUICallback('close', function(_, cb)
    closeUI()
    cb({ok=true})
end)

-- The web page cannot choose a net event name: these are the only callbacks it can invoke.
local allowed = {
    overview=true, selectBank=true, accountCreate=true, transfer=true, issueCard=true, cardStatus=true,
    pinChange=true, atmAuth=true, loanApply=true, loanPay=true, billPay=true,
    scheduleCreate=true, scheduleCancel=true
}

RegisterNUICallback('request', function(req, cb)
    if not visible or type(req) ~= 'table' or not allowed[req.action] then
        cb({ok=false,error='Action unavailable'}); return
    end
    local args = type(req.args) == 'table' and req.args or {}
    local a, b, c = request(req.action, table.unpack(args, 1, math.min(#args, 8)))
    local accepted = a ~= false and a ~= nil
    if req.action == 'atmAuth' and accepted and type(b)=='table' then remainingLimit = b.limit or Config.AtmDailyLimit end
    if req.action == 'selectBank' and accepted then
        local selected=type(b)=='table' and type(b.bank)=='table' and b.bank.key or args[1]
        if selected and Config.Banks[selected] then
            personalBankKey=selected
            refreshNativeScreens()
        end
    end
    cb({ok=accepted, data=accepted and ((req.action == 'overview') and a or b) or nil,
        error=not accepted and b or nil, extra=c})
end)

RegisterNUICallback('refresh', function(_, cb)
    if not visible then cb({ok=false}); return end
    local data, why = request('overview')
    cb({ok=data ~= false and data ~= nil, data=data or nil, error=why})
end)

-- The cash-to-inventory conversion is performed by WHIP's own atomic ATM callbacks.
-- They commit the ledger and inventory together, with rollback and anti-overdraft protection.
RegisterNUICallback('atmMoney', function(req, cb)
    if mode ~= 'atm' or not activeAtm or not DoesEntityExist(activeAtm) then
        cb({ok=false,error='ATM session closed'}); return
    end
    local kind = req.kind
    local money = tonumber(req.amount)
    local account = tonumber(req.accountId)
    if kind ~= 'withdraw' then cb({ok=false,error='Cash deposits are not available at ATMs'}); return end
    if not money or money < 1 or money % 1 ~= 0 or money > 999999999 then
        cb({ok=false,error='Enter a whole amount'}); return
    end
    if money > Config.AtmDailyLimit then
        cb({ok=false,error='Maximum cash withdrawal per transaction exceeded'}); return
    end
    local permitted, denied = request('atmPreflight', account, kind, money)
    if not permitted then cb({ok=false,error=denied or 'Enter your card PIN first'}); return end
    local ok, why, balance, pocketCash = CORE:Callback('whip_core:atm:withdraw', account, money)
    if ok == true then
        local still, left = request('atmStatus')
        if still then remainingLimit = left end
    end
    cb({ok=ok == true, error=ok ~= true and why or nil,
      data=ok and {balance=balance,cash=pocketCash,limit=remainingLimit} or nil})
end)

RegisterNUICallback('atmFrame', function(req, cb)
    if mode == 'atm' then
        -- Do not trust bankKey supplied by NUI; keep the server-verified
        -- character bank selected when this ATM session opened.
        local key=(Config.Banks or {})[terminalBankKey] and terminalBankKey or 'maze'
        local bank=Config.Banks[key]
        local safeSteps={idle=true,pin=true,menu=true,fast=true,balance=true,
          amount=true,processing=true,complete=true,error=true}
        local step=type(req.screen)=='string' and safeSteps[req.screen] and req.screen or 'idle'
        setScreen({screen=step, bankKey=key, brand=bank.name, currency=Config.Currency,
            name=req.name, last4=req.last4, balance=req.balance, cash=req.cash,
            amount=req.amount, enteredAmount=math.max(0,math.min(999999999,tonumber(req.enteredAmount) or 0)),
            pinCount=math.max(0,math.min(4,tonumber(req.pinCount) or 0)),
            limit=remainingLimit, message=req.message})
    end
    cb({ok=true})
end)

-- GTA's material replacement can miss retextured MLO ATMs. The fallback remains
-- available, but the expensive object-pool scan runs only if a cheap model
-- proximity probe has found at least one ATM in range. Offsets are cached so
-- the render path doesn't call multiple world-transform natives every frame.
local function screenGeometry(entity, model)
    local center, right, up, spec = screenOffset(entity, model)
    if not center then return nil end
    return {
        cx=center.x,cy=center.y,cz=center.z,
        rx=right.x,ry=right.y,rz=right.z,
        ux=up.x,uy=up.y,uz=up.z,
        width=spec.width,height=spec.height
    }
end

local function scanAtms()
    local pos = GetEntityCoords(PlayerPedId())
    local range = math.max(4.0,tonumber(Config.AtmDrawDistance) or 23.0)
    local found = {}
    for _, entity in ipairs(GetGamePool('CObject')) do
        if DoesEntityExist(entity) then
            local model = objectHashes[GetEntityModel(entity)]
            if model then
                local dist = #(pos - GetEntityCoords(entity))
                if dist <= range then
                    found[#found+1] = {entity=entity,model=model,dist=dist}
                end
            end
        end
    end
    -- WorldQuad is inexpensive, but avoid drawing dozens of bank props in a dense custom MLO.
    table.sort(found,function(a,b) return a.dist < b.dist end)
    cachedAtms = {}
    for i=1,math.min(#found,40) do
        local atm=found[i]
        atm.quad = screenGeometry(atm.entity, atm.model)
        atm.epoch = geometryEpoch
        cachedAtms[#cachedAtms+1]=atm
    end
end

local function drawAtmScreen(entity,model,texture,geometry)
    if not texture or not texture.ready then return false end
    local q=geometry or screenGeometry(entity,model)
    if not q then return false end
    WorldQuad.draw(texture.dict,texture.tex,
        q.cx,q.cy,q.cz,q.rx,q.ry,q.rz,
        q.ux,q.uy,q.uz,q.width,q.height,0.0,0.0,1.0,1.0,
        255,255,255,255)
    return true
end

CreateThread(function()
    Wait(750)
    ensureDuis(Config.AtmOverlayPreview)
    local nextProbeAt = 0
    local previewAtm = nil
    while true do
        local now = GetGameTimer()
        if now >= nextProbeAt then
            -- Four cheap model-specific lookups instead of copying the entire
            -- CObject pool across the Lua boundary while no ATM is nearby.
            local drawRange=math.max(4.0,tonumber(Config.AtmDrawDistance) or 23.0)
            local nearby, _, distance = findClosestAtm(drawRange)
            if nearby then
                scanAtms()
                nextProbeAt=now+2400
            else
                cachedAtms={}
                nextProbeAt=now+3500
            end
            previewAtm = (Config.AtmOverlayPreview and mode ~= 'atm' and nearby
                and distance < math.min(15.0,drawRange)) and nearby or nil
        end
        local preview = Config.AtmOverlayPreview and mode ~= 'atm' and not alignState
        local previewModel = previewAtm and DoesEntityExist(previewAtm)
            and objectHashes[GetEntityModel(previewAtm)] or nil
        if preview and (duiState.screen ~= 'calibration' or duiState.model ~= previewModel) then
            setScreen({screen='calibration',bankKey='maze',brand=Config.Brand,model=previewModel})
        end
        local rendered = false
        local activeSeen = false
        local alignSeen = false
        local wantsQuads=(Config.AtmStandbyEnabled and Config.AtmWorldStandbyFallback)
            or mode == 'atm' or alignState ~= nil or preview
        if wantsQuads then
            for _, atm in ipairs(cachedAtms) do
                local entity = atm.entity
                if DoesEntityExist(entity) and IsEntityOnScreen(entity) then
                    local selected = mode == 'atm' and entity == activeAtm
                    local calibration = preview and entity == previewAtm
                    local editing = alignState and entity == alignState.entity
                    local texture
                    if editing then
                        alignSeen = true
                        texture = activeDui
                    elseif selected then
                        activeSeen = true
                        texture = activeDui
                    elseif calibration then
                        texture = activeDui
                    elseif Config.AtmStandbyEnabled and Config.AtmWorldStandbyFallback then
                        texture = standbyDuis[shownBankKey(atm.model)]
                    end
                    if texture and texture.ready then
                        if atm.epoch ~= geometryEpoch then
                            atm.quad=screenGeometry(entity,atm.model)
                            atm.epoch=geometryEpoch
                        end
                        -- The alignment editor moves the quad live. In ordinary
                        -- play all coordinates come from the last nearby scan.
                        local quad=editing and screenGeometry(entity,atm.model) or atm.quad
                        if drawAtmScreen(entity,atm.model,texture,quad) then rendered=true end
                    end
                end
            end
        end
        -- Covers the first second after a machine streams in, before the next object scan.
        if mode == 'atm' and not activeSeen and activeAtm and DoesEntityExist(activeAtm) then
            local model = objectHashes[GetEntityModel(activeAtm)]
            if model and drawAtmScreen(activeAtm,model,activeDui) then rendered = true end
        end
        if alignState and not alignSeen and alignState.entity and DoesEntityExist(alignState.entity) then
            if drawAtmScreen(alignState.entity,alignState.model,activeDui) then rendered=true end
        end
        local waitingForPrivate=(mode == 'atm' or (alignState and alignState.entity))
            and activeDui and not activeDui.ready
        Wait(rendered and 0 or (waitingForPrivate and 100 or (wantsQuads and #cachedAtms > 0 and 180 or 850)))
    end
end)

-- Retry a temporarily unavailable FiveM Chromium DUI without restarting the resource.
CreateThread(function()
    while true do
        Wait(12000)
        if not standbyDuis.maze or not standbyDuis.fleeca or not standbyDuis.pacific or ((mode == 'atm' or alignState or Config.AtmOverlayPreview) and not activeDui) then
            ensureDuis(mode == 'atm' or alignState ~= nil or Config.AtmOverlayPreview)
        end
    end
end)

AddEventHandler('onResourceStop', function(name)
    if name ~= GetCurrentResourceName() then return end
    if atmCamera then RenderScriptCams(false,false,0,true,false); DestroyCam(atmCamera,false) end
    FreezeEntityPosition(PlayerPedId(),false)
    SetNuiFocus(false,false)
    if alignState then SendNUIMessage({type='alignClose'}); alignState=nil end
    if keypadAlignState then SendNUIMessage({type='keypadAlignClose'});keypadAlignState=nil end
    for _, replacement in pairs(nativeReplacements) do
        RemoveReplaceTexture(replacement.material.dict,replacement.material.name)
    end
    nativeReplacements = {}
    if activeDui and activeDui.browser then DestroyDui(activeDui.browser); activeDui.browser=nil end
    if cardDui and cardDui.browser then DestroyDui(cardDui.browser); cardDui.browser=nil end
    for key,dui in pairs(standbyDuis) do
        if dui and dui.browser then DestroyDui(dui.browser); dui.browser=nil end
        standbyDuis[key]=nil
    end
end)
