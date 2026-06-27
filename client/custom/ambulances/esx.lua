if Config.Ambulance ~= 'esx' then return end

function IsPlayerDead()
    return LocalPlayer.state.isDead == 1
end
