--! stage { name="argparse", before = {"header"}, write=block }
--> pairs{logging} globals = 1; section:writeln();
local ARGS = {...};
local WIRES,UNITS = {},{}
local WIRE_NEXT; -- TODO update wire var names to reflect
local REPL_PROMPT = "text> ";
local TRACING = true;
local MAX_HEAT = 100;
local HEAT = 0;
local FULL_LAPS = 0;
local DID_WORK = false;
local MANAGEMENT_OP = {};
local GODLUAC_OP = {};
local DOMAINS = {};
local ROOT_DOMAIN;
local UNASSIGNED_DOMAIN;

local OVR_SOURCES = {

}

local SOURCES = {

}

local SRC_BUILTINS = {
    ["sys/helloworld"]="print('hello world')",
}

--> nameconflicts = 1; section:writeln()
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


--TEMP until proper arg parsing
local PROJECT_MANIFEST = ARGS[1];
if not PROJECT_MANIFEST then log("fail","system","usage: emulator3 <project_file>") return end
local PROJECT_DIR = ARGS[1]:match("^(.*)[/\\]")

if true then
    local err;
    PROJECT_CONFIG,err = io.open(PROJECT_MANIFEST,"r");
    if not PROJECT_CONFIG then
        log("fail","system","cannot open project manifest %q: %s",PROJECT_MANIFEST,err);
        return;
    end
end

table.insert(SOURCES,PROJECT_DIR);
table.insert(SOURCES,PROJECT_DIR.."/luac/");
table.insert(OVR_SOURCES,PROJECT_DIR.."/ovr/");

--> pairs {logging,globals,poll_wire,wire_utils,management,json} mainloop = 1; section:writeln();

--io.stdin:setvbuf("no");

-- bootstrapping
if true then

    ROOT_DOMAIN = new_domain("root");
    UNASSIGNED_DOMAIN = new_domain("unassigned");

    local event = assert(new_wire{name = "event", domain = ROOT_DOMAIN});
    local global = assert(new_wire{name = "root", domain = ROOT_DOMAIN});

    local testluac = assert(new_luac{name = "test",domain = ROOT_DOMAIN});
    testluac.blessed = true; -- has access to advanceds lua stuffs
    testluac.src = "god";

    local godluac = assert(new_luac{name = "god",domain = ROOT_DOMAIN, god_of = ROOT_DOMAIN });

    wire_connect(godluac,global);

    wire_connect(testluac,global);
    wire_connect(testluac,event);
end

while true do
    poll_wire();
    if (FULL_LAPS >= 5 and not DID_WORK) or HEAT >= MAX_HEAT then
        FULL_LAPS = 0; HEAT = 0;
        --io.write(REPL_PROMPT);
        local res = io.read("*l");
        if res ~= "" then
            local reader_wire = ROOT_DOMAIN.wires.event;
            if reader_wire then
                REPL_PROMPT = reader_wire.label or (reader_wire.name.."> ");
                reader_wire:push({
                    type = "terminal",
                    text = res,
                })
            else
                REPL_PROMPT = "NO READER] "
            end

        end
    end
    DID_WORK = false;
end

--> pairs {globals,safeluac,fifoq,} poll_wire = 1 section:writeln();
local function poll_wire()
    CURRENT_WIRE,CURRENT_WIRE_NAME = next(WIRES,CURRENT_WIRE);
    if not CURRENT_WIRE then FULL_LAPS = FULL_LAPS +1; return end

    if (CURRENT_WIRE.steps or 1) <= 0 then return end -- if you need to suspend a luac, please use this rather than
    if  CURRENT_WIRE.steps_dec then
        CURRENT_WIRE.steps = CURRENT_WIRE.steps - 1;
    end

    local event = CURRENT_WIRE:pop();
    if not event then return end

    if CURRENT_WIRE.connections then
        for ivoke_unit,nickname in pairs(CURRENT_WIRE.connections) do
            HEAT = HEAT +1;
            DID_WORK = true
            luac_envoke(ivoke_unit,event,nickname,CURRENT_WIRE);
        end
    end
end

--> pairs {logging,safeglobals}; wire_utils = 1; section:writeln();

local function wire_disconnect_domain(wire,domain)
    log("info",(luanick or "") .. " " .. luac_name(luac),"connected wire %s to domain %s",(wire.name or "INVALID_WIRE") .. " " .. domain.name);
end

local function wire_connect_domain(wire,domain)

    if domain.wires[wire.name] then
        return false,'exists';
    end

    domain.wires[wire.name] = wire
    wire.domain = domain;

    log("info",(luanick or "") .. " " .. luac_name(luac),"transfered wire %s to domain %s",(wire.name or "INVALID_WIRE") .. " " .. domain.name);

end


local function luac_connect_domain(luac,domain)

log("info",(luanick or "") .. " " .. luac_name(luac),"connected domain %s",(wirenick or "") .. " " .. wire.name);

end


local function wire_connect(luac,wire,luacnick,wirenick)
    luac.connections[wire] = luacnick or wire.name;
    wire.connections[luac] = wirenick or luac.name;
    log("info",(luanick or "") .. " " .. luac_name(luac),"connected wire %s",(wirenick or "") .. " " .. wire.name);
end

local function wire_disconnect(luac,wire)
    luac.connections[wire] = nil;
    wire.connections[luac] = nil;
end

