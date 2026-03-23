#!/usr/bin/env bash
set -euo pipefail

# Find Chrome/Chromium binary
if [[ "$(uname)" == "Darwin" ]]; then
  CMD_CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
else
  CMD_CHROME="$(which chromium)"
fi

if [[ ! -x $CMD_CHROME ]]; then
  echo "error: Chrome/Chromium not found at $CMD_CHROME" >&2
  exit 1
fi

target="$1"
options="$2"
buffer_size="${3:-9999999}"

cleanup() {
  if [[ -n ${chrome_PID:-} ]]; then
    kill -9 "$chrome_PID" 2>/dev/null || true
    wait "$chrome_PID" 2>/dev/null || true
  fi
}
trap cleanup EXIT

echo "Running Chrome ($CMD_CHROME)" >&2
coproc chrome (
  "$CMD_CHROME" \
    --no-sandbox \
    --headless \
    --remote-debugging-port=0 \
    --remote-allow-origins='*' \
    "$(realpath "$target")" 2>&1
)

# Read lines until we find the DevTools URL with the allocated port
while IFS= read -r line <&"${chrome[0]}"; do
  echo "$line" >&2
  if [[ $line =~ DevTools\ listening\ on\ ws://([^/]+) ]]; then
    host="${BASH_REMATCH[1]}"
    break
  fi
done

if [[ -z ${host:-} ]]; then
  echo "error: failed to get DevTools listening address from Chrome" >&2
  exit 1
fi

echo "Getting page websocket url from $host" >&2
url="$(http --ignore-stdin GET "$host/json/list" | jq -r '.[] | select(.type == "page") | .webSocketDebuggerUrl')"

echo "Requesting print from $url" >&2
outfile="$target.pdf"

echo "Page.printToPDF { $options }" |
  websocat --buffer-size "$buffer_size" -n1 --jsonrpc --jsonrpc-omit-jsonrpc "$url" |
  jq -r '.result.data' |
  base64 -d -i - >"$outfile"

echo "Wrote PDF to '$outfile'" >&2
