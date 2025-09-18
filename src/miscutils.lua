
--> if not rawget(_G,"write") then function write(fmt,...) io.stdout:write(fmt:format(...)) end end
--> function s() write(("--BEGIN %s\n"):format(unitname or untitled)) section:writeln() write(("--END %s\n"):format(unitname or "untitled")) end

--> unique_name = 1; s()

local function into_unique_name(name,namedb)
    --prevent collision if `name` ends in a number
    if not name:sub(-1):match("%D") then
        name = name.."_"
    end

    local unumber = namedb[name] or 0;
    namedb[name] = unumber +1;

    return name,unumber,name ..tostring(unumber);
end

--> nameconflicts = 1; s()
function resolve_name_conflicts(names)
    local name_count = {}
    local unique_names = {}

    for i, name in ipairs(names) do
        if not name_count[name] then
            name_count[name] = 0
            table.insert(unique_names, name)
        else
            name_count[name] = name_count[name] + 1
            local new_name = name .. "_" .. name_count[name]

            -- Make sure the new name is also unique
            while name_count[new_name] do
                name_count[name] = name_count[name] + 1
                new_name = name .. "_" .. name_count[name]
            end

            name_count[new_name] = 0
            table.insert(unique_names, new_name)
        end
    end

    return unique_names
end

