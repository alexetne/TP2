# Dossier Étudiant — TP Monitoring & Traitement

## Ce que tu as sur la machine

Après exécution de `install.sh`, tu disposes de :

- Services systemd : `fake-api`, `log-generator`, `noisy-workers`
- Logs & datasets :
  - `/var/log/monitoring-lab/data/app.log` (texte)
  - `/var/log/monitoring-lab/data/metrics.csv` (CSV)
  - `/var/log/monitoring-lab/data/events.jsonl` (JSONL)
  - `/var/log/monitoring-lab/archive/*.gz` (archives)
  - `/var/log/monitoring-lab/tmp/tree/` (arborescence volumineuse)

Vérifications rapides :
```bash
systemctl status fake-api log-generator noisy-workers
ls -lah /var/log/monitoring-lab/data
```

## Objectif

Écrire un script shell **rejouable** qui :

- collecte l’état systemd + extraits journald
- collecte des infos process (ps/top/htop) et gère la priorité (nice) + kill optionnel
- traite les datasets (grep/awk/sed) et l’arborescence (find/xargs)
- génère des rapports versionnés à chaque run
- est exécuté automatiquement via un `systemd timer`

Les commandes **à utiliser** dans ta solution : `grep`, `awk`, `sed`, `find`, `xargs`, pipes/redirections, `ps`, `nice`, `kill`, `systemctl`, `journalctl`.

## Structure attendue (à produire)

Créer ton espace :
```bash
sudo mkdir -p /opt/monitoring-lab/Ton-Nom
sudo chown -R "$USER":"$USER" /opt/monitoring-lab/Ton-Nom
```

Fichiers :

- `/opt/monitoring-lab/Ton-Nom/monitor.sh`
- `/opt/monitoring-lab/Ton-Nom/lib.sh`
- `/opt/monitoring-lab/Ton-Nom/reports/` (sorties)
- `/etc/systemd/system/student-monitor.service`
- `/etc/systemd/system/student-monitor.timer`

## Contrainte de rendu (dossier d’archi)

Tu dois livrer un dossier `archi/` qui explique “ce que fait ton script” **à la main** :

- un diagramme Mermaid (flux de données)
- une explication étape par étape (quoi/commandes/outputs)
- une liste des fichiers de rapports produits

Template recommandé : voir `archi/ARCHI.md`.

## Script — exigences minimales

Dans `monitor.sh` :

- `set -euo pipefail`
- “run dir” unique : `reports/run-YYYYmmdd-HHMMSS/`
- un `reports/latest` qui pointe vers le dernier run
- une sortie journald (stdout/stderr) + un log fichier (ex: `/var/log/monitoring-lab/app/student-monitor.log`)
- pas d’édition destructrice des datasets sources (si tu masques, écris dans `reports/...`)

## Démarrage systemd (ton service + timer)

Créer le service + timer puis activer :
```bash
sudo systemctl daemon-reload
sudo systemctl enable --now student-monitor.timer
systemctl list-timers --all | grep student-monitor
journalctl -u student-monitor.service -n 100 --no-pager
```

## Checklist (auto-contrôle)

- [ ] `systemctl status student-monitor.timer` OK
- [ ] `journalctl -u student-monitor.service` sans erreurs awk/sed
- [ ] `reports/latest/` existe et contient les fichiers attendus
- [ ] tu as bien utilisé `find -print0 | xargs -0` au moins une fois
- [ ] un `archi/ARCHI.md` clair et complet (Mermaid + étapes + outputs)

## Spécification “pas à pas” (à retrouver dans ton script)

Cette section liste, dans l’ordre, **tout** ce qu’on doit retrouver dans ton `monitor.sh` (même les actions simples).

1) Démarrage & bannière
- Afficher l’heure de lancement (ex: `date -Is` ou `date '+%F %T'`)
- Afficher le nom du host (ex: `hostname`)
- Afficher l’utilisateur effectif (ex: `id -un`) et/ou vérifier root (`$EUID`)

