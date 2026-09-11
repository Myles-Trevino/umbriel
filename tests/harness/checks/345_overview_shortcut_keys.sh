#!/usr/bin/env bash
# Overview shortcut keys focus the labeled card, close the overview, and never leak to clients. Multi-key labels use
# sequential plain key presses, while disabling shortcuts leaves the overview open and continues swallowing input.
set -euo pipefail

readonly BTN_LEFT=272
readonly OUTPUT_W=1280
readonly OUTPUT_H=720
readonly POINTER="${UMBRIEL_POINTER_CLIENT:-./build-debug/tests/pointer-client}"
readonly CLIENT="${UMBRIEL_UNMAP_CLIENT:-./build-debug/tests/unmap-client}"
readonly FIRST_LOG="$UMBRIEL_RUNTIME_DIR/shortcut-first.log"
readonly SECOND_LOG="$UMBRIEL_RUNTIME_DIR/shortcut-second.log"
readonly THIRD_LOG="$UMBRIEL_RUNTIME_DIR/shortcut-third.log"
readonly FOURTH_LOG="$UMBRIEL_RUNTIME_DIR/shortcut-fourth.log"
BASELINE=$(< "$UMBRIEL_CONFIG")

pointer() {
  "$POINTER" "$OUTPUT_W" "$OUTPUT_H" "$@"
}

wait_for_count() {
  local want=$1
  for _ in $(seq 60); do
    [[ $("$UMBRIEL" windows --json | jq 'length') -eq $want ]] && return 0
    sleep 0.1
  done
  echo "expected $want windows, got: $("$UMBRIEL" windows --json)"
  return 1
}

focused_title() {
  "$UMBRIEL" windows --json | jq -r '[.[] | select(.focused) | .title] | if length == 1 then .[0] else "none" end'
}

active_title() {
  "$UMBRIEL" windows --json | jq -r '[.[] | select(.active) | .title] | if length == 1 then .[0] else "none" end'
}

focus_title() {
  local title=$1 id
  id=$("$UMBRIEL" windows --json | jq -r --arg title "$title" '.[] | select(.title == $title) | .id')
  if [[ -z $id ]]; then
    echo "could not resolve window '$title': $("$UMBRIEL" windows --json)"
    return 1
  fi
  "$UMBRIEL" msg "window-focus:$id" > /dev/null
}

write_config() {
  {
    printf '%s\n' "$BASELINE"
    printf '\n[animation.overview]\nduration_ms = 100\n'
    if [[ $# -gt 0 ]]; then
      printf '\n[overview]\n%s\n' "$1"
    fi
  } > "$UMBRIEL_CONFIG"
  "$UMBRIEL" msg config-reload > /dev/null
  sleep 0.3
}

"$CLIENT" shortcut-first 1200 700 > "$FIRST_LOG" 2>&1 &
wait_for_count 1
"$CLIENT" shortcut-second 1200 700 > "$SECOND_LOG" 2>&1 &
wait_for_count 2
"$CLIENT" shortcut-third 1200 700 > "$THIRD_LOG" 2>&1 &
wait_for_count 3
focus_title shortcut-first
sleep 0.2

write_config
pointer pause 500 tap 4 pause 500 tap 30 &
pointer_pid=$!
sleep 0.1
"$UMBRIEL" msg overview-open > /dev/null
wait "$pointer_pid"
if [[ $(focused_title) != shortcut-third ]]; then
  echo "single-key shortcut did not focus the third card: $("$UMBRIEL" windows --json)"
  exit 1
fi
for _ in $(seq 40); do
  grep -q '^key 30 1$' "$THIRD_LOG" 2>/dev/null && break
  sleep 0.05
done
if ! grep -q '^key 30 1$' "$THIRD_LOG" 2>/dev/null; then
  echo "keyboard focus was not restored after shortcut selection: $(< "$THIRD_LOG")"
  exit 1
fi
if grep -q '^key 4 1$' "$FIRST_LOG" "$SECOND_LOG" "$THIRD_LOG" 2>/dev/null; then
  echo "overview shortcut key leaked to a client"
  exit 1
fi
if grep -q '^key 30 1$' "$FIRST_LOG" "$SECOND_LOG" 2>/dev/null; then
  echo "post-overview input reached a client other than the focused third card"
  exit 1
fi

write_config 'shortcut_keys = "12"'
"$UMBRIEL" msg overview-open > /dev/null
sleep 0.5
pointer tap 3 tap 2
sleep 0.5
if [[ $(focused_title) != shortcut-second ]]; then
  echo "multi-key shortcut 21 did not focus the second card: $("$UMBRIEL" windows --json)"
  exit 1
fi

write_config 'shortcuts = false'
"$UMBRIEL" msg overview-open > /dev/null
sleep 0.5
pointer tap 2
sleep 0.5
if [[ $(focused_title) != shortcut-second ]]; then
  echo "disabled overview shortcuts changed focus: $("$UMBRIEL" windows --json)"
  exit 1
fi
if grep -q '^key 2 1$' "$FIRST_LOG" "$SECOND_LOG" "$THIRD_LOG" 2>/dev/null; then
  echo "disabled overview shortcut input leaked to a client"
  exit 1
fi
"$UMBRIEL" msg overview-close > /dev/null

write_config
"$UMBRIEL" msg workspace-switch:2 > /dev/null
sleep 0.2
"$UMBRIEL" msg overview-open > /dev/null
sleep 0.5
"$CLIENT" shortcut-fourth 1200 700 > "$FOURTH_LOG" 2>&1 &
wait_for_count 4
sleep 0.5
pointer tap 5
sleep 0.5
if [[ $(active_title) != shortcut-fourth ]]; then
  echo "a new window stole an existing badge instead of receiving shortcut 4: $("$UMBRIEL" windows --json)"
  exit 1
fi

write_config
focus_title shortcut-first
sleep 0.2
"$UMBRIEL" msg overview-open > /dev/null
sleep 0.5
pointer move 620 360 press "$BTN_LEFT" move 760 360 release "$BTN_LEFT"
focus_title shortcut-second
sleep 0.2
sleep 0.5
pointer tap 2
sleep 0.5
if [[ $(active_title) != shortcut-first ]]; then
  echo "the dragged card lost its shortcut badge after drop: $("$UMBRIEL" windows --json)"
  exit 1
fi

echo "overview shortcuts keep stable IDs through mapping, scrolling, and drag-drop while honoring opt-out"
