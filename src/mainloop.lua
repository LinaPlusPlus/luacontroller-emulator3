--! stage { name="argparse", before = {"header"}, write=block }
--> pairs{logging} globals = 1; s();
--BEGIN GLOBALS
local ARGS = {...};

--BEGIN Units global refrences
local WIRES,UNITS = {},{}
local DOMAINS = {};
local MANAGEMENT_OP = {};
local GODLUAC_OP = {}; --replaced with MANAGEMENT_OP?
--END

--BEGIN Internal state flags
local DID_WORK = false;
local HEAT = 0;
local FULL_LAPS = 0;
local MAX_HEAT = 100;
local TRACING = false;
local REPL_PROMPT = "text> ";
local WIRE_NEXT; -- TODO update wire var names to reflect
local HARD_SHUTDOWN; -- stops all actions (basically frying all luacs) and gracefully shuts dowh the kernal and the main loop.
--END

--BEGIN Hard coded units
local ROOT_DOMAIN;
local ROOT_TALK_WIRE;
local HOST_UNIT;
local DEV_DOMAIN;
local UNASSIGNED_DOMAIN;
--END

--BEGIN allocing state
local NEXT_INTERRUPT = 0;
local INTERRUPTS = {};
--END

-- BEGIN source system
local OVR_SOURCES = {}

local SOURCES = {}

local SRC_BUILTINS = {
    ["sys/helloworld"]="print('hello world')",
}
--END

--END GLOBALS

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
    PROJECT_CONFIG,err = PROJECT_CONFIG:read("*a");
    if not PROJECT_CONFIG then
        log("fail","system","cannot open project manifest %q: %s",PROJECT_MANIFEST,err);
        return;
    end
end

table.insert(SOURCES,PROJECT_DIR);
table.insert(SOURCES,PROJECT_DIR.."/luac/");
table.insert(OVR_SOURCES,PROJECT_DIR.."/ovr/");

--> pairs {safeglobals,logging,globals,poll_wire,wire_utils,management,json} mainloop = 1; s();

-- BEGIN bootstrapping
if true then

    ROOT_DOMAIN = new_domain("root");
    ROOT_DOMAIN.name = "root";

    UNASSIGNED_DOMAIN = new_domain("unassigned");
    UNASSIGNED_DOMAIN.unique_mode = {};
    unit_move_domain(UNASSIGNED_DOMAIN,ROOT_DOMAIN,"unassigned");

    -- do we need this as a *builtin*? why can't sysinit create it?
    -- because the HOST *also* uses it's capability to place trinkets into `/dev/*` (dev0)
    -- by default, only the user shell should have access to root0

    -- this diffrers from say walloc,
    -- walloc allocates and deallocates wires based on requests
    -- no system device needs this treatment directly

    DEV_DOMAIN = new_domain("dev");
    DEV_DOMAIN.domain = ROOT_DOMAIN;
    DEV_DOMAIN.unique_mode = {};
    ROOT_DOMAIN.children["dev"] = DEV_DOMAIN;

    ROOT_TALK_WIRE = assert(new_wire{name = "talk", domain = ROOT_DOMAIN});

    local godluac = assert(new_luac{
        name = "god",
        config = {
            channel = "root_god",
        },
        domain = ROOT_DOMAIN,
        god_of = ROOT_DOMAIN,
        is_blessed_godluac = true, -- is blessed to preform shutdown and sandbox escape tasks
    });
    wire_connect(godluac,ROOT_TALK_WIRE);

    local devgodluac = assert(new_luac{
        name = "dev_god",
        domain = ROOT_DOMAIN,
        god_of = DEV_DOMAIN,
        blessed = true,
    });
    wire_connect(devgodluac,ROOT_TALK_WIRE);

    -- this unit is the baseline creator of all other luacs (minus the primitives described here)
    local sysinit = assert(new_luac{
        name = "sysinit",
        src = "root/sysinit",
        allow_ace = true,
        domain = ROOT_DOMAIN,
        blessed = true
    });

    wire_connect(sysinit,ROOT_TALK_WIRE);

    local function host_virthw(luac,event,nickname,wire)
        -- host specific api here.
        --
    end

    HOST_UNIT = assert(new_luac{name = "host",domain = DEV_DOMAIN, virthw_of = host_virthw});

    local function host_text_virthw(luac,event,nickname,wire)
        -- host advanced IO controller here.
    end

    HOST_TEXT_UNIT = assert(new_luac{name = "text0",domain = DEV_DOMAIN, virthw_of = host_text_virthw});

    wire_connect(HOST_UNIT,ROOT_TALK_WIRE);
    --wire_connect(HOST_TEXT_UNIT,ROOT_TALK_WIRE); -- let us not, do this, there will be a root accessing shell that listens on this wire!
    -- user should not have access to root until given by sysinit

