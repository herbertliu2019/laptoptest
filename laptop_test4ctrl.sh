#!/bin/bash
# ============================================================
# laptop_test.sh — Laptop Hardware Test & Report Generator
# All sub-tests (screen, keyboard, audio) are embedded inline.
# Usage: sudo bash laptop_test.sh
# ============================================================

UPLOAD_URL="http://192.168.30.18:8080/laptop/api/upload"
REPORT_FILE="/tmp/laptop_report_$(date +%Y%m%d_%H%M%S).json"
PASS="PASS"
FAIL="FAIL"

# ── Colors ───────────────────────────────────────────────────
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
CYAN='\033[0;36m'; BOLD='\033[1m'; NC='\033[0m'

banner() { echo -e "\n${CYAN}${BOLD}=== $1 ===${NC}"; }
ok()     { echo -e "  ${GREEN}✓ $1${NC}"; }
warn()   { echo -e "  ${YELLOW}⚠ $1${NC}"; }
err()    { echo -e "  ${RED}✗ $1${NC}"; }

# ── Require root ─────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
  echo -e "${RED}Please run with sudo: sudo bash laptop_test.sh${NC}"; exit 1
fi

# ============================================================
# EMBEDDED: screen_test
# ============================================================
run_screen_test() {
  banner "SCREEN — Dead Pixel / Backlight Test"
  echo -e "  ${YELLOW}Displaying full-screen color patterns. Look carefully for dead/bright pixels.${NC}"
  echo -e "  ${YELLOW}Press Ctrl+C to skip to next color.${NC}"
  echo ""

  if [[ -n "$DISPLAY" ]] && command -v xterm &>/dev/null; then
    local colors=("red" "green" "blue" "white" "black")
    for color in "${colors[@]}"; do
      echo -e "  Showing: ${BOLD}$color${NC} (5 seconds)..."
      xterm -fullscreen -bg "$color" -fg "$color" -e "sleep 5" 2>/dev/null &
      local xpid=$!
      sleep 5
      kill "$xpid" 2>/dev/null
      wait "$xpid" 2>/dev/null
    done
  else
    python3 - <<'PYEOF'
import os, sys, time, signal

COLORS = [
    ("\033[41m\033[30m", "RED"),
    ("\033[42m\033[30m", "GREEN"),
    ("\033[44m\033[37m", "BLUE"),
    ("\033[47m\033[30m", "WHITE"),
    ("\033[40m\033[37m", "BLACK"),
]

interrupted = False

def handle_int(sig, frame):
    global interrupted
    interrupted = True

signal.signal(signal.SIGINT, handle_int)

try:
    rows, cols = os.get_terminal_size()
except Exception:
    rows, cols = 24, 80

for ansi, name in COLORS:
    interrupted = False
    sys.stdout.write("\033[2J\033[H")
    sys.stdout.write(ansi)
    line = " " * cols
    for _ in range(rows):
        sys.stdout.write(line)
    mid_row = rows // 2
    label = f" [ {name} - checking for dead pixels ] "
    col_pos = max(0, (cols - len(label)) // 2)
    sys.stdout.write(f"\033[{mid_row};{col_pos}H{label}")
    sys.stdout.flush()
    for _ in range(50):
        if interrupted:
            break
        time.sleep(0.1)
    sys.stdout.write("\033[0m\033[2J\033[H")
    sys.stdout.flush()

sys.stdout.write("\033[0m")
sys.stdout.flush()
PYEOF
  fi
  echo ""
  ok "Screen color test complete."
}

# ============================================================
# EMBEDDED: keyboard_test
# ============================================================
run_keyboard_test() {
  banner "KEYBOARD — Key Press Test"

  echo -e "  ${YELLOW}Press EVERY key. For Ctrl/Shift/Alt: press them as combos (e.g. Ctrl+A, Shift+A).${NC}"
  echo -e "  ${YELLOW}Note: Ctrl/Shift/Alt alone cannot be detected at TTY level — test as combos.${NC}"
  echo -e "  ${YELLOW}Keys appear on one line. Press Ctrl+C when done.${NC}"
  echo ""

  KB_TEST_RESULT="SKIPPED"

  python3 /dev/stdin </dev/tty <<'PYEOF'
import sys, tty, termios, select

try:
    tty_fd = open('/dev/tty', 'rb', buffering=0)
    out    = open('/dev/tty', 'w')
except OSError as e:
    print(f"  ERROR: Cannot open /dev/tty: {e}")
    sys.exit(1)

pressed = set()
old_settings = termios.tcgetattr(tty_fd.fileno())

def restore():
    try:
        termios.tcsetattr(tty_fd.fileno(), termios.TCSADRAIN, old_settings)
    except Exception:
        pass

# ── Single-byte control keys ────────────────────────────────
# Ctrl+Letter sends \x01-\x1a (A=1 ... Z=26)
CTRL_KEYS = {bytes([i]): f"Ctrl+{chr(i+64)}" for i in range(1, 27)}
CTRL_KEYS[b'\x1b'] = None          # ESC — handle via escape sequence path
CTRL_KEYS[b'\x03'] = 'Ctrl+C'      # exit sentinel (overrides Ctrl+C name below)

SINGLE = {
    b'\x08': 'Backspace',
    b'\x09': 'Tab',
    b'\x0a': 'Enter',
    b'\x0d': 'Enter',
    b'\x1b': 'Esc',
    b'\x7f': 'Backspace',
    b'\x00': 'Ctrl+Space',
}
# Merge ctrl keys (don't override dedicated names)
for k, v in CTRL_KEYS.items():
    if k not in SINGLE and v is not None:
        SINGLE[k] = v

# ── Escape sequences ────────────────────────────────────────
ESCAPE_SEQS = {
    # Arrows
    b'\x1b[A': 'Up',       b'\x1b[B': 'Down',
    b'\x1b[C': 'Right',    b'\x1b[D': 'Left',
    # Home/End/Ins/Del/PgUp/PgDn
    b'\x1b[H': 'Home',     b'\x1b[F': 'End',
    b'\x1bOH': 'Home',     b'\x1bOF': 'End',
    b'\x1b[1~': 'Home',    b'\x1b[4~': 'End',
    b'\x1b[2~': 'Insert',  b'\x1b[3~': 'Delete',
    b'\x1b[5~': 'PgUp',    b'\x1b[6~': 'PgDn',
    # F1-F12 (xterm style)
    b'\x1bOP':   'F1',     b'\x1bOQ':   'F2',
    b'\x1bOR':   'F3',     b'\x1bOS':   'F4',
    b'\x1b[15~': 'F5',     b'\x1b[17~': 'F6',
    b'\x1b[18~': 'F7',     b'\x1b[19~': 'F8',
    b'\x1b[20~': 'F9',     b'\x1b[21~': 'F10',
    b'\x1b[23~': 'F11',    b'\x1b[24~': 'F12',
    # F1-F4 alternate (vt100)
    b'\x1b[11~': 'F1',     b'\x1b[12~': 'F2',
    b'\x1b[13~': 'F3',     b'\x1b[14~': 'F4',
    # Win/Super key (common sequences)
    b'\x1b[1;2P': 'Win',   b'\x1b[1;6A': 'Ctrl+Up',
    b'\x1b[1;6B': 'Ctrl+Down', b'\x1b[1;6C': 'Ctrl+Right',
    b'\x1b[1;6D': 'Ctrl+Left',
    b'\x1b[1;2A': 'Shift+Up',  b'\x1b[1;2B': 'Shift+Down',
    b'\x1b[1;2C': 'Shift+Right', b'\x1b[1;2D': 'Shift+Left',
    b'\x1b[1;3A': 'Alt+Up',    b'\x1b[1;3B': 'Alt+Down',
    b'\x1b[1;3C': 'Alt+Right', b'\x1b[1;3D': 'Alt+Left',
    b'\x1b[1;3H': 'Alt+Home',  b'\x1b[1;3F': 'Alt+End',
    b'\x1b[1;5H': 'Ctrl+Home', b'\x1b[1;5F': 'Ctrl+End',
    # Alt+Letter sends ESC + letter
    **{bytes([0x1b, i]): f"Alt+{chr(i)}" for i in range(ord('a'), ord('z')+1)},
    **{bytes([0x1b, i]): f"Alt+{chr(i)}" for i in range(ord('A'), ord('Z')+1)},
    **{bytes([0x1b, i]): f"Alt+{chr(i)}" for i in range(ord('0'), ord('9')+1)},
    # PrintScreen / Pause / ScrollLock (when they send sequences)
    b'\x1b[P':    'PrintScr',
    b'\x1b[200~': 'BracketedPaste-Start',
}

def read_key():
    tty.setraw(tty_fd.fileno())
    ch = tty_fd.read(1)
    if ch == b'\x1b':
        seq = ch
        while True:
            r, _, _ = select.select([tty_fd], [], [], 0.08)
            if not r:
                break
            seq += tty_fd.read(1)
        return seq
    return ch

out.write("  Keys: ")
out.flush()

try:
    while True:
        key = read_key()

        # Exit on Ctrl+C
        if key == b'\x03':
            out.write("\n\n  Ctrl+C — keyboard test done.\n")
            out.flush()
            break

        # Look up name
        name = ESCAPE_SEQS.get(key) or SINGLE.get(key)
        if name is None:
            try:
                decoded = key.decode('utf-8')
                if len(decoded) == 1 and decoded.isprintable():
                    name = decoded
                else:
                    name = f"<{key.hex()}>"
            except Exception:
                name = f"<{key.hex()}>"

        # Only show each unique key once
        if key not in pressed:
            pressed.add(key)
            out.write(f"\033[32m{name}\033[0m ")
            out.flush()

except Exception as e:
    out.write(f"\n  Error: {e}\n")
    out.flush()
finally:
    restore()
    tty_fd.close()

out.write(f"\n  Total unique keys detected: {len(pressed)}\n")
out.flush()
out.close()
PYEOF

  echo ""
  read -rp "  Did all keys register correctly? [p=pass / f=fail / s=skip]: " ans </dev/tty
  case "$ans" in
    p|P) KB_TEST_RESULT="PASS" ;;
    f|F) KB_TEST_RESULT="FAIL" ;;
    *)   KB_TEST_RESULT="SKIPPED" ;;
  esac
}

