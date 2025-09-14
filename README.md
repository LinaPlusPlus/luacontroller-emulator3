# luacontroller-emulator3
A lua-controller emulatior focused on safety and multitasking. 

the project is structured into 5 layers, 
- Unblessed luacontrollers
  -  unaware of the sandbox
  -  enviornment is indistinguishable from an Luanti luacontroller
- Blessed luacontrollers
  - understands the sandbox and is built to manage it's domain
  - has aditional builtins, existing builtins are more trusting, can get additional info in the event object.
  - likely is wired to the "godluac" to control it's domain and all it's child domains
  - can reprogram controllers
  - can set the source ('src') string of luacontrollers
- Root Domain (root0) luacontrollers
  - designed to manage and distribute low level resources including `/dev/` and `/unassigned/`
  - communicates with the wrapper layer directly, can change the settngs of the emulator
  - can enable/disable the `load` function of a luacontroller
- Luacontroller Kernal
  - responsable for executing and sandboxing luacontrollers
  - it handles the wire based communication
  - it handles the "godluac" API and the object hierarchy
  - it handles the Kernal to Wrapper connuincation protocol, divided into channels
  - The Kernal is expected to work without command execution on the host OS nor have direct access it's files
     and these capabilities should be expected to be disabled by the kernal or the wrapper
- Wrapper
  - manages the connection between the kernal and the host OS
  - it hosts the kernal (process) and communicates with it via a duplex (Either via an IPC like STDIO or hooking lua's builtins)
  - responsable for setting timers
  - responsable for getting project files from require style 'src' format (TODO)
  - has enough power to in theory run ACE on the kernal
