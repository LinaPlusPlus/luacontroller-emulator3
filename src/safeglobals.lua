function poll_wire()
    CURRENT_WIRE,CURRENT_WIRE_NAME = next(WIRES,CURRENT_WIRE);
    if not CURRENT_WIRE then
        FULL_LAPS = FULL_LAPS +1;
        if TRACING then --TODO
            --log("trace","sleep","full lap")
        end
        return
    end

    if (CURRENT_WIRE.steps or 1) <= 0 then return end -- if you need to suspend a luac, please suspend it's wires rather than/as well as frying it.
    if  CURRENT_WIRE.steps_dec then
        CURRENT_WIRE.steps = CURRENT_WIRE.steps - 1;
    end

    local event = CURRENT_WIRE:pop();
    if not event then return end
    local tracing = TRACING or CURRENT_WIRE.tracing;
    if tracing == true or event.channel == true then --TODO make this way better;
        --TODO assumes everything is digilines, make it accept the other types too
        local name = luac_name(event.source or CURRENT_WIRE) or "unknown";
        log("trace",name,"%s","Event: "..dump(event.channel)..": "..dump(event.msg));
    end

    if CURRENT_WIRE.connections then
        for ivoke_unit,nickname in pairs(CURRENT_WIRE.connections) do
            HEAT = HEAT +1;
            DID_WORK = true
            FULL_LAPS = 0;
            luac_envoke(ivoke_unit,event,nickname,CURRENT_WIRE);
        end
    end
end


--TODO move this to another file
function traverse_nodes(dom,pathstr)
    local parent,partkey = nil,nil;
    for pathpart in string.gmatch(pathstr, "[^/]+") do
        if pathpart == "" or pathpart == "." then

        else
            parent = dom;
            partkey = pathpart;
            if not parent or not parent.type == "domain" then
                return false; -- file not found, cannot even write to parent
            end
            dom = parent.children[partkey];
        end
    end
    return dom,parent,partkey;
end

