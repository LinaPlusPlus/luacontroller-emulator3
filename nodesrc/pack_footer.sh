
EOF
)



tail -n +$PAYLOAD_START_LINE "$SCRIPT_PATH" > "$FIFO"&
tailpid=$!;

node -e "$nodecore" "$FIFO" "$@"
pid=$!

wait $pid;
#kill -SIGQUIT $tailpid;
exit 0

===PAYLOAD_START===
