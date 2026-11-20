local CORE = exports.whip_core
local visible = false
local mode = nil
local activeAtm = nil
local atmCamera = nil
local activeDui = nil
local standbyDui = nil
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
            SendDuiMessage(result.browser, json.encode(dict == 'maze_bank_standby'
                and {screen='idle',brand=Config.Brand,currency=Config.Currency} or duiState))
            if dict == 'maze_bank_standby' then
                -- The material replacement must be installed even when the player has never used an ATM.
                TriggerEvent('whip_banking:standbyReady')
            else
                TriggerEvent('whip_banking:activeReady')
            end
        else
            print('[whip_banking] ATM DUI page did not become available: ' .. dict)
            if result.browser then DestroyDui(result.browser); result.browser = nil end
            if activeDui == result then activeDui = nil end
            if standbyDui == result then standbyDui = nil end
        end
    end)
    return result
end

local function materialKey(material)
    return material.dict .. '/' .. material.name
end

local function refreshNativeScreens()
    local wanted = {}
    if Config.AtmStandbyEnabled and standbyDui and standbyDui.ready then
        for model, material in pairs(Config.AtmScreenMaterials) do
            if objectHashes[GetHashKey(model)] and type(material) == 'table'
                and material.dict and material.name then
                local key = materialKey(material)
                -- Optional full-material mode uses the model's real UVs but will show the
                -- same active session on all nearby instances of that model. The default
                -- private quad mode avoids that by changing only the chosen ATM.
                local useActive = mode == 'atm' and not Config.AtmInteractiveOverlay
                    and activeAtm and DoesEntityExist(activeAtm)
                    and objectHashes[GetEntityModel(activeAtm)] == model
                    and activeDui and activeDui.ready
                wanted[key] = {material=material,dict=useActive and activeDui.dict or standbyDui.dict}
            end
        end
    end
    for key, old in pairs(nativeReplacements) do
        if not wanted[key] or old.dict ~= wanted[key].dict then
            RemoveReplaceTexture(old.material.dict, old.material.name)
            nativeReplacements[key] = nil
        end
    end
    for key, nextOne in pairs(wanted) do
        if not nativeReplacements[key] then
            AddReplaceTexture(nextOne.material.dict, nextOne.material.name,
                nextOne.dict, 'screen')
            nativeReplacements[key] = nextOne
        end
    end
end

AddEventHandler('whip_banking:standbyReady', refreshNativeScreens)
AddEventHandler('whip_banking:activeReady', refreshNativeScreens)

-- Keep the standby DUI alive for all ATM material replacements. The private
-- session browser is allocated only when an ATM (or calibration) actually needs
-- it; an idle player no longer pays for two Chromium pages from login.
local function ensureDuis(needsPrivate)
    if not standbyDui then standbyDui = createDui('maze_bank_standby', 1024, 768) end
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

local function closeUI()
    if mode == 'atm' then CORE:Callback('whip_banking:atmEnd') end
    visible = false
    mode = nil
    activeAtm = nil
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
    SendNUIMessage({type='close'})
    if atmCamera then
        RenderScriptCams(false, true, 350, true, false)
        DestroyCam(atmCamera, false)
        atmCamera = nil
    end
    FreezeEntityPosition(PlayerPedId(), false)
    setScreen({screen='idle', brand=Config.Brand})
    refreshNativeScreens()
end

local function openBank(isTeller)
    if visible then closeUI() end
    local result, why = request('overview')
    if not result then return notify(why or 'Bank unavailable', 'error') end
    visible = true
    mode = 'bank'
    SetNuiFocus(true, true)
    SendNUIMessage({type='openBank', teller=isTeller, data=result})
end

