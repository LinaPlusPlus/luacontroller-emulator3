# Emulator Internals

## Types of Units
- Lua Controller (luac)
  - a single unit of agency,
  - can broadcast and receve "digiline" events
  - runs code apon receving an event
  - non special luacontrollers run and properly sandbox the code located at the path on disk set by their "src" property
  - there are special luacontrollers that rather than run your code, instead run code within the kernal, there are 2 main types:
    - a "godluac" is a special controller that can manage the domain it's paired to via it's API, making changes to the tree structure.
    - (TODO the name may change, also not implemented yet) a "host bridge" is a luacontroller that transparently bridges
      events it sends to and receves from the Wrapper via it's paired "context channel".
- Wires
  - uses an internal scheduling system to wake controllers for their events
  - wires are connected 0 or more luacontrollers
  - luacontrollers are connected 0 or more wires
  - when a luacontroller broadcasts, it enqueues a message into all connected wires
  - when a wire is ran, it runs it's connected luacontrollers with the context of the next event in it's queue.
  - (TODO) luacs can have firewalls for diffrent wires based on digilines channel
  - events while in transit include a "source" and "seenby" property so each event is only receved once per controller and the broadcaster does not receve it's own message.
- Domains
  - can contain child units, each addressable by their name
  - domains cannot have multiple children of the same name
  - there is a function to rename children to become unique by appending a number
  - refrencing children of a domain uses UNIX-style "path" syntax. Example: `./myChild/myGrandChild` (the './' is optional)

## the project is structured into 5 layers
- Unblessed luacontrollers
  -  unaware of the sandbox
  -  enviornment is indistinguishable from an [Mesecons luacontroller](https://mesecons.net/luacontroller/)
  -  has security features on the level of a Mesecons luacontroller (Work in progress)
- Blessed luacontrollers
  - understands the sandbox and is built to manage it's domain or any above it
  - has aditional builtins, existing builtins have aditional features, can get additional info in the event object.
  - there is a global `_G.is_le3_blessed = true` flag (Work in progress)
  - likely is wired to the "godluac" to control it's domain and it's children
  - send 'reprogram' and other special signals to controllers (TODO)
  - can set the source ('src') property of luacontrollers and other management actions via the "godluac"
- Root Domain (root0) luacontrollers
  - designed to manage and distribute low level resources including managing the `/dev/` and `/unassigned/` domains
  - communicates with the wrapper layer and can spawn new , can change the settngs of the emulator
  - can enable/disable the `load` function of a luacontroller via the "godluac"
- Luacontroller Kernal
  - responsable for executing and sandboxing luacontrollers
  - it handles the wire based communication
  - it handles the "godluac" API and the object hierarchy
  - it handles the Kernal to Wrapper connuincation protocol, divided into context channels, each context channel corrisponds to a "host bridge"
  - expects context channel 1 to be the command context with the "host bridge" placed at `/dev/host0`. the first luacontroller `/sysinit` is ment to setup and spawn `/dev/tty0` and `/dev/timer0`
  - (name of the "context channel" is up for debate as just "channel" conflicts with the term "digilines channel" which are also sent as part of the duplex communications to the wrapper)
  - The Kernal is expected to work without command execution on the host OS nor have direct access it's files (TODO)
     and these capabilities should be expected to be disabled by the kernal or the wrapper
  - luaconctrollers have property that when true gives it access to the kernal's global table (called `_HOST_G`), despite this, there is no way to obtain the privlage.
- Wrapper
  - manages the connection between the kernal and the host OS
  - it hosts the kernal (process) and communicates with it via a duplex (Either via an IPC like STDIO or hooking lua's builtins)
  - responsable for setting timers
  - responsable for getting project files from require style 'src' format (TODO)
  - has enough power to in theory run ACE on the kernal
