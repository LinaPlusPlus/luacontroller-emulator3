--> LuaProcess = 1; section:writeln()
class LuaProcess extends EventEmitter {
    constructor(luaScriptPath, args = []) {
        super();
        this.luaScriptPath = luaScriptPath;
        this.args = args;
        this.process = null;
        this.allow_writes = true;
    }

    start() {
        console.log("spawning lua process",this.luaScriptPath, ...this.args)
        this.process = spawn('lua', [this.luaScriptPath, ...this.args], {
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