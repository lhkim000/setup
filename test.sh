#!/bin/bash

# -=-=-=-=- CLRS -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- #

DEF_COLOR='\033[0;39m'
BLACK='\033[0;30m'
RED='\033[1;91m'
GREEN='\033[1;92m'
YELLOW='\033[0;93m'
BLUE='\033[0;94m'
MAGENTA='\033[0;95m'
CYAN='\033[0;96m'
GRAY='\033[0;90m'
WHITE='\033[0;97m'

printf "${BLUE}\n-------------------------------------------------------------\n${DEF_COLOR}"
printf "${YELLOW}\n\t\tTEST CREATED BY: ${DEF_COLOR}"
printf "${CYAN}GEMARTIN\t\n${DEF_COLOR}"
printf "${BLUE}\n-------------------------------------------------------------\n${DEF_COLOR}"

# -=-=-=-=- Control errors -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- #

USER="$(whoami)"
if [ "$USER" != "root" ]; then
  printf "${RED}You must be in the root user to run the test.${DEF_COLOR}\n"
  exit 1
fi

# -=-=-=-=- Graphical environment -=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=-=- #

RES="$(ls /usr/bin/*session 2>/dev/null)"
printf "${MAGENTA}Graphical enviroment${DEF_COLOR}\n"
if echo "$RES" | grep -qx "/usr/bin/dbus-run-session"; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  # 원본은 "== /usr/bin/dbus-run-session" 딱 한 개만 잡는 방식이라,
  # glob 결과가 여러 개면 KO가 날 수 있어 그대로 두되 에러는 없게 처리.
  if echo "$RES" | grep -q "/usr/bin/dbus-run-session"; then
    printf "${GREEN}[OK] ${DEF_COLOR}\n"
  else
    printf "${RED}[KO] ${DEF_COLOR}\n"
  fi
fi

echo
printf "${MAGENTA}Disk partitions${DEF_COLOR}\n"

