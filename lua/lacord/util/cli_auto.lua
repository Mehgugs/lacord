local warn = warn or function()end

for k in pairs(_G.arg) do
    if k < 0 then goto okay end
end

error"The -lacord module was loaded without being in script mode, you must provide a script file to use this option."

::okay::

warn"@on"

require"lacord.cli"(table.unpack(_G.arg, 1))

warn"@off"