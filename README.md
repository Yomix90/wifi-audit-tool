# WiFi Audit Toolkit

Script Bash interactif et automatisé pour l'audit de sécurité et l'analyse de réseaux sans fil sous Linux (Ubuntu, Debian, Kali Linux).

> **⚠️ Avertissement légal :** Cet outil est conçu à des fins éducatives et de test de sécurité défensif uniquement sur des réseaux pour lesquels vous disposez d'une autorisation explicite.

---

## 🚀 Fonctionnalités

- **Sélection automatique** des interfaces réseau WiFi sans saisie manuelle.
- **Scan et tableau interactif** : Détection des réseaux à proximité (BSSID, ESSID, Canal, Signal, Chiffrement) avec sélection par numéro.
- **Gestion des clients connectés** : Détection automatique des stations associées pour le ciblage.
- **Captures & Audits** : Handshake WPA/WPA2, PMKID sans client, audit WPS (Reaver), intégration Wifite.
- **Cracking & Analyse** : Détection automatique des fichiers `.cap` récents et des wordlists (`rockyou.txt`, etc.).
- **Gestion des interfaces** : Activation/désactivation propre du mode monitor, changement d'adresse MAC et restauration de NetworkManager.

---

## 📦 Installation depuis GitHub

Clonez le dépôt directement sur votre machine Linux :

```bash
# Cloner le dépôt
git clone https://github.com/yomix90/wifi-audit-tool.git

# Accéder au dossier
cd wifi-audit-tool

# Rendre le script exécutable
chmod +x wifi_audit.sh
```

---

## 📋 Dépendances & Prérequis

Installez les outils nécessaires via `apt` (ou laissez le script les installer automatiquement au premier lancement) :

```bash
sudo apt update
sudo apt install -y aircrack-ng wifite reaver pixiewps hcxdumptool hcxtools macchanger wireless-tools iw
```

---

## 💻 Lancement

Exécutez le script avec les privilèges root (`sudo`) :

```bash
sudo ./wifi_audit.sh
```
