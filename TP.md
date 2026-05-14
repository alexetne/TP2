# TP — Monitoring & Traitement (Linux Shell)

## Contexte de la machine (après `install.sh`)

L’installation met en place un mini-lab “monitoring” composé de :

- Dossiers
  - `/opt/monitoring-lab/` : scripts “service” et ressources
  - `/var/log/monitoring-lab/` : logs et datasets volumineux
- Utilisateur système
  - `monitorlab` (shell `nologin`) pour exécuter les services
- Services systemd
  - `fake-api.service` : génère des logs applicatifs + messages journald (`logger`)
  - `log-generator.service` : génère des logs type sshd/nginx/alertes + journald
  - `noisy-workers.service` : lance des processus CPU “bruyants” (priorités `nice` différentes)
- Fichiers “exercices” (volumineux)
  - `/var/log/monitoring-lab/data/app.log` : gros log texte structuré (aiguilles: `CRITICAL`, `ERROR`, `password=...`, `token=...`)
  - `/var/log/monitoring-lab/data/metrics.csv` : CSV volumineux (CPU/MEM/latence…)
  - `/var/log/monitoring-lab/data/events.jsonl` : JSON Lines (sévérité, hôte, event)
  - `/var/log/monitoring-lab/archive/*.gz` : archives gz de datasets (ex: `app.log.gz`)
  - `/var/log/monitoring-lab/tmp/tree/` : arborescence volumineuse (fichiers `.log/.conf/.bak/.csv/.json/...`) + timestamps variés

### Validation (à exécuter une fois)

```bash
systemctl status fake-api log-generator noisy-workers
journalctl -u fake-api -n 20 --no-pager
journalctl -u log-generator -n 20 --no-pager
journalctl -u noisy-workers -n 20 --no-pager
ls -lah /var/log/monitoring-lab/data/
ls -lah /var/log/monitoring-lab/archive/
find /var/log/monitoring-lab/tmp/tree -type f | head
```

## Objectif du TP

Mettre en place un **système de monitoring + traitement** (shell) qui :

1. Surveille l’état “RUNNING” des services `fake-api`, `log-generator`, `noisy-workers`
2. Surveille des indicateurs système (CPU/MEM, top processus)
3. Exploite les données générées (logs + CSV + JSONL + arborescence + archives `.gz`)
4. Produit des **rapports** (fichiers) exploitables et rejouables
5. Tourne en “tâche planifiée” (systemd timer) et journalise proprement (journald + fichiers)

Contraintes pédagogiques : votre solution doit obligatoirement mobiliser **tous** les outils suivants :

- Recherche/filtrage : `grep`, `awk`, `sed`
- Exploration batch : `find`, `xargs` (avec `-print0` / `-0`)
- Shell : redirections (`>`, `>>`, `2>`, `2>&1`), pipes (`|`)
- Process : `ps` et au moins un de `top`/`htop` (observation), `nice`, `kill`
- systemd : `systemctl`, `journalctl`, et **un** service + **un** timer que vous créez

## Livrables attendus

Créez vos fichiers dans un répertoire de travail :

```bash
sudo mkdir -p /opt/monitoring-lab/student
sudo chown -R "$USER":"$USER" /opt/monitoring-lab/student
cd /opt/monitoring-lab/student
```

Livrables minimaux :

- `/opt/monitoring-lab/student/monitor.sh` : script principal (idempotent)
- `/opt/monitoring-lab/student/lib.sh` : fonctions utilitaires (logs, erreurs, helpers)
- `/opt/monitoring-lab/student/reports/` : répertoire de sortie (rapports horodatés + “latest”)
- `/etc/systemd/system/student-monitor.service` : unité service (exécute `monitor.sh`)
- `/etc/systemd/system/student-monitor.timer` : timer (planification)

## Spécification technique (ce que le script doit faire)

### A. Hygiène & structure

Dans `monitor.sh` :

- Mode strict : `set -euo pipefail`
- Variables constantes : chemins, nom des services, répertoires rapports
- Logs : un fichier applicatif dédié, par ex. `/var/log/monitoring-lab/app/student-monitor.log`
- Codes retour : si une étape “critique” échoue, le script doit **échouer** (exit non-zero)
- Format de sortie : chaque exécution génère :
  - un rapport `reports/run-YYYYmmdd-HHMMSS/`
  - un lien (ou copie) `reports/latest/` (écrasé à chaque run)

### B. Monitoring systemd (services)

Pour chacun des services `fake-api`, `log-generator`, `noisy-workers` :

- Déterminer l’état via `systemctl is-active`
- En cas d’état différent de `active` :
  - écrire un évènement `ALERT` dans votre log
  - collecter `systemctl status <service> --no-pager` dans un fichier de rapport
  - collecter les 200 dernières lignes `journalctl -u <service> -n 200 --no-pager`

### C. Monitoring process (ps/nice/kill)

1. Produire un snapshot :
   - `ps aux --sort=-%cpu | head -n 20` → `reports/.../top_cpu.txt`
   - `ps aux --sort=-%mem | head -n 20` → `reports/.../top_mem.txt`
2. Identifier les processus “hogs” (ex: commande contient `cpu-hog.sh`)
   - extraire PID, NI (nice), %CPU