# ============================================================
# EMBEDDED: audio_test
# ============================================================
run_audio_test() {
  banner "AUDIO — Speaker & Microphone Test"

  SPEAKER_QUALITY_RESULT="SKIPPED"
  MIC_RECORD_RESULT="SKIPPED"

  # Speaker Test
  echo -e "\n  ${BOLD}[1/2] Speaker Test${NC}"
  if command -v speaker-test &>/dev/null; then
    echo "  Playing test tone for 3 seconds..."
    speaker-test -t sine -f 1000 -c 2 -l 1 &>/dev/null &
    SPKR_PID=$!
    sleep 3
    kill "$SPKR_PID" 2>/dev/null
    wait "$SPKR_PID" 2>/dev/null
  else
    echo "  Generating tone via Python + aplay..."
    python3 -c "
import struct, math, wave, io, sys
rate=44100; dur=2; freq=440
samples=[int(32767*math.sin(2*math.pi*freq*i/rate)) for i in range(rate*dur)]
buf=io.BytesIO()
w=wave.open(buf,'wb'); w.setnchannels(1); w.setsampwidth(2); w.setframerate(rate)
w.writeframes(struct.pack('<'+'h'*len(samples),*samples)); w.close()
sys.stdout.buffer.write(buf.getvalue())
" 2>/dev/null | aplay -q 2>/dev/null
  fi

  read -rp "  Did you hear the speaker clearly? [p=pass / f=fail / s=skip]: " ans
  case "$ans" in
    p|P) SPEAKER_QUALITY_RESULT="PASS" ;;
    f|F) SPEAKER_QUALITY_RESULT="FAIL" ;;
    *)   SPEAKER_QUALITY_RESULT="SKIPPED" ;;
  esac

  # Microphone Test
  echo -e "\n  ${BOLD}[2/2] Microphone Test${NC}"
  REC_FILE="/tmp/mic_test_$$.wav"
  echo "  Recording 3 seconds... Please speak now."
  if arecord -d 3 -f cd -q "$REC_FILE" 2>/dev/null; then
    if [[ -f "$REC_FILE" && -s "$REC_FILE" ]]; then
      echo "  Playing back the recording..."
      aplay -q "$REC_FILE" 2>/dev/null
      rm -f "$REC_FILE"
      read -rp "  Did you hear your voice clearly? [p=pass / f=fail / s=skip]: " ans
      case "$ans" in
        p|P) MIC_RECORD_RESULT="PASS" ;;
        f|F) MIC_RECORD_RESULT="FAIL" ;;
        *)   MIC_RECORD_RESULT="SKIPPED" ;;
      esac
    else
      err "Recording file empty — microphone may not be working."
      MIC_RECORD_RESULT="FAIL"
      rm -f "$REC_FILE"
    fi
  else
    err "arecord failed — no microphone device found."
    MIC_RECORD_RESULT="FAIL"
  fi
}

