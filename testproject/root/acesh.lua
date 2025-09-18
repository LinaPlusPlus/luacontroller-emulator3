local IO_SCHEME = "test";

local stdin; -- stdin event, `string or nil`
_G.print_raw = print;

if event.type == "program" then
    digiline_send("ioctl","get_capabilities");
    digiline_send("ioctl","pause");
    digiline_send("ioctl","pulse");
end

local function printerr(text)
    if mem.mode_local then
        print_raw("Error",text);
        return;
    end
    if mem.advio then
        digiline_send("errlcd",text);
    else
        digiline_send("lcd","err: " ..text);
    end
end


local function print(text)
    if mem.mode_local then
        print_raw(text);
        return;
    end
    if mem.advio then
        --TODO
    else
        digiline_send("lcd",text);
    end
end

if _G.caw or mem.caw then
    print(event);
end

if event.channel == "ioctl" and event.msg.type == "capabilities" then
       mem.advio = event.msg.advio
end

if (event.type == "digiline" and event.channel == "text") then
    stdin = event.msg;
    mem.mode_local = false
end

if event.text then
    stdin = event.text;
    mem.mode_local = true;
end

if stdin then
    -- do something with event.msg
    print("Received: " .. tostring(stdin));
    local ok
    local blob,err = load(stdin);
    if not blob then
        printerr(err);
        return;
    end
    ok,err = pcall(blob);
    if ok then
        print("Done")
    else
        printerr(err);
    end
end
