# Docker Local Test — Design Spec

## Objectif

Builder et lancer ShellFromBrowser en Docker sur la machine locale, vérifier que l'app répond sur `http://localhost:8080` et que le terminal fonctionne dans le navigateur.

## Contraintes

- Test local uniquement (pas de domaine public)
- Pas de TLS (HTTP simple)
- Pas d'authentification JWT
- Utiliser le `docker-compose.yml` principal (approche A : modification directe)

## Modifications requises

### 1. Dockerfile — Image Go

Remplacer `golang:1.26-alpine` par la dernière version stable disponible sur Docker Hub (ex: `golang:1.23-alpine` ou `golang:1.24-alpine`). Go 1.26 n'existe pas encore.

### 2. Créer `config.yaml`

Fichier minimal pour le test local :

```yaml
server:
  addr: ":8080"
  domain: ""

auth:
  enabled: false

shell:
  command: ""
  env:
    - "TERM=xterm-256color"

sessions:
  max_per_user: 10
  idle_timeout: "30m"

recording:
  enabled: false
```

### 3. Modifier `docker-compose.yml`

- Ports : `80:80` et `443:443` → `8080:8080`
- Variables d'env : supprimer `SHELLFB_DOMAIN`, `SHELLFB_JWT_SECRET`, remplacer `SHELLFB_AUTH_ENABLED=true` par `false`
- Volumes : supprimer le volume `certs` (inutile sans TLS)
- Supprimer le volume `shellfb-recordings` (recording désactivé)

Résultat :

```yaml
services:
  shellfb:
    build: .
    image: valorisa/shellfb:latest
    container_name: shellfb
    ports:
      - "8080:8080"
    environment:
      - SHELLFB_AUTH_ENABLED=false
    volumes:
      - ./config.yaml:/etc/shellfb/config.yaml:ro
    restart: unless-stopped
```

## Séquence de test

1. Corriger le Dockerfile (version Go)
2. Créer `config.yaml`
3. Modifier `docker-compose.yml`
4. `docker compose build`
5. `docker compose up -d`
6. Vérifier `http://localhost:8080` dans le navigateur
7. Tester la saisie clavier dans le terminal web

## Critères de succès

- Le build Docker réussit sans erreur
- Le conteneur démarre et reste healthy
- `http://localhost:8080` affiche l'interface terminal
- On peut taper des commandes et voir les résultats
