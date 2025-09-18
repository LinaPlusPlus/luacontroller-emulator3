--> requires = 1; section:writeln();

const fs = require('fs');
const { spawn } = require('child_process');
const readline = require('readline');
const EventEmitter = require('events');

const exit_codes = {
    root_panic: 5,
    shutdown: 0,
}
let exit_code = null


--> pairs {requires,LuaProcess} main = 1; section:writeln();
// ---- Application Entry Point ----

const lua = new LuaProcess(process.argv[1],process.argv.slice(2));
lua.start();

const commands = {
    echo(pkt,lua){
        lua.send(pkt)
    },
    log(pkt) {
        log("log",pkt.src || "??",pkt.msg);
    },
    print(pkt) {
        log("print",pkt.src || "??",pkt.msg);
    },
    error(pkt) {
        log("error",pkt.src || "??",pkt.msg);
    },
    warn(pkt) {
        log("warn",pkt.src || "??",pkt.msg);
    },
    trace(pkt) {
        log("trace",pkt.src || "??",pkt.msg);
    },
    fail(pkt) {
        log("fail",pkt.src || "??",pkt.msg);
        lua.allow_writes = false;
    },
    shutdown(pkt) {
        lua.allow_writes = false;
    },
    info(pkt) {
        log("info",pkt.src || "??",pkt.msg);
    },
    wait(pkt){
        // do nothing
    },
    exit_code(pkt){
        exit_code = exit_codes[pkt.code];
        console.log("set exit code: ",exit_code);
        lua.allow_writes = false;
    }
    //interrupt(pkt){
        //TODO
    //}
}

lua.on('line',(da)=>{
    process.stdout.write("\r");
    if (typeof da != "object"){
        lua.send({c:"malformed_command",msg:da});
        console.error("malformed command",da)
        return;
    }
    if (commands[da.c]) {
        commands[da.c](da,lua);
    } else {
        lua.send({c:"unknown_command",msg:da});
        console.error("unknown command",da)
    }
    rl.prompt("> ")
})


lua.on('close',(da)=>{
    console.log("bye")
    process.exit(exit_code);
})

const rl = readline.createInterface({
    input: process.stdin,
    output: process.stdout,
    //terminal: false,
});

rl.on('line', (line) => {
    lua.send({c:"terminal",msg:line});
    rl.prompt("> ")
});

rl.on('close', () => {
    process.stdout.write("\r");
    console.log("Stdin is gone, shutting down");
    lua.send({c:"shutdown"});

    //lua.stop();
});

rl.prompt("> ")