--! stage { name = "create_sandbox_env"}
--> pairs {dump,nameconflicts}; safeglobals = 1; safeluac = 1; section:writeln();

local function luac_name(luac)
    local name = luac.name or "INVALID_LUAC"
    local domain = (luac.domain and luac.domain.name or "INVALID_DOMAIN")

    if luac.fried then
        name = name .. " (dead)";
    end

    return ("%s/%s"):format(domain,name);
end


local function create_sandbox_env(luac)
    local safe_globals = {
        assert = assert,
        error = error,
        ipairs = ipairs,
        next = next,
        pairs = pairs,
        pcall = pcall,
        select = select,
        tonumber = tonumber,
        tostring = tostring,
        type = type,
        unpack = unpack or table.unpack,
        xpcall = xpcall,
        math = {
            abs = math.abs,
            acos = math.acos,
            asin = math.asin,
            atan = math.atan,
            ceil = math.ceil,
            cos = math.cos,
            deg = math.deg,
            exp = math.exp,
            floor = math.floor,
            fmod = math.fmod,
            huge = math.huge,
            log = math.log,
            max = math.max,
            min = math.min,
            pi = math.pi,
            rad = math.rad,
            random = math.random,
            sin = math.sin,
            sqrt = math.sqrt,
            tan = math.tan
        },
        string = {
            byte = string.byte,
            char = string.char,
            find = string.find,
            format = string.format,
            gmatch = string.gmatch,
            gsub = string.gsub,
            len = string.len,
            lower = string.lower,
            match = string.match,
            rep = string.rep,
            reverse = string.reverse,
            sub = string.sub,
            upper = string.upper
        },
        table = {
            insert = table.insert,
            maxn = table.maxn,
            remove = table.remove,
            sort = table.sort,
            concat = table.concat
        },
        os = {
            clock = os.clock
        }
    }

    safe_globals._G = safe_globals;

    if luac.unsandboxed then
        luac._HOST_G = _G
        safe_globals._LUAC = luac;
    end

    local blessed = luac.blessed;
    local semi_blessed = luac.semi_blessed ~= false;

    local name = luac_name(luac);
    if blessed then safe_globals.luacname = name end;

    function safe_globals.print(...)
        local buildup = {}
        for i = 1, select("#", ...) do
            buildup[i] = tostring(select(i, ...));
        end
        log("print", name, "%s", table.concat(buildup,"\t"));
    end

    -- way better but less anti stall safe print
    if blessed or semi_blessed then
        function safe_globals.print(...)
            local buildup = {};
            for i = 1, select("#", ...) do
                local statement = select(i, ...);
                if type(statement) == "string" then
                    buildup[i] = statement;
                else
                    buildup[i] = dump(statement);
                end
            end
            log("print", name, "%s", table.concat(buildup," "));
        end
    end

    function safe_globals.digiline_send(channel,message,limit_wire_nick,limit_nick)
        local chtype = type(channel);
        if chtype == "string" or chtype == "number" or chtype == "boolean" then
            --
        else
            error("Channel must be string, number or boolean.");
        end

        if not blessed then
            limit_wire_nick = nil;
            limit_nick = nil;
        end

        local fufilled = {};
        for wire,wire_nick in pairs(luac.connections) do
            if not limit_wire_nick or (limit_wire_nick == wire_nick) then
                wire:push{
                    type = "digiline",
                    channel = channel,
                    source = luac,
                    msg = safe_deep_clone(message),
                    only_nick = limit_nick,
                    fufilled = fufilled,
                };
            end
        end
    end

    return safe_globals
end

function safe_deep_clone(orig, seen)
    if type(orig) ~= "table" then
        return orig
    end

    if seen and seen[orig] then
        return seen[orig]
    end

    local copy = {}
    seen = seen or {}
    seen[orig] = copy

    -- This version uses raw iteration via `next`
    for k, v in next, orig do
        local safe_k = safe_deep_clone(k, seen)
        local safe_v = safe_deep_clone(v, seen)
        rawset(copy, safe_k, safe_v)
    end

    return copy
end


local function run_with_timeout(code, env, name, timeout_seconds)
    local load_func, err = load(code, name, "t", env)
    if not load_func then return false, "Load error: " .. err end

    local timed_out = false

    -- Set hook: every 10000 instructions, call this
    debug.sethook(function()
        timed_out = true
        error("Execution timed out", 0)
    end, "", 1000)

    local ok, result = pcall(load_func)

    debug.sethook() -- clear hook

    if not ok then
        if timed_out then
            return false, "Code tined out";
        else
            return false, "Runtime error: " .. result
        end
    end

    return true, result
end

