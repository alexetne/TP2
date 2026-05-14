# Dossier Professeur — TP Monitoring & Traitement (Corrigé & Grille)

## Intention pédagogique

Ce TP force l’usage “Unix” de :

- traitement de texte en flux : `grep | awk | sed`
- exploration & batch robuste : `find -print0 | xargs -0`
- pipes/redirections (stdout/stderr)
- inspection process : `ps`, observation `top/htop`, gestion de priorité `nice`, arrêt `kill`
- exploitation systemd : `systemctl`, `journalctl`, création service/timer

## Contexte installé (machine)

- Dossiers : `/opt/monitoring-lab/`, `/var/log/monitoring-lab/`
- Services : `fake-api`, `log-generator`, `noisy-workers`
- Datasets : `data/app.log`, `data/metrics.csv`, `data/events.jsonl`, `archive/*.gz`, `tmp/tree/`

Contrôles :
```bash
systemctl status fake-api log-generator noisy-workers
ls -lah /var/log/monitoring-lab/data
```

## Corrigé fourni

Corrigé prêt à déployer :

- `correction/monitor.sh` + `correction/lib.sh`
- `correction/correction.sh` (installe dans `/opt/monitoring-lab/student/` + timer/service)

Déploiement :
```bash
sudo bash correction/correction.sh
journalctl -u student-monitor.service -n 100 --no-pager
ls -lah /opt/monitoring-lab/student/reports/latest
```

## Grille de correction (suggestion)

### 1) Robustesse / Qualité shell

- `set -euo pipefail` présent
- variables centralisées (paths, services)
- script rejouable (idempotence)
- erreurs gérées (fichiers manquants → warning + rapport, pas crash “gratuit”)

### 2) Pipeline de traitement

- `grep/awk/sed` utilisés pour extractions/agrégations réelles
- pas de “cat inutile” (usage de pipes)
- redirections correctes (au moins un exemple `2>&1` ou fichier stderr)

### 3) `find/xargs`

- usage de `-print0` et `xargs -0`
- production de rapports (comptes + exemples)

### 4) Process / nice / kill

- snapshot `ps` (top CPU/mem)
- identification de processus cibles (ex: hogs)
- kill implémenté en mode sécurisé (désactivé par défaut, activable via variable)

### 5) systemd / journald

- `student-monitor.service` + `student-monitor.timer` fonctionnels
- diagnostic via `journalctl -u ...` maîtrisé
- rapports produits à intervalle régulier

## Ce qu’on attend dans le dossier “archi”

Exiger un dossier `archi/` dans le rendu étudiant :

- un diagramme Mermaid (flux global + points d’entrée)
- une explication “manuelle” : *commande → fichier → interprétation*
- un inventaire des outputs (noms de fichiers, où les trouver)

Template fourni : `archi/ARCHI.md`.

