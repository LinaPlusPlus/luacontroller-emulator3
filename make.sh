mkdir -p target scratchpad 2>/dev/null;

lua ./fileglue2.lua "$@" src/* >target/out.lua
lua ./fileglue2.lua "$@" nodesrc/*.js >target/out.js

cat nodesrc/pack_header.sh target/out.js nodesrc/pack_footer.sh target/out.lua > target/out.sh
chmod u+x target/out.sh