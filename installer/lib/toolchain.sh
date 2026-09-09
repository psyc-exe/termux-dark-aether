#!/usr/bin/env bash
# lib/toolchain.sh + lib/agents.sh — steps 1-4

APT='DEBIAN_FRONTEND=noninteractive apt-get -y -o Dpkg::Options::=--force-unsafe-io -o Dpkg::Options::=--force-confnew'

step_base_os() {
  header "base os"
  menu c "Base distribution" "Debian — latest stable" "Ubuntu — latest LTS"
  AE_DISTRO=$([[ $c == 1 ]] && echo debian || echo ubuntu); state_save AE_DISTRO
  [[ $AE_EXEC == chroot ]] && chroot_setup || proot_install
  run_in_distro "echo 'path-exclude /usr/share/man/*' >/etc/dpkg/dpkg.cfg.d/01_nodoc; $APT update && $APT install ca-certificates curl gnupg sudo dbus-x11 locales"
  run_in_distro "id aether >/dev/null 2>&1 || (useradd -m -s /bin/bash -G sudo aether && echo 'aether ALL=(ALL) NOPASSWD:ALL' >/etc/sudoers.d/aether)"
}

step_toolchain() {
  header "toolchain"
  menu c "Security toolchain overlay" "Kali NetHunter — kali-rolling" "Parrot OS — lory" "None"
  case $c in
    1) [[ $AE_DISTRO == ubuntu ]] && { warn "Kali overlay on Ubuntu breaks libc ABI — using Debian base is required"; return 1; }; overlay_kali;   AE_TOOL=kali;;
    2) [[ $AE_DISTRO == ubuntu ]] && { warn "Parrot overlay requires Debian 12 base"; return 1; };                          overlay_parrot; AE_TOOL=parrot;;
    3) AE_TOOL=none;;
  esac; state_save AE_TOOL
}

overlay_kali() {
  run_in_distro "curl -fsSL https://archive.kali.org/archive-keyring.gpg -o /usr/share/keyrings/kali-archive-keyring.gpg
    echo 'deb [signed-by=/usr/share/keyrings/kali-archive-keyring.gpg] http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware' >/etc/apt/sources.list.d/kali.list
    printf 'Package: *\nPin: release o=Kali\nPin-Priority: 50\n' >/etc/apt/preferences.d/kali   # opt-in only: apt -t kali-rolling
    $APT update"
  ok "Kali repo pinned at 50 — base stays Debian, tools pulled with -t kali-rolling"
}

overlay_parrot() {
  run_in_distro "curl -fsSL https://deb.parrot.sh/parrot/misc/parrotsec.gpg | gpg --dearmor -o /usr/share/keyrings/parrot.gpg
    echo 'deb [signed-by=/usr/share/keyrings/parrot.gpg] https://deb.parrot.sh/parrot lory main contrib non-free non-free-firmware' >/etc/apt/sources.list.d/parrot.list
    printf 'Package: *\nPin: release o=Parrot\nPin-Priority: 50\n' >/etc/apt/preferences.d/parrot
    $APT update"
}

step_footprint() {
  [[ $AE_TOOL == none ]] && return
  header "footprint"
  menu c "Installation footprint" "Minimal — base utilities" "Top-10 security tools" "Full toolchain (10+ GB, slow under proot)"
  local t=$([[ $AE_TOOL == kali ]] && echo kali-rolling || echo lory) pk
  case "$AE_TOOL$c" in
    kali1)   pk=kali-linux-core;;    kali2) pk=kali-tools-top10;;  kali3) pk=kali-linux-headless;;
    parrot1) pk=parrot-core;;
    parrot2) pk="nmap metasploit-framework sqlmap aircrack-ng hydra john wireshark burpsuite nikto gobuster";;
    parrot3) pk=parrot-tools-full;;
  esac
  ((c==3)) && ! confirm "Full install can exceed 10 GB and hours under proot. Continue?" && return
  termux-wake-lock
  spinner "installing $pk" run_in_distro "$APT -t $t install $pk"
  termux-wake-unlock
  # metasploit needs postgres, no systemd → service wrapper (lib/services.sh)
  [[ $pk == *metasploit* || $pk == *top10* ]] && svc_register postgresql
}

