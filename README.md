# Install script

# Uninstall 
```bash
sudo systemctl stop fake-api log-generator
sudo systemctl disable fake-api log-generator
sudo rm -f /etc/systemd/system/fake-api.service
sudo rm -f /etc/systemd/system/log-generator.service
sudo systemctl daemon-reload
sudo rm -rf /opt/monitoring-lab /var/log/monitoring-lab
sudo userdel monitorlab
```