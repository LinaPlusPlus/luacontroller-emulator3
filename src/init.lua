
if true then --BEGIN GLOBALS

    --BEGIN Units global refrences
    WIRES,UNITS = {},{}
    DOMAINS = {};
    MANAGEMENT_OP = {};
    GODLUAC_OP = {}; --replaced with MANAGEMENT_OP?
    --END

    --BEGIN Internal state flags
    DID_WORK = false;
    HEAT = 0;
    FULL_LAPS = 0;
    MAX_HEAT = 100;
    TRACING = true;
    REPL_PROMPT = "text> ";
    WIRE_NEXT = nil; -- TODO update wire var names to reflect
    HARD_SHUTDOWN = nil; -- stops all actions (basically frying all luacs) and gracefully shuts dowh the kernal and the main loop.
    --END

    --BEGIN Hard coded units
    ROOT_DOMAIN = nil;
    ROOT_TALK_WIRE = nil;
    HOST_UNIT = nil;
    DEV_DOMAIN = nil;
    UNASSIGNED_DOMAIN = nil;
    --END

    --BEGIN allocing state
    NEXT_INTERRUPT = 0;
    INTERRUPTS = {};
    --END

    -- BEGIN source system
    OVR_SOURCES = {}

    SOURCES = {}

    SRC_BUILTINS = {
        ["sys/helloworld"]="print('hello world')",
    }
    --END

end --END GLOBALS

--TEMP until proper arg parsing
local PROJECT_MANIFEST = ARGS[1];
if not PROJECT_MANIFEST then log("fail","system","usage: emulator3 <project_file>") return end
local PROJECT_DIR = ARGS[1]:match("^(.*)[/\\]")


local lib_dir = ...;
require (lib_dir..".fifo")
require (lib_dir..".dump")
require (lib_dir..".json")
require (lib_dir..".logging")
require (lib_dir..".managent")
require (lib_dir..".safeglobals")


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

            if resdata.c == "interrupt" then
                local irr = INTERRUPTS[resdata.echo]
                if not irr then
                    send({c="bad_wake",name=resdata.echo});
                else
                    INTERRUPTS[resdata.echo] = nil
                    --print ("irr resume "..dump(irr))
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
