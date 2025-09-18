-- this sysinit just spawns a simple shell and sends it the manifest to execute

spawn_shell_src = "root/acesh" --TESTING

local SPAWN_SHELL_PATH = spawn_shell_path or "/shell"
local SHELL_STDIO_PATH = spawn_stdio_path or "/talk"
local SPAWN_SHELL_SRC = spawn_shell_src or "sysh";
local WIRE_NAME = wire_name or "wire";
local ROOT_CHANNEL = root_channel or "root_god"

local at = mem.at or 1;
local function ready(p)
    local b = p[at]; b(b);
    mem.at = at;
end

if  mem.error_panic ~= false
    and event.channel == ROOT_CHANNEL
    and event.msg.echo == mem.echo
    and event.msg.error
then
    digiline_send(ROOT_CHANNEL,{
        command = "panic",
        echo = mem.echo,
        msg = ("sysinit: could not start the enviornment: at stage %s: command error %q returned %s with %s"):format(at,event.msg.name,event.msg.error,event.msg.detail);
        --TODO
    });
end

return ready {
    function() --@1
        if event.type == "program" then
            mem.echo = math.random()
            digiline_send(ROOT_CHANNEL,{
                command = "mkluac",
                allow_loadstring = true,
                src = SPAWN_SHELL_SRC,
                path = SPAWN_SHELL_PATH,

                echo = mem.echo,
                --TODO
            });
            at = 2;
        end
    end,
    function() --@2
        if event.channel == ROOT_CHANNEL and event.msg.echo == mem.echo then
            mem.shell_path = event.msg.path;

            mem.echo = math.random()
            digiline_send(ROOT_CHANNEL,{
                command = "connect",
                wire = SHELL_STDIO_PATH,
                luac = mem.shell_path,
                echo = mem.echo,
                --TODO
            });
            at = 3;
        end
    end,
    function() --@3
        if event.channel == ROOT_CHANNEL and event.msg.echo == mem.echo then
            --TODO
        end
    end
};