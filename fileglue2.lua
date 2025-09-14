-- File Glue v1.0, by Lina Plus
-- https://github.com/LinaPlusPlus/FileGlue
-- MIT lisense

local FLAGS = {};
local USED_FLAGS = {}; -- flags used by the program
local ENV = {
    coroutine=false,
    unsafe_coroutine=coroutine,
    CLI_ARGS={...},
};
ENV._G = _G;
local THREADS = {};
local CO_CURRENT = nil;
local NEW_THREAD,NEW_PROMISE,NEW_FILE_PART,NEW_SIMPLE_ASSIGNER;
local ACTIVE_THREADS = {};
local MAIN_THREAD,CURRENT_THREAD,LAST_THREAD;
local ENQUEUE_THREAD;
local GLOBAL_AWAITERS = {};
local PRINT_TRACE;
local DO_TRACE = false;
local STALLED_AWAITERS = {};
local ENV_THREAD = {};

local function SYNTAX_THREAD(thread)
    return (thread and thread.name) or ("Invalid Thread: "..tostring(thread));
end

local unpack = _G.unpack or table.unpack;

local function ASSIGN_TO_AWAIT_LIST(list,blocker,k)
    assert(list);
    assert(blocker);
    local v = list[k];
    if not v then v = {}; list[k] = v; end
    table.insert(v,blocker);
end
local colors = {
    reset   = "\27[0m",
    bold    = "\27[1m",

    TRACE   = "\27[90m",
    ETRACE  = "\27[35m",
    WTRACE  = "\27[33m",
    WARN    = "\27[1;33m",
    ERROR   = "\27[1;31m",
    INFO    = "\27[1;34m",
    FAIL    = "\27[1;97;41m",
    PRINT = "\27[1;36m",
}

