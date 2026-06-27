-- ============================================================
-- client/modules/keypad/main.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- PIN keypad UI module.  Shows a React overlay that accepts a
-- numeric PIN, then resolves the call with the entered code.
-- ============================================================

_G.keypad = {}

-- ──────────────────────────────────────────────────────────
-- keypad.open(self, title, maxLength)
--   Opens the PIN-entry overlay.  Blocks (via a poll loop)
--   until the player submits or cancels.
--   Returns the entered PIN string, or nil if cancelled.
-- ──────────────────────────────────────────────────────────
function keypad.open(self, title, maxLength)
    self.title     = title     or "Enter PIN Code"
    self.maxLength = maxLength or 4
    self.response  = nil   -- cleared before waiting

    SendReactMessage("toggle_keypad", {
        visible   = true,
        title     = self.title,
        maxLength = self.maxLength,
    })

    SetNuiFocus(true, true)

    -- Poll until the NUI callback sets `response`
    while self.response == nil do
        Wait(50)
    end

    return self.response
end

-- ──────────────────────────────────────────────────────────
-- keypad.close(self)
--   Hides the keypad overlay and releases NUI focus.
-- ──────────────────────────────────────────────────────────
function keypad.close(self)
    SendReactMessage("toggle_keypad", { visible = false })
    SetNuiFocus(false, false)
end

-- ──────────────────────────────────────────────────────────
-- NUI callback: "keypad:submit"
--   Fired when the player confirms a PIN in the UI.
--   Validates the PIN length, then closes the overlay and
--   stores the response so keypad.open() can return.
-- ──────────────────────────────────────────────────────────
RegisterNUICallback("keypad:submit", function(payload, cb)
    local pin = payload.pin

    -- Reject submissions that are shorter than the required length
    if not pin or #pin < keypad.maxLength then
        return cb("error")
    end

    keypad:close()
    keypad.response = pin
    cb("ok")
end)
