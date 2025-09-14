# luacontroller-emulator3
A lua-controller emulatior focused on safety and multitasking. 

## the project is structured into 5 layers
- Unblessed luacontrollers
  -  unaware of the sandbox
  -  enviornment is indistinguishable from an [Mesecons luacontroller](https://mesecons.net/luacontroller/)
  -  has security features on the level of a Mesecons luacontroller (Work in progress)
- Blessed luacontrollers
  - understands the sandbox and is built to manage it's domain
  - has aditional builtins, existing builtins have aditional features, can get additional info in the event object.
  - there is a global `_G.is_le3_blessed = true` flag (Work in progress)
  - likely is wired to the "godluac" to control it's domain and all child domains
  - send 'reprogram' and other special signals to controllers (TODO)
  - can set the source ('src') string of luacontrollers and other management actions via the "godluac"
- Root Domain (root0) luacontrollers
  - designed to manage and distribute low level resources including `/dev/` and `/unassigned/`
  - communicates with the wrapper layer directly, can change the settngs of the emulator
  - can enable/disable the `load` function of a luacontroller via the "godluac"
- Luacontroller Kernal
  - responsable for executing and sandboxing luacontrollers
  - it handles the wire based communication
  - it handles the "godluac" API and the object hierarchy
  - it handles the Kernal to Wrapper connuincation protocol, divided into context channels, each context channel corrisponds to a "hardware luacontroller"
  - expects context channel 1 to be the command context with the "hardware luacontroller" placed at `/dev/host0`. the initlizer luac is ment to spawn `/dev/tty0` and `/dev/timer0`
  - (name of the "context channel" is up for debate as just "channel" conflicts with the term "digilines channel" which are also sent as part of the duplex communications to the wrapper)
  - The Kernal is expected to work without command execution on the host OS nor have direct access it's files (TODO)
     and these capabilities should be expected to be disabled by the kernal or the wrapper
  - luacs have flag to get access to the `_HOST_G` object, despite this, there is no way to obtain the privlage.
- Wrapper
  - manages the connection between the kernal and the host OS
  - it hosts the kernal (process) and communicates with it via a duplex (Either via an IPC like STDIO or hooking lua's builtins)
  - responsable for setting timers
  - responsable for getting project files from require style 'src' format (TODO)
  - has enough power to in theory run ACE on the kernal
