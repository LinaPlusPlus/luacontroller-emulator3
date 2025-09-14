# luacontroller-emulator3
A lua-controller emulatior focused on safety and multitasking. 

the project is structured into 5 layers, 
- Unblessed luacontrollers
  -  unaware of the sandbox
- Blessed luacontrollers
  - understands the sandbox and is built to manage it's domain
  - likely is wired to the "godluac" to control it's domain and all it's child domains
  - can reprogram controllers
- Root Domain (root0) luacontrollers
  - designed to manage and distribute low level resources including `/dev/` and `/unassigned/`
  - communicates with the wrapper layer directly, can change the settngs of the emulator
  - can set the source of the 
- Luacontroller Kernal; responsable for executing and sandboxing luacontrollers, it also handles the wire based communication,
  the Kernal to Wrapper connuincations, the "godluac" API and the object hierarchy.
  The Kernal is expected to work without command execution on the host OS nor have direct access it's files and these capabilities should be expected to be disabled by the kernal or the wrapper.
- the wrapper manages the connection between the kernal and the host OS, it hosts the kernal and communicates with it on a channel (Either via an IPC like STDIO or running lua inside itself)
  the wrapper is responsable for setting timers, getting project files from require style 'src' format (TODO), keeping the kernal (process) alive and killing it when needed. the wrapper can communicate with the controllers at 