# ============================================================
# INSTALL DEPENDENCIES
# ============================================================
banner "Checking and Installing Dependencies"
PKGS=(dmidecode smartmontools util-linux pciutils usbutils curl jq alsa-utils v4l-utils iw ethtool bc fswebcam)
for pkg in "${PKGS[@]}"; do
  if ! dpkg -s "$pkg" &>/dev/null 2>&1; then
    warn "Installing $pkg ..."
    apt-get install -y -q "$pkg" 2>/dev/null
  fi
done
ok "All dependencies are ready."

# ============================================================
# 1. SYSTEM INFO
# ============================================================
banner "1. System Info"
SYS_VENDOR=$(dmidecode -s system-manufacturer 2>/dev/null | tr -d '\n')
SYS_MODEL=$(dmidecode -s system-product-name 2>/dev/null | tr -d '\n')
SYS_SERIAL=$(dmidecode -s system-serial-number 2>/dev/null | tr -d '\n')
BIOS_VER=$(dmidecode -s bios-version 2>/dev/null | tr -d '\n')
TEST_TIME=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
HOSTNAME=$(hostname)
ok "Vendor: $SYS_VENDOR | Model: $SYS_MODEL | Serial: $SYS_SERIAL"

# ============================================================
# 2. CPU
# ============================================================
banner "2. CPU"
CPU_MODEL=$(grep "model name" /proc/cpuinfo | head -1 | cut -d: -f2 | xargs)
CPU_CORES=$(nproc --all)
CPU_THREADS=$(grep -c "^processor" /proc/cpuinfo)
CPU_MAX_MHZ=$(lscpu | grep "CPU max MHz" | awk '{print $NF}' | cut -d. -f1)
CPU_ARCH=$(uname -m)
ok "$CPU_MODEL | ${CPU_CORES} cores / ${CPU_THREADS} threads | Max ${CPU_MAX_MHZ:-?} MHz"

