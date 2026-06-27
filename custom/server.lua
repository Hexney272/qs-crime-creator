-- Initialize sv_inventory and sv_society FIRST so server/custom/** can extend them
_G.sv_inventory = {}
_G.sv_society   = {}

local success, result = pcall(lib.load, ('custom.%s.server'):format(Config.Framework))

if not success then
    -- Log the error but do NOT call error() - that kills the entire resource
    print('^1[qs-crime-creator] Framework adapter failed to load: ' .. tostring(result) .. '^0')
    print('^1[qs-crime-creator] Framework: ' .. tostring(Config.Framework) .. '^0')
    print('^3[qs-crime-creator] The resource will continue but some features may not work.^0')
    _G.sfr = {}  -- empty stub so other modules don't nil-crash
else
    _G.sfr = result --[[@as ServerFramework]]
    print('^2[INFO]^7 Successfully loaded the framework: ' .. Config.Framework)
end

---@param src number
---@param msg string
---@param type 'info' | 'error' | 'success'
function Notification(src, msg, type)
    TriggerClientEvent('crime:notification', src, msg, type)
end
