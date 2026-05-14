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
sudo mkdir -p /opt/monitoring-lab/student
sudo chown -R "$USER":"$USER" /opt/monitoring-lab/student
```

Fichiers :

- `/opt/monitoring-lab/student/monitor.sh`
- `/opt/monitoring-lab/student/lib.sh`
- `/opt/monitoring-lab/student/reports/` (sorties)
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

