#!/usr/bin/env bash
set -euo pipefail

# -----------------------------
# Born2beRoot one-shot setup
# - Run as root: sudo bash born2beroot_setup.sh
# - Default target user: lkim (override with TARGET_USER env)
# -----------------------------

TARGET_USER="${TARGET_USER:-lkim}"
SSH_PORT="${SSH_PORT:-4242}"
IFACE="${IFACE:-enp0s3}"
STATIC_IP="${STATIC_IP:-10.0.2.15}"
NETMASK="${NETMASK:-255.255.255.0}"
GATEWAY="${GATEWAY:-10.0.2.2}"

log() { printf "\n[+] %s\n" "$*"; }
warn() { printf "\n[!] %s\n" "$*" >&2; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    warn "Run as root: sudo bash $0"
    exit 1
  fi
}

backup_file() {
  local f="$1"
  if [[ -f "$f" ]]; then
    cp -a "$f" "${f}.bak.$(date +%Y%m%d%H%M%S)"
  fi
}

replace_or_append_kv() {
  # replace "KEY ..." style lines in /etc/login.defs
  local key="$1" value="$2" file="$3"
  if grep -qE "^[#[:space:]]*${key}[[:space:]]+" "$file"; then
    sed -i -E "s|^[#[:space:]]*${key}[[:space:]]+.*|${key}\t${value}|g" "$file"
  else
    printf "%s\t%s\n" "$key" "$value" >> "$file"
  fi
}

ensure_pkg() {
  local pkgs=("$@")
  DEBIAN_FRONTEND=noninteractive apt-get update -y
  DEBIAN_FRONTEND=noninteractive apt-get install -y "${pkgs[@]}"
}

get_user_home() {
  local u="$1"
  getent passwd "$u" | cut -d: -f6
}

user_exists() { id "$1" >/dev/null 2>&1; }

ensure_target_user() {
  if ! user_exists "$TARGET_USER"; then
    warn "User '$TARGET_USER' does not exist. Create it first, or run with TARGET_USER=<user>."
    exit 1
  fi
}

install_packages() {
  log "1) Installing base packages"
  ensure_pkg vim lvm2 fdisk sudo ufw net-tools cron apparmor apparmor-utils libpam-pwquality
}

setup_path() {
  log "2) Adding /sbin to PATH in ${TARGET_USER}'s ~/.bashrc"
  local home
  home="$(get_user_home "$TARGET_USER")"
  [[ -n "$home" && -d "$home" ]] || { warn "Cannot resolve home directory for $TARGET_USER"; return 0; }
  local bashrc="${home}/.bashrc"
  touch "$bashrc"
  chown "$TARGET_USER":"$TARGET_USER" "$bashrc" || true
  if ! grep -qE 'export PATH=.*(/sbin|:\$PATH:/sbin)' "$bashrc"; then
    echo 'export PATH=$PATH:/sbin' >> "$bashrc"
  fi
}

add_user_to_sudo() {
  log "3) Adding ${TARGET_USER} to sudo group"
  usermod -aG sudo "$TARGET_USER"
}

configure_ssh() {
  log "4-7) Configuring SSH (Port ${SSH_PORT}, PermitRootLogin no)"
  local f="/etc/ssh/sshd_config"
  backup_file "$f"

  if grep -qE '^[#[:space:]]*Port[[:space:]]+' "$f"; then
    sed -i -E "s|^[#[:space:]]*Port[[:space:]]+.*|Port ${SSH_PORT}|g" "$f"
  else
    echo "Port ${SSH_PORT}" >> "$f"
  fi

  if grep -qE '^[#[:space:]]*PermitRootLogin[[:space:]]+' "$f"; then
    sed -i -E "s|^[#[:space:]]*PermitRootLogin[[:space:]]+.*|PermitRootLogin no|g" "$f"
  else
    echo "PermitRootLogin no" >> "$f"
  fi

  if command -v sshd >/dev/null 2>&1; then
    sshd -t || { warn "sshd config test failed. Check $f"; exit 1; }
  fi

  systemctl restart ssh 2>/dev/null || true
  systemctl restart sshd 2>/dev/null || true
}

