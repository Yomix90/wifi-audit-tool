# ⚡ WiFi Audit & Security Toolkit ⚡

Script Bash interactif, modulaire et automatisé pour l'audit de sécurité, l'analyse et les tests de robustesse des réseaux sans fil sous Linux (Kali Linux, Ubuntu, Debian).

> **⚠️ AVERTISSEMENT LÉGAL :** Cet outil est développé à des fins éducatives et d'audit de sécurité défensif uniquement sur des infrastructures pour lesquelles vous possédez une autorisation écrite et explicite.

---

## 📦 Installation depuis GitHub

Clonez le dépôt directement sur votre machine Linux :

```bash
# 1. Cloner le dépôt
git clone https://github.com/yomix90/wifi-audit-tool.git

# 2. Accéder au dossier
cd wifi-audit-tool

# 3. Rendre le script exécutable
chmod +x wifi_audit.sh
```

---

## 💻 Lancement

Exécutez le script avec les privilèges root (`sudo`) :

```bash
sudo ./wifi_audit.sh
```

---

## 🗺️ Guide Complet des Menus & Options Disponibles

Le script s'articule autour d'un menu principal structuré et de sous-menus dédiés :

```
========================= MENU PRINCIPAL =========================
  [1] 📡 Gestion Interface & Monitor
  [2] 🔍 Scanner & Sélectionner une Cible
  [3] 🎯 Captures Classiques (Handshake/PMKID/WPS)
  [4] 👻 Attaques Avancées (Evil Twin/Karma)
  [5] 🔑 Cracking & Analyse
  [6] 🛡️ Tests de Robustesse (KRACK/FragAttacks)
  [7] 📦 Vérifier / Installer dépendances
  [8] 🔄 Restaurer le réseau
  [9] ⬆️  Mettre à jour le script depuis GitHub
  [0] 🚪 Quitter
==================================================================
```

---

### 📡 [1] Gestion Interface & Monitor
- **`[1] Sélectionner interface WiFi`** : Détecte toutes les cartes sans fil avec leur nom, adresse MAC et pilote, et permet la sélection par numéro.
- **`[2] Activer mode monitor`** : Arrête les processus conflictuels (`airmon-ng check kill`) et active le mode moniteur (`wlan0mon`).
- **`[3] Désactiver mode monitor`** : Désactive le mode monitor et restaure l'interface en mode géré (`managed`).
- **`[4] Changer adresse MAC`** : Génération d'une MAC aléatoire, saisie d'une MAC personnalisée ou réinitialisation à la MAC constructeur via `macchanger`.
- **`[5] Test d'injection de paquets`** : Teste les capacités d'injection de la carte réseau sur différents canaux via `aireplay-ng --test`.
- **`[6] Sélectionner 2ème interface`** : Permet de configurer une carte secondaire pour les scénarios nécessitant deux interfaces.

---

### 🔍 [2] Scanner & Sélectionner une Cible (Automatique)
- **Scan Rapide (15s)** / **Scan Complet (30s)** / **Scan Continu** (arrêt manuel via `Ctrl+C`).
- **Parsing automatique** du scan `airodump-ng` : Affichage d'un tableau propre avec coloration du signal (BSSID, Canal, Puissance dBm, Chiffrement, ESSID).
- **Sélection directe** : Entrez simplement le numéro `[1..N]` de la cible pour l'enregistrer dans la session sans copier-coller.

---

### 🎯 [3] Captures Classiques (Handshake / PMKID / WPS)
- **`[1] Handshake WPA/WPA2`** :
  - Détection automatique des clients associés à la cible.
  - Déauthentification ciblée (`aireplay-ng`) sur un client précis ou en diffusion broadcast.
  - Écoute et validation automatique de la capture du 4-way handshake.
- **`[2] PMKID (hcxdumptool)`** : Capture de hashs PMKID côté borne AP (sans aucun client connecté requis) et conversion au format Hashcat `22000`.
- **`[3] WPS Pixie Dust`** : Attaque hors-ligne sur les points d'accès avec WPS vulnérable via `reaver` / `pixiewps`.
- **`[4] Wifite automatisé`** : Lance l'outil tout-en-un `wifite` sur l'interface de monitoring.

---

### 👻 [4] Attaques Avancées
- **`[1] Evil Twin classique`** : Création d'un faux point d'accès jumeau (`airbase-ng` / `hostapd`) avec passerelle DHCP (`dnsmasq`).
- **`[2] Evil Twin Wifiphisher`** : Intégration automatisée avec `wifiphisher`.
- **`[3] Karma Attack (MANA)`** : Réponse proactive aux requêtes de sondage (Probe Requests) des appareils clients.
- **`[4] Détection Rogue AP`** : Analyse des beacons pour détecter les points d'accès suspects ou usurpateurs à proximité.
- **`[5] Stress Test (Deauth flood)`** : Test de charge et de résilience aux paquets de déauthentification.

---

### 🔑 [5] Cracking & Analyse
- **`[1] Vérifier handshake dans .cap`** : Analyse les paquets EAPOL dans les captures `.cap` pour confirmer leur intégrité.
- **`[2] Cracker handshake WPA (aircrack-ng)`** :
  - Détection automatique des fichiers `.cap` récents.
  - Détection automatique des dictionnaires (`rockyou.txt`, `fasttrack.txt`, etc.) avec décompression automatique des archives `.gz`.
- **`[3] Cracker PMKID`** : Cracking des hashs PMKID (22000) via `hashcat` ou `aircrack-ng`.

---

### 🛡️ [6] Tests de Robustesse
- **`[1] Test KRACK`** : Vérifie la vulnérabilité de l'infrastructure à la réinstallation de clés (Key Reinstallation Attack).
- **`[2] Test FragAttacks`** : Analyse la résistance aux failles de fragmentation et d'agrégation de trames.
- **`[3] Test injection de paquets`** : Évalue la qualité et le taux de succès d'injection sur le point d'accès.
- **`[4] Vérifier PMF (802.11w)`** : Teste si le réseau applique les trames de gestion protégées contre l'usurpation.

---

### ⚙️ [7] à [9] Outils & Maintenance
- **`[7] Vérifier / Installer dépendances`** : Contrôle la présence des outils indispensables et propose l'installation automatique via `apt`.
- **`[8] Restaurer le réseau`** : Désactive le mode monitor, réinitialise `iptables`, tue les processus résiduels et redémarre `NetworkManager` et `wpa_supplicant`.
- **`[9] Mettre à jour le script depuis GitHub`** : Vérifie la dernière version sur GitHub, télécharge la mise à jour et sauvegarde automatiquement l'ancienne version.
- **`[0] Quitter`** : Fermeture propre avec proposition de restauration du réseau.

---

## 📋 Dépendances Logicielles

| Catégorie | Outils |
| :--- | :--- |
| **Essentiels** | `iw`, `aircrack-ng`, `airodump-ng`, `airmon-ng`, `aireplay-ng`, `macchanger`, `curl` |
| **Optionnels** | `wifite`, `reaver`, `pixiewps`, `hcxdumptool`, `hcxtools`, `hashcat`, `hostapd`, `dnsmasq`, `wifiphisher`, `tshark` |