end
-- END bootstrapping

ROOT_TALK_WIRE:push {
    --PROJECT_MANIFEST
    type = "event",
    msg = {
        type = "program",
        manifest = PROJECT_MANIFEST, --DEPRECATED!
    }
}

while true do --BEGIN main loop
    poll_wire();
    local sleep_no_work = FULL_LAPS >= 5 and not DID_WORK;
    local sleep_overheat = HEAT >= MAX_HEAT;
    if sleep_no_work or sleep_overheat then
        FULL_LAPS = 0; HEAT = 0;

        if TRACING and false then --TODO
            log("trace","sleep","overheat: %s, no_work: %s",sleep_overheat,sleep_no_work)
        end

        rsend('{"c":"wait"}');
        local res = io.read("*l");
        if HARD_SHUTDOWN then return HARD_SHUTDOWN end
        if not res then
            rsend('{"c":"fail","msg":"stdin disconnected"}');
            return
        end
        if res ~= "" then
            local ok,resdata = pcall(json_decode,res);
            if not ok then
                send({c="malformed_command",msg=res});
            end

            if resdata.c == "shutdown" then
                rsend('{"c":"shutdown"}');
                return
            end

            if resdata.c == "wake" then
                local irr = INTERRUPTS[resdata.name]
                if not irr then
                    send({c="bad_wake",name=resdata.name});
                else
                    luac_envoke(irr.luac,{
                        type = "event",
                        msg = {
                            type = "interrupt",
                            iid = irr.iid,
                        }
                    })
                end
            else

            --local reader_wire = ROOT_DOMAIN.wires.event;
            if resdata.c == "terminal" then
                luac_broadcast(HOST_UNIT,"text",resdata.msg or resdata.message);
            else
                luac_broadcast(HOST_UNIT,"host_rx",resdata);
            end

            end
        end
    end
    if HARD_SHUTDOWN then return HARD_SHUTDOWN end
    DID_WORK = false;
end --END main loop

--> pairs {globals,safeluac,fifoq,} poll_wire = 1 s();
local function poll_wire()
    CURRENT_WIRE,CURRENT_WIRE_NAME = next(WIRES,CURRENT_WIRE);
    if not CURRENT_WIRE then
        FULL_LAPS = FULL_LAPS +1;
        if TRACING then --TODO
            log("trace","sleep","full lap")
        end
        return
    end

    if (CURRENT_WIRE.steps or 1) <= 0 then return end -- if you need to suspend a luac, please suspend it's wires rather than/as well as frying it.
    if  CURRENT_WIRE.steps_dec then
        CURRENT_WIRE.steps = CURRENT_WIRE.steps - 1;
    end

    local event = CURRENT_WIRE:pop();
    if not event then return end
    local tracing = TRACING or luac.tracing;
    if tracing == true then --TODO make this way better;
        --TODO assumes everything is digilines, make it accept the other types too
        log("trace",luac_name(CURRENT_WIRE),"Event: "..dump(event.channel)..": "..dump(event.msg));
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