install_monitoring() {
  log "11) Creating /root/monitoring.sh"
  local m="/root/monitoring.sh"
  backup_file "$m"
  cat > "$m" <<"EOF"
#!/bin/bash
UNAME_S=`uname -s`
UNAME_RCMO=`uname -rvmo`
WHOAMI=`whoami`
MEMS=`top -b -n 1| head -n 4 | tail -n 1 | tr "," "\n" | tr ":" "\n" | head -n 3 | tail -n 2`
MEM_T=`echo ${MEMS} | tr -d " " | sed 's/total/\\n/g'`
MEM_TOTAL_=`echo ${MEM_T} | sed 's/ /\\n/g'|head -n 1|tr -dc '[[:print:]]\n'| sed 's|\[m\[39;49m\[1m||g' | sed 's|\[m\[39;49m||g'|tr -d 'B('|awk '{printf("%d",$1)}'`
MEM_NOW_=`echo ${MEM_T} | sed 's/ /\\n/g'|tail -n 1 |tr -dc '[[:print:]]\n'| sed 's|\[m\[39;49m\[1m||g' | sed 's|\[m\[39;49m||g' |sed 's|free||g'|tr -d 'B('|awk '{printf("%d",$1)}'`
PERCENTAGE=`echo "${MEM_NOW_} ${MEM_TOTAL_}"|awk '{printf "%.2f", $1 / $2 * 100}'`
DISK_NOW=`df -BM -a | grep /dev/mapper/ | awk '{sum+=$3}END{print sum}' | tr -d '\n';printf "/";df -BM -a | grep /dev/mapper/ | awk '{sum+=$4}END{print sum}' | tr -d '\n';printf "MB (";df -BM -a | grep /dev/mapper/ | awk '{sum1+=$3 ; sum2+=$4 }END{printf "%d", sum1 / sum2 * 100}' | tr -d '\n';printf "%%)\n"`
CPU_USAGE=`top -b -n 1| head -n 3 | tail -n 1 | tr ':,' '\n' |head -n 2 | tail -n 1|sed 's| ||g'|sed 's|us||g'|tr -dc '[[:print:]]\n'|sed 's|\[m\[39;49m\[1m||g'|sed 's|\[m\[39;49m||g' | tr -d 'B('`;
LAST_REBOOT_DATA=`who -b | sed 's/^ *system boot  //g'`
LVM_USE=`cat /etc/fstab | grep "mapper" | wc -l | awk '{if($1 >= "1") {printf("yes")}else{printf("no")}}'`
TCP_CONNECTIONS=`ss -s |grep "TCP:" | tr ' ' '\n'|head -n 4|tail -n 1`
USERS=`users|tr ' ' '\n'|wc -l`
IP=`/usr/sbin/ifconfig | grep "broadcast" | tr " " "\n" | tail -n 7 | head -n 1`
MAC_ADDRESS=`/usr/sbin/ifconfig | grep "ether" | tr " " "\n" | tail -n 6 | head -n 1`
SUDO_CNT=`journalctl _COMM=sudo -q | grep -E 'sudo\[[0-9]+\]' | sed 's/sudo\[/\n/'|awk 'NR%2==0'|sed 's/\]:/\n/' | awk 'NR%2==1' | sort -u |wc -l`

echo "#Architecture: ${UNAME_S} ${WHOAMI} ${UNAME_RCMO}";
echo "#CPU physical : `grep "physical id" /proc/cpuinfo | wc -l`";
echo "#vCPU : `nproc`";
echo "#Memory Usage: ${MEM_NOW_}/${MEM_TOTAL_}MB (${PERCENTAGE}%)";
echo "#Disk Usage: ${DISK_NOW}"
echo "#CPU load: ${CPU_USAGE}%";
echo "#Last boot: ${LAST_REBOOT_DATA}";
echo "#LVM use: ${LVM_USE}";
echo "#Connections TCP : ${TCP_CONNECTIONS}";
echo "#User log : ${USERS}";
echo "#Network: IP ${IP} (${MAC_ADDRESS})"
echo "#Sudo : ${SUDO_CNT} cmd";
EOF
  chmod 755 "$m"

  log "8 & 11) Setting root crontab"
  local cron_line='*/10 * * * * /root/monitoring.sh 2> /dev/null | wall'
  local tmp
  tmp="$(mktemp)"
  (crontab -l 2>/dev/null || true) > "$tmp"
  grep -qxF "$cron_line" "$tmp" || echo "$cron_line" >> "$tmp"

  local path_line='PATH=/usr/bin:/bin:/usr/sbin:/sbin:/usr/local/bin'
  grep -qxF "$path_line" "$tmp" || { echo "$path_line" | cat - "$tmp" > "${tmp}.new" && mv "${tmp}.new" "$tmp"; }

  crontab "$tmp"
  rm -f "$tmp"

  systemctl enable --now cron 2>/dev/null || true
}

configure_login_defs() {
  log "9) Configuring /etc/login.defs password aging policy"
  local f="/etc/login.defs"
  backup_file "$f"
  replace_or_append_kv "PASS_MAX_DAYS" "30" "$f"
  replace_or_append_kv "PASS_MIN_DAYS" "2"  "$f"
  replace_or_append_kv "PASS_WARN_AGE" "7"  "$f"
}