-- genarates a path to the given node from a domain
function shell_backtrace(node,domain)
    local bld = {};
    if node == domain then
        return ".";
    end
    while true do
        if not node then
            return false;
        end

        if node == domain then

            local reversed = {}
            for i = #bld, 1, -1 do
                reversed[#reversed + 1] = bld[i]
            end

            return table.concat(reversed,"/");
        end

        table.insert(bld,node.name);
        node = node.domain;
    end
end

-- TODO move this to safeglobals
function godluac_light_permissions(godluac,source,target_path)
    return true;
end

-- TODO almost even a HACK, make permission system more strict and granular
function godluac_heavy_permissions(godluac,source,target_path)
    if godluac.is_blessed_godluac then return true end
end

function luac_broadcast(luac,channel,response)
    local fufilled = {};
    if type(channel) ~= "string" then
        -- this check will be removed eventually
        error("Internal: channel must be string");
    end
    for wire,wire_nick in pairs(luac.connections) do
        wire:push{
            type = "digiline",
            channel = channel or luac.name, -- this silently does the wrong thing...
            source = luac,
            msg = response,
            fufilled = fufilled,
        };
    end
end


function luac_name(luac) --DEPRECATED, use other methods like trace
    local name = luac.name or "INVALID_LUAC"
    local domain = (luac.domain and luac.domain.global_name or "INVALID_DOMAIN")

    if luac.fried then
        name = name .. " (dead)";
    end

    return ("%s/%s"):format(domain,name);
end


function create_sandbox_env(luac)
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

    if luac.allow_loadstring then
        function safe_globals.load(code,name,mode,env)
            return load(code,("%s: %s"):format(luac.name,name or "blob"),"t",env or safe_globals);
        end
    end

    safe_globals.mem = safe_deep_clone(luac.mem);

    safe_globals._G = safe_globals;

    -- no longer safe if this flag is set :P
    -- only the root god luac is allowed to set this flag because
    -- only root is allowed to run code on the user's machine
    if luac.unsandboxed then
        safe_globals._HOST_G = _G
        safe_globals._LUAC = luac;
    end

    local things_to_print = {};
    local blessed = luac.blessed;
    local semi_blessed = luac.semi_blessed ~= false;

    local name = luac_name(luac);
    if blessed then safe_globals.luacname = name end;

    function safe_globals.print(...)
        table.insert(things_to_print,{name=name,...});
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

    function safe_globals.interrupt(time_secs,iid)
        local time = time_secs and tonumber(time_secs);
        if not time then error "interrupt expects a number" end
        time = time * 1000;

        NEXT_INTERRUPT = NEXT_INTERRUPT + 1;
        INTERRUPTS[NEXT_INTERRUPT] = {luac=luac,iid=safe_deep_clone(iid)};
        luac.irr_heat = (luac.irr_heat or 0) + 1
        send {
            c = "interrupt",
            echo = NEXT_INTERRUPT,
            time = time
        }
    end

    return safe_globals,things_to_print;
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


function run_with_timeout(code, env, name, timeout)

    local load_func, err;
    if type(code) == "function" then
        load_func = code
    else
        load_func, err = load(code, name, "t", env)
        if not load_func then return false, "Load error: " .. err end
    end

    local timed_out = false

    -- Set hook: every 10000 instructions, call this
    debug.sethook(function()
        timed_out = true

        timed_out = ("Execution timed out: %s"):format(debug.traceback())
        error(timed_out, 0)
    end, "", timeout or 1000)

    local ok, result = pcall(load_func)

    debug.sethook() -- clear hook

    if not ok then
        if timed_out then
            return false, timed_out;
        else
            return false, "Runtime error: " .. result
        end
    end

    return true, result
end

function luac_get_source(luac)
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

function luac_envoke(luac,event,nickname,wire)

    if HARD_SHUTDOWN then return end


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
        local hot_channel = (luac.config and luac.config.channel or luac.name)
        if event.type == "digiline" and event.channel == hot_channel then
            if type(event.msg) ~= "table" then
                return; -- ignore
            end
            local command = event.msg.command or "notfound";
            local ok,err,err2 = (GODLUAC_OP[command] or GODLUAC_OP.notfound)(luac,event,hot_channel,nickname,wire);
            if not ok and err then
                luac_broadcast(luac,hot_channel,{
                    error = err,
                    detail = err2,
                    name = command,
                    echo = event.msg.echo,
                })
            end
            if type(ok) == "table" then;
                ok.echo = event.msg.echo;
                luac_broadcast(luac,hot_channel,ok);
            end
        end
        return
    end

    if luac.virthw_of then
        if type(luac.virthw_of) == "function" then
            luac.virthw_of(luac,event,nickname,wire);
        else
            -- TODO if it's a domain, broadcast some proxy event
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

    local sb,things_to_print = create_sandbox_env((luac));

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
    ok,err = run_with_timeout(sourcecode,sb,luac_name(luac),1000); --TODO makde timeout controllable by domain
    if not ok then
        log("error",luac_name(luac),"%s",err)
    end

    local function print_results()

    --log("print", name, "print %s", dump(things_to_print));

    for k,buildup in pairs(things_to_print) do
        for i,statement in ipairs(buildup) do
            if not (luac.blessed or luac.semi_blessed) or type(statement) == "string" then
                buildup[i] = tostring(statement);
            else
                buildup[i] = dump(statement,nil,nil,nil,5);
            end
        end
        log("print", buildup.name, "%s", table.concat(buildup," "));
    end
    end

    local ok,err = run_with_timeout(print_results,_G,luac_name(luac).." (printing)",10000);
    if not ok then
        log("error", name, "while printing: %s",err);
    end

    luac.mem = safe_deep_clone(sb.mem);

end

function new_luac(luac)
    luac = luac or {};
    if not luac.name then luac.name = "luac" end

    if not luac.domain then
        luac.domain = UNASSIGNED_DOMAIN;
    end

    -- WARNING this logic unfortunately cannot be made DRY
    -- maintain this logic across each instance
    if luac.domain.unique_mode then
        luac.name = into_unique_name(luac.name,luac.domain.unique_mode);
    end

    if luac.domain.children[luac.name] then
        return false,'exists'
    end

    luac.domain.children[luac.name] = luac;

    luac.mem = luac.mem or {};

    luac.conf = luac.conf or {}; -- runtime find and replace snippets

    luac.connections = {}; -- connection,nick pairs
    --luac.blessed = false; -- can use advanced APIs
    --luac.god_of --is a "god controller",

    luac.type = "luac"

    UNITS[luac] = luac.name;

    return luac;
end

function new_wire(wire)
    wire = Queue.new(wire or {});
    if not wire.name then wire.name = "wire" end

    if not wire.domain then
        wire.domain = UNASSIGNED_DOMAIN;
    end

    -- WARNING this logic unfortunately cannot be made DRY
    -- maintain this logic across each instance
    if wire.domain.unique_mode then
        wire.name = into_unique_name(wire.name,wire.domain.unique_mode);
    end

    if wire.domain.children[wire.name] then
        return false,'exists'
    end

    if wire.god_of then
        if wire.god_of.god then
            return false,'domain_god_exists';
        end
        wire.god_of.god = luac;
    end

    wire.domain.children[wire.name] = wire;

    wire.connections = {}; -- connection,nick pairs

    WIRES[wire] = wire.name;

    wire.type = "wire"

    return wire;
end

DOMAIN_NAME_USAGE = {};


-- NOTE: only child domains should have known names to their parents
-- parent domains can 'peek' at child domains using varying commands, this can be recursive
-- the default setup for a domain is the god being called "domain_god" and a wire of the same name with them connected

function new_domain(name)

    local name,unumber,iname = into_unique_name(name,DOMAIN_NAME_USAGE);

    local domain = {
        type = "domain",
        global_name = iname, -- this is the *global* name
        name = iname, -- this is the *hiarchy* name
        basename = name,
        iteration = unumber,
        children = {},
    };
    DOMAINS[domain.global_name] = name;

    return domain;
end

function unit_move_domain(unit,domain,new_name) --TODO TESTME
    if not domain.type == "domain" then
        return false,'parent_isnt_domain';
    end

    if domain.unique_mode then
        new_name = into_unique_name(new_name,domain.unique_mode);
    end

    if domain.children[new_name] then
        return false,'exists';
    end

    if unit.domain then
        -- put disconnect logic here
        unit.domain.children[unit.name] = nil;
    end

    -- connect logic here
    domain.children[new_name] = unit;
    unit.domain = domain;
    unit.name = new_name;

    log("trace",(luanick or "") .. " " .. luac_name(unit),"moved to %s",(domain.global_name or "INVALID_UNIT"));

    return new_name;

end

function wire_connect(luac,wire,luacnick,wirenick)
    luac.connections[wire] = luacnick or wire.name;
    wire.connections[luac] = wirenick or luac.name;
    log("trace",(luanick or "") .. " " .. luac_name(luac),"connected wire %s",(wirenick or "") .. " " .. wire.name);
end

function wire_disconnect(luac,wire)
    luac.connections[wire] = nil;
    wire.connections[luac] = nil;
end

function into_unique_name(name,namedb)
    --prevent collision if `name` ends in a number
    if not name:sub(-1):match("%D") then
        name = name.."_"
    end

    local unumber = namedb[name] or 0;
    namedb[name] = unumber +1;

    return name,unumber,name ..tostring(unumber);
end

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

