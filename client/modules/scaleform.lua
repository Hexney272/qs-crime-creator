-- ============================================================
-- client/modules/scaleform.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- Scaleform movie helper library.  Wraps GTA scaleform natives
-- into a clean, typed API used throughout the resource.
-- ============================================================

Scaleforms = {}

-- ──────────────────────────────────────────────────────────
-- Scaleforms.LoadMovie(movieName)
--   Requests and waits for a regular scaleform movie.
--   Returns the movie handle.
-- ──────────────────────────────────────────────────────────
function Scaleforms.LoadMovie(movieName)
    local handle = RequestScaleformMovie(movieName)
    while not HasScaleformMovieLoaded(handle) do
        Wait(0)
    end
    return handle
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.LoadInteractive(movieName)
--   Requests and waits for an *interactive* scaleform movie.
--   Returns the movie handle.
-- ──────────────────────────────────────────────────────────
function Scaleforms.LoadInteractive(movieName)
    local handle = RequestScaleformMovieInteractive(movieName)
    while not HasScaleformMovieLoaded(handle) do
        Wait(0)
    end
    return handle
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.UnloadMovie(handle)
--   Marks a scaleform movie as no longer needed so the
--   engine can free its resources.
-- ──────────────────────────────────────────────────────────
function Scaleforms.UnloadMovie(handle)
    SetScaleformMovieAsNoLongerNeeded(handle)
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.LoadAdditionalText(textFile, maxSlot)
--   Ensures additional text slots 0..maxSlot are loaded for
--   `textFile`.  Clears and re-requests any slot that is not
--   yet loaded.
-- ──────────────────────────────────────────────────────────
function Scaleforms.LoadAdditionalText(textFile, maxSlot)
    for slot = 0, maxSlot, 1 do
        if not HasThisAdditionalTextLoaded(textFile, slot) then
            ClearAdditionalText(slot, true)
            RequestAdditionalText(textFile, slot)
            while not HasThisAdditionalTextLoaded(textFile, slot) do
                Wait(0)
            end
        end
    end
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.SetLabels(handle, labelsTable)
--   Calls SET_LABELS on a scaleform, pushing each label from
--   `labelsTable` as a scaleform string parameter.
-- ──────────────────────────────────────────────────────────
function Scaleforms.SetLabels(handle, labelsTable)
    PushScaleformMovieFunction(handle, "SET_LABELS")
    for i = 1, #labelsTable, 1 do
        BeginTextCommandScaleformString(labelsTable[i])
        EndTextCommandScaleformString()
    end
    PopScaleformMovieFunctionVoid()
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.PopMulti(handle, funcName, ...)
--   Calls `funcName` on `handle`, auto-detecting the type
--   of each extra argument and calling the appropriate
--   PushScaleformMovieFunctionParameter* native.
-- ──────────────────────────────────────────────────────────
function Scaleforms.PopMulti(handle, funcName, ...)
    PushScaleformMovieFunction(handle, funcName)

    local args = {}
    local a1, a2, a3, a4, a5, a6, a7 = ...
    args[1]=a1 ; args[2]=a2 ; args[3]=a3 ; args[4]=a4
    args[5]=a5 ; args[6]=a6 ; args[7]=a7

    for _, value in pairs(args) do
        local trueType = Scaleforms.TrueType(value)
        if trueType == "string" then
            PushScaleformMovieFunctionParameterString(value)
        elseif trueType == "boolean" then
            PushScaleformMovieFunctionParameterBool(value)
        elseif trueType == "int" then
            PushScaleformMovieFunctionParameterInt(value)
        elseif trueType == "float" then
            PushScaleformMovieFunctionParameterFloat(value)
        end
    end

    PopScaleformMovieFunctionVoid()
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.PopFloat(handle, funcName, value)
--   Calls `funcName` on `handle` with a single float param.
-- ──────────────────────────────────────────────────────────
function Scaleforms.PopFloat(handle, funcName, value)
    PushScaleformMovieFunction(handle, funcName)
    PushScaleformMovieFunctionParameterFloat(value)
    PopScaleformMovieFunctionVoid()
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.PopInt(handle, funcName, value)
--   Calls `funcName` on `handle` with a single integer param.
-- ──────────────────────────────────────────────────────────
function Scaleforms.PopInt(handle, funcName, value)
    PushScaleformMovieFunction(handle, funcName)
    PushScaleformMovieFunctionParameterInt(value)
    PopScaleformMovieFunctionVoid()
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.PopBool(handle, funcName, value)
--   Calls `funcName` on `handle` with a single boolean param.
-- ──────────────────────────────────────────────────────────
function Scaleforms.PopBool(handle, funcName, value)
    PushScaleformMovieFunction(handle, funcName)
    PushScaleformMovieFunctionParameterBool(value)
    PopScaleformMovieFunctionVoid()
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.PopRet(handle, funcName)
--   Calls `funcName` on `handle` with no params and returns
--   the scaleform function's return value.
-- ──────────────────────────────────────────────────────────
function Scaleforms.PopRet(handle, funcName)
    PushScaleformMovieFunction(handle, funcName)
    return PopScaleformMovieFunction()
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.PopVoid(handle, funcName)
--   Calls `funcName` on `handle` with no params (void return).
-- ──────────────────────────────────────────────────────────
function Scaleforms.PopVoid(handle, funcName)
    PushScaleformMovieFunction(handle, funcName)
    PopScaleformMovieFunctionVoid()
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.RetBool(handle)
--   Reads the boolean return value from the last scaleform call.
-- ──────────────────────────────────────────────────────────
function Scaleforms.RetBool(handle)
    return GetScaleformMovieFunctionReturnBool(handle)
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.RetInt(handle)
--   Reads the integer return value from the last scaleform call.
-- ──────────────────────────────────────────────────────────
function Scaleforms.RetInt(handle)
    return GetScaleformMovieFunctionReturnInt(handle)
end

-- ──────────────────────────────────────────────────────────
-- Scaleforms.TrueType(value)
--   Returns the "true" type string for a Lua value.
--   For numbers, distinguishes between "int" and "float"
--   by checking whether the tostring representation contains
--   a decimal point.
-- ──────────────────────────────────────────────────────────
function Scaleforms.TrueType(value)
    if "number" ~= type(value) then
        return type(value)
    end

    local strVal = tostring(value)
    if string.find(strVal, ".") then
        return "float"
    else
        return "int"
    end
end

-- Export the Scaleforms table so other resources can use it
exports("Scaleforms", function()
    return Scaleforms
end)