# ============================================================
# 3. MEMORY
# ============================================================
banner "3. Memory"
MEM_TOTAL_KB=$(grep MemTotal /proc/meminfo | awk '{print $2}')
MEM_TOTAL_GB=$(echo "scale=1; $MEM_TOTAL_KB/1024/1024" | bc)
MEM_TYPE=$(dmidecode -t memory 2>/dev/null | grep -E "^\s+Type:" | grep -v "Unknown\|Error" | head -1 | awk '{print $2}')
MEM_SPEED=$(dmidecode -t memory 2>/dev/null | grep -E "^\s+Speed:" | grep -v "Unknown" | head -1 | awk '{print $2, $3}')
MEM_SLOTS=$(dmidecode -t memory 2>/dev/null | grep -c "Memory Device$")
MEM_USED_SLOTS=$(dmidecode -t memory 2>/dev/null | grep -A5 "Memory Device$" | grep -cE "Size:.*GB|Size:.*MB")
ok "${MEM_TOTAL_GB} GB | Type: ${MEM_TYPE:-unknown} | Speed: ${MEM_SPEED:-unknown} | Slots used: ${MEM_USED_SLOTS}/${MEM_SLOTS}"

# ============================================================
# 4. STORAGE (original logic kept)
# ============================================================
banner "4. Storage"
DISK_STATUS=$PASS
DISK_JSON="["
first=1
while IFS= read -r disk; do
  [[ -z "$disk" ]] && continue
  name=$(basename "$disk")
  size=$(lsblk -dn -o SIZE "$disk" 2>/dev/null | xargs)
  model=$(cat /sys/block/$name/device/model 2>/dev/null | xargs)
  rotational=$(cat /sys/block/$name/queue/rotational 2>/dev/null)
  disk_type="HDD"
  [[ "$rotational" == "0" ]] && disk_type="SSD"

  smart_out=$(smartctl -H "$disk" 2>/dev/null)
  if echo "$smart_out" | grep -qE "PASSED|OK"; then
    smart="PASSED"
  elif echo "$smart_out" | grep -q "FAILED"; then
    smart="FAILED"
    DISK_STATUS=$FAIL
  else
    smart="UNKNOWN"
  fi

  power_hours=$(smartctl -a "$disk" 2>/dev/null | grep -iE "power.on.hours|Power_On_Hours" | awk '{print $NF}' | head -1)

  ok "$name | ${model:-unknown} | $size | $disk_type | SMART: $smart | Power-on: ${power_hours:-?} hrs"

  [[ $first -eq 0 ]] && DISK_JSON+=","
  DISK_JSON+="{\"device\":\"$name\",\"model\":\"${model:-unknown}\",\"size\":\"${size:-unknown}\",\"type\":\"$disk_type\",\"smart\":\"$smart\",\"power_on_hours\":\"${power_hours:-unknown}\"}"
  first=0
