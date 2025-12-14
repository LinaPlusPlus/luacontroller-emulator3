const fs = require('fs');
const { spawn } = require('child_process');
const readline = require('readline');
const EventEmitter = require('events');

class LuaProcess extends EventEmitter {
    constructor(args = []) {
        super();
        this.args = args;
        this.process = null;
        this.allow_writes = true;
    }

    start() {
        let lua_name = this.args.shift();
        console.log("spawning lua process",lua_name,this.args);
        this.process = spawn(lua_name, this.args, {
             stdio: ['pipe', 'pipe', 'pipe']
        });

        this.process.stderr.on('data', (data) => {
            console.error(`Lua stderr: ${data.toString()}`);
        });

        this.process.on('exit', (code) => {
            log("info","system",`child exited with code ${code}`);
            this.allow_writes = false
            this.emit('close')
        });


        // Read from Lua stdout
        const rlLua = readline.createInterface({ input: this.process.stdout });

        rlLua.on('line', (line) => {
            let jsonOutput
            try {
                jsonOutput = JSON.parse(line);
            } catch (e) {
                console.error("JSON parse error: " + e.tostring())
                jsonOutput = line;
            }
            this.emit('line',jsonOutput)
        });
    }

    send(line) {
        if (this.process.stdin.writable && this.allow_writes) {
            this.process.stdin.write(JSON.stringify(line) + '\n');
        }
    }

    stop() {
        this.process.stdin.end();
    }
}

const colors = {
    reset: "\x1b[0m",
    bold: "\x1b[1m",

    TRACE: "\x1b[90m",
    ETRACE: "\x1b[35m",
    WTRACE: "\x1b[33m",
    WARN: "\x1b[1;33m",
    ERROR: "\x1b[1;31m",
    INFO: "\x1b[1;34m",
    FAIL: "\x1b[1;97;41m",
    PRINT: "\x1b[1;36m",
};

function pad(str, len) {
    return str + " ".repeat(Math.max(0, len - str.length));
}

function log(mode, src, message) {
    process.stdout.write("\r");
    const lvl = mode.toUpperCase();
    const color = colors[lvl] || "";
    const reset = colors.reset;
    const bold = colors.bold;

    const levelStr = pad(lvl, 6);        // e.g., "INFO  "
    const sourceStr = pad(src, 15);      // e.g., "system        "

    console.log(`${color}[${levelStr}]${reset} ${bold}${sourceStr}${reset}`,message);
}

const exit_codes = {
    root_panic: 5,
    shutdown: 0,
}
let exit_code = null


console.log(process.argv.slice(2));
const lua = new LuaProcess(process.argv.slice(2));
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
    },
    interrupt(pkt){
       setTimeout(()=>{
        lua.send({
            c: "interrupt",
            echo: pkt.echo,
        })
       },pkt.time || 0)
    }
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

    setTimeout(()=>{
        lua.stop()
        console.log("Terminating stalled lua...")
    },1000)

    //lua.stop();
});

rl.prompt("> ")