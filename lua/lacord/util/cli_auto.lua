local unpack = table.unpack

for k in pairs(_G.arg) do
    if k < 0 then goto okay end
end

error"The -lacord module was loaded without being in script mode, you must provide a script file to use this option."

::okay::

require"lacord.cli"(unpack(_G.arg, 1))