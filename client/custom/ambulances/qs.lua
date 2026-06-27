if Config.Ambulance ~= 'qs' then return end

function IsPlayerDead()
    return LocalPlayer.state.dead
end
