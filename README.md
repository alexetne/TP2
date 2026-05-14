# Install script
## Données générées
- Logs “live” via services systemd : `fake-api`, `log-generator`, `noisy-workers`
- Gros fichiers pour recherche/filtrage : `/var/log/monitoring-lab/data/*`
- Arborescence volumineuse pour `find`/`xargs` : `/var/log/monitoring-lab/tmp/tree/`
- Archives gzip : `/var/log/monitoring-lab/archive/*.gz`

## Tailles (variables d'environnement)
Tu peux ajuster le volume généré avant l’installation :
```bash
sudo LAB_DATA_LINES=400000 LAB_METRICS_ROWS=300000 LAB_TREE_FILES=6000 ./install.sh
```

# Uninstall 
```bash
sudo systemctl stop fake-api log-generator noisy-workers
sudo systemctl disable fake-api log-generator noisy-workers
sudo rm -f /etc/systemd/system/fake-api.service
sudo rm -f /etc/systemd/system/log-generator.service
sudo rm -f /etc/systemd/system/noisy-workers.service
sudo systemctl daemon-reload
sudo rm -rf /opt/monitoring-lab /var/log/monitoring-lab
sudo userdel monitorlab
```
