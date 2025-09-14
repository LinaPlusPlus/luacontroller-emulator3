
local Queue = {}
Queue.__index = Queue;

function Queue.new(tab)
    return setmetatable(tab or {first = nil, last = nil}, Queue);
end

function Queue:push(value)
    local node = value or {next = nil};
    if not self.first then
        -- Queue is empty
        self.first = node
        self.last = node
    else
        -- Append to the end
        self.last.next = node
        self.last = node
    end
end

function Queue:pop()
    if not self.first then
        return nil -- Queue is empty
    end
    local first = self.first
    self.first = first.next
    if not self.first then
        self.last = nil -- Queue is now empty
    end
    return first
end

function Queue:empty()
    return self.first == nil
end
local json_decode,json_encecode
if true do
--
-- json.lua
--
-- Copyright (c) 2020 rxi
--
-- Permission is hereby granted, free of charge, to any person obtaining a copy of
-- this software and associated documentation files (the "Software"), to deal in
-- the Software without restriction, including without limitation the rights to
-- use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies
-- of the Software, and to permit persons to whom the Software is furnished to do
-- so, subject to the following conditions:
--
-- The above copyright notice and this permission notice shall be included in all
-- copies or substantial portions of the Software.
--
-- THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
-- IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
-- FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
-- AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
-- LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
-- OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
-- SOFTWARE.
--

local json = { _version = "0.1.2" }

-------------------------------------------------------------------------------
-- Encode
-------------------------------------------------------------------------------

local encode

local escape_char_map = {
  [ "\\" ] = "\\",
  [ "\"" ] = "\"",
  [ "\b" ] = "b",
  [ "\f" ] = "f",
  [ "\n" ] = "n",
  [ "\r" ] = "r",
  [ "\t" ] = "t",
}

local escape_char_map_inv = { [ "/" ] = "/" }
for k, v in pairs(escape_char_map) do
  escape_char_map_inv[v] = k
end


local function escape_char(c)
  return "\\" .. (escape_char_map[c] or string.format("u%04x", c:byte()))
end


local function encode_nil(val)
  return "null"
end


local function encode_table(val, stack)
  local res = {}
  stack = stack or {}

  -- Circular reference?
  if stack[val] then error("circular reference") end

  stack[val] = true

  if rawget(val, 1) ~= nil or next(val) == nil then
    -- Treat as array -- check keys are valid and it is not sparse
    local n = 0
    for k in pairs(val) do
      if type(k) ~= "number" then
        error("invalid table: mixed or invalid key types")
      end
      n = n + 1
    end
    if n ~= #val then
      error("invalid table: sparse array")
    end
    -- Encode
    for i, v in ipairs(val) do
      table.insert(res, encode(v, stack))
    end
    stack[val] = nil
    return "[" .. table.concat(res, ",") .. "]"

  else
    -- Treat as an object
    for k, v in pairs(val) do
      if type(k) ~= "string" then
        error("invalid table: mixed or invalid key types")
      end
      table.insert(res, encode(k, stack) .. ":" .. encode(v, stack))
    end
    stack[val] = nil
    return "{" .. table.concat(res, ",") .. "}"
  end
end


local function encode_string(val)
  return '"' .. val:gsub('[%z\1-\31\\"]', escape_char) .. '"'
end


local function encode_number(val)
  -- Check for NaN, -inf and inf
  if val ~= val or val <= -math.huge or val >= math.huge then
    error("unexpected number value '" .. tostring(val) .. "'")
  end
  return string.format("%.14g", val)
end


local type_func_map = {
  [ "nil"     ] = encode_nil,
  [ "table"   ] = encode_table,
  [ "string"  ] = encode_string,
  [ "number"  ] = encode_number,
  [ "boolean" ] = tostring,
}


encode = function(val, stack)
  local t = type(val)
  local f = type_func_map[t]
  if f then
    return f(val, stack)
  end
  error("unexpected type '" .. t .. "'")
end


function json_encode(val)
  return ( encode(val) )
end


-------------------------------------------------------------------------------
-- Decode
-------------------------------------------------------------------------------

local parse

local function create_set(...)
  local res = {}
  for i = 1, select("#", ...) do
    res[ select(i, ...) ] = true
  end
  return res
end

local space_chars   = create_set(" ", "\t", "\r", "\n")
local delim_chars   = create_set(" ", "\t", "\r", "\n", "]", "}", ",")
local escape_chars  = create_set("\\", "/", '"', "b", "f", "n", "r", "t", "u")
local literals      = create_set("true", "false", "null")

local literal_map = {
  [ "true"  ] = true,
  [ "false" ] = false,
  [ "null"  ] = nil,
}


local function next_char(str, idx, set, negate)
  for i = idx, #str do
    if set[str:sub(i, i)] ~= negate then
      return i
    end
  end
  return #str + 1
