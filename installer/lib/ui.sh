#!/usr/bin/env bash
# lib/ui.sh — Aether installer UI primitives (palette from src/styles.css, forge scheme)
# 24-bit color with whiptail/select fallbacks. Two-column "neofetch" blocks, ▸ prompt.

AE_BG='\e[48;2;22;18;15m';    AE_FG='\e[38;2;243;234;223m'
AE_MUTED='\e[38;2;181;160;144m'; AE_ACC='\e[38;2;224;122;56m'
AE_ACC_BG='\e[48;2;224;122;56m'; AE_LINE='\e[38;2;107;60;28m'
AE_OK='\e[38;2;127;183;126m';  AE_R='\e[0m'

ui_truecolor() { [[ "${COLORTERM:-}" =~ (truecolor|24bit) ]] || [[ "$TERM" == xterm-256color ]]; }

hr()     { local w=${COLUMNS:-$(tput cols 2>/dev/null || echo 60)}; printf "${AE_LINE}%*s${AE_R}\n" "$w" '' | tr ' ' '─'; }
header() { clear; printf "\n  ${AE_ACC}Aether Installer${AE_R} ${AE_MUTED}· termux · %s${AE_R}\n" "$1"; hr; echo; }
kv()     { printf "  ${AE_MUTED}%-8s${AE_R}%s\n" "$1" "$2"; }               # kv os "Debian 12"
ok()     { printf "  ${AE_OK}✔${AE_R} %s\n" "$*"; }
warn()   { printf "  ${AE_ACC}▲${AE_R} %s\n" "$*"; }
die()    { printf "  ${AE_ACC}✖ %s${AE_R}\n" "$*" >&2; exit 1; }
log()    { printf '%s %s\n' "$(date +%T)" "$*" >>"$AE_HOME/install.log"; }

# menu VAR "Title" "opt1" "opt2" ...   → sets VAR to 1-based index
menu() {
  local __var=$1 title=$2; shift 2; local opts=("$@") cur=0 n=${#opts[@]} key
  if ! ui_truecolor && command -v whiptail >/dev/null; then
    local args=() i; for i in "${!opts[@]}"; do args+=("$((i+1))" "${opts[$i]}"); done
    NEWT_COLORS='root=,black window=,black border=brightred,black title=brightred,black
      listbox=white,black actlistbox=black,brightred button=black,brightred' \
    printf -v "$__var" '%s' "$(whiptail --title "$title" --menu "" 20 70 "$n" "${args[@]}" 3>&1 1>&2 2>&3)"
    return
  fi
  if ! ui_truecolor; then
    if [[ ! -t 0 ]]; then
      # non-interactive (pipe/cron): auto-select first option
      printf -v "$__var" '%s' "1"; return
    fi
    PS3="  ${title} ▸ "; select _ in "${opts[@]}"; do printf -v "$__var" '%s' "$REPLY"; break; done; return
  fi
  printf "  ${AE_FG}%s${AE_R}\n\n" "$title"; tput civis
  if [[ ! -t 0 ]]; then
    # non-interactive: auto-select first option
    tput cnorm; echo; printf -v "$__var" '%s' "1"; return
  fi
  while :; do
    local i; for i in "${!opts[@]}"; do
      if ((i==cur)); then printf "  ${AE_ACC_BG}${AE_BG/48/38}  %d  %-40s${AE_R}\n" "$((i+1))" "${opts[$i]}"
      else printf "  ${AE_MUTED}  %d  ${AE_R}%s\n" "$((i+1))" "${opts[$i]}"; fi
    done
    printf "\n  ${AE_MUTED}↑↓ move · ⏎ select · q quit${AE_R}"
    IFS= read -rsn1 key
    case $key in
      $'\x1b') read -rsn2 key; [[ $key == '[A' ]] && ((cur=(cur-1+n)%n)); [[ $key == '[B' ]] && ((cur=(cur+1)%n));;
      [1-9]) ((key<=n)) && { cur=$((key-1)); break; };;
      '') break;; q) tput cnorm; die "aborted";;
    esac
    tput cuu $((n+2)); tput ed
  done
  tput cnorm; echo; printf -v "$__var" '%s' "$((cur+1))"
}

confirm() { if [[ ! -t 0 ]]; then return 0; fi; printf "  ${AE_FG}%s${AE_R} ${AE_MUTED}[y/N]${AE_R} " "$1"; read -r a; [[ $a =~ ^[Yy] ]]; }

# spinner "msg" cmd...   — reference script's dot animation, but bound to a real job
spinner() {
  local msg=$1; shift; "$@" >>"$AE_HOME/install.log" 2>&1 & local pid=$! d=0
  while kill -0 $pid 2>/dev/null; do printf "\r  ${AE_MUTED}%s%-5s${AE_R}" "$msg" "$(printf '.%.0s' $(seq 0 $((d%5))))"; ((d++)); sleep .4; done
  wait $pid && { printf '\r'; ok "$msg"; } || { printf '\r'; warn "$msg failed (see install.log)"; return 1; }
}

wait_for_socket() { local s=$1 t=${2:-20}; while ((t--)); do [[ -S $s ]] && return 0; sleep 1; done; return 1; }
