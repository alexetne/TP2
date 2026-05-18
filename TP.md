# TP - Monitoring Shell (format 1h a 2h)

Ce TP est une version courte : l'objectif est de faire manipuler les commandes Linux essentielles dans un script de monitoring simple.

Le sujet detaille pour les etudiants est dans `ETUDIANT.md`.
La grille et les consignes professeur sont dans `PROFESSEUR.md`.

## Objectif

Creer un script `monitor.sh` qui :

- verifie 3 services avec `systemctl`
- extrait quelques logs avec `journalctl`
- observe les processus avec `ps`
- analyse `app.log` avec `grep`, `awk`, `sed`
- analyse simplement `metrics.csv` avec `awk -F,`
- explore une arborescence avec `find` et `xargs`
- ecrit ses resultats dans `reports/run-YYYYmmdd-HHMMSS/`

## Donnees utiles

- Services : `fake-api`, `log-generator`, `noisy-workers`
- Logs :
  - `/var/log/monitoring-lab/data/app.log`
  - `/var/log/monitoring-lab/data/metrics.csv`
  - `/var/log/monitoring-lab/tmp/tree/`

## Fichiers attendus

Dans le dossier de rapport :

- `services.txt`
- `journald.txt`
- `journald_errors.txt`
- `top_cpu.txt`
- `hogs.txt`
- `app_summary.txt`
- `app_redacted.log`
- `metrics_summary.txt`
- `tree_bak.txt`
- `tree_secret.txt`

## Bonus

Les points suivants ne sont pas obligatoires dans la version courte :

- service/timer systemd etudiant
- `reports/latest`
- `REPORT.md`
- analyse JSONL
- verification des archives `.gz`
- `kill` automatique

