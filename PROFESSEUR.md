# Dossier Professeur - TP Monitoring Shell (1h a 2h)

## Positionnement

Le sujet a ete reduit pour tenir en 1h a 2h avec des etudiants de 1re/2e annee IT.

Ce que le TP couvre vraiment :

- lecture de services avec `systemctl`
- extraction de logs avec `journalctl`
- observation processus avec `ps`, `top` ou `htop`
- traitement texte simple avec `grep`, `awk`, `sed`
- exploration de fichiers avec `find` et `xargs`
- redirections et pipes

Ce qui passe en bonus :

- service/timer systemd etudiant
- lien `reports/latest`
- `kill` automatise
- JSONL, archives `.gz`, rapports avances

## Livrable attendu

Un dossier `/opt/monitoring-lab/student/` contenant :

- `monitor.sh`
- `reports/run-.../services.txt`
- `reports/run-.../journald.txt`
- `reports/run-.../journald_errors.txt`
- `reports/run-.../top_cpu.txt`
- `reports/run-.../hogs.txt`
- `reports/run-.../app_summary.txt`
- `reports/run-.../app_redacted.log`
- `reports/run-.../metrics_summary.txt`
- `reports/run-.../tree_bak.txt`
- `reports/run-.../tree_secret.txt`

Optionnel :

- `REPORT.md`
- `archi/ARCHI.md`
- `student-monitor.service`
- `student-monitor.timer`

## Corrige fourni

Le corrige installe un script plus complet que le minimum, mais reste lineaire et lisible.

```bash
sudo bash correction/correction.sh
journalctl -u student-monitor.service -n 100 --no-pager
ls -lah /opt/monitoring-lab/student/reports/latest
```

## Grille rapide

- 4 pts : creation correcte du dossier `reports/run-...`
- 4 pts : verification des services avec `systemctl is-active`
- 4 pts : extraction `journalctl` + filtrage `grep -E`
- 4 pts : analyse `app.log` avec `wc`, `grep`, `awk`, `sed`
- 3 pts : analyse simple `metrics.csv` avec `awk -F,`
- 3 pts : usage correct de `find` + `xargs`
- 2 pts : proprete generale du script (`bash -n`, variables, chemins)

Total : 24 pts, a ramener sur 20 si besoin.

## Points a surveiller

- Les etudiants ne doivent pas modifier les fichiers sources dans `/var/log/monitoring-lab/data/`.
- `kill` doit rester manuel ou bonus, pas obligatoire.
- `top`/`htop` peut etre valide par observation pendant la seance.
- Le dossier d'architecture doit rester court : un schema et quelques phrases suffisent.
