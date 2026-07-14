#!/usr/bin/env fish
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
#  ◈ BITE-OS  ·  © 2026 GLITCH-BITE404  ·  // THE SYSTEM BIT YOU
#  https://github.com/GLITCH-BITE404/BITE-OS  ·  GPLv3 — keep this notice
# ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
# BITE-OS Glitch Mode HUD — hollywood DEDSEC trace output (black bg, amber text).

function header
    printf '\033[2J\033[H'
    printf '\033[1;33m╔══════════════════════════════════════╗\033[0m\n'
    printf '\033[1;33m║      BITE-OS  //  GLITCH MODE        ║\033[0m\n'
    printf '\033[1;31m║      ▓▓ TRACE ACTIVE ▓▓              ║\033[0m\n'
    printf '\033[1;33m╚══════════════════════════════════════╝\033[0m\n\n'
end

set --local lines \
    "[+] handshake established with 0xB1TE.relay" \
    "[+] route via tor::guard-7   lat 38ms" \
    "[+] keylog daemon  ..............  IDLE" \
    "[+] mic capture   ...............  ARMED" \
    "[+] cam capture   ...............  ARMED" \
    "[+] uplink active   tx=14.2MB rx=982KB" \
    "[+] payload queued  // size 4.2k" \
    "[+] sniffer  ....................  PASSIVE" \
    "[!] kernel ring buffer compromised" \
    "[!] selinux  ....................  BYPASSED" \
    "[!] firewall  ...................  BLIND" \
    "[+] target.lat  41.0082  lon 28.9784" \
    "[+] decoy traffic generated  17 streams" \
    "[+] mac spoof  ..................  ROTATED" \
    "[+] dns over tor  ...............  OK" \
    "[+] rootkit injected  ...........  STAGE 2" \
    "[+] kernel symbol table  ........  HOOKED" \
    "[+] exfil channel  // 0xB1TE.relay <- ok"

header

while true
    set --local idx (random 1 (count $lines))
    set --local line $lines[$idx]
    # Default: bright amber/yellow (hollywood)
    set --local color "\033[1;33m"
    if string match -qr '^\[!\]' -- $line
        set color "\033[1;31m"
    end
    printf "%b%s\033[0m\n" "$color" $line
    set --local d (random 2 7)
    sleep 0.$d
    if test (random 1 22) -eq 1
        header
    end
end
