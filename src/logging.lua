rsend = print;

function send(jsonable)
    rsend(json_encode(jsonable));
end

function print(...)
    local args = {...};
    for i = 1, select("#",...) do
        args[i] = dump(args[i])
    end
    log("print","system","%s",table.concat(args,"\t"));
end


function log(mode, src, fmt, ...)
    local message = (fmt or ""):format(...)

    rsend(json_encode({c=mode,src=src,msg=message}));
end
