local success, result = pcall(lib.load, ('custom.%s.client'):format(Config.Framework))

if not success then
    error(result, 0)
end

_G.cfr = result --[[@as ClientFramework]]

---@param msg string
---@param type 'info' | 'error' | 'success'
function Notification(msg, type)
    -- if GetResourceState('qs-interface') == 'started' then
    --     if type == 'info' then
    --         exports['qs-interface']:AddNotify(msg, 'Inform', 5000, 'fas fa-file')
    --     elseif type == 'error' then
    --         exports['qs-interface']:AddNotify(msg, 'Error', 5000, 'fas fa-bug')
    --     elseif type == 'success' then
    --         exports['qs-interface']:AddNotify(msg, 'Success', 5000, 'fas fa-thumbs-up')
    --     end
    --     return
    -- end
    SendReactMessage('notification', {
        msg = msg,
        type = type
    })
    -- if type == 'info' then
    --     lib.notify({
    --         title = 'Shops',
    --         description = msg,
    --         type = 'info'
    --     })
    -- elseif type == 'error' then
    --     lib.notify({
    --         title = 'Shops',
    --         description = msg,
    --         type = 'error'
    --     })
    -- elseif type == 'success' then
    --     lib.notify({
    --         title = 'Shops',
    --         description = msg,
    --         type = 'success'
    --     })
    -- end
end

RegisterNetEvent('crime:notification', Notification)

print('^2[INFO]^7 Successfully loaded the framework.', Config.Framework)

local texts = {}
if GetResourceState('qs-textui') == 'started' then
    function DrawText3D(x, y, z, text, id, key)
        local _id = id
        if not texts[_id] then
            CreateThread(function()
                texts[_id] = 5
                while texts[_id] > 0 do
                    texts[_id] = texts[_id] - 1
                    Wait(0)
                end
                texts[_id] = nil
                exports['qs-textui']:DeleteDrawText3D(id)
                Debug('Deleted text', id)
            end)
            TriggerEvent('textui:DrawText3D', x, y, z, text, id, key)
        end
        texts[_id] = 5
    end
else
    function DrawText3D(x, y, z, text)
        SetTextScale(0.35, 0.35)
        SetTextFont(4)
        SetTextProportional(1)
        SetTextColour(255, 255, 255, 215)
        SetTextEntry('STRING')
        SetTextCentre(true)
        AddTextComponentString(text)
        SetDrawOrigin(x, y, z, 0)
        DrawText(0.0, 0.0)
        local factor = text:len() / 370
        DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
        ClearDrawOrigin()
    end
end

function DrawText3Ds(x, y, z, text)
    SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(1)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry('STRING')
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x, y, z, 0)
    DrawText(0.0, 0.0)
    local factor = text:len() / 370
    DrawRect(0.0, 0.0 + 0.0125, 0.017 + factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

function DrawGenericText(text)
    SetTextColour(186, 186, 186, 255)
    SetTextFont(4)
    SetTextScale(0.5, 0.5)
    SetTextWrap(0.0, 1.0)
    SetTextCentre(false)
    SetTextDropshadow(0, 0, 0, 0, 255)
    SetTextEdge(1, 0, 0, 0, 205)
    SetTextEntry('STRING')
    AddTextComponentString(text)
    DrawText(0.40, 0.00)
end

local _world3dToSreen2d, _getGameplayCamCoords, _getGameplayCamFov = World3dToScreen2d, GetGameplayCamCoords, GetGameplayCamFov
DrawText3DX = function(text, coords)
    local _coords        = vec3(coords.x, coords.y, coords.z)
    local onScreen, x, y = _world3dToSreen2d(_coords.x, _coords.y, _coords.z)
    local camCoords      = _getGameplayCamCoords()
    local dist           = #(camCoords - _coords)

    local size           = 2
    local scale          = (size / dist) * 2
    local fov            = (1 / _getGameplayCamFov()) * 100
    scale                = scale * fov

    if onScreen then
        SetTextScale(0.0 * scale, 0.55 * scale)
        SetTextFont(0)
        SetTextColour(255, 255, 255, 255)
        SetTextDropshadow(0, 0, 0, 0, 255)
        SetTextDropShadow()
        SetTextOutline()
        SetTextEntry('STRING')
        SetTextCentre(1)

        AddTextComponentString(text)
        DrawText(x, y)
    end
end

---@param data ProgressProps
---@return boolean?
function ProgressBar(data)
    IsBusy = true
    local success
    if GetResourceState('qs-interface') == 'started' then
        success = exports['qs-interface']:ProgressBar(data)
    else
        success = lib.progressCircle(data)
    end
    if not success then
        Notification(i18n.t('cancelled'), 'error')
    end
    IsBusy = false
    return success
end

function ToggleHud(bool)
    DisplayRadar(bool) -- You can enable or disable mini-map here
    if GetResourceState('qs-interface') == 'started' then
        exports['qs-interface']:ToggleHud(bool)
    end
end

CurrentTextUI = nil
function ShowTextUI(str)
    CurrentTextUI = str
    if GetResourceState('qs-textui') == 'started' then
        exports['qs-textui']:displayTextUI(str)
    else
        lib.showTextUI(str, Config.TextUIOptions)
    end
end

function HideTextUI(noUpdate)
    if not noUpdate then
        CurrentTextUI = nil
    end
    if GetResourceState('qs-textui') == 'started' then
        exports['qs-textui']:hideTextUI()
    else
        lib.hideTextUI()
    end
end

function OpenInteractionMenu()
    local organization = LocalPlayer.state.organization
    if not organization then
        -- Notification(i18n.t('no_organization'), 'error')
        return
    end
    local options = {
        {
            icon = 'FaSearch',
            title = 'Steal',
            onSelect = function()
                SearchPlayer()
            end
        },
        {
            icon = 'FaUser',
            title = 'Escort',
            onSelect = function()
                EscortPlayer()
            end
        },
        {
            icon = 'Fa6Handcuffs',
            title = 'Handcuff',
            onSelect = function()
                HandcuffPlayer()
            end
        },
        {
            icon = 'FaHandPointLeft',
            title = 'Put In Vehicle',
            onSelect = function()
                PutInVehicle()
            end
        },
        {
            icon = 'FaHandPointRight',
            title = 'Get Out Vehicle',
            onSelect = function()
                OutVehicle()
            end
        },
        {
            icon = 'FaHandHoldingUsd',
            title = 'Sell Drugs',
            onSelect = function()
                cornerselling:start()
            end
        },
        {
            icon = 'Fa6Diamond',
            title = 'Open Boss Menu',
            onSelect = function()
                bossmenu:open()
            end
        },
        {
            icon = 'Fa6Tablet',
            title = 'Open Tablet',
            onSelect = function()
                tablet:open()
            end
        },
        {
            icon = 'FaMask',
            title = 'Put Headbag',
            onSelect = function()
                PutHeadbagOn()
            end
        },
        {
            icon = 'FaMask',
            title = 'Take Off Headbag',
            onSelect = function()
                TakeHeadbagOff()
            end
        },
    }

    interaction:open(options)
end

if Config.InteractionKey then
    RegisterCommand('organization_interaction_menu', OpenInteractionMenu)
    RegisterKeyMapping('organization_interaction_menu', 'Open Organization Interaction Menu', 'keyboard', Config.InteractionKey)
end
