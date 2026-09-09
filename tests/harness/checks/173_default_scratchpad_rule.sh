#!/usr/bin/env bash
# A default_scratchpad window rule stores a matching window without showing or
# focusing it, and the ordinary scratchpad action can summon it afterwards.
set -euo pipefail

readonly CLIENT="${UMBRIEL_UNMAP_CLIENT:-./build-debug/tests/unmap-client}"
readonly CLIENT_APP_ID=scratchpad-terminal
readonly TITLE=default-scratchpad-rule

windows() { "$UMBRIEL" windows --json; }

wait_for_state() {
  local active=$1 state=
  for _ in $(seq 80); do
    state=$(windows)
    if jq -e --arg app_id "$CLIENT_APP_ID" --argjson active "$active" '
      any(.[];
        .app_id == $app_id
        and .scratchpad == "term"
        and .workspace == ""
        and .floating == true
        and .active == $active
        and .focused == false)
    ' <<< "$state" > /dev/null; then
      return 0
    fi
    sleep 0.1
  done
  echo "expected '$CLIENT_APP_ID' in the term scratchpad with active=$active: $state"
  return 1
}

cat >> "$UMBRIEL_CONFIG" <<'EOF'

[animation]
enabled = false

[[scratchpad]]
name = "term"

[[window_rule]]
match.app_id = "^scratchpad-terminal$"
default_scratchpad = "term"
EOF
"$UMBRIEL" msg config-reload > /dev/null

APP_ID="$CLIENT_APP_ID" "$CLIENT" "$TITLE" 480 300 > "$UMBRIEL_RUNTIME_DIR/$TITLE.log" 2>&1 &
wait_for_state false

"$UMBRIEL" msg scratchpad-toggle:term > /dev/null
wait_for_state true

echo "default scratchpad rule stored a matching window quietly and summoned it on demand"
