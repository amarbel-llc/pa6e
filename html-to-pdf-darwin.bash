#!/usr/bin/env bash
set -euo pipefail

CMD_CHROME="/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

if [[ ! -x $CMD_CHROME ]]; then
  echo "error: Google Chrome not found at $CMD_CHROME" >&2
  exit 1
fi

target="$1"
options="$2"
buffer_size="${3:-9999999}"
port="9222"

echo "Running Chrome ($CMD_CHROME)" >&2
coproc chrome (
  "$CMD_CHROME" \
    --no-sandbox \
    --headless \
    --remote-debugging-port=$port \
    --remote-allow-origins=http://127.0.0.1:$port \
    --remote-allow-origins=http://localhost:$port \
    "$(realpath "$target")" 2>&1
)

trap 'kill -9 $chrome_PID 2>/dev/null' EXIT
read -r output <&"${chrome[0]}"
echo "$output" >&2

get_websocket_debugger_url() {
  http GET localhost:$port/json/list |
    jq -r '.[] | select(.type == "page") | .webSocketDebuggerUrl'
}

echo "Getting chrome websocket debugger url" >&2
url="$(get_websocket_debugger_url)"

request_print_page() {
  echo "Page.printToPDF { $options }" |
    websocat --buffer-size "$buffer_size" -n1 --jsonrpc --jsonrpc-omit-jsonrpc "$url"
}

outfile="$target.pdf"

echo "Requesting chrome print page from debugger url ($url)" >&2
request_print_page |
  jq -r '.result.data' |
  base64 -d -i - >"$outfile"

echo "Wrote PDF to '$outfile'" >&2