configure_pam_pwquality() {
  log "10) Configuring /etc/pam.d/common-password (pam_pwquality)"
  local f="/etc/pam.d/common-password"
  backup_file "$f"
  local opts='minlen=10 ucredit=-1 lcredit=-1 dcredit=-1 maxrepeat=3 reject_username difok=7 enforce_for_root'

  if grep -qE 'pam_pwquality\.so' "$f"; then
    local line
    line="$(grep -nE 'pam_pwquality\.so' "$f" | head -n 1)"
    local lno="${line%%:*}"
    local content="${line#*:}"
    local new="$content"
    for o in $opts; do
      if ! grep -qE "(^|[[:space:]])${o}([[:space:]]|$)" <<<"$new"; then
        new="${new} ${o}"
      fi
    done
    sed -i "${lno}s|.*|${new}|" "$f"
  else
    if grep -qE 'pam_unix\.so' "$f"; then
      sed -i -E "0,/pam_unix\.so/s||password requisite pam_pwquality.so ${opts}\n&|" "$f"
    else
      echo "password requisite pam_pwquality.so ${opts}" >> "$f"
    fi
  fi
}

enable_apparmor() {
  log "12) Enabling AppArmor"
  systemctl enable --now apparmor
}

configure_ufw() {
  log "13) Configuring UFW"
  ufw --force reset >/dev/null 2>&1 || true
  ufw default deny incoming
  ufw default allow outgoing
  ufw allow "${SSH_PORT}/tcp"
  yes | ufw enable
}

configure_network_static() {
  log "14) Configuring static IP for ${IFACE} in /etc/network/interfaces"
  local f="/etc/network/interfaces"
  backup_file "$f"

  sed -i -E "s|^([[:space:]]*iface[[:space:]]+${IFACE}[[:space:]]+inet[[:space:]]+)dhcp|\1dhcp # disabled by born2beroot_setup|g" "$f" || true

  if grep -qE "^iface[[:space:]]+${IFACE}[[:space:]]+inet[[:space:]]+static" "$f"; then
    awk -v IFACE="$IFACE" '
      BEGIN{del=0}
      $0 ~ "^iface[[:space:]]+"IFACE"[[:space:]]+inet[[:space:]]+static" {del=1; next}
      del==1 && ($0 ~ "^(iface|allow-hotplug|auto|source)[[:space:]]" || $0 ~ "^[[:space:]]*$") {del=0}
      del==0 {print}
    ' "$f" > "${f}.tmp" && mv "${f}.tmp" "$f"
  fi

  if ! grep -qE "^allow-hotplug[[:space:]]+${IFACE}\b" "$f"; then
    echo "allow-hotplug ${IFACE}" >> "$f"
  fi

  cat >> "$f" <<EOF

# Static IPv4 (Born2beRoot)
iface ${IFACE} inet static
  address ${STATIC_IP}
  netmask ${NETMASK}
  gateway ${GATEWAY}
EOF

  if [[ -n "${SSH_CONNECTION:-}" ]]; then
    warn "SSH session detected. Networking restart skipped. Reboot later to apply static IP."
  else
    systemctl restart networking 2>/dev/null || true
    ifdown "$IFACE" 2>/dev/null || true
    ifup "$IFACE" 2>/dev/null || true
  fi
}
configure_sudoers_logging() {
  log "3.x) Configuring sudo I/O logging via /etc/sudoers.d (validated by visudo)"

  # iolog_dir가 실제로 존재해야 평가에서 OK가 나오는 경우가 많음
  mkdir -p /var/log/sudo
  chown root:root /var/log/sudo
  chmod 750 /var/log/sudo

  local d="/etc/sudoers.d"
  local f="${d}/born2beroot"

  mkdir -p "$d"
  chmod 750 "$d"
  chown root:root "$d"

  # 드롭인 파일 생성 (sudoers 본파일 직접 수정 X)
  cat > "$f" <<'EOF'
Defaults  authfail_message="%d incorrect password attempts"
Defaults  badpass_message="Incorrect password"
Defaults  log_input
Defaults  log_output
Defaults  requiretty
Defaults  iolog_dir="/var/log/sudo/"
Defaults  passwd_tries=3
Defaults  secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin:/snap/bin"
EOF

  chmod 440 "$f"
  chown root:root "$f"

  # visudo로 문법 검증 (문법 틀리면 바로 중단)
  if ! visudo -c -f "$f"; then
    warn "visudo validation failed for $f"
    exit 1
  fi

  # 전체 sudo 설정도 같이 검증(안전)
  if ! visudo -c; then
    warn "visudo validation failed for /etc/sudoers"
    exit 1
  fi
}

main() {
  require_root
  ensure_target_user

  install_packages
  setup_path
  add_user_to_sudo
  configure_sudoers_logging
  configure_ssh
  configure_login_defs
  configure_pam_pwquality
  install_monitoring
  enable_apparmor
  configure_ufw
  configure_network_static

  log "DONE"
  echo "Reboot recommended: reboot"
}

main "$@"