local function pad(str, len)
    return str .. string.rep(" ", math.max(0, len - #str))
end

function log(mode, src, fmt, ...)
    local lvl = mode:upper()
    local color = colors[lvl] or ""
    local reset = colors.reset
    local bold = colors.bold

    local level_str = pad(lvl, 6)          -- e.g., "INFO  "
    local source_str = pad(src, 15)        -- e.g., "main.lua      "
    local message = fmt:format(...)

    io.stderr:write(("%s[%s]%s  %s%s%s  %s\n"):format(
        color, level_str, reset,
        bold, source_str, reset,
        message
    ))
end
-- arg_parser.lua
function ENV.parse_cli_args(args)
  local kv = {}
  local positional = {}

  for _, arg in ipairs(args) do
    if arg:sub(1, 2) == "--" then
      local key, val = arg:match("^%-%-([^=]+)=(.*)$")
      if key then
        kv[key] = val
      else
        -- Handle flags without =value as boolean true
        key = arg:sub(3)
        kv[key] = true
      end
    else
      positional[#positional + 1] = arg
    end
  end

  return kv, positional
end

local ENV_FLAG = {};
local ENV_FLAG_MT = {};

function ENV_FLAG_MT:__index(k)
    USED_FLAGS[k] = true;

    local got =  FLAGS[k]
    if got == nil then
        log("warn",SYNTAX_THREAD(CURRENT_THREAD),"flag %q is unset",k);
    end
    return got;
end

function ENV_FLAG_MT:__newindex(k,v)
    FLAGS[k] = v;
    if USED_FLAGS[k] then
      log("error",SYNTAX_THREAD(CURRENT_THREAD),"flag %q was changed after it was already used somwhere else",k);
      error("unsafe flag reassignment");
    end
end

local function anti_unused_flags()
    for k,v in pairs(FLAGS) do
      if not USED_FLAGS[k] then
        log("warn","unused_flags","flag %q was set but never used",k);
      end
    end
end

local ENV_FLAGON = {};
local ENV_FLAGON_MT = {};

function ENV_FLAGON_MT:__index(k)
    USED_FLAGS[k] = true; --TODO: should flagon be able to lock
    return FLAGS[k] or false;
end

-- just a shim but forced value into a boolean
function ENV_FLAGON_MT:__newindex(k,v)
    ENV_FLAG[k] = not not v;
    return true;
end

setmetatable(ENV_FLAG,ENV_FLAG_MT);
setmetatable(ENV_FLAGON,ENV_FLAGON_MT);

--TODO make a system where the flag data cannot be written to
rawset(ENV,"flag",ENV_FLAG);
rawset(ENV,"flagon",ENV_FLAGON);
-- unlike the kernal project, this is not about supervised code's safety or efficency

local env_mt = {};

function env_mt:__index(k)
    local tryval;
    if DO_TRACE then
        log("trace",SYNTAX_THREAD(CURRENT_THREAD),"Global Get %q",k);
    end
    --TODO add the awaiters to localzone, have the on resource found for globals scan all threads for `thread.blocker_global_key == key_being_assigned` rather than the big global awaitlist.
    --TODO: add the awaiting system to localzone
    --NOTE: the task of resuming a blocked thread by writing to global or localzone are going to be slightly diffrent
    -- the correct table should receve the written value,
    -- reading from pure global should avoid including localzone
    -- writing to this should mainly block awaiting a localzone change but global assignment of the same key can wake it.
    --



    tryval = _G[k];
    if tryval ~= nil then return tryval end

    local lz = CURRENT_THREAD and CURRENT_THREAD.localzone;
    tryval = lz and lz[k];
    if tryval ~= nil then return tryval end

    local sz = CURRENT_THREAD and CURRENT_THREAD.specificzone;
    tryval = sz and sz[k];
    if tryval ~= nil then return tryval end



    if k == "tracing" then
        return DO_TRACE;
    end

    -- try to await our global to be written to

    CURRENT_THREAD.blocker = ("Global %q"):format(k);
    CURRENT_THREAD.blocker_global_key = k;
    ASSIGN_TO_AWAIT_LIST(GLOBAL_AWAITERS,CURRENT_THREAD,k);
    return coroutine.yield();
end

function env_mt:__newindex(k,v)
    local awaiters = GLOBAL_AWAITERS[k];

    if k == "tracing" then
        DO_TRACE = not not v;
        return true;
    end

    if DO_TRACE then
        log("trace",SYNTAX_THREAD(CURRENT_THREAD),"Global Set %s = %s",k,v);
    end

    local lz = CURRENT_THREAD and CURRENT_THREAD.localzone;
    lz = lz and lz[k];
    if lz ~= nil then
        CURRENT_THREAD.localzone[k] = v;
        return true;
    end

    if awaiters then
        for i,t in ipairs(awaiters) do
            t.resume_data = {v};
            ENQUEUE_THREAD(t);
        end
    end

    rawset(self,k,v);

    return true; --is this correct/needed?
end

setmetatable(ENV,env_mt);

function PRINT_TRACE()
    for t,v in pairs(ACTIVE_THREADS) do
        log("trace",SYNTAX_THREAD(t),("Evergreen: %s\tAwaiting: %s"):format(t.evergreen,t.blocker));
    end
end
rawset(ENV,"trace",PRINT_TRACE);

function ENQUEUE_THREAD(t)
    assert(t and t._type == "thread","ENQUEUE_THREAD: thats not a thread");
    LAST_THREAD.next = t;
    LAST_THREAD = t;
end

function NEW_THREAD(t)
    t = t or {};
    t._type = "thread"
    t.name = t.name or ("Thread "..tostring(t):sub(6));
    t.evergreen = false;
    ACTIVE_THREADS[t] = true;
    return t;
end

function NEW_PROMISE(t)
    t = t or {};
    t._type = "promise";
    t.name = t.name or ("Promise "..tostring(t):sub(6));;

    return t;
end

local simple_assigner_mt = {};

function NEW_SIMPLE_ASSIGNER(t)
    t = t or {};
    setmetatable(t,simple_assigner_mt);
end

function simple_assigner_mt:__index(k)
    if type(k) ~= "string" then return end;

    local v = self["get_"..k];
    if v then return v() end
end

function simple_assigner_mt:__index(k,nv)
    if type(k) ~= "string" then
        rawset(self,k,nv);
        return true;
    end;

    local v = self["set_"..k];
    if v then
        v(nv);
        return true;
    end

    rawset(self,k,nv);
end

-- these are just shims so they live here
rawset(ENV,"load",function(chunk, chunkname, mode, env)
    env = env or ENV;
    return load(chunk, chunkname, mode, env)
end)

rawset(ENV,"loadfile",function(filename, mode, env)
    env = env or ENV
    return loadfile(filename, mode, env)
end)



-- TODO no API to declare your thread evergreen
-- meaning infinite loops need to die (somehow, they're usually blocked and can't express agency) once all threads stop or it will be concidered a failure

rawset(ENV,"print",function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    log("print", SYNTAX_THREAD(CURRENT_THREAD),"%s",table.concat(parts, "\t\t"));
end)

--TODO add object parsing
rawset(ENV,"dbg",function(...)
    local parts = {}
    for i = 1, select("#", ...) do
        parts[i] = tostring(select(i, ...))
    end
    log("trace", SYNTAX_THREAD(CURRENT_THREAD),"%s",table.concat(parts, "\t\t"));
end)

rawset(ENV,"thread",ENV_THREAD);
NEW_SIMPLE_ASSIGNER(ENV_THREAD);

function ENV_THREAD.get_list()
    --TODO
end

function ENV_THREAD.stop(...)
    CURRENT_THREAD.finished = "stopped"
    CURRENT_THREAD.result = {...};
end

function ENV_THREAD.onsettled()
    CURRENT_THREAD.blocker = "Other Threads settled/stalled";
    table.insert(STALLED_AWAITERS,CURRENT_THREAD);
    return coroutine.yield();
end

function ENV_THREAD.get_internal_structure()
    if not CURRENT_THREAD.allow_unsafe then
        error("this thread is not allowed to access unsafe apis");
    end
end

function ENV_THREAD.get_allow_unsafe()
    return CURRENT_THREAD.allow_unsafe;
end

function ENV_THREAD.get_name()
    return ENV_THREAD.name;
end

function ENV_THREAD.set_name(v)
    ENV_THREAD.name = tostring(v); --TODO enshure uniqueness and other important naming things
end

function ENV_THREAD.get_evergreen()
    return CURRENT_THREAD.evergreen or false;
end

function ENV_THREAD.set_evergreen(v)
    CURRENT_THREAD.evergreen = not not v;
end


rawset(ENV,"extract_arrow_text",function(filename,cb)
    local pattern = "^%s*%-%->%s*(.+)$"
    local buildup = {};
    local heading = nil;
    local lineno = 0;
    local headline = 0;

    local file = io.open(filename, "r")
    if not file then
        error("Failed to open file: " .. filename) --HACK builtin failure
    end

    for line in file:lines() do
        lineno = lineno +1;
        local text = line:match(pattern)
        if text then
            local ok,err = cb(heading,buildup,headline);
            if ok == false then return ok,err end;
            headline = lineno;
            buildup = {}
            heading = text
        else
            table.insert(buildup,line);
        end
    end

    if heading then
       return cb(heading,buildup,headline);
    end

    file:close()
    return;
end)


rawset(ENV,"use",function(filename)
    local localzone = {
        filename=filename,

    };
    localzone._LZ = localzone;

    return ENV.extract_arrow_text(filename,function(header,body,lineno)
        if header then

            local thread = NEW_THREAD({
                name = ("%s:%s"):format(filename,lineno),
                localzone = localzone,
                specificzone = {
                    -- a context even more specific than localzone
                    --TODO implement into __index
                    section = {
                        -- HACK: this is a shim until actual file slice object type can be written
                        __string=body,
                        tostring = function(self) return table.concat(self.__string,"\n") end,
                        write = function(self) io.stdout:write(self:tostring()) end, -- you can benifit from not storing this in ram for the length of the program i think
                        writeln = function(self) io.stdout:write(self:tostring().."\n") end,
                    },
                }
            });

            local unit,err = ENV.load(header);
            if not unit then
                log("error",SYNTAX_THREAD(thread),"Parse error: %s",err);
                thread.finished = true;
                ACTIVE_THREADS[thread] = nil;
                return unit,err;
            end

            thread.coro = coroutine.create(unit);
            ENQUEUE_THREAD(thread);

        end
    end)
end)

MAIN_THREAD = NEW_THREAD({
    name = "Main",
});

--HACK, technically, no non coroutine code should call (or even read/write)
-- anything inside ENV as it is *designed* to cause side-effects on calling code!
-- however, nothing is loaded yet so no untrusted code. I can hand verify this is safe to call.
MAIN_THREAD.coro = coroutine.create(ENV.load([[
    -- a flag for disabling the standard Main thread
    -- just leaving the threading engine itself,
    -- why is this a useful feature? I dont know!

    if CLI_ARGS[1] == "--nostd" then
        table.remove(CLI_ARGS,1)
        local loadpath = table.remove(CLI_ARGS,1);
        assert(load(loadpath))();
        return
    end

    local kv,infiles = parse_cli_args(CLI_ARGS);

    -- TODO make an "annoying warnings" flag to enable "annoying" (extremely helpful but verbose) warnings
    -- cheating here to avoid locking the tracing variable
    tracing = kv.trace;
    local log = _G.log;

    for k,v in pairs(kv) do
        flag[k] = v;
    end

    for i,k in pairs(infiles) do
        if kv.trace then log("info","Main","read file: %s",k); end
        use(k);
    end

    -- I will likely make a name based ordering structure that threads can use to wait
    -- there will be a default one that everyone is expected to use probably just called "stage";
    -- NOTE the stage object should be assigned created as late as possable and stage:fire() should be delayed until all others settle

    thread.onsettled();

]]));


CURRENT_THREAD = MAIN_THREAD;
LAST_THREAD = MAIN_THREAD;

-- a lot of logic from the main loop,
-- exported here to handle the variadic `coroutine.resume` function and
-- skip throwaway table creation
local function coro_next(ok,err,...)
    if not ok then
        if CURRENT_THREAD.manager then
            --TODO add manager code here
        else
            log("fail",SYNTAX_THREAD(CURRENT_THREAD),"Runtime error: %s",err);
        end
    end

    if coroutine.status(CURRENT_THREAD.coro) == "dead" then
        ACTIVE_THREADS[CURRENT_THREAD] = nil;
        CURRENT_THREAD.finished = "returned";
        CURRENT_THREAD.result = {ok,err,...};
        if DO_TRACE then
            log("trace",SYNTAX_THREAD(CURRENT_THREAD),"Finished")
        end
    end

    local next_thread = CURRENT_THREAD.next; --TODO when `next == current` will there be problems?
    CURRENT_THREAD.next = nil;
    CURRENT_THREAD = next_thread;

    if not CURRENT_THREAD then

        -- I made this a `pop()` instead,
        -- making it first come last served
        -- that way older callers will get priority,
        -- meaning `Main` will always be able to get the last execution if it wants to.

        CURRENT_THREAD = table.remove(STALLED_AWAITERS);
        if DO_TRACE and CURRENT_THREAD then
            log("trace",SYNTAX_THREAD(CURRENT_THREAD),"Awoke from settle")
        end
    end
end

-- main thread loop;
while CURRENT_THREAD do
    if DO_TRACE then -- TODO make this behind a more extreme trace setting
        log("trace",SYNTAX_THREAD(CURRENT_THREAD),"Execution Turn")
    end

    coro_next(coroutine.resume(CURRENT_THREAD.coro,unpack(CURRENT_THREAD.resume_data or {})));
end

-- code that runs after main loop
local function anti_stall()
    local test_failed = false;
    for k,v in pairs(ACTIVE_THREADS) do
        if not k.evergreen then
            test_failed = true;
        end
    end

    if test_failed then
        log("fail","program_stall","complation target did not finish all non evergreen threads");
    end

    PRINT_TRACE();
end

anti_stall();
anti_unused_flags();