end


local function decode_error(str, idx, msg)
  local line_count = 1
  local col_count = 1
  for i = 1, idx - 1 do
    col_count = col_count + 1
    if str:sub(i, i) == "\n" then
      line_count = line_count + 1
      col_count = 1
    end
  end
  error( string.format("%s at line %d col %d", msg, line_count, col_count) )
end


local function codepoint_to_utf8(n)
  -- http://scripts.sil.org/cms/scripts/page.php?site_id=nrsi&id=iws-appendixa
  local f = math.floor
  if n <= 0x7f then
    return string.char(n)
  elseif n <= 0x7ff then
    return string.char(f(n / 64) + 192, n % 64 + 128)
  elseif n <= 0xffff then
    return string.char(f(n / 4096) + 224, f(n % 4096 / 64) + 128, n % 64 + 128)
  elseif n <= 0x10ffff then
    return string.char(f(n / 262144) + 240, f(n % 262144 / 4096) + 128,
                       f(n % 4096 / 64) + 128, n % 64 + 128)
  end
  error( string.format("invalid unicode codepoint '%x'", n) )
end


local function parse_unicode_escape(s)
  local n1 = tonumber( s:sub(1, 4),  16 )
  local n2 = tonumber( s:sub(7, 10), 16 )
   -- Surrogate pair?
  if n2 then
    return codepoint_to_utf8((n1 - 0xd800) * 0x400 + (n2 - 0xdc00) + 0x10000)
  else
    return codepoint_to_utf8(n1)
  end
end


local function parse_string(str, i)
  local res = ""
  local j = i + 1
  local k = j

  while j <= #str do
    local x = str:byte(j)

    if x < 32 then
      decode_error(str, j, "control character in string")

    elseif x == 92 then -- `\`: Escape
      res = res .. str:sub(k, j - 1)
      j = j + 1
      local c = str:sub(j, j)
      if c == "u" then
        local hex = str:match("^[dD][89aAbB]%x%x\\u%x%x%x%x", j + 1)
                 or str:match("^%x%x%x%x", j + 1)
                 or decode_error(str, j - 1, "invalid unicode escape in string")
        res = res .. parse_unicode_escape(hex)
        j = j + #hex
      else
        if not escape_chars[c] then
          decode_error(str, j - 1, "invalid escape char '" .. c .. "' in string")
        end
        res = res .. escape_char_map_inv[c]
      end
      k = j + 1

    elseif x == 34 then -- `"`: End of string
      res = res .. str:sub(k, j - 1)
      return res, j + 1
    end

    j = j + 1
  end

  decode_error(str, i, "expected closing quote for string")
end


local function parse_number(str, i)
  local x = next_char(str, i, delim_chars)
  local s = str:sub(i, x - 1)
  local n = tonumber(s)
  if not n then
    decode_error(str, i, "invalid number '" .. s .. "'")
  end
  return n, x
end


local function parse_literal(str, i)
  local x = next_char(str, i, delim_chars)
  local word = str:sub(i, x - 1)
  if not literals[word] then
    decode_error(str, i, "invalid literal '" .. word .. "'")
  end
  return literal_map[word], x
end


local function parse_array(str, i)
  local res = {}
  local n = 1
  i = i + 1
  while 1 do
    local x
    i = next_char(str, i, space_chars, true)
    -- Empty / end of array?
    if str:sub(i, i) == "]" then
      i = i + 1
      break
    end
    -- Read token
    x, i = parse(str, i)
    res[n] = x
    n = n + 1
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "]" then break end
    if chr ~= "," then decode_error(str, i, "expected ']' or ','") end
  end
  return res, i
end


local function parse_object(str, i)
  local res = {}
  i = i + 1
  while 1 do
    local key, val
    i = next_char(str, i, space_chars, true)
    -- Empty / end of object?
    if str:sub(i, i) == "}" then
      i = i + 1
      break
    end
    -- Read key
    if str:sub(i, i) ~= '"' then
      decode_error(str, i, "expected string for key")
    end
    key, i = parse(str, i)
    -- Read ':' delimiter
    i = next_char(str, i, space_chars, true)
    if str:sub(i, i) ~= ":" then
      decode_error(str, i, "expected ':' after key")
    end
    i = next_char(str, i + 1, space_chars, true)
    -- Read value
    val, i = parse(str, i)
    -- Set
    res[key] = val
    -- Next token
    i = next_char(str, i, space_chars, true)
    local chr = str:sub(i, i)
    i = i + 1
    if chr == "}" then break end
    if chr ~= "," then decode_error(str, i, "expected '}' or ','") end
  end
  return res, i
end


