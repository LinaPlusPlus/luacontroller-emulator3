--> pairs{} luac_broadcast = 1; section:writeln();
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

--> pairs{ safeglobals,luac_broadcast } management = 1; section:writeln();
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