local function luac_get_source(luac)
    if luac.srcstr then return luac.srcstr end
    if luac.srcpath then
        local data
        local fd,err = io.open(luac.srcpath,"r");
        if not fd then return false,err end

        data,err = fd:read("*all");
        if not data then return false,err end

        if luac.src_caching then
            luac.srcstr = data;
        end

        return data;
    end

    if luac.src then
        local src = luac.src;
        local srcpath = src:gsub("%.","/");
        for k,base in pairs(OVR_SOURCES) do
            local path = ("%s/%s.lua"):format(base,srcpath);
            local ok,err = io.open(path,"r");
            if ok then
                ok:close();
                luac.srcpath = path;
                log("info",luac_name(luac),"found src %q at: %s",src,path);
                return luac_get_source(luac)
            end
        end

        for k,base in pairs(SOURCES) do
            local path = ("%s/%s.lua"):format(base,srcpath);
            log("trace",luac_name(luac),"find: %s",path);
            local ok,err = io.open(path,"r");
            if ok then
                ok:close();
                luac.srcpath = path;
                log("info",luac_name(luac),"found src %q at: %s",src,path);
                return luac_get_source(luac)
            end
        end

        return false,("could not find %q"):format(src);

    end

    return false,"no source provided";
end

local function luac_envoke(luac,event,nickname,wire)


    if not event.fufilled then
        event.fufilled = {};
    end




    if event.source == luac and not event.allow_source then return end
    if event.only_nick and event.only_nick ~= nickname then return end
    if event.only_luac and event.only_luac ~= luac then return end

    if event.fufilled[luac] then return else
        event.fufilled[luac] = true;
        --print("again",event.type)
    end



    -- god objects cannot be suspended or fried
    if luac.god_of then
        print(luac.name,event.channel)
        if event.type == "digiline" and event.channel == luac.name then
            if type(event.msg) ~= "table" then
                return;
            end
            local command = event.msg.command or "notfound";
            (GODLUAC_OP[command] or GODLUAC_OP.notfound)(luac,event,nickname,wire);
        end
        return
    end

    -- the remaining event types likely envoke the luac
    -- fried luacs can still be managed
    if luac.fried then return end;

    local sourcecode,err = luac_get_source(luac);
    if not sourcecode then
        luac.fried = true;
        log("error",luac_name(luac),"Source error: %s",err)
        return
    end

    local sb = create_sandbox_env((luac));

    local wire_name = luac.blessed and wire and wire.name;
    local connections = luac.blessed and wire and wire.connections;
    local source_name = connections and connections[event.source or false];

    if event.type == "event" then
        sb.event = safe_deep_clone(event.message or event.msg);
    elseif event.type == "digiline" then
        sb.event = {
            type = "digiline",
            channel = event.channel,
            msg = safe_deep_clone(event.message or event.msg),
            wire = wire_name,
            source = source_name,
        }
    elseif event.type == "terminal" then
        sb.event = {
            type = "terminal",
            text = event.text,
            wire = wire_name,
            source = source_name,
        }
    else
        log("error",luac_name(luac),"invalid event: %s",dump(event));
        eb.event = {
            type = "invalid_event"
        }
    end

    local ok;
    ok,err = run_with_timeout(sourcecode,sb,luac_name(luac),1000);
    if not ok then
        log("error",luac_name(luac),"%s",err)
    end
end

local function new_luac(luac)
    luac = luac or {};
    if not luac.name then luac.name = "luac" end

    if not luac.domain then
        luac.domain = UNASSIGNED_DOMAIN;
    end

    if luac.domain.luacs[luac.name] then
        return false,'exists'
    end

    luac.domain.luacs[luac.name] = luac;
    luac.domain_name = luac.domain.name;

    luac.mem = {};

    luac.connections = {}; -- connection,nick pairs
    luac.blessed = false; -- can use advanced APIs
    luac.god_of = false; --is a "god controller",


    UNITS[luac] = luac.name;

    return luac;
end

local function new_wire(wire)
    wire = Queue.new(wire or {});
    if not wire.name then wire.name = "wire" end

    if not wire.domain then
        wire.domain = UNASSIGNED_DOMAIN;
    end

    if wire.domain.wires[wire.name] then
        return false,'exists'
    end

    if wire.god_of then
        if wire.god_of.god then
            return false,'domain_god_exists';
        end
        wire.god_of.god = luac;
    end

    wire.domain.wires[wire.name] = wire;

    wire.connections = {}; -- connection,nick pairs
    wire.domain_name = wire.domain.name;

    WIRES[wire] = wire.name;
    return wire;
end

local DOMAIN_NAME_USAGE = {};

local function new_domain(name)
    local unumber = DOMAIN_NAME_USAGE[name] or 0;
    DOMAIN_NAME_USAGE[name] = unumber +1;

    local domain = {
        name = name..tostring(unumber),
        basename = name,
        iteration = unumber,
        luacs = {},
        wires = {},
    };
    DOMAINS[domain.name] = name;

    return domain;
end