local function openAtm(contextEntity)
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

    -- View is from the actual screen face (the ATM's local negative Y). No fake ATM photograph or shell.
    local view = GetOffsetFromEntityInWorldCoords(entity, spec.side, spec.out-1.05, spec.up+0.12)
    local cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, view.x, view.y, view.z)
    PointCamAtCoord(cam, center.x, center.y, center.z)
    SetCamFov(cam, 51.0)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 450, true, false)
    atmCamera = cam

    activeAtm = entity
    mode = 'atm'
    visible = true
    FreezeEntityPosition(PlayerPedId(), true)
    SetNuiFocus(true, true)
    setScreen({screen='idle', brand=Config.Brand})
    refreshNativeScreens()
    SendNUIMessage({type='openAtm', data={cards=overview.cards, cash=overview.cash,
      currency=Config.Currency, brand=Config.Brand, dailyLimit=Config.AtmDailyLimit}})
end

Whip.register(function()
    for i, branch in ipairs(Config.Branches) do
        local entry = branch
        Whip.core:AddAction({
            id='branch_'..i,
            at={coords=vector3(entry.coords.x,entry.coords.y,entry.coords.z)},
            label='Speak to Maze Bank teller', icon='bank',
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
Whip.onConfigChanged('Brand', function()
    if standbyDui and standbyDui.ready then
        SendDuiMessage(standbyDui.browser,json.encode({screen='idle',brand=Config.Brand,currency=Config.Currency}))
    end
    if not visible then setScreen({screen='idle',brand=Config.Brand,currency=Config.Currency}) end
end)
Whip.onConfigChanged('Currency', function()
    if standbyDui and standbyDui.ready then
        SendDuiMessage(standbyDui.browser,json.encode({screen='idle',brand=Config.Brand,currency=Config.Currency}))
    end
end)
Whip.onConfigChanged('AtmOverlayPreview', function()
    if mode ~= 'atm' then setScreen({screen=Config.AtmOverlayPreview and 'calibration' or 'idle',brand=Config.Brand}) end
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

-- Uses WHIP's own developer page in /w, not a player-facing chat command.
Whip.register(function()
    Whip.core:RegisterDevPage('banking_atm_alignment',{
        label='Banking - ATM Alignment',
        desc='Move, resize and tilt ATM DUIs live, then copy one JSON for all models.',
        rows=function()
            return {rows={
                {id='nearest',label='Align nearest ATM',desc='Stand in front of the model you want to tune.',close=true},
                {id='export',label='Export all ATM positions',desc='Copy a JSON file for your developer.',close=true},
                {sep='Saved on this PC'},
                {kind='note',label=alignmentCount()..' model(s) calibrated locally'},
            }}
        end,
        onSelect=function(id)
            CreateThread(function()
                Wait(170) -- let /w close before this resource takes NUI focus
                if id=='nearest' then alignmentNearest()
                elseif id=='export' then alignmentOpen(nil) end
            end)
        end,
    })
end)

RegisterNetEvent('whip_core:devtools:modeChanged',function(evt)
    if alignState and (not evt or evt.on==false) then alignmentClose() end
end)

RegisterNetEvent('whip_banking:client:cardUsed', function(metadata)
    if visible then return end
    CreateThread(function() openBank(false) end)
end)

RegisterNUICallback('close', function(_, cb)
    closeUI()
    cb({ok=true})
end)

-- The web page cannot choose a net event name: these are the only callbacks it can invoke.
local allowed = {
    overview=true, accountCreate=true, transfer=true, issueCard=true, cardStatus=true,
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
        setScreen({screen=req.screen, brand=Config.Brand, currency=Config.Currency,
            name=req.name, last4=req.last4, balance=req.balance, cash=req.cash,
            amount=req.amount, limit=remainingLimit, message=req.message})
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
            setScreen({screen='calibration',brand=Config.Brand,model=previewModel})
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
                        texture = standbyDui
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
        if not standbyDui or ((mode == 'atm' or alignState or Config.AtmOverlayPreview) and not activeDui) then
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
    for _, replacement in pairs(nativeReplacements) do
        RemoveReplaceTexture(replacement.material.dict,replacement.material.name)
    end
    nativeReplacements = {}
    if activeDui and activeDui.browser then DestroyDui(activeDui.browser); activeDui.browser=nil end
    if standbyDui and standbyDui.browser then DestroyDui(standbyDui.browser); standbyDui.browser=nil end
end)
