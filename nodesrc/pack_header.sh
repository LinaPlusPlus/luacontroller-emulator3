#!/bin/bash
SCRIPT_PATH="$0"
MARKER="===PAYLOAD_START""==="

PAYLOAD_START_LINE=$(grep -n "^$MARKER$" "$SCRIPT_PATH" | cut -d: -f1)
if [ -z "$PAYLOAD_START_LINE" ]; then
  echo "Payload marker not found!"
  exit 1
fi
PAYLOAD_START_LINE=$((PAYLOAD_START_LINE + 1))

# Create a unique temporary FIFO
FIFO=$(mktemp -u)
mkfifo "$FIFO"

cleanup() {
  rm -f "$FIFO"
}
trap cleanup EXIT

nodecore=$(cat <<'EOF'