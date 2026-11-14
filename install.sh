#!/usr/bin/env bash
# ALOOZ HOSTING V101 - VPS + Minecraft Hosting + Advanced Invite System
set -Eeuo pipefail

INSTALL_DIR="${INSTALL_DIR:-/opt/alooz-bot}"
SYSTEMD_DIR="${SYSTEMD_DIR:-/etc/systemd/system}"
SERVICE="alooz-bot"
PORT_START=20000
PORT_END=20999
MC_PORT_START=25565
MC_PORT_END=25999
ENV_FILE="$INSTALL_DIR/.env"

# ----------------------------------------------------------------------
# Animated banner
# ----------------------------------------------------------------------
PAL=(196 202 208 214 220 226 190 154 118 82 46 47 48 49 50 51 45 39 33 27 57 93 129 165 201 200 199 198 197)

show_banner() {
  local text="ALOOZ HOSTING" subtitle="VPS + MINECRAFT + INVITE REWARDS"
  local -a rows=("" "" "" "" "")
  local -A G=(
    [A]=" ### |#   #|#####|#   #|#   #"
    [L]="#    |#    |#    |#    |#####"
    [O]=" ### |#   #|#   #|#   #| ### "
    [Z]="#####|   # |  #  | #   |#####"
    [H]="#   #|#   #|#####|#   #|#   #"
    [S]=" ####|#    | ### |    #|#### "
    [T]="#####|  #  |  #  |  #  |  #  "
    [I]="#####|  #  |  #  |  #  |#####"
    [N]="#   #|##  #|# # #|#  ##|#   #"
    [G]=" ####|#    |#  ##|#   #| ### "
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

  if [ ! -t 1 ]; then
    for r in 0 1 2 3 4; do echo "${rows[r]//#/█}"; done
    echo "$subtitle"; return
  fi
  printf '\033[?25l'; printf '\n\n\n\n\n\n'
  draw() {
    local shift=$1 vis=$2
    printf '\033[5A'
    for r in 0 1 2 3 4; do
      row="${rows[r]}"; line=""
      for ((x = 0; x < ${#row}; x++)); do
        c="${row:x:1}"
        if [ "$c" = "#" ] && [ "$x" -lt "$vis" ]; then
          line+=$'\033[38;5;'"${PAL[(x + shift) % ${#PAL[@]}]}"$'m█'
        else line+=" "; fi
      done
      printf '\r%s\033[0m\033[K\n' "$line"
    done
  }
  for ((frame = 0; frame <= 30; frame++)); do draw "$frame" $((width * frame / 30)); sleep 0.02; done
  for ((frame = 0; frame < 50; frame++)); do draw $((30 + frame)) "$width"; sleep 0.03; done
  printf '\033[38;5;245m'
  for ((x = 0; x < width; x++)); do printf '═'; done
  printf '\033[0m\n'
  printf '%*s' $(((width - ${#subtitle}) / 2)) ''
  for ((n = 0; n < ${#subtitle}; n++)); do
    printf '\033[1;38;5;%sm%s\033[0m' "${PAL[(n * 2) % ${#PAL[@]}]}" "${subtitle:n:1}"; sleep 0.02
  done
  printf '\n\033[?25h\n'
}
restore_terminal() { printf '\033[0m\033[?25h'; }
trap restore_terminal EXIT

# ----------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------
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
  code="$(curl -sS -m 15 -o "$tmp" -w '%{http_code}' -H "Authorization: Bot $1" \
    https://discord.com/api/v10/users/@me 2>/dev/null || true)"
  if [ "$code" = "200" ]; then
    BOT_ID="$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["id"])' "$tmp" 2>/dev/null || true)"
    rm -f "$tmp"; return 0
  fi
  rm -f "$tmp"
  [ "$code" = "401" ] && return 1; return 2
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
    if [ "$rc" -eq 0 ]; then
      say "Token accepted by Discord."
      update_env_file "DISCORD_TOKEN" "$DISCORD_TOKEN"; break
    elif [ "$rc" -eq 2 ]; then
      warn "Could not reach Discord to verify. Saving anyway."
      update_env_file "DISCORD_TOKEN" "$DISCORD_TOKEN"; break
    else warn "Discord rejected this token. Try again."; fi
    [ "$attempts" -lt 3 ] || { warn "Too many attempts."; return; }
  done
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  say "Token updated. Bot restarted."
}

set_owner_interactive() {
  local OWNER_ID="" attempts=0
  while ! [[ "$OWNER_ID" =~ ^[0-9]{15,22}$ ]]; do
    attempts=$((attempts + 1))
    [ "$attempts" -le 3 ] || { warn "Too many attempts."; return; }
    [ -z "$OWNER_ID" ] || warn "Owner ID must be numbers only (approx 18 digits)."
    ask OWNER_ID "Enter your Discord owner ID"
    OWNER_ID="$(printf '%s' "$OWNER_ID" | tr -d '[:space:]')"
  done
  update_env_file "OWNER_ID" "$OWNER_ID"
  systemctl restart "$SERVICE" >/dev/null 2>&1 || true
  say "Owner ID updated to $OWNER_ID. Bot restarted."
}

# ----------------------------------------------------------------------
# System install
# ----------------------------------------------------------------------
install_system() {
  say "Preparing the system..."
  export DEBIAN_FRONTEND=noninteractive NEEDRESTART_MODE=a NEEDRESTART_SUSPEND=1
  APT=(apt-get -y -o DPkg::Lock::Timeout=300 -o Dpkg::Options::=--force-confold -o Dpkg::Options::=--force-confdef)
  dpkg --configure -a >/dev/null 2>&1 || true
  "${APT[@]}" -f install >/dev/null 2>&1 || true
  "${APT[@]}" update || warn "apt update reported problems, continuing anyway."
  apt-get install -y -o DPkg::Lock::Timeout=300 curl ca-certificates python3 python3-venv python3-pip docker.io || die "Could not install dependencies."
  systemctl enable --now docker >/dev/null 2>&1 || service docker start >/dev/null 2>&1 || true
  for _ in 1 2 3 4 5 6 7 8 9 10; do docker info >/dev/null 2>&1 && break; sleep 2; done
  docker info >/dev/null 2>&1 || die "Docker is installed but not running."

  say "Writing bot files to $INSTALL_DIR ..."
  mkdir -p "$INSTALL_DIR"

  # ===================== main.py =====================
  cat > "$INSTALL_DIR/main.py" <<'__ALOOZ_EOF__'
"""Entry point: shows the animated ALOOZ HOSTING banner, then starts the bot."""
import logging, sys, config
from banner import play_banner
EXIT_BAD_CONFIG = 78
def main() -> None:
    play_banner()
    if not config.TOKEN:
        print("ERROR: DISCORD_TOKEN is missing.")
        sys.exit(EXIT_BAD_CONFIG)
    logging.basicConfig(level=logging.INFO, format="%(asctime)s [%(levelname)s] %(name)s: %(message)s")
    import discord
    from bot import bot
    try:
        bot.run(config.TOKEN, log_handler=None)
    except discord.LoginFailure:
        print("ERROR: Discord rejected the bot token.")
        sys.exit(EXIT_BAD_CONFIG)
if __name__ == "__main__":
    main()
__ALOOZ_EOF__

  # ===================== config.py =====================
  cat > "$INSTALL_DIR/config.py" <<'__ALOOZ_EOF__'
"""Configuration loaded from environment variables (.env file supported)."""
import os
try:
    from dotenv import load_dotenv
    load_dotenv()
except ImportError: pass

def _int(name: str, default: int) -> int:
    try: return int(os.getenv(name, str(default)))
    except ValueError: return default

def _int_set(name: str) -> set:
    raw = os.getenv(name, "")
    return {int(x) for x in raw.replace(" ", "").split(",") if x.isdigit()}

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
BACKUP_DIR = os.getenv("BACKUP_DIR", "/opt/alooz-bot/backups")
__ALOOZ_EOF__

  # ===================== banner.py =====================
  cat > "$INSTALL_DIR/banner.py" <<'__ALOOZ_EOF__'
"""Animated ALOOZ HOSTING startup banner."""
import os, sys, time
GLYPHS = {
    "A": [" ### ", "#   #", "#####", "#   #", "#   #"], "L": ["#    ", "#    ", "#    ", "#    ", "#####"],
    "O": [" ### ", "#   #", "#   #", "#   #", " ### "], "Z": ["#####", "   # ", "  #  ", " #   ", "#####"],
    "H": ["#   #", "#   #", "#####", "#   #", "#   #"], "S": [" ####", "#    ", " ### ", "    #", "#### "],
    "T": ["#####", "  #  ", "  #  ", "  #  ", "  #  "], "I": ["#####", "  #  ", "  #  ", "  #  ", "#####"],
    "N": ["#   #", "##  #", "# # #", "#  ##", "#   #"], "G": [" ####", "#    ", "#  ##", "#   #", " ### "],
    " ": ["   ", "   ", "   ", "   ", "   "],
}
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

def play_banner(text: str = "ALOOZ HOSTING", subtitle: str = "VPS + MINECRAFT + INVITES", reveal_seconds: float = 1.6, shimmer_seconds: float = 3.0, fps: int = 24) -> None:
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

  # ===================== database.py (V101) =====================
  cat > "$INSTALL_DIR/database.py" <<'__ALOOZ_EOF__'
"""SQLite storage for VPS + Minecraft + Invites."""
import sqlite3, threading, time, uuid
from typing import List, Optional, Set

SCHEMA = """
CREATE TABLE IF NOT EXISTS vps (
  id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id INTEGER NOT NULL, container TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL DEFAULT 'My VPS',
  ram_mb INTEGER NOT NULL, cpu REAL NOT NULL, disk_gb INTEGER NOT NULL, ssh_port INTEGER NOT NULL UNIQUE,
  root_password TEXT NOT NULL, os_image TEXT NOT NULL, suspended INTEGER NOT NULL DEFAULT 0,
  created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL DEFAULT 0, server_ip TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_vps_owner ON vps(owner_id);

CREATE TABLE IF NOT EXISTS mc_servers (
  id INTEGER PRIMARY KEY AUTOINCREMENT, owner_id INTEGER NOT NULL, container TEXT NOT NULL UNIQUE,
  name TEXT NOT NULL, mc_version TEXT NOT NULL, server_type TEXT NOT NULL, ram_mb INTEGER NOT NULL,
  cpu REAL NOT NULL, disk_gb INTEGER NOT NULL, port INTEGER NOT NULL UNIQUE, rcon_port INTEGER NOT NULL UNIQUE,
  rcon_password TEXT NOT NULL, suspended INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL,
  expires_at INTEGER NOT NULL DEFAULT 0, server_ip TEXT NOT NULL DEFAULT ''
);
CREATE INDEX IF NOT EXISTS idx_mc_owner ON mc_servers(owner_id);

CREATE TABLE IF NOT EXISTS admins (user_id INTEGER PRIMARY KEY, added_by INTEGER NOT NULL, added_at INTEGER NOT NULL);

CREATE TABLE IF NOT EXISTS invites (
  user_id INTEGER PRIMARY KEY, total INTEGER NOT NULL DEFAULT 0, fake INTEGER NOT NULL DEFAULT 0
);
CREATE TABLE IF NOT EXISTS invite_logs (
  invited_id INTEGER PRIMARY KEY, inviter_id INTEGER NOT NULL, joined_at INTEGER NOT NULL
);
"""

_UPDATABLE_VPS = {"name", "ram_mb", "cpu", "disk_gb", "root_password", "suspended", "server_ip", "expires_at"}
_UPDATABLE_MC = {"ram_mb", "cpu", "disk_gb", "suspended", "server_ip", "name", "server_type", "mc_version", "expires_at"}

class Database:
    def __init__(self, path: str):
        self._conn = sqlite3.connect(path, check_same_thread=False)
        self._conn.row_factory = sqlite3.Row
        self._lock = threading.Lock()
        with self._lock:
            self._conn.executescript(SCHEMA); self._conn.commit()
            for col, table in [("name", "vps"), ("expires_at", "vps"), ("expires_at", "mc_servers")]:
                try: self._conn.execute(f"ALTER TABLE {table} ADD COLUMN {col} TEXT NOT NULL DEFAULT '0'")
                except sqlite3.OperationalError: pass

    def _execute(self, sql: str, params: tuple = ()) -> sqlite3.Cursor:
        with self._lock:
            cur = self._conn.execute(sql, params); self._conn.commit(); return cur

    def _query(self, sql: str, params: tuple = ()) -> List[sqlite3.Row]:
        with self._lock: return self._conn.execute(sql, params).fetchall()

    # ---------------- VPS ----------------
    def add_vps(self, owner_id: int, ram_mb: int, cpu: float, disk_gb: int, ssh_port: int, root_password: str, os_image: str, server_ip: str = "") -> int:
        placeholder = f"pending-{uuid.uuid4().hex}"
        expiry = int(time.time()) + (30 * 24 * 60 * 60)
        cur = self._execute(
            "INSERT INTO vps (owner_id, container, ram_mb, cpu, disk_gb, ssh_port, root_password, os_image, server_ip, created_at, expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?)",
            (owner_id, placeholder, ram_mb, cpu, disk_gb, ssh_port, root_password, os_image, server_ip, int(time.time()), expiry))
        vps_id = cur.lastrowid
        self._execute("UPDATE vps SET container = ?, name = ? WHERE id = ?", (f"alooz-vps-{vps_id}", f"VPS-{vps_id}", vps_id))
        return vps_id

    def get_vps(self, vps_id: int) -> Optional[sqlite3.Row]:
        rows = self._query("SELECT * FROM vps WHERE id = ?", (vps_id,)); return rows[0] if rows else None
    def list_vps_by_owner(self, owner_id: int) -> List[sqlite3.Row]: return self._query("SELECT * FROM vps WHERE owner_id = ? ORDER BY id", (owner_id,))
    def list_all_vps(self) -> List[sqlite3.Row]: return self._query("SELECT * FROM vps ORDER BY id")
    def delete_vps(self, vps_id: int) -> None: self._execute("DELETE FROM vps WHERE id = ?", (vps_id,))
    def update_vps(self, vps_id: int, **fields) -> None:
        for key in fields:
            if key not in _UPDATABLE_VPS: raise ValueError(f"Field not updatable: {key}")
        if not fields: return
        assignments = ", ".join(f"{k} = ?" for k in fields)
        self._execute(f"UPDATE vps SET {assignments} WHERE id = ?", (*fields.values(), vps_id))
    def used_vps_ports(self) -> Set[int]: return {row["ssh_port"] for row in self._query("SELECT ssh_port FROM vps")}
    def vps_totals(self) -> sqlite3.Row:
        return self._query("SELECT COUNT(*) AS n, COALESCE(SUM(ram_mb),0) AS ram, COALESCE(SUM(cpu),0) AS cpu, COALESCE(SUM(disk_gb),0) AS disk FROM vps")[0]

    # ---------------- Minecraft ----------------
    def add_mc(self, owner_id: int, name: str, mc_version: str, server_type: str, ram_mb: int, cpu: float, disk_gb: int, port: int, rcon_port: int, rcon_password: str, server_ip: str = "") -> int:
        placeholder = f"pending-{uuid.uuid4().hex}"
        expiry = int(time.time()) + (30 * 24 * 60 * 60)
        cur = self._execute(
            "INSERT INTO mc_servers (owner_id, container, name, mc_version, server_type, ram_mb, cpu, disk_gb, port, rcon_port, rcon_password, server_ip, created_at, expires_at) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
            (owner_id, placeholder, name, mc_version, server_type, ram_mb, cpu, disk_gb, port, rcon_port, rcon_password, server_ip, int(time.time()), expiry))
        mc_id = cur.lastrowid
        self._execute("UPDATE mc_servers SET container = ? WHERE id = ?", (f"alooz-mc-{mc_id}", mc_id))
        return mc_id

    def get_mc(self, mc_id: int) -> Optional[sqlite3.Row]:
        rows = self._query("SELECT * FROM mc_servers WHERE id = ?", (mc_id,)); return rows[0] if rows else None
    def list_mc_by_owner(self, owner_id: int) -> List[sqlite3.Row]: return self._query("SELECT * FROM mc_servers WHERE owner_id = ? ORDER BY id", (owner_id,))
    def list_all_mc(self) -> List[sqlite3.Row]: return self._query("SELECT * FROM mc_servers ORDER BY id")
    def delete_mc(self, mc_id: int) -> None: self._execute("DELETE FROM mc_servers WHERE id = ?", (mc_id,))
    def update_mc(self, mc_id: int, **fields) -> None:
        for key in fields:
            if key not in _UPDATABLE_MC: raise ValueError(f"Field not updatable: {key}")
        if not fields: return
        assignments = ", ".join(f"{k} = ?" for k in fields)
        self._execute(f"UPDATE mc_servers SET {assignments} WHERE id = ?", (*fields.values(), mc_id))
    def used_mc_ports(self) -> Set[int]: return {row["port"] for row in self._query("SELECT port FROM mc_servers")}
    def used_rcon_ports(self) -> Set[int]: return {row["rcon_port"] for row in self._query("SELECT rcon_port FROM mc_servers")}
    def mc_totals(self) -> sqlite3.Row:
        return self._query("SELECT COUNT(*) AS n, COALESCE(SUM(ram_mb),0) AS ram, COALESCE(SUM(cpu),0) AS cpu, COALESCE(SUM(disk_gb),0) AS disk FROM mc_servers")[0]

    # ---------------- Admins ----------------
    def add_admin(self, user_id: int, added_by: int) -> bool:
        if self.is_admin(user_id): return False
        self._execute("INSERT INTO admins (user_id, added_by, added_at) VALUES (?,?,?)", (user_id, added_by, int(time.time()))); return True
    def remove_admin(self, user_id: int) -> bool: return self._execute("DELETE FROM admins WHERE user_id = ?", (user_id,)).rowcount > 0
    def is_admin(self, user_id: int) -> bool: return bool(self._query("SELECT 1 FROM admins WHERE user_id = ?", (user_id,)))
    def list_admins(self) -> List[int]: return [row["user_id"] for row in self._query("SELECT user_id FROM admins ORDER BY added_at")]

    # ---------------- Invites ----------------
    def get_invites(self, user_id: int) -> int:
        row = self._query("SELECT total FROM invites WHERE user_id = ?", (user_id,))
        return row[0]["total"] if row else 0

    def add_invite(self, user_id: int, amount: int):
        self._execute("INSERT INTO invites (user_id, total) VALUES (?, ?) ON CONFLICT(user_id) DO UPDATE SET total = total + ?", (user_id, amount, amount))

    def remove_invite(self, user_id: int, amount: int = 1):
        current = self.get_invites(user_id)
        if current > 0:
            new_val = max(0, current - amount)
            self._execute("UPDATE invites SET total = ? WHERE user_id = ?", (new_val, user_id))

    def log_join(self, invited_id: int, inviter_id: int):
        self._execute("INSERT OR REPLACE INTO invite_logs (invited_id, inviter_id, joined_at) VALUES (?, ?, ?)", (invited_id, inviter_id, int(time.time())))

    def get_inviter(self, invited_id: int) -> int:
        row = self._query("SELECT inviter_id FROM invite_logs WHERE invited_id = ?", (invited_id,))
        return row[0]["inviter_id"] if row else 0

    def remove_join_log(self, invited_id: int):
        self._execute("DELETE FROM invite_logs WHERE invited_id = ?", (invited_id,))

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

  # ===================== docker_utils.py (RAM Fix) =====================
  cat > "$INSTALL_DIR/docker_utils.py" <<'__ALOOZ_EOF__'
"""Docker wrappers for VPS containers and Minecraft servers."""
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

TYPE="$MC_TYPE"
VERSION="$MC_VERSION"
MEM="$MC_RAM"
RCON_PW="$MC_RCON_PW"
JAR="server.jar"

if [ ! -f "$JAR" ]; then
  case "$TYPE" in
    vanilla)
      URL="https://piston-data.mojang.com/v1/objects/$(curl -s https://launchermeta.mojang.com/mc/game/version_manifest.json | jq -r --arg v "$VERSION" '.versions[] | select(.id==$v) | .url' | xargs curl -s | jq -r '.downloads.server.url')"
      wget -q -O "$JAR" "$URL" ;;
    paper|purpur)
      if [ "$TYPE" = "paper" ]; then
        BUILD=$(curl -s "https://api.papermc.io/v2/projects/paper/versions/$VERSION" | jq -r '.builds | last')
        URL="https://api.papermc.io/v2/projects/paper/versions/$VERSION/builds/$BUILD/downloads/paper-$VERSION-$BUILD.jar"
      else
        BUILD=$(curl -s "https://api.purpurmc.org/v2/purpur/$VERSION" | jq -r '.builds.latest')
        URL="https://api.purpurmc.org/v2/purpur/$VERSION/$BUILD/download"
      fi
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
    try:
        proc = await asyncio.create_subprocess_exec(*args, stdout=asyncio.subprocess.PIPE, stderr=asyncio.subprocess.PIPE)
    except FileNotFoundError: raise DockerError("Docker is not installed on the host.")
    try: out, err = await asyncio.wait_for(proc.communicate(), timeout=timeout)
    except asyncio.TimeoutError: proc.kill(); raise DockerError("Docker command timed out.")
    return proc.returncode, out.decode(errors="replace").strip(), err.decode(errors="replace").strip()

async def _docker(*args: str, timeout: int = 600) -> str:
    code, out, err = await _run("docker", *args, timeout=timeout)
    if code != 0: raise DockerError(err or out or "docker command failed")
    return out

def generate_password(length: int = 16) -> str:
    alphabet = string.ascii_letters + string.digits
    return "".join(secrets.choice(alphabet) for _ in range(length))

def port_is_free(port: int) -> bool:
    with socket.socket(socket.AF_INET, socket.SOCK_STREAM) as sock:
        try: sock.bind(("0.0.0.0", port)); return True
        except OSError: return False

# FIXED RAM LIMIT: Added --memory-reservation and --cpu-shares to strictly enforce limits.
def build_run_args(name: str, image: str, ram_mb: int, cpu: float, disk_gb: int, port: int, password: str, use_disk_limit: bool = False) -> List[str]:
    cpu_shares = int(cpu * 1024)
    args = ["run", "-d", "--name", name, "--hostname", name, "--restart", "unless-stopped",
            "--memory", f"{ram_mb}m", "--memory-reservation", f"{ram_mb}m", "--memory-swap", f"{ram_mb}m", 
            "--cpus", f"{cpu:g}", "--cpu-shares", str(cpu_shares),
            "--pids-limit", "4096", "-p", f"{port}:22", "-e", f"ROOT_PASSWORD={password}",
            "--label", "alooz.vps=1"]
    if use_disk_limit: args += ["--storage-opt", f"size={disk_gb}g"]
    args += [image, "bash", "-c", BOOT_SCRIPT]; return args

async def create_vps_container(name: str, image: str, ram_mb: int, cpu: float, disk_gb: int, port: int, password: str, use_disk_limit: bool = False) -> str:
    args = build_run_args(name, image, ram_mb, cpu, disk_gb, port, password, use_disk_limit)
    return await _docker(*args, timeout=900)

async def power(name: str, action: str) -> None:
    if action not in ("start", "stop", "restart"): raise ValueError(f"Unknown action: {action}")
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
    out = await _docker("stats", "--no-stream", "--format", "{{.CPUPerc}}|{{.MemUsage}}|{{.NetIO}}|{{.BlockIO}}|{{.PIDs}}", name, timeout=60)
    cpu, mem, net, block, pids = (out.split("|") + [""] * 5)[:5]
    return {"cpu": cpu, "mem": mem, "net": net, "block": block, "pids": pids}

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
    raise DockerError("Could not generate SSHX URL. Check container internet access.")

async def create_mc_container(name: str, mc_version: str, server_type: str, ram_mb: int, cpu: float, disk_gb: int, port: int, rcon_port: int, rcon_password: str, use_disk_limit: bool = False) -> str:
    cpu_shares = int(cpu * 1024)
    args = ["run", "-d", "--name", name, "--hostname", name, "--restart", "unless-stopped",
            "--memory", f"{ram_mb}m", "--memory-reservation", f"{ram_mb}m", "--memory-swap", f"{ram_mb + 512}m", 
            "--cpus", f"{cpu:g}", "--cpu-shares", str(cpu_shares),
            "--pids-limit", "2048", "-p", f"{port}:25565", "-p", f"{rcon_port}:25575",
            "-e", f"MC_VERSION={mc_version}", "-e", f"MC_TYPE={server_type}",
            "-e", f"MC_RAM={ram_mb}", "-e", f"MC_RCON_PW={rcon_password}",
            "-v", f"{name}-data:/data", "--label", "alooz.mc=1"]
    if use_disk_limit: args += ["--storage-opt", f"size={disk_gb}g"]
    args += ["eclipse-temurin:17-jre", "bash", "-c", MC_BOOT_SCRIPT]
    return await _docker(*args, timeout=900)

async def mc_send_command(name: str, rcon_password: str, command: str) -> str:
    out = await _docker("exec", name, "bash", "-c",
        f"command -v mcrcon >/dev/null 2>&1 || (apt-get update -qq && apt-get install -y -qq mcrcon >/dev/null); mcrcon -p '{rcon_password}' '{command}'",
        timeout=30)
    return out

def host_stats() -> Dict[str, float]:
    stats: Dict[str, float] = {"cpus": float(os.cpu_count() or 1)}
    try: stats["load1"], stats["load5"], stats["load15"] = os.getloadavg()
    except (OSError, AttributeError): stats["load1"] = stats["load5"] = stats["load15"] = 0.0
    try:
        meminfo = {}
        with open("/proc/meminfo") as fh:
            for line in fh:
                key, value = line.split(":", 1); meminfo[key] = int(value.split()[0])
        stats["ram_total_mb"] = meminfo["MemTotal"] / 1024
        stats["ram_avail_mb"] = meminfo.get("MemAvailable", meminfo.get("MemFree", 0)) / 1024
    except (OSError, KeyError, ValueError):
        stats["ram_total_mb"] = stats["ram_avail_mb"] = 0.0
    usage = shutil.disk_usage("/")
    stats["disk_total_gb"] = usage.total / 1024 ** 3
    stats["disk_free_gb"] = usage.free / 1024 ** 3
    return stats
__ALOOZ_EOF__

  # ===================== bot.py (V101) =====================
  cat > "$INSTALL_DIR/bot.py" <<'__ALOOZ_EOF__'
"""ALOOZ HOSTING - Discord VPS + Minecraft + Invite bot."""
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

def is_owner(user_id: int) -> bool: return config.OWNER_ID != 0 and user_id == config.OWNER_ID
def is_admin(user_id: int) -> bool: return is_owner(user_id) or user_id in config.ADMIN_IDS or db.is_admin(user_id)
def admin_only():
    async def predicate(interaction: discord.Interaction) -> bool:
        if is_admin(interaction.user.id): return True
        raise app_commands.CheckFailure("Only ALOOZ HOSTING admins can use this command.")
    return app_commands.check(predicate)
def owner_only():
    async def predicate(interaction: discord.Interaction) -> bool:
        if is_owner(interaction.user.id): return True
        raise app_commands.CheckFailure("Only the bot owner can use this command.")
    return app_commands.check(predicate)
def short(error: Exception, limit: int = 300) -> str: return str(error)[:limit]

async def reply(interaction: discord.Interaction, content: str = None, **kwargs) -> None:
    kwargs.setdefault("ephemeral", True)
    if interaction.response.is_done(): await interaction.followup.send(content, **kwargs)
    else: await interaction.response.send_message(content, **kwargs)

async def get_vps_for(interaction: discord.Interaction, vps_id: int) -> Optional[sqlite3.Row]:
    row = db.get_vps(vps_id)
    if row is None or (row["owner_id"] != interaction.user.id and not is_admin(interaction.user.id)):
        await reply(interaction, f"VPS #{vps_id} was not found."); return None
    return row

async def get_mc_for(interaction: discord.Interaction, mc_id: int) -> Optional[sqlite3.Row]:
    row = db.get_mc(mc_id)
    if row is None or (row["owner_id"] != interaction.user.id and not is_admin(interaction.user.id)):
        await reply(interaction, f"Minecraft server #{mc_id} was not found."); return None
    return row

def pick_port(db_used: set, start: int, end: int) -> Optional[int]:
    for port in range(start, end + 1):
        if port not in db_used and dk.port_is_free(port): return port
    return None

INVITE_TIERS = [
    (32, 24576, 30, 6.0), (28, 20480, 30, 5.0), (24, 16384, 25, 4.0),
    (20, 12288, 20, 3.5), (16, 10240, 15, 3.0), (14, 8192, 13, 2.5),
    (9, 6144, 10, 2.0), (5, 4096, 10, 1.5), (3, 2048, 10, 1.0)
]

def vps_embed(row: sqlite3.Row, status: str, *, show_password: bool = False, stats: dict = None) -> discord.Embed:
    color = discord.Color.green() if status == "running" else discord.Color.red()
    embed = discord.Embed(title=f"{config.BOT_NAME} • {row['name']} (#{row['id']})", color=color)
    suspended = " (suspended)" if row["suspended"] else ""
    expiry = datetime.datetime.fromtimestamp(row['expires_at']).strftime('%Y-%m-%d') if row['expires_at'] else 'Never'
    embed.add_field(name="Status", value=f"{STATUS_EMOJI.get(status, '⚫')} {status}{suspended}")
    embed.add_field(name="Expires", value=expiry)
    embed.add_field(name="Owner ID", value=f"{row['owner_id']}")
    embed.add_field(name="OS", value=row["os_image"])
    embed.add_field(name="RAM", value=f"{row['ram_mb']} MB")
    embed.add_field(name="CPU", value=f"{row['cpu']:g} core(s)")
    embed.add_field(name="Disk", value=f"{row['disk_gb']} GB")
    embed.add_field(name="SSH", value=f"`ssh root@{config.SERVER_IP} -p {row['ssh_port']}`", inline=False)
    if show_password: embed.add_field(name="Root password", value=f"||{row['root_password']}||", inline=False)
    if stats: embed.add_field(name="Live usage", value=f"CPU: {stats['cpu']}\nRAM: {stats['mem']}\nNet: {stats['net']}", inline=False)
    embed.set_footer(text="ALOOZ HOSTING • Renew for 2 invites")
    return embed

def mc_embed(row: sqlite3.Row, status: str, *, show_rcon: bool = False, stats: dict = None) -> discord.Embed:
    color = discord.Color.green() if status == "running" else discord.Color.red()
    embed = discord.Embed(title=f"⛏️ Minecraft • {row['name']} (#{row['id']})", color=color)
    suspended = " (suspended)" if row["suspended"] else ""
    expiry = datetime.datetime.fromtimestamp(row['expires_at']).strftime('%Y-%m-%d') if row['expires_at'] else 'Never'
    embed.add_field(name="Status", value=f"{STATUS_EMOJI.get(status, '⚫')} {status}{suspended}")
    embed.add_field(name="Expires", value=expiry)
    embed.add_field(name="Type", value=row["server_type"].capitalize())
    embed.add_field(name="Version", value=row["mc_version"])
    embed.add_field(name="RAM", value=f"{row['ram_mb']} MB")
    embed.add_field(name="CPU", value=f"{row['cpu']:g} core(s)")
    embed.add_field(name="Address", value=f"`{config.SERVER_IP}:{row['port']}`", inline=False)
    if show_rcon: embed.add_field(name="RCON Password", value=f"||{row['rcon_password']}||", inline=False)
    if stats: embed.add_field(name="Live usage", value=f"CPU: {stats['cpu']}\nRAM: {stats['mem']}", inline=False)
    embed.set_footer(text="ALOOZ HOSTING • Renew for 2 invites")
    return embed

class AloozBot(commands.Bot):
    def __init__(self):
        super().__init__(command_prefix=commands.when_mentioned, intents=discord.Intents.all())
        self.deploy_lock: Optional[asyncio.Lock] = None
    async def setup_hook(self) -> None:
        self.deploy_lock = asyncio.Lock(); await self.tree.sync()
        self.cleanup_task.start()
    async def on_ready(self) -> None:
        log.info("Logged in as %s (%s)", self.user, self.user.id)
        await self.change_presence(activity=discord.Activity(type=discord.ActivityType.watching, name=f"{config.BOT_NAME} | Invites & Hosting"))

    @tasks.loop(minutes=30)
    async def cleanup_task(self):
        vps, mc = db.get_expired_servers()
        for v in vps:
            await dk.remove(v["container"]); db.delete_vps(v["id"])
            log.info(f"Auto-deleted expired VPS #{v['id']}")
        for m in mc:
            await dk.remove(m["container"]); db.remove_volume(f"{m['container']}-data"); db.delete_mc(m["id"])
            log.info(f"Auto-deleted expired MC #{m['id']}")

bot = AloozBot()

@bot.tree.error
async def on_app_command_error(interaction: discord.Interaction, error: app_commands.AppCommandError):
    if isinstance(error, app_commands.CheckFailure): message = str(error) or "Not allowed."
    else: log.exception("Unhandled error", exc_info=error); message = "Something went wrong."
    try: await reply(interaction, message)
    except discord.HTTPException: pass

# =====================================================================
# INVITE EVENTS (90 days account check)
# =====================================================================
@bot.event
async def on_member_join(member: discord.Member):
    if member.bot: return
    
    # 90 Days Check
    account_age_days = (datetime.datetime.now(datetime.timezone.utc) - member.created_at).days
    if account_age_days < 90:
        log.info(f"{member.name} account is too new ({account_age_days} days). Invite not counted.")
        return

    invites_before = {inv.code: inv.uses for inv in await member.guild.invites()}
    await asyncio.sleep(2)
    invites_after = await member.guild.invites()
    inviter = None
    for invite in invites_after:
        if invites_before.get(invite.code, 0) < invite.uses:
            inviter = invite.inviter; break
    if inviter:
        db.add_invite(inviter.id, 1)
        db.log_join(member.id, inviter.id)
        total = db.get_invites(inviter.id)
        try:
            await inviter.send(f"✅ **{member.name}** joined! Total invites: `{total}`")
            # Check if they hit a new tier
            for inv, ram, disk, cpu in INVITE_TIERS:
                if total == inv:
                    await inviter.send(f"🎉 **CONGRATULATIONS!** You reached a new tier!\nUse `/invite-claim` to claim your {ram}MB RAM / {cpu}x CPU server!")
                    break
        except: pass

@bot.event
async def on_member_remove(member: discord.Member):
    if member.bot: return
    inviter_id = db.get_inviter(member.id)
    if inviter_id:
        db.remove_invite(inviter_id)
        db.remove_join_log(member.id)
        try:
            user = await bot.fetch_user(inviter_id)
            await user.send(f"🔴 **{member.name}** left. -1 invite. Total: `{db.get_invites(inviter_id)}`")
        except: pass

# =====================================================================
# INVITE COMMANDS
# =====================================================================
@bot.tree.command(name="invites", description="Check your invites")
async def invites(interaction: discord.Interaction):
    total = db.get_invites(interaction.user.id)
    embed = discord.Embed(title="👑 Your Invite Stats", color=discord.Color.gold())
    embed.add_field(name="Total Invites", value=f"📊 **{total}** valid invites", inline=False)
    current = None; nxt = None
    for inv, ram, disk, cpu in INVITE_TIERS:
        if total >= inv: current = (inv, ram, disk, cpu)
        else: nxt = (inv, ram, disk, cpu); break
    if current: embed.add_field(name="🎁 Current Tier", value=f"💾 {current[1]}MB RAM • 📦 {current[2]}GB Disk • ⚡ {current[3]}x CPU", inline=False)
    if nxt: embed.add_field(name="📈 Next Tier", value=f"{nxt[0]} invites ➜ {nxt[1]}MB RAM", inline=False)
    await interaction.response.send_message(embed=embed, ephemeral=True)

@bot.tree.command(name="invites-plan", description="Show the full invite reward plan")
async def invites_plan(interaction: discord.Interaction):
    embed = discord.Embed(title="👑 INVITE REWARD PLAN", color=discord.Color.gold())
    desc = ""
    for inv, ram, disk, cpu in reversed(INVITE_TIERS):
        desc += f"**{inv} Invites** ➜ 💾 {ram}MB RAM • 📦 {disk}GB Disk • ⚡ {cpu}x CPU\n"
    embed.description = desc
    embed.set_footer(text="Accounts older than 90 days count as valid invites.")
    await interaction.response.send_message(embed=embed, ephemeral=True)

@bot.tree.command(name="invite-claim", description="Claim your free server")
@app_commands.describe(type="VPS or Minecraft")
@app_commands.choices(type=[app_commands.Choice(name="Minecraft", value="mc"), app_commands.Choice(name="VPS", value="vps")])
async def invite_claim(interaction: discord.Interaction, type: app_commands.Choice[str]):
    total = db.get_invites(interaction.user.id)
    best_tier = None
    for inv, ram, disk, cpu in INVITE_TIERS:
        if total >= inv: best_tier = (ram, disk, cpu)
        else: break
    if not best_tier: return await interaction.response.send_message("❌ Need at least **3 invites**.", ephemeral=True)
    ram_mb, disk_gb, cpu = best_tier
    await interaction.response.defer(ephemeral=True, thinking=True)
    if type.value == "vps":
        port = pick_port(db.used_vps_ports(), config.PORT_START, config.PORT_END)
        if not port: return await interaction.followup.send("No ports available.", ephemeral=True)
        vps_id = db.add_vps(interaction.user.id, ram_mb, cpu, disk_gb, port, dk.generate_password(), "ubuntu:22.04", config.SERVER_IP)
        row = db.get_vps(vps_id)
        await dk.create_vps_container(row["container"], "ubuntu:22.04", ram_mb, cpu, disk_gb, port, row["root_password"], config.USE_DISK_LIMIT)
        await interaction.followup.send(f"🎉 **VPS Claimed!** (#{vps_id})\nUse `/ssh {vps_id}`. Expires in 30 days.", ephemeral=True)
    else:
        port = pick_port(db.used_mc_ports(), config.MC_PORT_START, config.MC_PORT_END)
        if not port: return await interaction.followup.send("No ports available.", ephemeral=True)
        rcon_pw = dk.generate_password()
        mc_id = db.add_mc(interaction.user.id, f"Claimed-{interaction.user.name[:10]}", "1.20.1", "paper", ram_mb, cpu, disk_gb, port, port+1, rcon_pw, config.SERVER_IP)
        row = db.get_mc(mc_id)
        await dk.create_mc_container(row["container"], "1.20.1", "paper", ram_mb, cpu, disk_gb, port, port+1, rcon_pw, config.USE_DISK_LIMIT)
        await interaction.followup.send(f"🎉 **Minecraft Claimed!** (#{mc_id})\nIP: `{config.SERVER_IP}:{port}`. Expires in 30 days.", ephemeral=True)

@bot.tree.command(name="renew", description="Renew a server for 1 month (Costs 2 invites)")
@app_commands.describe(type="VPS or MC", server_id="Server ID")
@app_commands.choices(type=[app_commands.Choice(name="VPS", value="vps"), app_commands.Choice(name="Minecraft", value="mc")])
async def renew(interaction: discord.Interaction, type: app_commands.Choice[str], server_id: int):
    if db.get_invites(interaction.user.id) < 2:
        return await interaction.response.send_message("❌ You need at least **2 invites**.", ephemeral=True)
    row = db.get_vps(server_id) if type.value == "vps" else db.get_mc(server_id)
    if not row or row["owner_id"] != interaction.user.id:
        return await interaction.response.send_message("❌ Server not found.", ephemeral=True)
    db.remove_invite(interaction.user.id, 2)
    db.renew_server(type.value, server_id)
    await interaction.response.send_message(f"✅ Renewed {type.name} (#{server_id}) for 30 days! (-2 invites)", ephemeral=True)

# =====================================================================
# ADMIN COMMANDS
# =====================================================================
@bot.tree.command(name="deploy", description="[Admin] Create a VPS for a member (Auto DMs)")
@admin_only()
async def deploy(interaction: discord.Interaction, member: discord.Member, ram_mb: app_commands.Range[int, 128, 262144], cpu: app_commands.Range[float, 0.1, 128.0], disk_gb: app_commands.Range[int, 1, 10000]):
    await interaction.response.defer(ephemeral=True, thinking=True)
    port = pick_port(db.used_vps_ports(), config.PORT_START, config.PORT_END)
    if not port: return await interaction.followup.send("No ports available.", ephemeral=True)
    vps_id = db.add_vps(member.id, ram_mb, float(cpu), disk_gb, port, dk.generate_password(), "ubuntu:22.04", config.SERVER_IP)
    row = db.get_vps(vps_id)
    await dk.create_vps_container(row["container"], "ubuntu:22.04", ram_mb, float(cpu), disk_gb, port, row["root_password"], config.USE_DISK_LIMIT)
    
    # Auto DM
    try:
        dm = discord.Embed(title="🎉 Your VPS is Ready!", color=discord.Color.green())
        dm.add_field(name="VPS ID", value=f"#{vps_id}")
        dm.add_field(name="RAM", value=f"{ram_mb} MB")
        dm.add_field(name="SSH Command", value=f"`ssh root@{config.SERVER_IP} -p {port}`", inline=False)
        dm.add_field(name="Password", value=f"||{row['root_password']}||", inline=False)
        await member.send(embed=dm)
    except: pass
    
    await interaction.followup.send(f"VPS #{vps_id} deployed for {member.mention}.", ephemeral=True)

@bot.tree.command(name="create-mc", description="[Admin] Create a Minecraft server for a member")
@admin_only()
async def create_mc(interaction: discord.Interaction, member: discord.Member, name: str, ram_mb: app_commands.Range[int, 512, 262144], cpu: app_commands.Range[float, 0.5, 64.0], disk_gb: app_commands.Range[int, 1, 1000]):
    await interaction.response.defer(ephemeral=True, thinking=True)
    port = pick_port(db.used_mc_ports(), config.MC_PORT_START, config.MC_PORT_END)
    if not port: return await interaction.followup.send("No ports available.", ephemeral=True)
    rcon_pw = dk.generate_password()
    mc_id = db.add_mc(member.id, name[:32], "1.20.1", "paper", ram_mb, float(cpu), disk_gb, port, port+1, rcon_pw, config.SERVER_IP)
    row = db.get_mc(mc_id)
    await dk.create_mc_container(row["container"], "1.20.1", "paper", ram_mb, float(cpu), disk_gb, port, port+1, rcon_pw, config.USE_DISK_LIMIT)
    
    # Auto DM
    try:
        dm = discord.Embed(title="⛏️ Your Minecraft Server is Ready!", color=discord.Color.green())
        dm.add_field(name="Name", value=name)
        dm.add_field(name="IP", value=f"`{config.SERVER_IP}:{port}`", inline=False)
        dm.add_field(name="RCON", value=f"||{rcon_pw}||", inline=False)
        await member.send(embed=dm)
    except: pass
    
    await interaction.followup.send(f"Minecraft #{mc_id} deployed for {member.mention}.", ephemeral=True)

@bot.tree.command(name="reset-invites", description="[Admin] Reset a user's invites to 0")
@admin_only()
async def reset_invites(interaction: discord.Interaction, member: discord.Member):
    db.remove_invite(member.id, db.get_invites(member.id))
    await reply(interaction, f"Reset invites for {member.mention}.")

@bot.tree.command(name="add-invites", description="[Admin] Add invites to a user")
@admin_only()
async def add_invites(interaction: discord.Interaction, member: discord.Member, amount: int):
    db.add_invite(member.id, amount)
    await reply(interaction, f"Added {amount} invites to {member.mention}. Total: {db.get_invites(member.id)}")

@bot.tree.command(name="remove-invites", description="[Admin] Remove invites from a user")
@admin_only()
async def remove_invites(interaction: discord.Interaction, member: discord.Member, amount: int):
    db.remove_invite(member.id, amount)
    await reply(interaction, f"Removed {amount} invites from {member.mention}. Total: {db.get_invites(member.id)}")

# =====================================================================
# USER COMMANDS
# =====================================================================
@bot.tree.command(name="myvps", description="List your VPS")
async def myvps(interaction: discord.Interaction):
    await interaction.response.defer(ephemeral=True)
    rows = db.list_vps_by_owner(interaction.user.id)
    if not rows: return await interaction.followup.send("No VPS.", ephemeral=True)
    embeds = []
    for r in rows[:5]:
        st = await dk.container_status(r["container"])
        embeds.append(vps_embed(r, st))
    await interaction.followup.send(embeds=embeds, ephemeral=True)

@bot.tree.command(name="myserver", description="List your Minecraft servers")
async def myserver(interaction: discord.Interaction):
    await interaction.response.defer(ephemeral=True)
    rows = db.list_mc_by_owner(interaction.user.id)
    if not rows: return await interaction.followup.send("No Minecraft servers.", ephemeral=True)
    embeds = []
    for r in rows[:5]:
        st = await dk.container_status(r["container"])
        embeds.append(mc_embed(r, st))
    await interaction.followup.send(embeds=embeds, ephemeral=True)

@bot.tree.command(name="ssh", description="Get SSH info and web terminal link")
async def ssh(interaction: discord.Interaction, vps_id: int):
    row = await get_vps_for(interaction, vps_id)
    if not row: return
    await interaction.response.defer(ephemeral=True, thinking=True)
    status = await dk.container_status(row["container"])
    if status != "running": return await interaction.followup.send("VPS is not running.", ephemeral=True)
    url = await dk.start_sshx_and_get_url(row["container"])
    embed = vps_embed(row, status, show_password=True)
    embed.add_field(name="🌐 Web Terminal", value=f"[Click Here]({url})", inline=False)
    await interaction.followup.send(embed=embed, ephemeral=True)

@bot.tree.command(name="resshx", description="Restart and get a new SSHX web terminal link")
async def resshx(interaction: discord.Interaction, vps_id: int):
    row = await get_vps_for(interaction, vps_id)
    if not row: return
    await interaction.response.defer(ephemeral=True, thinking=True)
    try:
        url = await dk.start_sshx_and_get_url(row["container"])
        await interaction.followup.send(f"🌐 **New SSHX Link:** [Click Here]({url})", ephemeral=True)
    except Exception as e:
        await interaction.followup.send(f"Failed: {short(e)}", ephemeral=True)

@bot.tree.command(name="reinstall-os", description="Reinstall the OS on your VPS")
@app_commands.choices(os=[app_commands.Choice(name="Ubuntu 22.04", value="ubuntu:22.04"), app_commands.Choice(name="Ubuntu 24.04", value="ubuntu:24.04"), app_commands.Choice(name="Debian 12", value="debian:12")])
async def reinstall_os(interaction: discord.Interaction, vps_id: int, os: app_commands.Choice[str]):
    row = await get_vps_for(interaction, vps_id)
    if not row: return
    await interaction.response.defer(ephemeral=True, thinking=True)
    
    await dk.remove(row["container"])
    new_pw = dk.generate_password()
    db.update_vps(vps_id, os_image=os.value, root_password=new_pw)
    
    await dk.create_vps_container(row["container"], os.value, row["ram_mb"], row["cpu"], row["disk_gb"], row["ssh_port"], new_pw, config.USE_DISK_LIMIT)
    await interaction.followup.send(f"✅ OS Reinstalled to {os.name}!\nNew Root Password: ||{new_pw}||", ephemeral=True)

# =====================================================================
# UTILITY COMMANDS
# =====================================================================
@bot.tree.command(name="node", description="[Admin] Host server resources")
@admin_only()
async def node(interaction: discord.Interaction):
    host = dk.host_stats(); vps_t = db.vps_totals(); mc_t = db.mc_totals()
    embed = discord.Embed(title="Node Status", color=discord.Color.blurple())
    embed.add_field(name="CPU", value=f"{host['cpus']:.0f} cores\nLoad: {host['load1']:.2f}")
    embed.add_field(name="RAM", value=f"{host['ram_total_mb'] - host['ram_avail_mb']:.0f} / {host['ram_total_mb']:.0f} MB")
    embed.add_field(name="VPS", value=f"{vps_t['n']} servers")
    embed.add_field(name="MC", value=f"{mc_t['n']} servers")
    await interaction.response.send_message(embed=embed, ephemeral=True)

@bot.tree.command(name="help", description="Show all commands")
async def help_command(interaction: discord.Interaction):
    embed = discord.Embed(title="ALOOZ HOSTING Help", color=discord.Color.blurple())
    embed.add_field(name="🎁 Invites", value="`/invites` `/invites-plan` `/invite-claim` `/renew`", inline=False)
    embed.add_field(name="🖥️ User", value="`/myvps` `/ssh` `/resshx` `/reinstall-os`", inline=False)
    embed.add_field(name="⛏️ Minecraft", value="`/myserver`", inline=False)
    if is_admin(interaction.user.id):
        embed.add_field(name="Admin", value="`/deploy` `/create-mc` `/add-invites` `/remove-invites` `/reset-invites` `/node`", inline=False)
    await interaction.response.send_message(embed=embed, ephemeral=True)
__ALOOZ_EOF__

  cat > "$INSTALL_DIR/requirements.txt" <<'__ALOOZ_EOF__'
discord.py>=2.3.2
python-dotenv>=1.0.0
__ALOOZ_EOF__

  say "Setting up Python environment..."
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
  mkdir -p "$INSTALL_DIR/backups"
}

# ----------------------------------------------------------------------
# Menu
# ----------------------------------------------------------------------
main_menu() {
  while true; do
    echo ""
    echo -e "\033[1;36m=========================================\033[0m"
    echo -e "\033[1;32m    ALOOZ HOSTING - MAIN MENU (V101)     \033[0m"
    echo -e "\033[1;36m=========================================\033[0m"
    echo -e "  \033[1;33m1.\033[0m Set Token & Owner ID"
    echo -e "  \033[1;33m2.\033[0m Restart Bot"
    echo -e "  \033[1;33m3.\033[0m View Logs"
    echo -e "  \033[1;33m4.\033[0m Reinstall Bot"
    echo -e "  \033[1;31m5. Delete All (Danger)\033[0m"
    echo -e "  \033[1;33m6.\033[0m Exit"
    local choice=""
    ask choice "Enter choice [1-6]"
    case "$choice" in
      1) set_token_interactive; set_owner_interactive ;;
      2) systemctl restart alooz-bot; say "Restarted." ;;
      3) journalctl -u alooz-bot -f -n 50 ;;
      4) systemctl stop alooz-bot; install_system; systemctl restart alooz-bot ;;
      5) warn "Deleting all..."; rm -rf /opt/alooz-bot; systemctl stop alooz-bot; systemctl disable alooz-bot; rm /etc/systemd/system/alooz-bot.service; exit 0 ;;
      6) exit 0 ;;
    esac
  done
}

show_banner
if [ ! -f "$SYSTEMD_DIR/$SERVICE.service" ]; then
  install_system
  say "Enter Bot Token:"
  set_token_interactive
  say "Enter Owner ID:"
  set_owner_interactive
  systemctl restart alooz-bot
fi
main_menu