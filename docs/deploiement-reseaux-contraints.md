# Déploiement en réseau contraint

## Le problème

Dans les aéroports, gares, centres commerciaux et entreprises, le réseau
ne laisse passer que les ports 53 (DNS), 80 (HTTP) et 443 (HTTPS).
Les connexions SSH (port 22), VPN, et la plupart des autres protocoles
sont bloqués.

## Pourquoi ShellFromBrowser passe

ShellFromBrowser utilise du **HTTPS standard** (port 443) et du **WebSocket**
(protocole HTTP). Pour un firewall, c'est indistinguable d'une visite sur
un site web ordinaire.

```text
┌─ Réseau contraint ──────────────────────────────────────┐
│                                                         │
│  Navigateur ──HTTPS:443──▶ Firewall ──▶ Internet       │
│              (site web normal pour le firewall)         │
│                                                         │
└─────────────────────────────────────────────────────────┘
                                              │
                                              ▼
                                    ┌─ Ton serveur ────────┐
                                    │                      │
                                    │  ShellFromBrowser    │
                                    │  (déchiffre, exécute)│
                                    │                      │
                                    └──────────────────────┘
```

Le navigateur fait du HTTPS. Le firewall voit du HTTPS. Personne ne sait
qu'il y a un terminal derrière.

## Prérequis

- Un serveur (VPS) accessible sur Internet
- Un nom de domaine pointant vers ce serveur (DNS A record)
- Les ports 80 et 443 ouverts sur le serveur

## Déploiement — Méthode 1 : Auto-TLS (recommandé)

La méthode la plus simple. ShellFromBrowser obtient son certificat tout seul.

### Option A : Binaire standalone

```bash
# Télécharger le binaire
wget https://github.com/valorisa/ShellFromBrowser/releases/latest/download/shellfb-linux-amd64
chmod +x shellfb-linux-amd64

# Lancer avec auto-TLS
./shellfb-linux-amd64 --domain shell.monserveur.com
```

C'est tout. Le certificat est obtenu automatiquement, HTTPS actif sur :443.

### Option B : Docker one-liner

```bash
docker run -d --name shellfb \
  -p 80:80 -p 443:443 \
  -e SHELLFB_DOMAIN=shell.monserveur.com \
  -v shellfb-certs:/var/lib/shellfb/certs \
  valorisa/shellfb
```

### Option C : Docker Compose

```bash
# Éditer docker-compose.yml : remplacer shell.example.com par votre domaine
docker compose up -d
```

## Déploiement — Méthode 2 : Derrière un reverse proxy

Si vous avez déjà Nginx, Caddy ou Traefik sur votre serveur :

```bash
docker compose -f docker-compose.reverse-proxy.yml up -d
```

ShellFromBrowser écoute en HTTP sur :4200, le reverse proxy gère le TLS.

### Exemple Caddy

```text
shell.monserveur.com {
    reverse_proxy shellfb:4200
}
```

### Exemple Nginx

```nginx
server {
    listen 443 ssl;
    server_name shell.monserveur.com;

    ssl_certificate /etc/letsencrypt/live/shell.monserveur.com/fullchain.pem;
    ssl_certificate_key /etc/letsencrypt/live/shell.monserveur.com/privkey.pem;

    location / {
        proxy_pass http://localhost:4200;
        proxy_http_version 1.1;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_set_header Host $host;
        proxy_set_header X-Forwarded-For $proxy_add_x_forwarded_for;
    }
}
```

## Ports requis

| Côté | Port | Protocole | Requis |
|------|------|-----------|--------|
| Serveur (entrant) | 443 | HTTPS | Oui |
| Serveur (entrant) | 80 | HTTP | Oui (auto-TLS) ou Non (reverse proxy) |
| Client (sortant) | 443 | HTTPS | Oui — c'est tout ce dont le navigateur a besoin |

## Utilisation depuis un réseau contraint

1. Ouvrir un navigateur (Chrome, Firefox, Safari, Edge)
2. Aller sur `https://shell.monserveur.com`
3. Se connecter avec ses identifiants
4. Utiliser le terminal

Rien à installer côté client. Aucune configuration réseau. Aucun VPN.

## FAQ

### Et si le port 80 est déjà pris sur mon serveur ?

Utilisez la méthode reverse proxy. Votre Nginx/Caddy existant gère déjà
les ports 80/443 — ajoutez simplement un virtual host pour ShellFromBrowser.

### Et sans nom de domaine ?

L'auto-TLS nécessite un domaine. Alternatives :
- Utiliser un sous-domaine gratuit (DuckDNS, FreeDNS)
- Utiliser un certificat auto-signé (TLS manuel) — attention : le navigateur
  affichera un avertissement

### Et derrière un proxy d'entreprise (type Zscaler) ?

Si le proxy fait de l'inspection TLS (MITM), le WebSocket devrait quand
même fonctionner car il utilise le protocole HTTP standard. Si ce n'est
pas le cas, c'est un scénario prévu pour une version future.

### Le trafic est-il détectable ?

Non. ShellFromBrowser utilise :
- Du vrai HTTPS (pas du SSH déguisé)
- Un certificat Let's Encrypt valide
- Le protocole WebSocket standard (RFC 6455)
- Un upgrade HTTP classique

Même l'inspection profonde (DPI) ne voit qu'un site web HTTPS normal.
