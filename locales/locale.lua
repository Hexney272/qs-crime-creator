local _resourceName = GetCurrentResourceName()
local defaultLocale = json.decode(LoadResourceFile(_resourceName, 'locales/en.json')) or {}
local locale = LoadResourceFile(_resourceName, ('locales/%s.json'):format(Config.Locale))
if not locale then
    locale = defaultLocale
    print(('^1 WARNING: ^7Locale %s does not exist, falling back to default (en).'):format(Config.Locale))
end
_T = locale and json.decode(locale) or nil
if not _T then
    print(('^1 ERROR: ^7Failed to load locale file %s, falling back to default (en).'):format(('locales/%s.json'):format(Config.Locale)))
    _T = defaultLocale
end
for k, v in pairs(defaultLocale) do
    if not _T[k] then
        _T[k] = v
        CreateThread(function()
            Wait(5000) --  Wait 5 seconds so people can see the warning
            print(('^3[qs-crime-creator]^1 WARNING: ^7Locale %s is missing key `%s`, falling back to default (en). Please add this key to your locale file.'):format(Config.Locale, k))
        end)
    end
end

function _L(key, params)
    local value = _T
    for k in key:gmatch('[^.]+') do
        value = value[k]
        if not value then
            print('Missing locale for: ' .. key)
            return 'missing_' .. key
        end
    end
    if params then
        for k, v in pairs(params) do
            if type(v) == 'string' or type(v) == 'number' then
                value = value:gsub('{{' .. k .. '}}', v)
            end
        end
    end
    return value
end

_G['i18n'] = {
    t = _L
}
