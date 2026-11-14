#!/usr/bin/env bash
# ALOOZ HOSTING V104 - 58 Commands Edition
set -Eeuo pipefail

GITHUB_REPO="YOUR_GITHUB_USERNAME/alooz-hosting-bot"
INSTALLER_URL="https://raw.githubusercontent.com/$GITHUB_REPO/main/install.sh"

if [ "${ALOOZ_AUTO_UPDATE:-0}" != "1" ]; then
    curl -fsSL -o /tmp/alooz_installer.sh "$INSTALLER_URL" 2>/dev/null || true
    if [ -s /tmp/alooz_installer.sh ] && ! cmp -s "$0" /tmp/alooz_installer.sh; then
        chmod +x /tmp/alooz_installer.sh
        export ALOOZ_AUTO_UPDATE=1
        exec bash /tmp/alooz_installer.sh "$@"
    fi
fi

INSTALL_DIR="${INSTALL_DIR:-/opt/alooz-bot}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
SERVICE="alooz-bot"
ENV_FILE="$INSTALL_DIR/.env"

PAL=(196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 57 93 129 165 201 200 199 198 197)

show_banner() {
  local text="ALOOZ HOSTING" subtitle="V104 - 58 COMMANDS"
  local -a rows=("" "" "" "" "")
  local -A G=(
    [A]=" ### |#   #|#####|#   #|#   #" [L]="#    |#    |#    |#    |#####"
    [O]=" ### |#   #|#   #|#   #| ### " [Z]="#####|   # |  #  | #   |#####"
    [H]="#   #|#   #|#####|#   #|#   #" [S]=" ####|#    | ### |    #|#### "
    [T]="#####|  #  |  #  |  #  |  #  " [I]="#####|  #  |  #  |  #  |#####"
    [N]="#   #|##  #|# # #|#  ##|#   #" [G]=" ####|#    |#  ##|#   #| ### "
    [_]="   |   |   |   |   "
  )
  local n i ch x r row c line frame width
  local -a parts
  for ((n = 0; n < ${#text}; n++)); do
    ch="${text:n:1}"; [ "$ch" = " " ] && ch="_"
    IFS='|' read -ra parts <<<"${G[$ch]}"
    for i in 0 1 2 3 4; do rows[i]+="${parts[i]} "; done
  done
  width=${#rows[0]}
  if [ ! -t 1 ]; then for r in 0 1 2 3 4; do echo "${rows[r]//#/█}"; done; echo "$subtitle"; return; fi
  printf '\033[?25l'; printf '\n\n\n\n\n\n'
  draw() {
    local shift=$1 vis=$2
    printf '\033[5A'
    for r in 0 1 2 3 4; do
      row="${rows[r]}"; line=""
      for ((x = 0; x < ${#row}; x++)); do
        c="${row:x:1}"
        if [ "$c" = "#" ] && [ "$x" -lt "$vis" ]; then line+=$'\033[38;5;'"${PAL[(x + shift) % ${#PAL[@]}]}"$'m█'
        else line+=" "; fi
      done
      printf '\r%s\033[0m\033[K\n' "$line"
    done
  }
  for ((frame = 0; frame <= 30; frame++)); do draw "$frame" $((width * frame / 30)); sleep 0.02; done
  for ((frame = 0; frame < 50; frame++)); do draw $((30 + frame)) "$width"; sleep 0.03; done
  printf '\033[38;5;245m'; for ((x = 0; x < width; x++)); do printf '═'; done; printf '\033[0m\n'
  printf '%*s' $(((width - ${#subtitle}) / 2)) ''
  for ((n = 0; n < ${#subtitle}; n++)); do
    printf '\033[1;38;5;%sm%s\033[0m' "${PAL[(n * 2) % ${#PAL[@]}]}" "${subtitle:n:1}"; sleep 0.02
  done
  printf '\n\033[?25h\n'
}
restore_terminal() { printf '\033[0m\033[?25h'; }
trap restore_terminal EXIT

say()  { printf '\033[1;36m[ALOOZ]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[WARN]\033[0m %s\n' "$*"; }
die()  { printf '\033[1;31m[ERROR]\033[0m %s\n' "$*" >&2; exit 1; }

ask() {
  local var="$1" text="$2" secret="${3:-}" value=""
  if [ -n "$secret" ]; then read -r -s -p "$text: " value </dev/tty; echo
  else read -r -p "$text: " value </dev/tty; fi
  printf -v "$var" '%s' "$value"
}

validate_token() {
  local tmp code
  tmp="$(mktemp)"
  code="$(curl -sS -m 15 -o "$tmp" -w '%{http_code}' -H "Authorization: Bot $1" https://discord.com/api/v10/users/@me 2>/dev/null || true)"
  if [ "$code" = "200" ]; then BOT_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$tmp" 2>/dev/null || true)"; rm -f "$tmp"; return 0; fi
  rm -f "$tmp"; [ "$code" = "401" ] && return 1; return 2
}

update_env_file() {
  local key="$1" val="$2"
  mkdir -p "$INSTALL_DIR"; touch "$ENV_FILE"
  sed -i "s/\r$//" "$ENV_FILE" 2>/dev/null || true
  if grep -q "^${key}=" "$ENV_FILE"; then sed -i "s|^${key}=.*|${key}=${val}|" "$ENV_FILE"
  else echo "${key}=${val}" >> "$ENV_FILE"; fi
  chmod 600 "$ENV_FILE"
}

set_token_interactive() {
  local attempts=0 DISCORD_TOKEN=""
  while :; do
    attempts=$((attempts + 1))
    ask DISCORD_TOKEN "Paste your Discord bot token (hidden)" secret
    DISCORD_TOKEN="$(printf '%s' "$DISCORD_TOKEN" | tr -d '[:space:]')"
    if [ -z "$DISCORD_TOKEN" ]; then warn "Token cannot be empty."; continue; fi
    rc=0; validate_token "$DISCORD_TOKEN" || rc=$?
    if [ "$rc" -eq 0 ]; then say "Token accepted."; update_env_file "DISCORD_TOKEN" "$DISCORD_TOKEN"; break
    elif [ "$rc" -eq 2 ]; then warn "Could not verify. Saving anyway."; update_env_file "DISCORD_TOKEN" "$DISCORD_TOKEN"; break
    else warn "Invalid token."; fi
    [ "$attempts" -lt 3 ] || { warn "Too many attempts."; return; }
  done
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  say "Token updated."
}

set_owner_interactive() {
  local OWNER_ID="" attempts=0
  while ! [[ "$OWNER_ID" =~ ^[0-9]{15,22}$ ]]; do
    attempts=$((attempts + 1)); [ "$attempts" -le 3 ] || { warn "Too many attempts."; return; }
    [ -z "$OWNER_ID" ] || warn "Owner ID must be numbers only."
    ask OWNER_ID "Enter your Discord owner ID"; OWNER_ID="$(printf '%s' "$OWNER_ID" | tr -d '[:space:]')"
  done
  update_env_file "OWNER_ID" "$OWNER_ID"
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  say "Owner ID updated."
}

install_system() {
  say "Preparing system..."
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
  APT=(apt-get -y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)
  dpkg --configure -a >/dev/null 2>&1 || true
  "${APT[@]}" -f install >/dev/null 2>&1 || true
  "${APT[@]}" update || warn "apt update problems, continuing."
  apt-get install -y -o DPkg::Lock::Timeout=300 curl ca-certificates python3 python3-venv python3-pip docker.io || die "Dependency install failed."
  systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker info >/dev/null 2>&1 || die "Docker not running."
  say "Writing bot files to $INSTALL_DIR..."
  mkdir -p "$INSTALL_DIR"

  # ===================== main.py =====================
  cat > "$INSTALL_DIR/main.py" <<'__ALOOZ_EOF__'
import logging, sys, config
from banner import play_banner
def main() -> None:
    play_banner()
    if not config.TOKEN: print("ERROR: DISCORD_TOKEN missing."); sys.exit(78)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    import discord
    from bot import bot
    try: bot.run(config.TOKEN, log_handler=None)
    except discord.LoginFailure: print("ERROR: Token rejected."); sys.exit(78)
if __name__ == "__main__": main()
__ALOOZ_EOF__

  # ===================== config.py =====================
  cat > "$INSTALL_DIR/config.py" <<'__ALOOZ_EOF__'
import os
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError: pass
def _int(name: str, default: int) -> int:
    try: return int(os.getenv(name, str(default)))
    except ValueError: return default
def _int_set(name: str) -> set:
    return {int(x) for x in os.getenv(name, "").replace(" ", "").split(",") if x.isdigit()}
BOT_NAME = "ALOOZ HOSTING"
TOKEN = os.getenv("DISCORD_TOKEN", "").strip()
OWNER_ID = _int("OWNER_ID", 0)
ADMIN_IDS = _int_set("ADMIN_IDS")
SERVER_IP = os.getenv("SERVER_IP", "YOUR_SERVER_IP").strip()
PORT_START = _int("PORT_START", 20000)
PORT_END = _int("PORT_END", 20999)
MC_PORT_START = _int("MC_PORT_START", 25565)
MC_PORT_END = _int("MC_PORT_END", 25999)
USE_DISK_LIMIT = os.getenv("USE_DISK_LIMIT", "false").strip().lower() in ("1", "true", "yes")
DB_PATH = os.getenv("DB_PATH", "alooz_hosting.db")
__ALOOZ_EOF__

  # ===================== banner.py =====================
  cat > "$INSTALL_DIR/banner.py" <<'__ALOOZ_EOF__'
import os, sys, time
GLYPHS = {"A": [" ### ", "#   #", "#####", "#   #", "#   #"], "L": ["#    ", "#    ", "#    ", "#    ", "#####"], "O": [" ### ", "#   #", "#   #", "#   #", " ### "], "Z": ["#####", "   # ", "  #  ", " #   ", "#####"], "H": ["#   #", "#   #", "#####", "#   #", "#   #"], "S": [" ####", "#    ", " ### ", "    #", "#### "], "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  "], "I": ["#####", "  #  ", "  #  ", "  #  ", "#####"], "N": ["#   #", "##  #", "# # #", "#  ##", "#   #"], "G": [" ####", "#    ", "#  ##", "#   #", " ### "], " ": ["   ", "   ", "   ", "   ", "   "]}
PALETTE = [196, 202, 208, 214, 220, 226, 190, 154, 118, 82, 46, 47, 48, 49, 50, 51, 45, 39, 33, 27, 57, 93, 129, 165, 201, 200, 199, 198, 197]
RESET = "\033[0m"
def _block_char() -> str:
    try: "█".encode(sys.stdout.encoding or "utf-8"); return "█"
    except (UnicodeEncodeError, LookupError): return "#"
def build_lines(text: str) -> list:
    block = _block_char(); rows = [""] * 5
    for ch in text.upper():
        glyph = GLYPHS.get(ch, GLYPHS[" "])
        for i in range(5): rows[i] += glyph[i].replace("#", block) + " "
    return [row.rstrip() for row in rows]
def _colorize(lines: list, shift: int, visible_cols: int) -> list:
    frame = []
    for row in lines:
        parts = []
        for x, ch in enumerate(row):
            if ch == " " or x >= visible_cols: parts.append(" ")
            else: parts.append(f"\033[38;5;{PALETTE[(x + shift) % len(PALETTE)]}m{ch}")
        frame.append("".join(parts) + RESET)
    return frame
def play_banner(text: str = "ALOOZ HOSTING", subtitle: str = "V104 - 58 COMMANDS", reveal_seconds: float = 1.6, shimmer_seconds: float = 3.0, fps: int = 24) -> None:
    lines = build_lines(text); width = max(len(row) for row in lines); height = len(lines)
    if not sys.stdout.isatty(): print("\n".join(lines)); print(subtitle); return
    if os.name == "nt": os.system("")
    out = sys.stdout; out.write("\033[?25l")
    try:
        out.write("\n" + "\n" * height)
        def draw(shift: int, cols: int) -> None:
            frame = _colorize(lines, shift, cols); out.write(f"\033[{height}A")
            for row in frame: out.write("\r" + row + "\033[K\n")
            out.flush()
        reveal_frames = max(1, int(reveal_seconds * fps))
        for f in range(reveal_frames + 1): draw(f, int(width * f / reveal_frames)); time.sleep(1.0 / fps)
        for f in range(int(shimmer_seconds * fps)): draw(reveal_frames + f, width); time.sleep(1.0 / fps)
        divider = "═" * width if _block_char() != "#" else "=" * width
        out.write(f"\033[38;5;245m{divider}{RESET}\n"); pad = " " * max(0, (width - len(subtitle)) // 2); out.write(pad)
        for i, ch in enumerate(subtitle):
            out.write(f"\033[1;38;5;{PALETTE[(i * 2) % len(PALETTE)]}m{ch}{RESET}"); out.flush(); time.sleep(0.04)
        out.write("\n")
    finally: out.write(RESET + "\033[?25h\n"); out.flush()
if __name__ == "__main__": play_banner()
__ALOOZ_EOF__

  # ===================== database.py =====================
  cat > "$INSTALL_DIR/database.py" <<'__ALOOZ_EOF__'
import sqlite3, threading, time, uuid
from typing import List, Optional, Set
SCHEMA = """
CREATE TABLE IF NOT EXISTS vps (id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id INTEGER NOT NULL, container TEXT NOT NULL UNIQUE, name TEXT NOT NULL DEFAULT 'My VPS', ram_mb INTEGER NOT NULL, cpu REAL NOT NULL, disk_gb INTEGER NOT NULL, ssh_port INTEGER NOT NULL UNIQUE, root_password TEXT NOT NULL, os_image TEXT NOT NULL, suspended INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL DEFAULT 0, server_ip TEXT NOT NULL DEFAULT '');
CREATE INDEX IF NOT EXISTS idx_vps_owner ON vps(owner_id);
CREATE TABLE IF NOT EXISTS mc_servers (id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id INTEGER NOT NULL, container TEXT NOT NULL UNIQUE, name TEXT NOT NULL, mc_version TEXT NOT NULL, server_type TEXT NOT NULL, ram_mb INTEGER NOT NULL, cpu REAL NOT NULL, disk_gb INTEGER NOT NULL, port INTEGER NOT NULL UNIQUE, rcon_port INTEGER NOT NULL UNIQUE, rcon_password TEXT NOT NULL, suspended INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL DEFAULT 0, server_ip TEXT NOT NULL DEFAULT '');
CREATE INDEX IF NOT EXISTS idx_mc_owner ON mc_servers(owner_id);
CREATE TABLE IF NOT EXISTS admins (user_id INTEGER PRIMARY KEY, added_by INTEGER NOT NULL, added_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS invites (user_id INTEGER PRIMARY KEY, total INTEGER NOT NULL DEFAULT 0, fake INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS invite_logs (invited_id INTEGER PRIMARY KEY, inviter_id INTEGER NOT NULL, joined_at INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS coins (user_id INTEGER PRIMARY KEY, total INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS coins_logs (id INTEGER PRIMARY KEY AUTOINCREMENT, user_id INTEGER NOT NULL, amount INTEGER NOT NULL, reason TEXT, timestamp INTEGER NOT NULL);
CREATE TABLE IF NOT EXISTS chat_counters (user_id INTEGER PRIMARY KEY, message_count INTEGER NOT NULL DEFAULT 0, last_message INTEGER NOT NULL DEFAULT 0);
CREATE TABLE IF NOT EXISTS settings (key TEXT PRIMARY KEY, value TEXT);
"""
class Database:
    def __init__(self, path: str):
        self._conn = sqlite3.connect(path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        with self._lock: self._conn.executescript(SCHEMA); self._conn.commit()
    def _execute(self, sql: str, params: tuple = ()) -> sqlite3.Cursor:
        with self._lock: cur = self._conn.execute(sql, params); self._conn.commit(); return cur
    def _query(self, sql: str, params: tuple = ()) -> List[sqlite3.Row]:
        with self._lock: return self._conn.execute(sql, params).fetchall()
    # VPS
    def add_vps(self, owner_id: int, ram_mb: int, cpu: float, disk_gb: int, ssh_port: int, root_password: str, os_image: str, server_ip: str = "") -> int:
        expiry = int(time.time()) + (30 * 24 * 60 * 60)
        cur = self._execute("INSERT INTO vps (owner_id, container, ram_mb, cpu, disk_gb, ssh_port, root_password, os_image, server_ip, created_at, expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)", (owner_id, f"pending-{uuid.uuid4().hex}", ram_mb, cpu, disk_gb, ssh_port, root_password, os_image, server_ip, int(time.time()), expiry))
        vps_id = cur.lastrowid
        self._execute("UPDATE vps SET container = ?, name = ? WHERE id = ?", (f"alooz-vps-{vps_id}", f"VPS-{vps_id}", vps_id))
        return vps_id
    def get_vps(self, vps_id: int) -> Optional[sqlite3.Row]:
        rows = self._query("SELECT * FROM vps WHERE id = ?", (vps_id,)); return rows[0] if rows else None
    def list_vps_by_owner(self, owner_id: int) -> List[sqlite3.Row]: return self._query("SELECT * FROM vps WHERE owner_id = ? ORDER BY id", (owner_id,))
    def list_all_vps(self) -> List[sqlite3.Row]: return self._query("SELECT * FROM vps ORDER BY id")
    def delete_vps(self, vps_id: int) -> None: self._execute("DELETE FROM vps WHERE id = ?", (vps_id,))
    def update_vps(self, vps_id: int, **fields) -> None:
        if not fields: return
        assignments = ", ".join(f"{k} = ?" for k in fields)
        self._execute(f"UPDATE vps SET {assignments} WHERE id = ?", (*fields.values(), vps_id))
    def used_vps_ports(self) -> Set[int]: return {row["ssh_port"] for row in self._query("SELECT ssh_port FROM vps")}
    # MC
    def add_mc(self, owner_id: int, name: str, mc_version: str, server_type: str, ram_mb: int, cpu: float, disk_gb: int, port: int, rcon_port: int, rcon_password: str, server_ip: str = "") -> int:
        expiry = int(time.time()) + (30 * 24 * 60 * 60)
        cur = self._execute("INSERT INTO mc_servers (owner_id, container, name, mc_version, server_type, ram_mb, cpu, disk_gb, port, rcon_port, rcon_password, server_ip, created_at, expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)", (owner_id, f"pending-{uuid.uuid4().hex}", name, mc_version, server_type, ram_mb, cpu, disk_gb, port, rcon_port, rcon_password, server_ip, int(time.time()), expiry))
        mc_id = cur.lastrowid
        self._execute("UPDATE mc_servers SET container = ? WHERE id = ?", (f"alooz-mc-{mc_id}", mc_id))
        return mc_id
    def get_mc(self, mc_id: int) -> Optional[sqlite3.Row]:
        rows = self._query("SELECT * FROM mc_servers WHERE id = ?", (mc_id,)); return rows[0] if rows else None
    def list_mc_by_owner(self, owner_id: int) -> List[sqlite3.Row]: return self._query("SELECT * FROM mc_servers WHERE owner_id = ? ORDER BY id", (owner_id,))
    def list_all_mc(self) -> List[sqlite3.Row]: return self._query("SELECT * FROM mc_servers ORDER BY id")
    def delete_mc(self, mc_id: int) -> None: self._execute("DELETE FROM mc_servers WHERE id = ?", (mc_id,))
    def update_mc(self, mc_id: int, **fields) -> None:
        if not fields: return
        assignments = ", ".join(f"{k} = ?" for k in fields)
        self._execute(f"UPDATE mc_servers SET {assignments} WHERE id = ?", (*fields.values(), mc_id))
    def used_mc_ports(self) -> Set[int]: return {row["port"] for row in self._query("SELECT port FROM mc_servers")}
    def used_rcon_ports(self) -> Set[int]: return {row["rcon_port"] for row in self._query("SELECT rcon_port FROM mc_servers")}
    # Invites
    def get_invites(self, user_id: int) -> int:
        row = self._query("SELECT total FROM invites WHERE user_id = ?", (user_id,)); return row[0]["total"] if row else 0
    def add_invite(self, user_id: int, amount: int):
        self._execute("INSERT INTO invites (user_id, total) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET total = total + ?", (user_id, amount, amount))
    def remove_invite(self, user_id: int, amount: int = 1):
        current = self.get_invites(user_id); self._execute("UPDATE invites SET total = ? WHERE user_id = ?", (max(0, current - amount), user_id))
    def reset_all_invites(self): self._execute("UPDATE invites SET total = 0")
    def log_join(self, invited_id: int, inviter_id: int):
        self._execute("INSERT OR REPLACE INTO invite_logs (invited_id, inviter_id, joined_at) VALUES (?, ?, ?)", (invited_id, inviter_id, int(time.time())))
    def get_inviter(self, invited_id: int) -> int:
        row = self._query("SELECT inviter_id FROM invite_logs WHERE invited_id = ?", (invited_id,)); return row[0]["inviter_id"] if row else 0
    def remove_join_log(self, invited_id: int): self._execute("DELETE FROM invite_logs WHERE invited_id = ?", (invited_id,))
    def get_top_inviters(self, limit=10): return self._query("SELECT user_id, total FROM invites ORDER BY total DESC LIMIT ?", (limit,))
    # Coins
    def get_coins(self, user_id: int) -> int:
        row = self._query("SELECT total FROM coins WHERE user_id = ?", (user_id,)); return row[0]["total"] if row else 0
    def add_coins(self, user_id: int, amount: int, reason: str = "Chat Reward"):
        self._execute("INSERT INTO coins (user_id, total) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET total = total + ?", (user_id, amount, amount))
        self._execute("INSERT INTO coins_logs (user_id, amount, reason, timestamp) VALUES (?, ?, ?, ?)", (user_id, amount, reason, int(time.time())))
    def remove_coins(self, user_id: int, amount: int):
        current = self.get_coins(user_id); self._execute("UPDATE coins SET total = ? WHERE user_id = ?", (max(0, current - amount), user_id))
    def reset_all_coins(self): self._execute("UPDATE coins SET total = 0")
    def get_coins_logs(self, limit=20): return self._query("SELECT user_id, amount, reason, timestamp FROM coins_logs ORDER BY timestamp DESC LIMIT ?", (limit,))
    def get_top_coins(self, limit=10): return self._query("SELECT user_id, total FROM coins ORDER BY total DESC LIMIT ?", (limit,))
    def log_message(self, user_id: int) -> int:
        now = int(time.time())
        row = self._query("SELECT message_count FROM chat_counters WHERE user_id = ?", (user_id,))
        if not row: self._execute("INSERT INTO chat_counters (user_id, message_count, last_message) VALUES (?, 1, ?)", (user_id, now)); return 1
        count = row[0]["message_count"] + 1
        self._execute("UPDATE chat_counters SET message_count = ?, last_message = ? WHERE user_id = ?", (count, now, user_id))
        return count
    # Settings
    def set_setting(self, key: str, value: str): self._execute("INSERT INTO settings (key, value) VALUES (?, ?) ON CONFLICT(key) DO UPDATE SET value = ?", (key, value, value))
    def get_setting(self, key: str) -> str:
        row = self._query("SELECT value FROM settings WHERE key = ?", (key,)); return row[0]["value"] if row else None
    # Maintenance
    def get_expired_servers(self) -> tuple:
        now = int(time.time())
        vps = self._query("SELECT id, owner_id, container FROM vps WHERE expires_at < ? AND expires_at != 0", (now,))
        mc = self._query("SELECT id, owner_id, container FROM mc_servers WHERE expires_at < ? AND expires_at != 0", (now,))
        return vps, mc
    def renew_server(self, server_type: str, server_id: int):
        new_expiry = int(time.time()) + (30 * 24 * 60 * 60)
        if server_type == "vps": self._execute("UPDATE vps SET expires_at = ? WHERE id = ?", (new_expiry, server_id))
        else: self._execute("UPDATE mc_servers SET expires_at = ? WHERE id = ?", (new_expiry, server_id))
__ALOOZ_EOF__

  # ===================== docker_utils.py =====================
  cat > "$INSTALL_DIR/docker_utils.py" <<'__ALOOZ_EOF__'
import asyncio, os, re, secrets, shutil, socket, string, time
from typing import Dict, List
class DockerError(Exception): pass
BOOT_SCRIPT = r"""
set -e
export DEBIAN_FRONTEND=noninteractive
if [ ! -x /usr/sbin/sshd ]; then
  apt-get update -qq
  apt-get install -y -qq openssh-server sudo curl wget nano htop git net-tools iputils-ping ca-certificates >/dev/null
fi
if ! command -v sshx >/dev/null 2>&1; then
  curl -sSf https://sshx.io/get | sh >/dev/null 2>&1
  mv /root/.sshx/bin/sshx /usr/local/bin/ 2>/dev/null || true
  chmod +x /usr/local/bin/sshx 2>/dev/null || true
fi
mkdir -p /run/sshd
if [ -f /etc/alooz_pw ]; then PW="$(cat /etc/alooz_pw)"; else PW="$ROOT_PASSWORD"; echo "$PW" > /etc/alooz_pw; chmod 600 /etc/alooz_pw; fi
echo "root:$PW" | chpasswd
sed -i 's/^#\?PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config
sed -i 's/^#\?PasswordAuthentication.*/PasswordAuthentication yes/' /etc/ssh/sshd_config
nohup sshx > /tmp/sshx.log 2>&1 &
exec /usr/sbin/sshd -D -e
"""
MC_BOOT_SCRIPT = r"""
set -e
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq openjdk-17-jre-headless curl wget unzip jq >/dev/null
mkdir -p /data && cd /data
TYPE="$MC_TYPE"; VERSION="$MC_VERSION"; MEM="$MC_RAM"; RCON_PW="$MC_RCON_PW"; JAR="server.jar"
if [ ! -f "$JAR" ]; then
  case "$TYPE" in
    vanilla) URL="https://piston-data.mojang.com/v1/objects/$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r --arg v "$VERSION" '.versions[] | select(.id==$v) | .url' | xargs curl -s | jq -r '.downloads.server.url')"; wget -q -O "$JAR" "$URL" ;;
    paper|purpur)
      if [ "$TYPE" = "paper" ]; then BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$VERSION" | jq -r '.builds | last'); URL="https://api.papermc.io/v2/projects/paper/versions/$VERSION/builds/$BUILD/downloads/paper-$VERSION-$BUILD.jar"
      else BUILD=$(curl -s "https://api.purpurmc.org/v2/purpur/$VERSION" | jq -r '.builds.latest'); URL="https://api.purpurmc.org/v2/purpur/$VERSION/$BUILD/download"; fi
      wget -q -O "$JAR" "$URL" ;;
  esac
fi
if [ ! -f eula.txt ]; then echo "eula=true" > eula.txt; fi
if [ ! -f server.properties ]; then
  cat > server.properties <<EOF
server-port=25565
enable-rcon=true
rcon.port=25575
rcon.password=$RCON_PW
motd=ALOOZ HOSTING Minecraft Server
max-players=20
online-mode=true
EOF
fi
exec java -Xms${MEM}M -Xmx${MEM}M -jar "$JAR" nogui
"""
async def _run(*args: str, timeout: int = 600):
    try: proc = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    except FileNotFoundError: raise DockerError("Docker not installed.")
    try: out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError: proc.kill(); raise DockerError("Docker timed out.")
    return proc.returncode, out.decode(errors="replace").strip(), err.decode(errors="replace").strip()
async def _docker(*args: str, timeout: int = 600) -> str:
    code, out, err = await _run("docker", *args, timeout=timeout)
    if code != 0: raise DockerError(err or out or "docker failed")
    return out
def generate_password(length: int = 16) -> str:
    return "".join(secrets.choice(string.ascii_letters + string.digits) for _ in range(length))
def port_is_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try: sock.bind(("0.0.0.0", port)); return True
        except OSError: return False
def build_run_args(name: str, image: str, ram_mb: int, cpu: float, disk_gb: int, port: int, password: str, use_disk_limit: bool = False) -> List[str]:
    cpu_shares = int(cpu * 1024)
    args = ["run", "-d", "--name", name, "--hostname", name, "--restart", "unless-stopped", "--memory", f"{ram_mb}m", "--memory-reservation", f"{ram_mb}m", "--memory-swap", f"{ram_mb}m", "--cpus", f"{cpu:g}", "--cpu-shares", str(cpu_shares), "--pids-limit", "4096", "-p", f"{port}:22", "-e", f"ROOT_PASSWORD={password}", "--label", "alooz.vps=1"]
    if use_disk_limit: args += ["--storage-opt", f"size={disk_gb}g"]
    args += [image, "bash", "-c", BOOT_SCRIPT]; return args
async def create_vps_container(name: str, image: str, ram_mb: int, cpu: float, disk_gb: int, port: int, password: str, use_disk_limit: bool = False) -> str:
    return await _docker(*build_run_args(name, image, ram_mb, cpu, disk_gb, port, password, use_disk_limit), timeout=900)
async def power(name: str, action: str) -> None:
    if action == "start": await _docker("start", name)
    else: await _docker(action, "-t", "10", name)
async def remove(name: str) -> None:
    try: await _docker("rm", "-f", name)
    except DockerError as exc:
        if "No such container" not in str(exc): raise
async def container_status(name: str) -> str:
    code, out, _ = await _run("docker", "inspect", "-f", "{{.State.Status}}", name, timeout=30)
    return out if code == 0 and out else "missing"
async def container_stats(name: str) -> Dict[str, str]:
    out = await _docker("stats", "--no-stream", "--format", "{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}", name, timeout=60)
    cpu, mem, net = (out.split("|") + [""] * 3)[:3]; return {"cpu": cpu, "mem": mem, "net": net}
async def set_password(name: str, password: str) -> None:
    await _docker("exec", name, "bash", "-c", 'echo "$1" > /etc/alooz_pw && chmod 600 /etc/alooz_pw && echo "root:$1" | chpasswd', "_", password, timeout=60)
async def update_limits(name: str, ram_mb: int, cpu: float) -> None:
    cpu_shares = int(cpu * 1024)
    await _docker("update", "--memory", f"{ram_mb}m", "--memory-reservation", f"{ram_mb}m", "--memory-swap", f"{ram_mb}m", "--cpus", f"{cpu:g}", "--cpu-shares", str(cpu_shares), name, timeout=60)
async def start_sshx_and_get_url(container_name: str) -> str:
    await _run("docker", "exec", container_name, "pkill", "-f", "sshx", timeout=10)
    await asyncio.sleep(2)
    await _run("docker", "exec", "-d", container_name, "bash", "-c", "nohup sshx > /tmp/sshx.log 2>&1 &", timeout=10)
    url_pattern = re.compile(r'https://sshx\.io/s/[a-zA-Z0-9]+#[a-zA-Z0-9]+')
    for _ in range(15):
        code, out, _ = await _run("docker", "exec", container_name, "cat", "/tmp/sshx.log", timeout=5)
        if code == 0:
            match = url_pattern.search(out)
            if match: return match.group(0)
        await asyncio.sleep(2)
    raise DockerError("Could not generate SSHX URL.")
async def create_mc_container(name: str, mc_version: str, server_type: str, ram_mb: int, cpu: float, disk_gb: int, port: int, rcon_port: int, rcon_password: str, use_disk_limit: bool = False) -> str:
    cpu_shares = int(cpu * 1024)
    args = ["run", "-d", "--name", name, "--hostname", name, "--restart", "unless-stopped", "--memory", f"{ram_mb}m", "--memory-reservation", f"{ram_mb}m", "--memory-swap", f"{ram_mb + 512}m", "--cpus", f"{cpu:g}", "--cpu-shares", str(cpu_shares), "--pids-limit", "2048", "-p", f"{port}:25565", "-p", f"{rcon_port}:25575", "-e", f"MC_VERSION={mc_version}", "-e", f"MC_TYPE={server_type}", "-e", f"MC_RAM={ram_mb}", "-e", f"MC_RCON_PW={rcon_password}", "-v", f"{name}-data:/data", "--label", "alooz.mc=1"]
    if use_disk_limit: args += ["--storage-opt", f"size={disk_gb}g"]
    args += ["eclipse-temurin:17-jre", "bash", "-c", MC_BOOT_SCRIPT]
    return await _docker(*args, timeout=900)
async def mc_send_command(name: str, rcon_password: str, command: str) -> str:
    return await _docker("exec", name, "bash", "-c", f"command -v mcrcon >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq mcrcon >/dev/null); mcrcon -p '{rcon_password}' '{command}'", timeout=30)
def host_stats() -> Dict[str, float]:
    stats: Dict[str, float] = {"cpus": float(os.cpu_count() or 1)}
    try: stats["load1"], stats["load5"], stats["load15"] = os.getloadavg()
    except (OSError, AttributeError): stats["load1"] = stats["load5"] = stats["load15"] = 0.0
    try:
        meminfo = {}
        with open("/proc/meminfo") as fh:
            for line in fh: key, value = line.split(":", 1); meminfo[key] = int(value.split()[0])
        stats["ram_total_mb"] = meminfo["MemTotal"] / 1024; stats["ram_avail_mb"] = meminfo.get("MemAvailable", meminfo.get("MemFree", 0)) / 1024
    except (OSError, KeyError, ValueError): stats["ram_total_mb"] = stats["ram_avail_mb"] = 0.0
    usage = shutil.disk_usage("/"); stats["disk_total_gb"] = usage.total / 1024 ** 3; stats["disk_free_gb"] = usage.free / 1024 ** 3
    return stats
__ALOOZ_EOF__

  # ===================== bot.py (58 commands) =====================
  cat > "$INSTALL_DIR/bot.py" <<'__ALOOZ_EOF__'
import asyncio, logging, sqlite3, os, datetime
from typing import Optional
import discord
from discord import app_commands
from discord.ext import commands, tasks
import config, docker_utils as dk
from database import Database

log = logging.getLogger("alooz")
db = Database(config.DB_PATH)
STATUS_EMOJI = {"running": "🟢", "exited": "🔴", "created": "🟡", "restarting": "🟡", "paused": "🟠", "missing": "⚫"}

INVITE_TIERS = [(32,24576,30,6.0),(28,20480,30,5.0),(24,16384,25,4.0),(20,12288,20,3.5),(16,10240,15,3.0),(14,8192,13,2.5),(9,6144,10,2.0),(5,4096,10,1.5),(3,2048,10,1.0)]
COIN_TIERS = [(2300,24576,30,6.0),(1500,16384,30,5.0),(1100,12288,25,4.0),(900,10240,20,3.5),(700,8192,20,3.0),(500,6144,15,2.5),(300,4096,10,1.5)]

def is_owner(uid): return config.OWNER_ID != 0 and uid == config.OWNER_ID
def is_admin(uid): return is_owner(uid) or uid in config.ADMIN_IDS or db.is_admin(uid)
def admin_only():
    async def predicate(interaction):
        if is_admin(interaction.user.id): return True
        raise app_commands.CheckFailure("Admin only.")
    return app_commands.check(predicate)
def owner_only():
    async def predicate(interaction):
        if is_owner(interaction.user.id): return True
        raise app_commands.CheckFailure("Owner only.")
    return app_commands.check(predicate)
def short(e, l=300): return str(e)[:l]
async def reply(i, c=None, **kw):
    kw.setdefault("ephemeral", True)
    if i.response.is_done(): await i.followup.send(c, **kw)
    else: await i.response.send_message(c, **kw)
async def get_vps(i, vid):
    r = db.get_vps(vid)
    if not r or (r["owner_id"] != i.user.id and not is_admin(i.user.id)): await reply(i, f"VPS #{vid} not found."); return None
    return r
async def get_mc(i, mid):
    r = db.get_mc(mid)
    if not r or (r["owner_id"] != i.user.id and not is_admin(i.user.id)): await reply(i, f"MC #{mid} not found."); return None
    return r
def pick_port(used, s, e):
    for p in range(s, e+1):
        if p not in used and dk.port_is_free(p): return p
    return None
async def send_log(g, t):
    cid = db.get_setting("log_channel")
    if cid:
        ch = g.get_channel(int(cid))
        if ch: await ch.send(t)
async def send_user_log(g, t):
    cid = db.get_setting("user_channel")
    if cid:
        ch = g.get_channel(int(cid))
        if ch: await ch.send(t)

def vps_embed(r, st, show_pw=False, stats=None):
    e = discord.Embed(title=f"{config.BOT_NAME} • {r['name']} (#{r['id']})", color=discord.Color.green() if st=="running" else discord.Color.red())
    exp = datetime.datetime.fromtimestamp(r['expires_at']).strftime('%Y-%m-%d') if r['expires_at'] else 'Never'
    e.add_field(name="Status", value=f"{STATUS_EMOJI.get(st,'⚫')} {st}{' ⛔' if r['suspended'] else ''}")
    e.add_field(name="Expires", value=exp)
    e.add_field(name="RAM", value=f"{r['ram_mb']} MB")
    e.add_field(name="CPU", value=f"{r['cpu']:g}")
    e.add_field(name="Disk", value=f"{r['disk_gb']} GB")
    e.add_field(name="SSH", value=f"`ssh root@{config.SERVER_IP} -p {r['ssh_port']}`", inline=False)
    if show_pw: e.add_field(name="Password", value=f"||{r['root_password']}||", inline=False)
    if stats: e.add_field(name="Stats", value=f"CPU: {stats['cpu']}\nRAM: {stats['mem']}", inline=False)
    return e

def mc_embed(r, st, show_rcon=False):
    e = discord.Embed(title=f"⛏️ {r['name']} (#{r['id']})", color=discord.Color.green() if st=="running" else discord.Color.red())
    exp = datetime.datetime.fromtimestamp(r['expires_at']).strftime('%Y-%m-%d') if r['expires_at'] else 'Never'
    e.add_field(name="Status", value=f"{STATUS_EMOJI.get(st,'⚫')} {st}")
    e.add_field(name="Expires", value=exp)
    e.add_field(name="Type", value=r["server_type"].capitalize())
    e.add_field(name="Version", value=r["mc_version"])
    e.add_field(name="RAM", value=f"{r['ram_mb']} MB")
    e.add_field(name="IP", value=f"`{config.SERVER_IP}:{r['port']}`", inline=False)
    if show_rcon: e.add_field(name="RCON", value=f"||{r['rcon_password']}||", inline=False)
    return e

class ConfirmView(discord.ui.View):
    def __init__(self, uid):
        super().__init__(timeout=30); self.uid = uid; self.value = None
    async def interaction_check(self, i):
        if i.user.id != self.uid: await i.response.send_message("Not for you.", ephemeral=True); return False
        return True
    @discord.ui.button(label="Confirm", style=discord.ButtonStyle.danger)
    async def confirm(self, i, b): self.value = True; await i.response.edit_message(content="Working...", view=None); self.stop()
    @discord.ui.button(label="Cancel", style=discord.ButtonStyle.secondary)
    async def cancel(self, i, b): self.value = False; await i.response.edit_message(content="Cancelled.", view=None); self.stop()

class AloozBot(commands.Bot):
    def __init__(self): super().__init__(command_prefix="-", intents=discord.Intents.all())
    async def setup_hook(self):
        await self.tree.sync(); self.cleanup_task.start()
    async def on_ready(self):
        log.info(f"Logged in as {self.user} ({self.user.id})")
        await self.change_presence(activity=discord.Activity(type=discord.ActivityType.watching, name=f"{config.BOT_NAME} | 58 commands"))
    @tasks.loop(minutes=30)
    async def cleanup_task(self):
        vps, mc = db.get_expired_servers()
        for v in vps: await dk.remove(v["container"]); db.delete_vps(v["id"])
        for m in mc: await dk.remove(m["container"]); db.delete_mc(m["id"])

bot = AloozBot()

@bot.tree.error
async def on_app_command_error(i, e):
    if isinstance(e, app_commands.CheckFailure): m = str(e) or "Not allowed."
    else: log.exception("Error", exc_info=e); m = "Something went wrong."
    try: await reply(i, m)
    except: pass

@bot.event
async def on_message(m):
    if m.author.bot or not m.guild: return
    count = db.log_message(m.author.id)
    if count % 5 == 0: db.add_coins(m.author.id, 1, "Chat Reward")
    await bot.process_commands(m)

@bot.event
async def on_member_join(m):
    if m.bot: return
    if (datetime.datetime.now(datetime.timezone.utc) - m.created_at).days < 90: return
    ib = {i.code: i.uses for i in await m.guild.invites()}
    await asyncio.sleep(2)
    ia = await m.guild.invites()
    inviter = None
    for inv in ia:
        if ib.get(inv.code, 0) < inv.uses: inviter = inv.inviter; break
    if inviter:
        db.add_invite(inviter.id, 1); db.log_join(m.id, inviter.id)
        try: await inviter.send(f"✅ **{m.name}** joined! Total: `{db.get_invites(inviter.id)}`")
        except: pass
        await send_log(m.guild, f"📥 {m.name} joined via {inviter.name}")

@bot.event
async def on_member_remove(m):
    if m.bot: return
    iid = db.get_inviter(m.id)
    if iid: db.remove_invite(iid); db.remove_join_log(m.id)

# ============ PREFIX COMMANDS (8) ============
@bot.command(name="i")
async def p_i(ctx): await ctx.send(f"📊 **{ctx.author.name}**, invites: **{db.get_invites(ctx.author.id)}**")
@bot.command(name="cash")
async def p_cash(ctx): await ctx.send(f"🪙 **{ctx.author.name}**, coins: **{db.get_coins(ctx.author.id)}**")
@bot.command(name="shop")
async def p_shop(ctx):
    e = discord.Embed(title="🎁 Coin Shop", color=discord.Color.gold())
    for c,r,d,cp in COIN_TIERS: e.add_field(name=f"🪙 {c} Coins", value=f"➜ 💾 {r}MB RAM", inline=False)
    await ctx.send(embed=e)
@bot.command(name="buy")
async def p_buy(ctx, coins: int, type: str):
    await handle_buy(ctx, coins, type, True)
@bot.command(name="give")
async def p_give(ctx, member: discord.Member, amount: int):
    if amount <= 0: return await ctx.send("❌ Positive amount required.")
    if db.get_coins(ctx.author.id) < amount: return await ctx.send("❌ Not enough coins.")
    db.remove_coins(ctx.author.id, amount); db.add_coins(member.id, amount, f"From {ctx.author.name}")
    await ctx.send(f"✅ Sent **{amount}** to {member.mention}")
@bot.command(name="vps")
async def p_vps(ctx):
    rs = db.list_vps_by_owner(ctx.author.id)
    if not rs: return await ctx.send("No VPS.")
    await ctx.send(embed=vps_embed(rs[0], await dk.container_status(rs[0]["container"])))
@bot.command(name="mc")
async def p_mc(ctx):
    rs = db.list_mc_by_owner(ctx.author.id)
    if not rs: return await ctx.send("No MC.")
    await ctx.send(embed=mc_embed(rs[0], await dk.container_status(rs[0]["container"])))
@bot.command(name="help")
async def p_help(ctx):
    e = discord.Embed(title="Help", color=discord.Color.blurple())
    e.add_field(name="Prefix", value="`-i -cash -shop -buy -give -vps -mc -help`", inline=False)
    await ctx.send(embed=e)

async def handle_buy(x, coins, ts, pref):
    ts = ts.lower()
    if ts not in ("vps", "mc"): return await (x.send("Use vps or mc") if pref else x.response.send_message("Use vps or mc", ephemeral=True))
    bt = None
    for req, r, d, c in COIN_TIERS:
        if coins >= req: bt = (req, r, d, c); break
    if not bt: return await (x.send("Not enough coins.") if pref else x.response.send_message("Not enough coins.", ephemeral=True))
    req, r, d, c = bt
    u = x.author if pref else x.user
    if db.get_coins(u.id) < req: return await (x.send("Not enough coins.") if pref else x.response.send_message("Not enough coins.", ephemeral=True))
    if not pref: await x.response.defer(ephemeral=True)
    db.remove_coins(u.id, req)
    await (x.send(f"✅ Bought {ts} with {req} coins!") if pref else x.followup.send(f"✅ Bought {ts} with {req} coins!", ephemeral=True))

# ============ USER SLASH (21) ============
@bot.tree.command(name="invites", description="Check invites")
async def s_inv(i):
    await i.response.send_message(f"📊 {db.get_invites(i.user.id)} invites", ephemeral=True)

@bot.tree.command(name="invites-plan", description="Invite plan")
async def s_invp(i):
    e = discord.Embed(title="Invite Plan", color=discord.Color.gold())
    for inv, r, d, c in reversed(INVITE_TIERS): e.add_field(name=f"{inv} Invites", value=f"{r}MB / {d}GB / {c}x", inline=False)
    await i.response.send_message(embed=e, ephemeral=True)

@bot.tree.command(name="invite-claim", description="Claim server")
@app_commands.choices(type=[app_commands.Choice(name="VPS", value="vps"), app_commands.Choice(name="MC", value="mc")])
async def s_ic(i, type: app_commands.Choice[str]):
    await i.response.send_message(f"✅ Claimed {type.name}!", ephemeral=True)

@bot.tree.command(name="renew", description="Renew server")
@app_commands.choices(type=[app_commands.Choice(name="VPS", value="vps"), app_commands.Choice(name="MC", value="mc")])
async def s_ren(i, type: app_commands.Choice[str], server_id: int):
    if db.get_invites(i.user.id) < 2: return await i.response.send_message("❌ Need 2 invites.", ephemeral=True)
    db.remove_invite(i.user.id, 2); db.renew_server(type.value, server_id)
    await i.response.send_message(f"✅ Renewed {type.name}", ephemeral=True)

@bot.tree.command(name="cash", description="Show coins")
async def s_cash(i): await i.response.send_message(f"🪙 {db.get_coins(i.user.id)} coins", ephemeral=True)

@bot.tree.command(name="shop", description="Coin shop")
async def s_shop(i):
    e = discord.Embed(title="Coin Shop", color=discord.Color.gold())
    for c,r,d,cp in COIN_TIERS: e.add_field(name=f"🪙 {c}", value=f"{r}MB RAM", inline=False)
    await i.response.send_message(embed=e, ephemeral=True)

@bot.tree.command(name="buy", description="Buy server")
@app_commands.choices(type=[app_commands.Choice(name="VPS", value="vps"), app_commands.Choice(name="MC", value="mc")])
async def s_buy(i, coins: int, type: app_commands.Choice[str]):
    await handle_buy(i, coins, type.value, False)

@bot.tree.command(name="give", description="Give coins")
async def s_give(i, member: discord.Member, amount: int):
    if amount <= 0: return await i.response.send_message("❌ Positive only.", ephemeral=True)
    if db.get_coins(i.user.id) < amount: return await i.response.send_message("❌ Not enough.", ephemeral=True)
    db.remove_coins(i.user.id, amount); db.add_coins(member.id, amount, f"From {i.user.name}")
    await i.response.send_message(f"✅ Sent {amount} to {member.mention}", ephemeral=True)

@bot.tree.command(name="myvps", description="My VPS")
async def s_myv(i):
    await i.response.defer(ephemeral=True)
    rs = db.list_vps_by_owner(i.user.id)
    if not rs: return await i.followup.send("No VPS.", ephemeral=True)
    for r in rs[:5]:
        await i.followup.send(embed=vps_embed(r, await dk.container_status(r["container"])), ephemeral=True)

@bot.tree.command(name="myserver", description="My MC")
async def s_mys(i):
    await i.response.defer(ephemeral=True)
    rs = db.list_mc_by_owner(i.user.id)
    if not rs: return await i.followup.send("No MC.", ephemeral=True)
    for r in rs[:5]:
        await i.followup.send(embed=mc_embed(r, await dk.container_status(r["container"])), ephemeral=True)

@bot.tree.command(name="ssh", description="SSHX link")
async def s_ssh(i, vps_id: int):
    r = await get_vps(i, vps_id)
    if not r: return
    await i.response.defer(ephemeral=True)
    st = await dk.container_status(r["container"])
    if st != "running": return await i.followup.send("VPS not running.", ephemeral=True)
    url = await dk.start_sshx_and_get_url(r["container"])
    e = vps_embed(r, st, True); e.add_field(name="🌐 Terminal", value=f"[Click]({url})")
    await i.followup.send(embed=e, ephemeral=True)

@bot.tree.command(name="resshx", description="New SSHX link")
async def s_resh(i, vps_id: int):
    r = await get_vps(i, vps_id)
    if not r: return
    await i.response.defer(ephemeral=True)
    try: url = await dk.start_sshx_and_get_url(r["container"]); await i.followup.send(f"[Click]({url})", ephemeral=True)
    except Exception as e: await i.followup.send(f"Failed: {short(e)}", ephemeral=True)

@bot.tree.command(name="reinstall-os", description="Reinstall OS")
@app_commands.choices(os=[app_commands.Choice(name="Ubuntu 22.04", value="ubuntu:22.04"), app_commands.Choice(name="Ubuntu 24.04", value="ubuntu:24.04"), app_commands.Choice(name="Debian 12", value="debian:12")])
async def s_reos(i, vps_id: int, os: app_commands.Choice[str]):
    r = await get_vps(i, vps_id)
    if not r: return
    await i.response.defer(ephemeral=True)
    await dk.remove(r["container"])
    np = dk.generate_password()
    db.update_vps(vps_id, os_image=os.value, root_password=np)
    await dk.create_vps_container(r["container"], os.value, r["ram_mb"], r["cpu"], r["disk_gb"], r["ssh_port"], np, config.USE_DISK_LIMIT)
    await i.followup.send(f"✅ Reinstalled. New password: ||{np}||", ephemeral=True)

@bot.tree.command(name="vps-rename", description="Rename VPS")
async def s_vrn(i, vps_id: int, name: str):
    r = await get_vps(i, vps_id)
    if not r: return
    db.update_vps(vps_id, name=name[:32])
    await i.response.send_message(f"✅ Renamed to {name}", ephemeral=True)

@bot.tree.command(name="vps-upgrade", description="Upgrade VPS")
async def s_vup(i, vps_id: int, add_ram: int, add_cpu: float):
    r = await get_vps(i, vps_id)
    if not r: return
    await i.response.defer(ephemeral=True)
    await dk.update_limits(r["container"], r["ram_mb"]+add_ram, r["cpu"]+add_cpu)
    db.update_vps(vps_id, ram_mb=r["ram_mb"]+add_ram, cpu=r["cpu"]+add_cpu)
    await i.followup.send(f"✅ Upgraded", ephemeral=True)

@bot.tree.command(name="vps-stats", description="VPS stats")
async def s_vst(i, vps_id: int):
    r = await get_vps(i, vps_id)
    if not r: return
    st = await dk.container_status(r["container"])
    if st != "running": return await i.response.send_message("Not running.", ephemeral=True)
    s = await dk.container_stats(r["container"])
    await i.response.send_message(f"CPU: {s['cpu']}\nRAM: {s['mem']}", ephemeral=True)

@bot.tree.command(name="mc-start", description="Start MC")
async def s_mcst(i, mc_id: int):
    r = await get_mc(i, mc_id)
    if not r: return
    await dk.power(r["container"], "start")
    await i.response.send_message(f"✅ Started `{config.SERVER_IP}:{r['port']}`", ephemeral=True)

@bot.tree.command(name="mc-stop", description="Stop MC")
async def s_mcsp(i, mc_id: int):
    r = await get_mc(i, mc_id)
    if not r: return
    await dk.power(r["container"], "stop")
    await i.response.send_message("✅ Stopped", ephemeral=True)

@bot.tree.command(name="mc-restart", description="Restart MC")
async def s_mcrs(i, mc_id: int):
    r = await get_mc(i, mc_id)
    if not r: return
    await dk.power(r["container"], "restart")
    await i.response.send_message("✅ Restarted", ephemeral=True)

@bot.tree.command(name="mc-console", description="RCON")
async def s_mcc(i, mc_id: int, command: str):
    r = await get_mc(i, mc_id)
    if not r: return
    out = await dk.mc_send_command(r["container"], r["rcon_password"], command)
    await i.response.send_message(f"```\n{out[:1500]}\n```", ephemeral=True)

@bot.tree.command(name="help", description="Help")
async def s_help(i):
    e = discord.Embed(title="Help - 58 Commands", color=discord.Color.blurple())
    e.add_field(name="Prefix", value="`-i -cash -shop -buy -give -vps -mc -help`", inline=False)
    e.add_field(name="User Slash", value="`/invites /invites-plan /invite-claim /renew /cash /shop /buy /give /myvps /myserver /ssh /resshx /reinstall-os /vps-rename /vps-upgrade /vps-stats /mc-start /mc-stop /mc-restart /mc-console /help`", inline=False)
    if is_admin(i.user.id): e.add_field(name="Admin", value="`/deploy /create-mc /delete-vps /delete-mc /suspend-vps /unsuspend-vps /suspend-mc /unsuspend-mc /resize-vps /resize-mc /add-coins /remove-coins /reset-coins /coins-log /coins-leaderboard /add-invites /remove-invites /reset-invites`", inline=False)
    if is_owner(i.user.id): e.add_field(name="Owner", value="`/reset-all-coins /reset-all-invites /invites-leaderboard /log-channel /user-channel /add-admin /remove-admin /admin-list /node-stats /backup-db /broadcast`", inline=False)
    await i.response.send_message(embed=e, ephemeral=True)

# ============ ADMIN (18) ============
@bot.tree.command(name="deploy", description="[Admin] Deploy VPS")
@admin_only()
async def a_dep(i, member: discord.Member, ram_mb: int, cpu: float, disk_gb: int):
    await i.response.defer(ephemeral=True)
    port = pick_port(db.used_vps_ports(), config.PORT_START, config.PORT_END)
    if not port: return await i.followup.send("No ports.", ephemeral=True)
    vid = db.add_vps(member.id, ram_mb, cpu, disk_gb, port, dk.generate_password(), "ubuntu:22.04", config.SERVER_IP)
    r = db.get_vps(vid)
    await dk.create_vps_container(r["container"], "ubuntu:22.04", ram_mb, cpu, disk_gb, port, r["root_password"], config.USE_DISK_LIMIT)
    await i.followup.send(f"✅ VPS #{vid} for {member.mention}", ephemeral=True)
    await send_log(i.guild, f"🖥️ VPS #{vid} deployed for {member.mention}")

@bot.tree.command(name="create-mc", description="[Admin] Create MC")
@admin_only()
async def a_cmc(i, member: discord.Member, name: str, ram_mb: int, cpu: float, disk_gb: int):
    await i.response.defer(ephemeral=True)
    port = pick_port(db.used_mc_ports(), config.MC_PORT_START, config.MC_PORT_END)
    if not port: return await i.followup.send("No ports.", ephemeral=True)
    rp = dk.generate_password()
    mid = db.add_mc(member.id, name[:32], "1.20.1", "paper", ram_mb, cpu, disk_gb, port, port+1, rp, config.SERVER_IP)
    r = db.get_mc(mid)
    await dk.create_mc_container(r["container"], "1.20.1", "paper", ram_mb, cpu, disk_gb, port, port+1, rp, config.USE_DISK_LIMIT)
    await i.followup.send(f"✅ MC #{mid} for {member.mention}", ephemeral=True)

@bot.tree.command(name="delete-vps", description="[Admin] Delete VPS")
@admin_only()
async def a_dv(i, vps_id: int):
    r = db.get_vps(vps_id)
    if not r: return await i.response.send_message("Not found.", ephemeral=True)
    await dk.remove(r["container"]); db.delete_vps(vps_id)
    await i.response.send_message(f"✅ Deleted VPS #{vps_id}", ephemeral=True)

@bot.tree.command(name="delete-mc", description="[Admin] Delete MC")
@admin_only()
async def a_dm(i, mc_id: int):
    r = db.get_mc(mc_id)
    if not r: return await i.response.send_message("Not found.", ephemeral=True)
    await dk.remove(r["container"]); db.delete_mc(mc_id)
    await i.response.send_message(f"✅ Deleted MC #{mc_id}", ephemeral=True)

@bot.tree.command(name="suspend-vps", description="[Admin] Suspend VPS")
@admin_only()
async def a_sv(i, vps_id: int):
    r = db.get_vps(vps_id)
    if not r: return await i.response.send_message("Not found.", ephemeral=True)
    db.update_vps(vps_id, suspended=1); await dk.power(r["container"], "stop")
    await i.response.send_message(f"✅ Suspended", ephemeral=True)

@bot.tree.command(name="unsuspend-vps", description="[Admin] Unsuspend VPS")
@admin_only()
async def a_uv(i, vps_id: int):
    r = db.get_vps(vps_id)
    if not r: return await i.response.send_message("Not found.", ephemeral=True)
    db.update_vps(vps_id, suspended=0); await dk.power(r["container"], "start")
    await i.response.send_message(f"✅ Unsuspended", ephemeral=True)

@bot.tree.command(name="suspend-mc", description="[Admin] Suspend MC")
@admin_only()
async def a_smc(i, mc_id: int):
    r = db.get_mc(mc_id)
    if not r: return await i.response.send_message("Not found.", ephemeral=True)
    db.update_mc(mc_id, suspended=1); await dk.power(r["container"], "stop")
    await i.response.send_message(f"✅ Suspended", ephemeral=True)

@bot.tree.command(name="unsuspend-mc", description="[Admin] Unsuspend MC")
@admin_only()
async def a_umc(i, mc_id: int):
    r = db.get_mc(mc_id)
    if not r: return await i.response.send_message("Not found.", ephemeral=True)
    db.update_mc(mc_id, suspended=0); await dk.power(r["container"], "start")
    await i.response.send_message(f"✅ Unsuspended", ephemeral=True)

@bot.tree.command(name="resize-vps", description="[Admin] Resize VPS")
@admin_only()
async def a_rv(i, vps_id: int, ram_mb: int, cpu: float):
    r = db.get_vps(vps_id)
    if not r: return await i.response.send_message("Not found.", ephemeral=True)
    await dk.update_limits(r["container"], ram_mb, cpu)
    db.update_vps(vps_id, ram_mb=ram_mb, cpu=cpu)
    await i.response.send_message("✅ Resized", ephemeral=True)

@bot.tree.command(name="resize-mc", description="[Admin] Resize MC")
@admin_only()
async def a_rmc(i, mc_id: int, ram_mb: int, cpu: float):
    r = db.get_mc(mc_id)
    if not r: return await i.response.send_message("Not found.", ephemeral=True)
    await dk.update_limits(r["container"], ram_mb, cpu)
    db.update_mc(mc_id, ram_mb=ram_mb, cpu=cpu)
    await i.response.send_message("✅ Resized", ephemeral=True)

@bot.tree.command(name="add-coins", description="[Admin] Add coins")
@admin_only()
async def a_ac(i, member: discord.Member, amount: int):
    db.add_coins(member.id, amount, f"Admin: {i.user.name}")
    await i.response.send_message(f"✅ Added {amount}", ephemeral=True)

@bot.tree.command(name="remove-coins", description="[Admin] Remove coins")
@admin_only()
async def a_rc(i, member: discord.Member, amount: int):
    db.remove_coins(member.id, amount)
    await i.response.send_message(f"✅ Removed {amount}", ephemeral=True)

@bot.tree.command(name="reset-coins", description="[Admin] Reset coins")
@admin_only()
async def a_rstc(i, member: discord.Member):
    db.remove_coins(member.id, db.get_coins(member.id))
    await i.response.send_message(f"✅ Reset", ephemeral=True)

@bot.tree.command(name="coins-log", description="[Admin] Coin logs")
@admin_only()
async def a_cl(i):
    logs = db.get_coins_logs()
    t = "\n".join(f"<@{l['user_id']}>: {l['amount']} ({l['reason']})" for l in logs) or "None"
    await i.response.send_message(embed=discord.Embed(title="Coin Logs", description=t), ephemeral=True)

@bot.tree.command(name="coins-leaderboard", description="Top coins")
async def a_clb(i):
    top = db.get_top_coins()
    t = "\n".join(f"#{n+1} <@{r['user_id']}>: {r['total']}" for n, r in enumerate(top)) or "None"
    await i.response.send_message(embed=discord.Embed(title="🏆 Coins", description=t), ephemeral=True)

@bot.tree.command(name="add-invites", description="[Admin] Add invites")
@admin_only()
async def a_ai(i, member: discord.Member, amount: int):
    db.add_invite(member.id, amount)
    await i.response.send_message(f"✅ Added {amount}", ephemeral=True)

@bot.tree.command(name="remove-invites", description="[Admin] Remove invites")
@admin_only()
async def a_ri(i, member: discord.Member, amount: int):
    db.remove_invite(member.id, amount)
    await i.response.send_message(f"✅ Removed {amount}", ephemeral=True)

@bot.tree.command(name="reset-invites", description="[Admin] Reset invites")
@admin_only()
async def a_rsti(i, member: discord.Member):
    db.remove_invite(member.id, db.get_invites(member.id))
    await i.response.send_message(f"✅ Reset", ephemeral=True)

# ============ OWNER (11) ============
@bot.tree.command(name="reset-all-coins", description="[Owner] Reset all coins")
@owner_only()
async def o_rac(i):
    db.reset_all_coins()
    await i.response.send_message("⚠️ All coins reset.", ephemeral=True)

@bot.tree.command(name="reset-all-invites", description="[Owner] Reset all invites")
@owner_only()
async def o_rai(i):
    db.reset_all_invites()
    await i.response.send_message("⚠️ All invites reset.", ephemeral=True)

@bot.tree.command(name="invites-leaderboard", description="Top inviters")
async def o_ilb(i):
    top = db.get_top_inviters()
    t = "\n".join(f"#{n+1} <@{r['user_id']}>: {r['total']}" for n, r in enumerate(top)) or "None"
    await i.response.send_message(embed=discord.Embed(title="🏆 Invites", description=t), ephemeral=True)

@bot.tree.command(name="log-channel", description="[Owner] Set log channel")
@owner_only()
async def o_lc(i, channel: discord.TextChannel):
    db.set_setting("log_channel", str(channel.id))
    await i.response.send_message(f"✅ Set to {channel.mention}", ephemeral=True)

@bot.tree.command(name="user-channel", description="[Owner] Set user channel")
@owner_only()
async def o_uc(i, channel: discord.TextChannel):
    db.set_setting("user_channel", str(channel.id))
    await i.response.send_message(f"✅ Set to {channel.mention}", ephemeral=True)

@bot.tree.command(name="add-admin", description="[Owner] Add admin")
@owner_only()
async def o_aa(i, member: discord.Member):
    db.add_admin(member.id, i.user.id)
    await i.response.send_message(f"✅ {member.mention} is admin", ephemeral=True)

@bot.tree.command(name="remove-admin", description="[Owner] Remove admin")
@owner_only()
async def o_ra(i, member: discord.Member):
    db.remove_admin(member.id)
    await i.response.send_message(f"✅ {member.mention} removed", ephemeral=True)

@bot.tree.command(name="admin-list", description="List admins")
async def o_al(i):
    ids = [config.OWNER_ID] + list(config.ADMIN_IDS) + db.list_admins()
    t = "\n".join(f"<@{x}>" for x in set(ids)) or "None"
    await i.response.send_message(embed=discord.Embed(title="Admins", description=t), ephemeral=True)

@bot.tree.command(name="node-stats", description="Host stats")
async def o_ns(i):
    h = dk.host_stats()
    e = discord.Embed(title="Node Stats", color=discord.Color.blurple())
    e.add_field(name="CPU", value=f"{h['cpus']:.0f} cores, load: {h['load1']:.2f}")
    e.add_field(name="RAM", value=f"{h['ram_total_mb']-h['ram_avail_mb']:.0f}/{h['ram_total_mb']:.0f} MB")
    e.add_field(name="Disk", value=f"{h['disk_total_gb']-h['disk_free_gb']:.1f}/{h['disk_total_gb']:.1f} GB")
    await i.response.send_message(embed=e, ephemeral=True)

@bot.tree.command(name="backup-db", description="[Owner] Backup DB")
@owner_only()
async def o_bdb(i):
    path = config.DB_PATH
    if not os.path.exists(path): return await i.response.send_message("DB not found.", ephemeral=True)
    await i.response.send_message(file=discord.File(path, "backup.db"), ephemeral=True)

@bot.tree.command(name="broadcast", description="[Owner] Broadcast")
@owner_only()
async def o_bc(i, message: str):
    await i.response.defer(ephemeral=True)
    sent = 0
    for g in bot.guilds:
        for ch in g.text_channels:
            try: await ch.send(message); sent += 1; break
            except: continue
    await i.followup.send(f"✅ Sent to {sent} servers", ephemeral=True)
__ALOOZ_EOF__

  cat > "$INSTALL_DIR/requirements.txt" <<'__ALOOZ_EOF__'
discord.py>=2.3.2
python-dotenv>=1.0.0
__ALOOZ_EOF__

  say "Setting up Python..."
  python3 -m venv "$INSTALL_DIR/venv" >/dev/null 2>&1 || die "venv failed"
  PY="$INSTALL_DIR/venv/bin/python"
  "$INSTALL_DIR/venv/bin/pip" install -q -r "$INSTALL_DIR/requirements.txt" || die "pip failed"

  cat > "$SYSTEMD_DIR/$SERVICE.service" <<EOF
[Unit]
Description=ALOOZ HOSTING Bot
After=network-online.target docker.service
Wants=network-online.target docker.service

[Service]
Type=simple
WorkingDirectory=$INSTALL_DIR
ExecStart=$PY main.py
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF
  systemctl daemon-reload
  systemctl enable "$SERVICE" >/dev/null 2>&1 || true
}

menu_bot_status() {
  say "--- Bot Status ---"
  systemctl is-active --quiet "$SERVICE" && echo -e "Bot: \033[1;32mRUNNING\033[0m" || echo -e "Bot: \033[1;31mSTOPPED\033[0m"
  systemctl is-active --quiet docker && echo -e "Docker: \033[1;32mRUNNING\033[0m" || echo -e "Docker: \033[1;31mSTOPPED\033[0m"
  echo "CPU: $(uptime | awk -F'load average:' '{ print $2 }')"
  echo "RAM: $(free -h | awk '/^Mem:/ {print $3 "/" $2}')"
  echo "Disk: $(df -h / | awk 'NR==2 {print $3 "/" $2}')"
  echo -e "\nContainers:"
  docker ps --format "table {{.Names}}\t{{.Status}}" | grep alooz || echo "None"
}

menu_update() {
  say "Updating system..."
  apt-get -y update && apt-get -y upgrade
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
}

menu_logs() { journalctl -u "$SERVICE" -f -n 50; }

menu_delete() {
  local c=""; ask c "Type YES to delete everything"
  [ "$c" != "YES" ] && return
  docker ps -a --filter "label=alooz.vps=1" -q | xargs -r docker rm -f >/dev/null 2>&1 || true
  docker ps -a --filter "label=alooz.mc=1" -q | xargs -r docker rm -f >/dev/null 2>&1 || true
  systemctl stop "$SERVICE" >/dev/null 2>&1 || true
  rm -rf "$INSTALL_DIR"
  systemctl disable "$SERVICE" >/dev/null 2>&1 || true
  rm -f "$SYSTEMD_DIR/$SERVICE.service"
  systemctl daemon-reload
  exit 0
}

main_menu() {
  while true; do
    echo -e "\033[1;36m=========================================\033[0m"
    echo -e "\033[1;32m    ALOOZ HOSTING - V104 (58 COMMANDS)   \033[0m"
    echo -e "\033[1;36m=========================================\033[0m"
    echo -e "  \033[1;33m1.\033[0m Set Token & Owner ID"
    echo -e "  \033[1;33m2.\033[0m Restart Bot"
    echo -e "  \033[1;33m3.\033[0m View Live Logs"
    echo -e "  \033[1;33m4.\033[0m Bot Status & Resources"
    echo -e "  \033[1;33m5.\033[0m Full System Update"
    echo -e "  \033[1;33m6.\033[0m Reinstall Bot"
    echo -e "  \033[1;31m7. Delete All (Danger)\033[0m"
    echo -e "  \033[1;33m8.\033[0m Exit"
    local c=""; ask c "Choice [1-8]"
    case "$c" in
      1) set_token_interactive; set_owner_interactive ;;
      2) systemctl restart alooz-bot; say "Restarted." ;;
      3) menu_logs ;;
      4) menu_bot_status ;;
      5) menu_update ;;
      6) systemctl stop alooz-bot; install_system; systemctl restart alooz-bot ;;
      7) menu_delete ;;
      8) exit 0 ;;
    esac
    echo ""; ask _ "Press Enter..."
  done
}

show_banner
if [ ! -f "$SYSTEMD_DIR/$SERVICE.service" ]; then
  install_system
  set_token_interactive
  set_owner_interactive
  systemctl restart alooz-bot
fi
main_menu