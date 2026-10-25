# ShellFromBrowser

[![CI](https://github.com/valorisa/ShellFromBrowser/actions/workflows/ci.yml/badge.svg)](https://github.com/valorisa/ShellFromBrowser/actions/workflows/ci.yml)
[![Go Version](https://img.shields.io/github/go-mod/go-version/valorisa/ShellFromBrowser)](https://go.dev/)
[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-linux%20%7C%20macos%20%7C%20windows-lightgrey)](https://github.com/valorisa/ShellFromBrowser/releases)
[![Docker](https://img.shields.io/badge/docker-ready-2496ED?logo=docker&logoColor=white)](Dockerfile)

> 🇺🇸 **[Read in English](README.md)**

**Un terminal web traversant.** ShellFromBrowser fonctionne partout où un navigateur peut ouvrir un site web — aéroports, gares, réseaux d'entreprise, partout. Il utilise du HTTPS standard sur le port 443 : aucun firewall ne le distingue d'une visite web ordinaire.

Un émulateur de terminal web moderne et multiplateforme écrit en Go. Successeur spirituel de [ShellInBox](https://code.google.com/archive/p/shellinabox/) — réécrit intégralement avec WebSocket, xterm.js, client SSH intégré, multi-sessions, transfert de fichiers et enregistrement de sessions.

---

## Fonctionnalités

| Fonctionnalité | Description |
|----------------|-------------|
| **Terminal dans le navigateur** | Émulation complète xterm.js — 256 couleurs, Unicode, souris, presse-papiers |
| **Onglets multi-sessions** | Ouvrir plusieurs sessions terminal dans une seule fenêtre, basculer entre elles |
| **Client SSH** | Se connecter à des hôtes distants directement depuis le navigateur (`user@host:port`) |
| **Authentification** | Auth JWT avec hachage bcrypt des mots de passe, configurable par utilisateur |
| **TLS/HTTPS** | Support TLS intégré — fournir simplement les chemins vers le certificat et la clé |
| **Transfert de fichiers** | Upload/download via l'interface web avec protection contre le path traversal |
| **Enregistrement de sessions** | Enregistrer et rejouer les sessions au format asciicast v2 (compatible asciinema) |
| **Multiplateforme** | Fonctionne nativement sur Linux, macOS et Windows (ConPTY) |
| **Binaire unique** | Zéro dépendance runtime — frontend et assets embarqués via `go:embed` |
| **Docker ready** | Dockerfile multi-stage + docker-compose inclus |

---

## Démarrage rapide

### Prérequis

- [Go 1.27+](https://go.dev/dl/) installé (requis pour les Options 1, 2 et 4)
- [Docker](https://docs.docker.com/get-docker/) installé (requis pour l'Option 3 uniquement)

### Option 1 : Test rapide (aucune installation)

La manière la plus rapide d'essayer ShellFromBrowser. Fonctionne sur Windows, macOS et Linux — Go gère les différences cross-platform automatiquement.

```bash
git clone https://github.com/valorisa/ShellFromBrowser.git
cd ShellFromBrowser

# Lancer directement sans installer (compile et exécute en une seule étape)
go run ./cmd/shellfb
```

Puis ouvrir http://localhost:4200 dans votre navigateur. Vous devriez voir un terminal interactif (xterm.js).

> Ceci n'installe **rien** sur votre système. Go compile un binaire temporaire et l'exécute. Arrêter avec `Ctrl+C`.

### Option 2 : Installation globale

Installe le binaire `shellfb` dans votre `$GOPATH/bin` (ou `%GOPATH%\bin` sous Windows), le rendant disponible partout sur le système.

```bash
go install github.com/valorisa/ShellFromBrowser/cmd/shellfb@latest

# Lancer avec les paramètres par défaut (sans auth, port 4200)
shellfb

# Lancer avec une adresse personnalisée
shellfb --addr :3000

# Lancer avec un fichier de configuration
shellfb --config config.yaml

# Afficher la version
shellfb --version
```

Puis ouvrir http://localhost:4200 (ou votre port personnalisé) dans votre navigateur. Arrêter avec `Ctrl+C`.

### Option 3 : Docker (déploiement)

Le `docker-compose.yml` par défaut expose les ports 80/443 avec auto-TLS — conçu pour le déploiement en réseaux contraints (aéroports, gares, réseaux d'entreprise) où seul le trafic HTTPS standard passe les pare-feu.

```bash
git clone https://github.com/valorisa/ShellFromBrowser.git
cd ShellFromBrowser

# Créer votre configuration
cp config.example.yaml config.yaml
# Éditer config.yaml : domaine, auth, etc.

docker compose up -d
```

Ouvrir `https://votre-domaine.com` — le terminal est prêt. Pour arrêter : `docker compose down`.

> **Test local avec Docker ?** On peut lancer sans TLS :
> ```bash
> docker build -t shellfb .
> docker run --rm --name shellfb-test -p 4200:4200 shellfb
> ```
> Puis ouvrir http://localhost:4200. Arrêter avec `Ctrl+C`, ou depuis un autre terminal : `docker stop shellfb-test`.

### Option 4 : Compiler depuis les sources (Makefile)

Compile le binaire dans `./bin/shellfb`. Utile pour le développement ou le packaging.

```bash
git clone https://github.com/valorisa/ShellFromBrowser.git
cd ShellFromBrowser

# Compiler le binaire
make build

# Lancer
./bin/shellfb

# Exécuter les tests
make test
```

Puis ouvrir http://localhost:4200 dans votre navigateur. Arrêter avec `Ctrl+C`.

---

## Réseau contraint (aéroport, gare, entreprise)

ShellFromBrowser fonctionne partout où un navigateur peut ouvrir un site web.
Il utilise du HTTPS standard (port 443) et du WebSocket — aucun firewall ne
le distingue d'une visite sur un site web ordinaire.

Configuration minimale pour être accessible depuis n'importe quel réseau :

```bash
shellfb --domain shell.monserveur.com
```

Voir le [guide complet de déploiement en réseau contraint](docs/deploiement-reseaux-contraints.md).

---

## Configuration

Copier `config.example.yaml` vers `config.yaml` et personnaliser :

```yaml
server:
  addr: ":4200"
  tls:
    enabled: true
    cert: "/chemin/vers/cert.pem"
    key: "/chemin/vers/key.pem"

auth:
  enabled: true
  jwt_secret: "generez-une-chaine-aleatoire-ici"
  users:
    - username: admin
      password_hash: "$2a$10$..."
    - username: developpeur
      password_hash: "$2a$10$..."

shell:
  # Laisser vide pour la valeur système (SHELL sur Unix, COMSPEC sur Windows)
  command: ""
  env:
    - "TERM=xterm-256color"

sessions:
  max_per_user: 10
  idle_timeout: "30m"

ssh:
  enabled: true
  known_hosts: "~/.ssh/known_hosts"

recording:
  enabled: true
  dir: "./recordings"
```

### Générer un hash de mot de passe

```bash
shellfb hash-password
# Enter password: ********
# $2a$10$xxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxxx
```

Copier la sortie dans votre `config.yaml` sous `password_hash`.

### Options CLI

| Flag | Défaut | Description |
|------|--------|-------------|
| `--addr` | `:4200` | Adresse d'écoute (remplace le fichier de config) |
| `--config` | aucun | Chemin vers le fichier de configuration YAML |
| `--version` | — | Afficher la version et quitter |

Sous-commandes :

| Commande | Description |
|----------|-------------|
| `hash-password` | Générer un hash bcrypt pour la configuration |

---

## Utilisation du client SSH

Se connecter à des hôtes distants directement depuis le navigateur via une connexion WebSocket vers `/ws/ssh` :

```
ws://localhost:4200/ws/ssh?target=user@host.com:22&password=secret&token=JWT_TOKEN
```

Paramètres :
- `target` (requis) : Cible SSH au format `user@host:port` (port par défaut : 22)
- `password` : Authentification par mot de passe
- `key` : Chemin vers le fichier de clé privée (côté serveur)
- `token` : Jeton d'authentification JWT

---

## Points d'accès API

| Méthode | Chemin | Auth | Description |
|---------|--------|------|-------------|
| POST | `/api/login` | Non | S'authentifier et recevoir un jeton JWT |
| GET | `/api/sessions` | Oui | Lister les sessions terminal actives |
| DELETE | `/api/sessions?id=X` | Oui | Détruire une session spécifique |
| POST | `/api/upload` | Oui | Uploader un fichier (multipart) |
| GET | `/api/download?file=X` | Oui | Télécharger un fichier |
| GET | `/api/recordings` | Oui | Lister les sessions enregistrées |
| GET | `/api/recordings/get?id=X` | Oui | Récupérer les données d'enregistrement (asciicast v2) |
| WS | `/ws` | Oui | WebSocket terminal (shell local) |
| WS | `/ws/ssh` | Oui | WebSocket SSH (hôte distant) |

---

## Sécurité

- **Authentification** : Jetons JWT avec expiration configurable (24h par défaut)
- **Rate limiting** : Endpoint de login limité à 5 tentatives par minute par IP
- **En-têtes de sécurité** : CSP, X-Frame-Options (DENY), X-Content-Type-Options, Referrer-Policy
- **Protection path traversal** : Toutes les opérations fichiers validées contre le répertoire de base
- **Pas d'eval()** : Aucun script inline, aucune exécution de code dynamique côté frontend
- **TLS** : Support HTTPS intégré — pas de reverse proxy nécessaire
- **Auth WebSocket** : Toutes les connexions WebSocket exigent un jeton JWT valide quand l'auth est activée

---

## Structure du projet

```
ShellFromBrowser/
├── cmd/shellfb/          # Point d'entrée, CLI
├── internal/
│   ├── auth/             # Authentification JWT + bcrypt
│   ├── config/           # Configuration YAML
│   ├── recording/        # Enregistrement sessions asciicast v2
│   ├── server/           # Serveur HTTP, WebSocket, middleware
│   ├── ssh/              # Wrapper client SSH
│   ├── terminal/         # Gestion sessions PTY (Unix + Windows)
│   └── transfer/         # Upload/download fichiers
├── web/
│   └── static/           # Frontend embarqué (xterm.js, CSS, JS)
├── config.example.yaml   # Configuration d'exemple
├── Dockerfile            # Build Docker multi-stage
├── docker-compose.yml    # Déploiement prêt à l'emploi
└── Makefile              # Automatisation du build
```

---

## Licence

[MIT](LICENSE) — Copyright (c) 2026 valorisa