local char_func_map = {
  [ '"' ] = parse_string,
  [ "0" ] = parse_number,
  [ "1" ] = parse_number,
  [ "2" ] = parse_number,
  [ "3" ] = parse_number,
  [ "4" ] = parse_number,
  [ "5" ] = parse_number,
  [ "6" ] = parse_number,
  [ "7" ] = parse_number,
  [ "8" ] = parse_number,
  [ "9" ] = parse_number,
  [ "-" ] = parse_number,
  [ "t" ] = parse_literal,
  [ "f" ] = parse_literal,
  [ "n" ] = parse_literal,
  [ "[" ] = parse_array,
  [ "{" ] = parse_object,
}


parse = function(str, idx)
  local chr = str:sub(idx, idx)
  local f = char_func_map[chr]
  if f then
    return f(str, idx)
  end
  decode_error(str, idx, "unexpected character '" .. chr .. "'")
end


function json_decode(str)
  if type(str) ~= "string" then
    error("expected argument of type string, got " .. type(str))
  end
  local res, idx = parse(str, next_char(str, 1, space_chars, true))
  idx = next_char(str, idx, space_chars, true)
  if idx <= #str then
    decode_error(str, idx, "trailing garbage")
  end
  return res
end

end

local function dump(o, indent, visited, depth, maxDepth)
    indent = indent or ""
    visited = visited or {}
    depth = depth or 0
    maxDepth = maxDepth or 5

    local function colorize(val, valType)
        if valType == "string" then
            return ("\27[32m\"%s\"\27[0m"):format(val);
        elseif valType == "number" then
            return ("\27[35m%s\27[0m"):format(val)
        elseif valType == "boolean" then
            return ("\27[31m%s\27[0m"):format(tostring(val))
        elseif valType == "nil" then
            return "\27[90mnil\27[0m"
        else
            return tostring(val)
        end
    end

    local function formatKey(k)
        if type(k) == "string" and k:match("^[%a_][%w_]*$") then
            return ("\27[33m%s\27[0m"):format(k)
        else
            return ("\27[36m[%s\27[36m]\27[0m"):format(dump(k,nextIndent,visited, depth + 1))
        end
    end

    if type(o) == "table" then
        if visited[o] then
            return "\27[36m<recursion>\27[0m"
        end
        if depth >= maxDepth then
            return "\27[36m{...}\27[0m"
        end

        visited[o] = true

        local nextIndent = indent .. "  "
        local s = "\27[36m{\27[0m\n"
        for k, v in pairs(o) do
            local keyStr = formatKey(k)
            local sep = keyStr:match("^%[%") and " = " or " = ";
            local valueStr = dump(v, nextIndent, visited, depth + 1, maxDepth);
            s = s .. ("%s%s%s%s,\n"):format(nextIndent, keyStr, sep, valueStr);
        end
        s = s .. indent .. "\27[36m}\27[0m"
        return s
    else
        return colorize(o, type(o))
    end
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

local function log(mode, src, fmt, ...)
    local lvl = mode:upper()
    local color = colors[lvl] or ""
    local reset = colors.reset
    local bold = colors.bold

    local level_str = pad(lvl, 6)          -- e.g., "INFO  "
    local source_str = pad(src, 15)        -- e.g., "main.lua      "
    local message = fmt:format(...)

    print(("%s[%s]%s  %s%s%s  %s"):format(
        color, level_str, reset,
        bold, source_str, reset,
        message
    ))
end
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

local function luac_broadcast(luac,response)
    local fufilled = {};
    for wire,wire_nick in pairs(luac.connections) do
        wire:push{
            type = "digiline",
            channel = luac.name,
            source = luac,
            msg = response,
            fufilled = fufilled,
        };
    end
end


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

function GODLUAC_OP.luac_info(godluac,event)

    local target_name = event.msg.name or "luac";

    local luac = godluac.god_of.luacs[target_name]
    if not luac then
        luac_broadcast(godluac,{
            error = "luac_not_found",
            echo = event.msg.echo,
        });
        return
    end

    luac_broadcast(godluac,{
        ok = true,
        name = luac_name(luac),
        label = luac.label,
        burnt = luac.burnt,
        blessed = luac.blessed,
        semi_blessed = luac.semi_blessed,
        unsandboxed = luac.unsandboxed,
        src = luac.src,
        echo = event.msg.echo,
    })
end

function GODLUAC_OP.notfound(godluac,event,nickname,wire)
    log("error",luac_name(event.source),"invalid godluac command: %s",event.action)
    godluac_respond(godluac,{
        echo = event.msg.echo,
        error = "command_not_found"
    })
end

function GODLUAC_OP.notfond(luac,event,nickname,wire)

end

function GODLUAC_OP.get_mem(luac,event,nickname,wire)

end

function GODLUAC_OP.set_mem(luac,event,nickname,wire)

end
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

