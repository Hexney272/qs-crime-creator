if Config.Ambulance ~= 'qbx' then return end

function IsPlayerDead()
    if LocalPlayer.state.isDead then
        return true
    end


    local success, isDead = pcall(function()
        return exports.qbx_medical:IsDead()
    end)

    return success and isDead or false
end