3. Action “guidée” (à activer via variable d’env) :
   - si `LAB_KILL_HOGS=1`, tuer **un seul** hog (au choix : le plus consommateur)
   - sinon, juste reporter (pas de kill)

Objectif : utiliser `ps`, `awk`, `sort`, redirections/pipes. Pour `kill`, prévoir un mode “sec” (désactivé par défaut).

### D. Traitement des datasets (gros fichiers)

#### 1) `data/app.log` (texte)

Générer un rapport `app_log_summary.txt` contenant :

- Nombre de lignes total
- Top 10 des `host` les plus présents
- Top 10 des `user` les plus présents
- Compte par `level` (`INFO/WARN/ERROR/CRITICAL`)
- Compte des occurrences de :
  - `password=`
  - `token=`
  - `status=500`

Techniques attendues :

- `grep` (avec `-E`, `-n`, `-H` si nécessaire)
- `awk` (champs, agrégations)
- `sed` (nettoyage/normalisation, ex: retirer `msg="..."` pour analyser)
- pipes/redirections (`|`, `>`, `>>`)

#### 2) `data/metrics.csv` (CSV)

Générer `metrics_summary.txt` avec :

- Top 10 des hosts par moyenne `cpu_pct`
- Top 10 des hosts par moyenne `latency_ms`
- Nombre de lignes “staging”
- Détection simple d’anomalies :
  - `cpu_pct >= 95` ou `mem_pct >= 95` (compte + exemples)

Techniques attendues :

- `awk -F,` (header, moyennes, agrégation par host)
- `sort -n`, `head`

#### 3) `data/events.jsonl` (JSONL)

Sans dépendre d’outils externes (pas de `jq` obligatoire), générer `events_summary.txt` avec :

- Compte par `severity` (`info/error/critical`) via `grep`/`awk`
- Top 10 des `host`

Indication : vous pouvez utiliser des regex simples (`grep -oE`) et `awk` pour extraire `"host":"..."`.

#### 4) Archives `.gz`

Vérifier l’intégrité des archives :

- `find /var/log/monitoring-lab/archive -name '*.gz' -print0 | xargs -0 gzip -t`

Écrire le résultat (succès/échec) dans `archive_check.txt`.

### E. Exploration `find`/`xargs` (arborescence)

Sur `/var/log/monitoring-lab/tmp/tree` :

- Lister les `*.bak` (compte + exemples)
- Lister les fichiers modifiés il y a plus de 7 jours (`-mtime +7`) (compte + exemples)
- Chercher les fichiers contenant `SECRET=` et `DEBUG=true`

Contraintes :

- Utiliser `find ... -print0` + `xargs -0` (gestion espaces/caractères)
- Produire un fichier de rapport par check

### F. Journald (journalctl)

Créer un fichier `journald_extract.txt` contenant :

- Les 200 dernières lignes de `journalctl -u log-generator --no-pager`
- Les 200 dernières lignes de `journalctl -u fake-api --no-pager`

Option : filtrer uniquement `ERROR|CRITICAL` dans une section du rapport.

## Mise en place systemd (votre propre service + timer)

### 1) Service

Créer `/etc/systemd/system/student-monitor.service` :

- `Type=oneshot`
- `ExecStart=/opt/monitoring-lab/student/monitor.sh`
- `User=root` (plus simple : accès `/var/log/monitoring-lab/` et `journalctl`)
- Rediriger stdout/stderr vers journald (par défaut) + écrire aussi vos rapports sur disque

### 2) Timer

Créer `/etc/systemd/system/student-monitor.timer` :

- `OnBootSec=1min`
- `OnUnitActiveSec=2min`
- `Unit=student-monitor.service`

Activer et vérifier :

```bash
sudo systemctl daemon-reload
sudo systemctl enable --now student-monitor.timer
systemctl list-timers --all | grep student-monitor
journalctl -u student-monitor.service -n 50 --no-pager
```

## Guidage (squelette recommandé)

### `lib.sh` (idées de fonctions)

- `log_info`, `log_warn`, `log_err` (timestamp + niveau)
- `require_cmd` (vérifie une commande, sinon erreur)
- `mkdir_run_dir` (crée run dir + latest)

### `monitor.sh` (pipeline)

1. Pré-check (`require_cmd grep awk sed find xargs ps systemctl journalctl`)
2. Créer répertoires de run
3. Collecte services + journald
4. Collecte process (ps) + mode kill optionnel
5. Traitement datasets (app.log, metrics.csv, events.jsonl, archives gz)
6. Exploration arborescence (find/xargs)
7. Écrire un `REPORT.md` de synthèse (liens vers fichiers produits)

## Critères d’évaluation (techniques)

- Robustesse : script rejouable, logs propres, erreurs gérées
- Performance : traitement “streaming” (pipes) plutôt que chargement complet
- Qualité Unix : usage correct `find -print0 | xargs -0`, pas de parsing fragile
- systemd : service/timer fonctionnels, diagnostiquer via `journalctl`
- Justesse : rapports cohérents (comptes corrects, top N pertinents)

## Bonus (optionnel)

- “Mode incrémental” : ne retraiter que les N dernières minutes/heures (journalctl `--since`)
- Détection d’anomalies plus avancée sur `metrics.csv`
- Rotation/archivage de vos rapports (`find reports -mtime +14 -type d -print0 | xargs -0 rm -rf`)