2) Mode strict & variables
- `set -euo pipefail`
- Variables centralisées : chemins (`/var/log/monitoring-lab/...`, `/opt/monitoring-lab/student/...`), liste des services, répertoire de rapports
- (Recommandé) variables d’activation : ex `LAB_KILL_HOGS=1` (désactivé par défaut)

3) Pré-check (commandes requises)
- Vérifier l’existence des commandes utilisées (au minimum) : `grep`, `awk`, `sed`, `find`, `xargs`, `ps`, `systemctl`, `journalctl`
- Optionnel selon ton implémentation : `gzip`, `sort`, `head`, `wc`

4) Initialisation des sorties
- Créer `reports/run-YYYYmmdd-HHMMSS/` (un nouveau dossier à chaque run)
- Mettre à jour `reports/latest` pour pointer vers ce run
- Écrire un log dans un fichier dédié (ex: `/var/log/monitoring-lab/app/student-monitor.log`) *et* laisser des traces dans journald (stdout/stderr)

5) Monitoring systemd (services)
Pour chaque service (`fake-api`, `log-generator`, `noisy-workers`) :
- `systemctl is-active <service>` (état)
- Écrire l’état dans un fichier de rapport (ex: `services_status.txt`)
- Si l’état n’est pas `active` :
  - Collecter `systemctl status <service> --no-pager` → fichier
  - Collecter `journalctl -u <service> -n 200 --no-pager` → fichier

6) Collecte journald (extraction)
- Produire un fichier (ex: `journald_extract.txt`) avec :
  - `journalctl -u log-generator -n 200 --no-pager`
  - `journalctl -u fake-api -n 200 --no-pager`
- (Recommandé) un fichier filtré `ERROR|CRITICAL` via `grep -E` + pipes

7) Collecte process (ps/top/htop) + nice/kill
- Générer un snapshot :
  - `ps aux --sort=-%cpu | head -n 20` → `top_cpu.txt`
  - `ps aux --sort=-%mem | head -n 20` → `top_mem.txt`
- Identifier les processus ciblés (ex: `cpu-hog.sh`) dans la table process (`ps -eo ...`)
- Si `LAB_KILL_HOGS=1` :
  - sélectionner un PID (ex: plus gros CPU via `awk | sort | head`)
  - tuer ce PID (`kill -TERM`, puis éventuellement `kill -KILL`)
- Sinon : ne pas tuer, seulement reporter (mode sûr par défaut)

8) Traitement `data/app.log` (grep/awk/sed)
- Compter les lignes (ex: `wc -l`)
- Compter par niveau (`INFO/WARN/ERROR/CRITICAL`)
- Top 10 hosts / top 10 users (agrégation `awk`, tri `sort`)
- Compter `password=`, `token=`, `status=500` (via `grep -c`)
- (Recommandé) produire une version masquée via `sed` (dans les rapports)

9) Traitement `data/metrics.csv` (awk -F,)
- Compter les lignes
- Compter les lignes `staging`
- Calculer des moyennes par host (CPU, latence) et sortir un top 10
- Détecter des anomalies (ex: `cpu>=95` ou `mem>=95`) : count + exemples

10) Traitement `data/events.jsonl`
- Compter par `severity` (via extraction simple `grep -oE` + `awk`)
- Top 10 hosts (extraction + agrégation)

11) Vérification des archives `.gz`
- `find ... -name '*.gz' -print0 | xargs -0 gzip -t`
- Écrire `OK`/`FAIL` dans un rapport

12) Exploration arborescence `tmp/tree` (find/xargs)
- Lister/compter `*.bak` + exemples
- Lister/compter `-mtime +7` + exemples
- Rechercher dans les fichiers : `SECRET=` et `DEBUG=true` (avec `find -print0 | xargs -0 grep -Hn ...`)

13) Synthèse finale
- Générer un `REPORT.md` (ou équivalent) qui référence les fichiers produits
- Afficher l’heure de fin + durée (optionnel) et quitter avec un code de retour cohérent
