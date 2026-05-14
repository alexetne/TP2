# ARCHI — Diagrammes & Explication (Template à compléter)

Objectif : expliquer “ce que fait le script” avec un **diagramme Mermaid** + une **procédure manuelle**.

## Diagramme (flux global)

```mermaid
flowchart LR
  subgraph systemd[systemd]
    T[student-monitor.timer] --> S[student-monitor.service]
  end

  S --> M[monitor.sh]

  subgraph inputs[Inputs]
    J[journald\njournalctl -u fake-api/log-generator]
    D1[/var/log/monitoring-lab/data/app.log]
    D2[/var/log/monitoring-lab/data/metrics.csv]
    D3[/var/log/monitoring-lab/data/events.jsonl]
    A[/var/log/monitoring-lab/archive/*.gz]
    TR[/var/log/monitoring-lab/tmp/tree/]
    P[process table\nps]
    U[systemctl status/is-active]
  end

  inputs --> M

  subgraph outputs[Outputs]
    R[/opt/monitoring-lab/student/reports/run-.../]
    L[/opt/monitoring-lab/student/reports/latest/]
    AL[/var/log/monitoring-lab/app/student-monitor.log]
  end

  M --> R
  M --> L
  M --> AL
```

## Étapes (explication manuelle)

Décris ici, étape par étape, ce que fait ton script.

### 1) Pré-check

- Commandes vérifiées : `grep`, `awk`, `sed`, `find`, `xargs`, `ps`, `systemctl`, `journalctl`, ...
- Pourquoi : éviter un crash en cours d’exécution

### 2) Création du “run dir”

- Dossier créé : `reports/run-YYYYmmdd-HHMMSS/`
- Lien : `reports/latest -> run-...`
- Pourquoi : conserver l’historique et un pointeur vers le dernier run

### 3) Monitoring systemd + journald

Pour chaque service :

- `systemctl is-active <svc>`
- si KO : `systemctl status <svc> --no-pager` → fichier rapport
- `journalctl -u <svc> -n 200 --no-pager` → fichier rapport

### 4) Process (ps/top/htop) + nice/kill

- Snapshot `ps` (top cpu/mem)
- Détection des hogs (pattern `cpu-hog.sh`)
- Option kill : via variable d’env (ex: `LAB_KILL_HOGS=1`)

### 5) Traitement des datasets

Explique précisément :

- `app.log` : quelles extractions (level/host/user/status/password/token)
- `metrics.csv` : moyennes par host, anomalies, staging
- `events.jsonl` : compte par severity, top hosts
- `archive/*.gz` : `gzip -t` via `find -print0 | xargs -0`

### 6) `find/xargs` sur `tmp/tree`

- `.bak` : comptage + exemples
- `-mtime +7` : comptage + exemples
- recherche contenu : `SECRET=`, `DEBUG=true`

## Inventaire des outputs (à remplir)

Liste ici tous les fichiers produits (nom + rôle), par exemple :

- `services_status.txt` : état des services
- `journald_extract.txt` : logs journald bruts
- `metrics_summary.txt` : agrégats csv
- `tree_secret_hits.txt` : occurrences `SECRET=`