# ── step 4: agentic CLIs ─────────────────────────────────────────────────────
# Reality (Sept 2026): Codex is Rust (codex-rs), Claude Code and OpenCode are
# compiled binaries. "npm i" often just fetches a native binary. TermuxVoid
# packages third-party forks (@mmmbuto/codex-cli-termux) or runs glibc builds
# via a C loader pointing at $PREFIX/glibc/lib/ld-linux-aarch64.so.1 — those are
# packaging strategies, not upstream support. Cline and Kilo Code build with
# Bun and have explicit glibc/musl interpreter lists; Android is NOT a target.
# Community reports (cline#8455 GLIBC_2.34 missing, kilo#12445 PRoot failure,
# cline#13722 hardcoded /bin/bash) prove these are fragile. Strategy:
#   A. Native Termux: try the official binary first; if it fails on bionic,
#      fall back to termuxvoid's glibc-loader or third-party fork.
#   B. Distro: install in Debian/glibc where node/bun run natively; wrap in
#      $AE_HOME/bin for Termux access. This is the reliable path for Cline/Kilo.
step_agents() {
  header "agentic ai"
  kv model "hybrid — official binaries where possible, distro for glibc-only tools"
  menu c "Agentic coding CLIs" "Native set: codex · claude-code · opencode (try native, fall back to glibc/fork)" "Distro set: cline · kilo-code · code-server (glibc native)" "Both" "Skip"
  install -d -m700 "$AE_HOME"; touch "$AE_HOME/agent.env"; chmod 600 "$AE_HOME/agent.env"
  [[ $c == 1 || $c == 3 ]] && agents_native
  [[ $c == 2 || $c == 3 ]] && agents_distro
}

agents_native() {
  spinner "node (termux)" pkg install -y nodejs-lts git ripgrep
  # Try official Codex first — its launcher has an Android case but ships musl
  # binaries; often crashes on bionic. If it fails, install termuxvoid's fork.
  if ! spinner "codex (official)" npm i -g @openai/codex; then
    warn "official codex failed — trying termuxvoid fork @mmmbuto/codex-cli-termux"
    spinner "codex (fork)" npm i -g @mmmbuto/codex-cli-termux@0.150.1
  fi
  # Claude Code / OpenCode ship linux-arm64 glibc builds; use termuxvoid's
  # loader wrappers if the repo is enabled, else skip with a warning.
  if pkg list-all 2>/dev/null | grep -q '^claude-code/'; then
    spinner "claude-code (termuxvoid)" pkg install -y claude-code
    spinner "opencode (termuxvoid)" pkg install -y opencode
  else
    warn "claude-code/opencode need glibc — enable termuxvoid repo or use Distro set"
  fi
  grep -q agent.env ~/.bashrc || echo "[ -f $AE_HOME/agent.env ] && . $AE_HOME/agent.env" >>~/.bashrc
}

agents_distro() {
  # Cline/Kilo build with Bun and list glibc/musl interpreters; Android bionic
  # is not a target. Install in Debian where the loader matches.
  run_in_distro "curl -fsSL https://deb.nodesource.com/setup_22.x | bash - && $APT install nodejs build-essential python3 ripgrep
    su - aether -c 'npm config set prefix ~/.npm-global && npm i -g @cline/cli @kilocode/cli code-server'"
  mkdir -p "$AE_HOME/bin"
  local t; for t in cline kilocode code-server; do
    cat >"$AE_HOME/bin/$t" <<EOF
#!/data/data/com.termux/files/usr/bin/bash
. $AE_HOME/agent.env 2>/dev/null
exec proot-distro login $AE_DISTRO --shared-tmp --user aether --kill-on-exit --bind \$HOME/storage/shared:/sdcard -- bash -lc 'PATH=~/.npm-global/bin:\$PATH exec $t "\$@"' -- "\$@"
EOF
    chmod +x "$AE_HOME/bin/$t"
  done
  grep -q '.aether/bin' ~/.bashrc || echo "export PATH=\"$AE_HOME/bin:\$PATH\"" >>~/.bashrc
  ok "glibc agents wrapped: cline · kilocode · code-server (run from Termux prompt)"
}
