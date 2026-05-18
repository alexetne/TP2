#!/bin/bash


DOSSIER_TRAVAIL=/opt/travail
DATE=$(date +%Y-%m-%d)

DOSS_REPORT=$DOSSIER_TRAVAIL/report/run-$DATE

FILE_ACTU_REPORT=rapport-$DATE.md
FILE_ACTU_SERVICES=services.txt
FILE_ACTU_JOURNAL=journarld.txt
HOSTNAME=$(hostname)
WHOIS=$(whoami)





mkdir -p "$DOSS_REPORT"
touch "$DOSS_REPORT/$FILE_ACTU_REPORT"
touch "$DOSS_REPORT/$FILE_ACTU_SERVICES"
touch "$DOSS_REPORT/$FILE_ACTU_JOURNAL"




echo "# Rapport de l'exécution du script install.sh" > "$DOSS_REPORT/$FILE_ACTU_REPORT"
echo "Date d'exécution : $DATE" >> "$DOSS_REPORT/$FILE_ACTU_REPORT"
echo "Nom de l'hôte : $HOSTNAME" >> "$DOSS_REPORT/$FILE_ACTU_REPORT"
echo "Utilisateur actuel : $WHOIS" >> "$DOSS_REPORT/$FILE_ACTU_REPORT"

echo "=============== Services fake-api $DATE =======================" >> "$DOSS_REPORT/$FILE_ACTU_SERVICES"
echo "service fake-api $(systemctl is-active fake-api)" >> "$DOSS_REPORT/$FILE_ACTU_SERVICES"
echo "=============== Services log-generator $DATE =======================" >> "$DOSS_REPORT/$FILE_ACTU_SERVICES"
echo "service log-generator $(systemctl is-active log-generator)" >> "$DOSS_REPORT/$FILE_ACTU_SERVICES"
echo "=============== Services noisy-workers $DATE =======================" >> "$DOSS_REPORT/$FILE_ACTU_SERVICES"
echo "service noisy-workers $(systemctl is-active noisy-workers)" >> "$DOSS_REPORT/$FILE_ACTU_SERVICES"


journalctl -u fake-api -n 30 --no-pager >> "$DOSS_REPORT/$FILE_ACTU_JOURNAL"
journalctl -u log-generator -n 30 --no-pager >> "$DOSS_REPORT/$FILE_ACTU_JOURNAL