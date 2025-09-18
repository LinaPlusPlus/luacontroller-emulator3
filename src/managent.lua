--> pairs{ } traverse_nodes = 1; s();

--TODO move this to another file
local function traverse_nodes(dom,pathstr)
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
local function shell_backtrace(node,domain)
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
local function godluac_light_permissions(godluac,source,target_path)
    return true;
end

-- TODO almost even a HACK, make permission system more strict and granular
local function godluac_heavy_permissions(godluac,source,target_path)
    if godluac.is_blessed_godluac then return true end
end

--> pairs{ safeglobals,logging,wire_utils, traverse_nodes }  management = 1; s();

function GODLUAC_OP.info(godluac,event)

    local target_name = tostring(event.msg.path or "/unassigned/untitled");

    local target = traverse_nodes(godluac.god_of,target_name);
    --TODO
    if not target then
        return false, "unit_not_found";
    end

    --TODO make shure no data leaks given other types
    return {
        ok = true,
        type = target.type,
        --old_name = luac_name(target), --DEPRECATED this may crash given non luacs, it also leaks the domain's global_name
        name = target.name,
        echo = event.msg.echo,

        label = target.label,
        burnt = target.burnt,
        blessed = target.blessed,
        semi_blessed = target.semi_blessed,
        unsandboxed = target.unsandboxed,
        src = target.src,
    };
end

-- shuts down a domain and it's children and alerts the parent domain
-- unless it's blessed, then it shuts down the emulator
function GODLUAC_OP.shutdown(godluac,event,nickname,wire)
    if not godluac_heavy_permissions(godluac,event) then
        --HACK, instead it should nuke all children and emit a signal to the parent
        return GODLUAC_OP.permission_denied(godluac,event,nickname,wire);
    end

    send({c="info",msg=event.msg.msg or "shutting down..."});
    HARD_SHUTDOWN = true; --no point returning a message :P
end

function GODLUAC_OP.panic(godluac,event,nickname,wire)
    if not godluac_heavy_permissions(godluac,event) then
        --HACK, instead it should nuke all children and emit a signal to the parent
        return GODLUAC_OP.permission_denied(godluac,event,nickname,wire);
    end

    send({c="exit_code",code="root_panic"});
    log("fail",godluac.god_of.name,"%s",event.msg.msg or "root level panic...")
    HARD_SHUTDOWN = true; --no point returning a message :P
end

function GODLUAC_OP.notfound(godluac,event,nickname,wire)
    log("error",event.source and luac_name(event.source) or "??","unknown godluac command: %s",dump(event.msg.command))
    return false,"command_not_found";
end

function GODLUAC_OP.notfond(luac,event,nickname,wire)
    --TODO easter egg
    return GODLUAC_OP._unfinished();
end

function GODLUAC_OP.get_mem(luac,event,nickname,wire)
    return GODLUAC_OP._unfinished();
end

function GODLUAC_OP.get_config(luac,event,nickname,wire)
    return GODLUAC_OP._unfinished();
end

function GODLUAC_OP.set_config(luac,event,nickname,wire)
    return GODLUAC_OP._unfinished();
end


function GODLUAC_OP.get_file(godluac,event,nickname,wire)
    return GODLUAC_OP._unfinished();
end

function GODLUAC_OP._unfinished(godluac,event,nickname,wire)
    log("error",luac_name(event.source),"unfinished godluac command: %s",event.command)
    return false,"command_todo";
end

function GODLUAC_OP.permission_denied(godluac,event,nickname,wire)
    log("error",luac_name(event.source),"was denied godluac permssion to: %s",event.command)
    return false,"permission_denied"
end

-- overrite a file src for a domain
-- usually for compiled luacs
function GODLUAC_OP.ovr_file(godluac,event,nickname,wire)
    return GODLUAC_OP._unfinished();
end


function GODLUAC_OP.mkluac(godluac,event,nickname,wire)
    local msg = event.msg;
    local path = tostring(msg.path or "/unassigned/untitled");
    local src = msg.src and tostring(msg.src) or nil;
    --TODO mabe some other baubles to set when creating

    local _mabe_existing,domain_onto,new_name = traverse_nodes(godluac.god_of,path);

    if not domain_onto then
        return false,"parent_missing";
    end

    if not new_name then -- HACK, mabe useless edgecase
        return false,"somehow_not_child";
    end

    local luac,err = new_luac({
        allow_loadstring = msg.allow_loadstring,
        domain = domain_onto,
        name = new_name,
        src = src,
    })

    if not luac then
        return false,err;
    end

    return {
        ok = true,
        path = shell_backtrace(luac,godluac.god_of),
    }

end

function GODLUAC_OP.connect(godluac,event,nickname,wire)

    local msg = event.msg;
    local wire_path = tostring(msg.wire or "/unassigned/untitled");
    local luac_path = tostring(msg.luac or "/unassigned/untitled");

    local wire = traverse_nodes(godluac.god_of,wire_path);
    if not wire then
        return false, "wire_not_found";
    end

    if wire.type ~= "wire" then
        return false,"wire_wrong_type",wire.type;
    end

    local luac = traverse_nodes(godluac.god_of,luac_path);

    if not luac then
        return false, "luac_not_found";
    end

    if luac.type ~= "luac" then
        return false,"luac_wrong_type",luac.type;
    end

    wire_connect(luac,wire);

    return {
        ok = true,
    }
end