done < <(lsblk -dpn -o PATH 2>/dev/null | grep -E "^/dev/(sd|nvme|hd)")
DISK_JSON+="]"

# ============================================================
# 5. BATTERY (original logic kept)
# ============================================================
banner "5. Battery"
BAT_STATUS=$PASS
BAT_JSON="{}"
BAT_HEALTH="N/A"
BAT_CYCLE="N/A"

BAT_DIR=$(ls -d /sys/class/power_supply/BAT* 2>/dev/null | head -1)
if [[ -n "$BAT_DIR" && -d "$BAT_DIR" ]]; then
  BAT_DESIGN=$(cat "$BAT_DIR/energy_full_design" 2>/dev/null)
  [[ -z "$BAT_DESIGN" ]] && BAT_DESIGN=$(cat "$BAT_DIR/charge_full_design" 2>/dev/null)
  BAT_FULL=$(cat "$BAT_DIR/energy_full" 2>/dev/null)
  [[ -z "$BAT_FULL" ]] && BAT_FULL=$(cat "$BAT_DIR/charge_full" 2>/dev/null)
  BAT_CYCLE=$(cat "$BAT_DIR/cycle_count" 2>/dev/null)
  BAT_MANUF=$(cat "$BAT_DIR/manufacturer" 2>/dev/null | xargs)
  BAT_MODEL_NAME=$(cat "$BAT_DIR/model_name" 2>/dev/null | xargs)
  BAT_CAPACITY=$(cat "$BAT_DIR/capacity" 2>/dev/null)

  if [[ -n "$BAT_DESIGN" && -n "$BAT_FULL" && "$BAT_DESIGN" -gt 0 ]]; then
    BAT_HEALTH=$(echo "scale=1; $BAT_FULL * 100 / $BAT_DESIGN" | bc)
  else
    BAT_HEALTH="?"
  fi

  if [[ "$BAT_HEALTH" != "?" ]] && (( $(echo "$BAT_HEALTH < 60" | bc -l) )); then
    BAT_STATUS=$FAIL
    err "Battery health critically low: ${BAT_HEALTH}%"
  else
    ok "Battery detected | Health: ${BAT_HEALTH}% | Cycles: ${BAT_CYCLE:-?}"
  fi

  BAT_JSON="{\"manufacturer\":\"${BAT_MANUF:-unknown}\",\"model\":\"${BAT_MODEL_NAME:-unknown}\",\"health_percent\":\"${BAT_HEALTH}\",\"current_percent\":\"${BAT_CAPACITY:-unknown}\",\"cycle_count\":\"${BAT_CYCLE:-unknown}\",\"status\":\"$BAT_STATUS\"}"
else
  warn "No battery detected."
  BAT_JSON="{\"status\":\"NOT_FOUND\"}"
