if not mem.inited then
    mem = {
        inited = true,
        statements = {},
        env = {}, 
        var = {},
    }
end

if event.type == "interrupt" then 
    mem.irr = false;
end

if event.type == "terminal" then
    event = {
        channel = "text",
        msg = event.text,
    }
end

if event.channel == "text" and event.msg == "erase" then 
    mem = {};
    print "Erased acesh";
    return
end

if event.channel == "text" and event.msg == "dbg" then
    digiline_send(true,mem);
    return
end

if event.channel == "acesh" or event.channel == "text" then
    if event.msg == "" then
        -- noop
    elseif not mem.statement then
        mem.statement = tostring(event.msg);
        mem.sp = 1;
    else
        table.insert(mem.statements,tostring(event.msg));
    end
end

local function expand(text)
    local alt = tonumber(text);
    if alt then return alt end;

    if text == "true" then return true; end
    if text == "false" then return false; end
    if text == "nil" then return end

    if text == "$env" then 
        return mem.env
    end

    if text:byte() == 37 then 
        return mem.env[text:sub(2)]
    end

    if text:byte() == 36 then 
        return mem.var[text:sub(2)]
    end

    return text;
end

local function commands(cmd)
    if cmd == "help" then 
        print ("hello there squishy human!");
    elseif cmd == "with" then
        mem.env[mem.arg or false] = mem.arg2;
    elseif cmd == "set" then
        mem.var[mem.arg or false] = mem.arg2;
    elseif cmd == "emit" then -- emit env
        digiline_send(mem.arg,mem.arg2);
    elseif cmd == "emite" then -- emit env
        digiline_send(mem.arg,mem.env);
    elseif cmd == "cle" then
        mem.env = {};
    else
        print(("unknown command %q"):format(cmd));
        mem.error = "unknown command";
    end
end

local on = true
local heated = 0;
local sp = mem.sp; 
while sp and on do
    on = false;
    if not mem.statement or sp > #mem.statement then
       print ("next" .. tostring(sp))
       mem.statement = table.remove(mem.statements);
       sp = 1;
    end
    local statement = mem.statement;
    if not statement then mem.sp = nil return end

    if mem.cmd then -- parse cmd
    else     
        mem.arg = nil;
        mem.arg2 = nil;
        mem.error = nil;
        local j = sp;
        local h = j;
        while #statement >= j and statement:byte(j) ~= 32 and statement:byte(j) ~= 10 do j = j + 1 end
        mem.cmd = statement:sub(sp,j - 1);
        if statement:byte(j) ~= 10 then
            j = j + 1;
            sp = j; 
            while #statement >= j and statement:byte(j) ~= 32 and statement:byte(j) ~= 10 do j = j + 1 end
            mem.arg = expand(statement:sub(sp,j - 1));

            if statement:byte(j) ~= 10 then
                j = j + 1;
                sp = j; 

                while statement:byte(j) ~= 10 and #statement >= j do j = j + 1 end
                mem.arg2 = expand(statement:sub(sp,j - 1));
            end
        end
        j = j + 1;
        sp = j; 
        heated = heated + (j - h);
        mem.virgin = true;
    end

    if mem.cmd then -- run cmd
        local cmd = mem.cmd;
        mem.cmd = nil;
        on = not commands(cmd);
        mem.virgin = false;
    end

    if heated > 15 then -- return if high heat
        if not mem.irr then 
            mem.irr = true;
            interrupt(1);
        end
        mem.sp = sp;
        return
    end
end
mem.sp = sp;