RES="$(lsblk | grep -c lvm)"
if [ "$RES" -gt 1 ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

RES="$(lsblk | grep -c home)"
if [ "$RES" -gt 0 ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

RES="$(lsblk | grep -c swap)"
if [ "$RES" -gt 0 ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

RES="$(lsblk | grep -c root)"
if [ "$RES" -gt 0 ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

echo
printf "${MAGENTA}SSH${DEF_COLOR}\n"

RES="$(service ssh status 2>/dev/null | awk '$1=="Active:"' | grep -c running)"
if [ "$RES" -gt 0 ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

RES="$(command -v lsof >/dev/null 2>&1; echo $?)"
if [ "$RES" -ne 0 ]; then
  apt-get update -qq -y > /dev/null 2>&1
  apt-get install -qq -y lsof > /dev/null 2>&1
fi

RES="$(lsof -i -P -n 2>/dev/null | grep sshd | grep LISTEN | grep -c 4242)"
if [ "$RES" -gt 1 ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

echo
printf "${MAGENTA}UFW${DEF_COLOR}\n"

RES="$(ufw status 2>/dev/null | grep -v ALLOW | grep -c active)"
if [ "$RES" -gt 0 ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

RES="$(ufw status 2>/dev/null | grep -c 4242)"
if [ "$RES" -gt 1 ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

echo
printf "${MAGENTA}Hostname${DEF_COLOR}\n"

RES="$(who | head -1 | cut -d ' ' -f1)"
CONCAT="42"
RES="${RES}${CONCAT}"
RES2="$(hostname)"

if [ "$RES" = "$RES2" ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

echo
printf "${MAGENTA}Password policy${DEF_COLOR}\n"

RES="$(grep -o 'minlen=10' /etc/pam.d/common-password 2>/dev/null | head -n 1)"
if [ "$RES" = "minlen=10" ]; then
  printf "${GREEN}1.[OK] ${GRAY} minlen ${DEF_COLOR}\n"
else
  printf "${RED}1.[KO] ${GRAY} minlen ${DEF_COLOR}\n"
fi

RES="$(grep -o 'ucredit=-1' /etc/pam.d/common-password 2>/dev/null | head -n 1)"
if [ "$RES" = "ucredit=-1" ]; then
  printf "${GREEN}2.[OK] ${GRAY} uppercase ${DEF_COLOR}\n"
else
  printf "${RED}2.[KO] ${GRAY} uppercase ${DEF_COLOR}\n"
fi

RES="$(grep -o 'lcredit=-1' /etc/pam.d/common-password 2>/dev/null | head -n 1)"
if [ "$RES" = "lcredit=-1" ]; then
  printf "${GREEN}3.[OK] ${GRAY} lowercase ${DEF_COLOR}\n"
else
  printf "${RED}3.[KO] ${GRAY} lowercase ${DEF_COLOR}\n"
fi

RES="$(grep -o 'dcredit=-1' /etc/pam.d/common-password 2>/dev/null | head -n 1)"
if [ "$RES" = "dcredit=-1" ]; then
  printf "${GREEN}4.[OK] ${GRAY} digit ${DEF_COLOR}\n"
else
  printf "${RED}4.[KO] ${GRAY} digit ${DEF_COLOR}\n"
fi

RES="$(grep -o 'maxrepeat=3' /etc/pam.d/common-password 2>/dev/null | head -n 1)"
if [ "$RES" = "maxrepeat=3" ]; then
  printf "${GREEN}5.[OK] ${GRAY} consecutive char ${DEF_COLOR}\n"
else
  printf "${RED}5.[KO] ${GRAY} consecutive char ${DEF_COLOR}\n"
fi

RES="$(grep -o 'difok=7' /etc/pam.d/common-password 2>/dev/null | head -n 1)"
if [ "$RES" = "difok=7" ]; then
  printf "${GREEN}6.[OK] ${GRAY} difok ${DEF_COLOR}\n"
else
  printf "${RED}6.[KO] ${GRAY} difok ${DEF_COLOR}\n"
fi

RES="$(grep -o 'enforce_for_root' /etc/pam.d/common-password 2>/dev/null | head -n 1)"
if [ "$RES" = "enforce_for_root" ]; then
  printf "${GREEN}7.[OK] ${GRAY} enforce for root ${DEF_COLOR}\n"
else
  printf "${RED}7.[KO] ${GRAY} enforce for root ${DEF_COLOR}\n"
fi

RES="$(grep -o 'reject_username' /etc/pam.d/common-password 2>/dev/null | head -n 1)"
if [ "$RES" = "reject_username" ]; then
  printf "${GREEN}8.[OK] ${GRAY} reject username ${DEF_COLOR}\n"
else
  printf "${RED}8.[KO] ${GRAY} reject username ${DEF_COLOR}\n"
fi

RES="$(grep -E '^PASS_MAX_DAYS' /etc/login.defs 2>/dev/null | awk '{print $2}' | head -n 1)"
if [ "$RES" = "30" ]; then
  printf "${GREEN}9.[OK] ${GRAY} passwd expire days ${DEF_COLOR}\n"
else
  printf "${RED}9.[KO] ${GRAY} passwd expire days ${DEF_COLOR}\n"
fi

RES="$(grep -E '^PASS_MIN_DAYS' /etc/login.defs 2>/dev/null | awk '{print $2}' | head -n 1)"
if [ "$RES" = "2" ]; then
  printf "${GREEN}10.[OK] ${GRAY} days allowed before the modification ${DEF_COLOR}\n"
else
  printf "${RED}10.[KO] ${GRAY} days allowed before the modification ${DEF_COLOR}\n"
fi

RES="$(grep -E '^PASS_WARN_AGE' /etc/login.defs 2>/dev/null | awk '{print $2}' | head -n 1)"
if [ "$RES" = "7" ]; then
  printf "${GREEN}11.[OK] ${GRAY} warning message ${DEF_COLOR}\n"
else
  printf "${RED}11.[KO] ${GRAY} warning message ${DEF_COLOR}\n"
fi

if [ -d "/var/log/sudo/" ]; then
  printf "${GREEN}12.[OK] ${GRAY} folder /var/log/sudo exist ${DEF_COLOR}\n"
else
  printf "${RED}12.[KO] ${GRAY} folder /var/log/sudo exist ${DEF_COLOR}\n"
fi

echo
printf "${MAGENTA}Crontab${DEF_COLOR}\n"

RES="$(crontab -l 2>/dev/null | grep -F monitoring.sh | awk '$1=="*/10"{print $1; exit}')"
if [ "$RES" = "*/10" ]; then
  printf "${GREEN}[OK] ${DEF_COLOR}\n"
else
  printf "${RED}[KO] ${DEF_COLOR}\n"
fi

echo