fi

# ============================================================
# 6. SCREEN
# ============================================================
banner "6. Screen"
SCREEN_RES=$(xrandr 2>/dev/null | grep " connected" | grep -oP '\d+x\d+' | head -1)
SCREEN_NAME=$(xrandr 2>/dev/null | grep " connected" | awk '{print $1}' | head -1)
[[ -z "$SCREEN_RES" ]] && SCREEN_RES=$(cat /sys/class/drm/*/modes 2>/dev/null | head -1)
ok "Interface: ${SCREEN_NAME:-unknown} | Resolution: ${SCREEN_RES:-unknown}"

run_screen_test

ask_manual() {
  local item="$1"
  local hint="$2"
  echo -e "  ${BOLD}► $item${NC}"
  [[ -n "$hint" ]] && echo -e "    ${CYAN}Hint: $hint${NC}"
  read -rp "    Result [p=pass / f=fail / s=skip]: " ans
  case "$ans" in
    p|P) echo "PASS" ;;
    f|F) echo "FAIL" ;;
    *)   echo "SKIPPED" ;;
  esac
}

SCREEN_DEADPIXEL=$(ask_manual "Dead pixels / bright spots" "Look for any pixel that stayed the wrong color during color test")
SCREEN_BACKLIGHT=$(ask_manual "Backlight uniformity" "Check corners for uneven brightness on white screen")

# ============================================================
# 7. CAMERA
# ============================================================
banner "7. Camera"

CAM_STATUS=$FAIL
CAM_DEVICES=()

for dev in /dev/video*; do
  if [[ -e "$dev" ]]; then
    cam_name=$(v4l2-ctl --device="$dev" --info 2>/dev/null | grep "Card type" | cut -d: -f2 | xargs)
    CAM_DEVICES+=("${dev}:${cam_name:-unknown}")
    CAM_STATUS=$PASS
    ok "Found: $dev | $cam_name"
  fi
done

if [[ ${#CAM_DEVICES[@]} -eq 0 ]]; then
  err "No camera device found."
  CAM_STATUS=$FAIL
fi

CAM_COUNT=${#CAM_DEVICES[@]}
CAM_IMAGE_RESULT="SKIPPED"

if [[ $CAM_COUNT -gt 0 ]]; then
  SNAP="/tmp/cam_test_$$.jpg"
  echo "  Capturing test image with fswebcam (640x480)..."
  if fswebcam -q -r 640x480 --no-banner "$SNAP" 2>/dev/null; then
    if [[ -f "$SNAP" && -s "$SNAP" ]]; then
      ok "Test image captured: $SNAP"
    else
      err "Captured file is empty."
      rm -f "$SNAP"
    fi
  else
    err "fswebcam capture failed."
  fi

  CAM_IMAGE_RESULT=$(ask_manual "Camera image quality" "If using desktop GUI: open $SNAP with Cheese or eog. In pure CLI: only check if file exists.")
fi

# ============================================================
# 8. AUDIO
# ============================================================
banner "8. Audio"
AUDIO_CARDS=$(aplay -l 2>/dev/null | grep "^card" | wc -l)
MIC_CARDS=$(arecord -l 2>/dev/null | grep "^card" | wc -l)

[[ $AUDIO_CARDS -gt 0 ]] && ok "Speaker devices found: ${AUDIO_CARDS} card(s)" || err "No audio output device found."
[[ $MIC_CARDS -gt 0 ]]   && ok "Microphone devices found: ${MIC_CARDS} card(s)" || err "No audio input device found."

run_audio_test
SPEAKER_QUALITY_CHECK=$SPEAKER_QUALITY_RESULT
MIC_RECORD_CHECK=$MIC_RECORD_RESULT

# ============================================================
# 9. KEYBOARD
# ============================================================
banner "9. Keyboard"
KB_DEVICES=$(ls /dev/input/by-path/ 2>/dev/null | grep -ci kbd)
[[ $KB_DEVICES -gt 0 ]] && ok "Keyboard device(s) found: $KB_DEVICES" || err "No keyboard device found."

run_keyboard_test
KB_KEYS_CHECK=$KB_TEST_RESULT

TOUCHPAD=$(ask_manual "Touchpad click / scroll" "Test single click, double click, and two-finger scroll")

# ============================================================
# 10. NETWORK
# ============================================================
banner "10. Network"
WIFI_DEV=$(iw dev 2>/dev/null | awk '/Interface/{print $2}' | head -1)
ETH_DEV=$(ip -o link show 2>/dev/null | awk -F': ' '{print $2}' | grep -vE "^lo$|^wl" | head -1)

[[ -n "$WIFI_DEV" ]] && ok "WiFi: $WIFI_DEV" || err "No WiFi device found."
[[ -n "$ETH_DEV" ]] && ok "Ethernet: $ETH_DEV" || warn "No Ethernet device found."

# ============================================================
# 11. USB PORTS
# ============================================================
banner "11. USB Ports"
USB_DEVICE_COUNT=$(lsusb 2>/dev/null | wc -l)
USB3_COUNT=$(lsusb 2>/dev/null | grep -ciE "3\.0|3\.1|3\.2")
ok "USB devices detected: ${USB_DEVICE_COUNT} | USB 3.x controllers: ${USB3_COUNT}"

PORTS_PHYSICAL=$(ask_manual "Physical port condition (USB/HDMI/audio)" "Check for bent pins or physical damage")

# ============================================================
# 12. APPEARANCE
# ============================================================
banner "12. Appearance"
HINGE=$(ask_manual "Hinge smoothness" "Open and close the lid 10 times, check for wobble or stiffness")
APPEARANCE=$(ask_manual "Exterior condition" "Inspect all sides for scratches or damage")

# ============================================================
# BUILD JSON REPORT
# ============================================================
banner "Generating Report"

esc() { echo "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }

JSON=$(cat <<EOF
{
  "test_info": {
    "test_time": "$(esc "$TEST_TIME")",
    "hostname": "$(esc "$HOSTNAME")",
    "script_version": "2.0.0"
  },
  "system": {
    "vendor": "$(esc "$SYS_VENDOR")",
    "model": "$(esc "$SYS_MODEL")",
    "serial_number": "$(esc "$SYS_SERIAL")",
    "bios_version": "$(esc "$BIOS_VER")"
  },
  "cpu": {
    "model": "$(esc "$CPU_MODEL")",
    "cores": ${CPU_CORES:-0},
    "threads": ${CPU_THREADS:-0},
    "max_mhz": "${CPU_MAX_MHZ:-0}",
    "architecture": "$(esc "$CPU_ARCH")"
  },
  "memory": {
    "total_gb": "$(esc "$MEM_TOTAL_GB")",
    "type": "$(esc "${MEM_TYPE:-unknown}")",
    "speed": "$(esc "${MEM_SPEED:-unknown}")",
    "slots_total": ${MEM_SLOTS:-0},
    "slots_used": ${MEM_USED_SLOTS:-0}
  },
  "storage": ${DISK_JSON},
  "battery": ${BAT_JSON},
  "screen": {
    "resolution": "$(esc "${SCREEN_RES:-unknown}")",
    "interface": "$(esc "${SCREEN_NAME:-unknown}")",
    "dead_pixel_check": "$(esc "$SCREEN_DEADPIXEL")",
    "backlight_check": "$(esc "$SCREEN_BACKLIGHT")"
  },
  "camera": {
    "device_status": "$(esc "$CAM_STATUS")",
    "device_count": ${CAM_COUNT:-0},
    "image_quality_check": "$(esc "$CAM_IMAGE_RESULT")"
  },
  "audio": {
    "speaker_device_status": "$(esc "${AUDIO_CARDS:-0}")",
    "mic_device_status": "$(esc "${MIC_CARDS:-0}")",
    "speaker_quality_check": "$(esc "$SPEAKER_QUALITY_CHECK")",
    "mic_record_check": "$(esc "$MIC_RECORD_CHECK")"
  },
  "keyboard": {
    "device_status": "$(esc "${KB_DEVICES:-0}")",
    "keys_check": "$(esc "$KB_KEYS_CHECK")",
    "touchpad_check": "$(esc "$TOUCHPAD")"
  },
  "network": {
    "wifi_status": "$(esc "${WIFI_DEV:+PASS:-FAIL}")",
    "wifi_device": "$(esc "${WIFI_DEV:-none}")",
    "ethernet_status": "$(esc "${ETH_DEV:+PASS:-FAIL}")",
    "ethernet_device": "$(esc "${ETH_DEV:-none}")"
  },
  "ports": {
    "usb_device_count": ${USB_DEVICE_COUNT:-0},
    "usb3_count": ${USB3_COUNT:-0},
    "physical_check": "$(esc "$PORTS_PHYSICAL")"
  },
  "appearance": {
    "hinge_check": "$(esc "$HINGE")",
    "scratch_check": "$(esc "$APPEARANCE")"
  },
  "overall_result": "PENDING"
}
EOF
)

FAIL_COUNT=$(echo "$JSON" | grep -o '"FAIL"' | wc -l)
OVERALL=$([[ $FAIL_COUNT -gt 0 ]] && echo "FAIL" || echo "PASS")
JSON=$(echo "$JSON" | sed 's/"PENDING"/"'"$OVERALL"'"/')

if command -v jq &>/dev/null; then
  if echo "$JSON" | jq . &>/dev/null; then
    echo "$JSON" | jq . > "$REPORT_FILE"
    ok "Report saved (validated): $REPORT_FILE"
  else
    echo "$JSON" > "$REPORT_FILE"
    err "JSON validation failed — saved raw version."
  fi
else
  echo "$JSON" > "$REPORT_FILE"
  ok "Report saved: $REPORT_FILE"
fi

# ============================================================
# UPLOAD REPORT
# ============================================================
banner "Uploading Report"
HTTP_CODE=$(curl -s -o /tmp/upload_response.txt -w "%{http_code}" \
  -X POST "$UPLOAD_URL" \
  -H "Content-Type: application/json" \
  -d @"$REPORT_FILE" \
  --connect-timeout 10 --max-time 30)

if [[ "$HTTP_CODE" == "200" || "$HTTP_CODE" == "201" ]]; then
  ok "Upload successful (HTTP $HTTP_CODE)"
else
  err "Upload failed (HTTP ${HTTP_CODE:-no response})"
  warn "Report kept locally: $REPORT_FILE"
fi

# ============================================================
# TEST SUMMARY
# ============================================================
banner "TEST SUMMARY"
echo ""
printf "  %-20s %s\n" "Vendor/Model:"     "$SYS_VENDOR $SYS_MODEL"
printf "  %-20s %s\n" "Serial:"           "$SYS_SERIAL"
printf "  %-20s %s\n" "CPU:"              "$CPU_MODEL"
printf "  %-20s %s\n" "Memory:"           "${MEM_TOTAL_GB} GB"
printf "  %-20s %s\n" "Battery Health:"   "${BAT_HEALTH}%"
printf "  %-20s %s\n" "Screen:"           "Dead pixel: $SCREEN_DEADPIXEL | Backlight: $SCREEN_BACKLIGHT"
printf "  %-20s %s\n" "Camera:"           "$CAM_STATUS | Image: $CAM_IMAGE_RESULT"
printf "  %-20s %s\n" "Speaker:"          "Quality: $SPEAKER_QUALITY_CHECK"
printf "  %-20s %s\n" "Microphone:"       "Record: $MIC_RECORD_CHECK"
printf "  %-20s %s\n" "Keyboard:"         "Keys: $KB_KEYS_CHECK | Touchpad: $TOUCHPAD"
printf "  %-20s %s\n" "WiFi:"             "${WIFI_DEV:+PASS}"
printf "  %-20s %s\n" "Ports:"            "$PORTS_PHYSICAL"
printf "  %-20s %s\n" "Appearance:"       "Hinge: $HINGE | Scratches: $APPEARANCE"
echo ""

if [[ "$OVERALL" == "PASS" ]]; then
  echo -e "  ${GREEN}${BOLD}RESULT: ✓ PASS — Ready for resale${NC}"
else
  echo -e "  ${RED}${BOLD}RESULT: ✗ FAIL — Needs repair${NC}"
fi

echo -e "\n  Report file: $REPORT_FILE"
echo ""