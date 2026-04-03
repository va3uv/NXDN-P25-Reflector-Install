####################################################################################################################################################################
#  Script to install NXDN and (optionally) P25 Reflector
#  This is a modification and expansion of a script from PE1BZF
#  Modified by Ramesh Dhami, VA3UV
#  Script will install NXDNReflector from the N7HUD Repo (the packages in the NOSTAR repo generated buffer overflow errors on Ubuntu systems)
#  and optionally, if the P25 variable below is set to 1, build and configure the P25 reflector package
#  
#  The script assumes that you are installing on a server where xlxd is already installed, and thus
#  some of the dependency packages like php are already installed.  I have also commented out the dashboard installation
#  since in my application, I peer the NXDN and P25 reflector to my xlxd using xlxd v2.6.0 (thanks to Andy Taylor, MW0MWZ for the excellent work to enable this :)
#
####################################################################################################################################################################

#!/bin/bash
set -e

###########################################################
# Tested on the following OS'
# Raspberry Pi OS Lite / Debian >= 11, and Ubuntu 24.04 LTS
###########################################################

### Set Variables ###

# Set P25=1 if you want to config and install the P25 reflector
# the script will pull YSF/NXDN, and P25 reflectors from the N7HUD repo, but only builds the P25 Reflector if you explicitly set the P25 flag to 1
#
P25=1


USER="mmdvm"
INSTALL_DIR="/usr/local/bin/DVReflectors"
INI_FILE="/etc/NXDNReflector.ini"

P25_INI_FILE="/etc/P25Reflector.ini"

SERVICE="nxdnreflector"

P25_SERVICE="p25reflector"

REPO="https://github.com/N7HUD/DVReflectors.git"


echo "=== NXDNReflector Installation ==="

# ROOT CHECK
if [[ $EUID -ne 0 ]]; then
  echo "This script must be run as root ... exiting!"
  exit 1
fi

#############################################
# APT RESET (Prevents 404 Errors)
#############################################
echo ">> Reset APT"
apt clean
rm -rf /var/lib/apt/lists/*
apt update
apt --fix-broken install -y || true
full-upgrade -y || true

#############################################
# INSTALL DEPENDENCY PACKAGES
#############################################

echo ">> Installing dependency packages..."

# VA3UV - since we are installing on an XLX box, it already has Nginx and php installed on it

apt -y install wget curl nodejs npm logrotate whiptail dos2unix 
 
#############################################
# Create mmdvm user
#############################################

echo ">> Configuring user $USER"
if ! id "$USER" &>/dev/null; then
  adduser --disabled-password --gecos "" $USER
  echo "$USER:mmdvm" | chpasswd
fi

usermod -aG adm $USER

#############################################
# NXDNReflector INSTALLATION
#############################################

echo ">> Installing NXDNReflector"
mkdir -p $INSTALL_DIR
rm -rf /tmp/DVReflectors
git clone $REPO /tmp/DVReflectors
cp -r /tmp/DVReflectors/* $INSTALL_DIR/


cd $INSTALL_DIR/NXDNReflector
make clean
make -j 1
strip NXDNReflector

chown -R $USER:$USER $INSTALL_DIR/NXDNReflector
chmod +x NXDNReflector

#############################################
# CONFIG FILE
#############################################

echo ">> Copying NXDN Configuration File"
if [[ ! -f $INI_FILE ]]; then
  cp $INSTALL_DIR/NXDNReflector/NXDNReflector.ini $INI_FILE
fi

#############################################
# SYSTEMD SERVICE (self-daemonizing!)
#############################################

echo ">> installing systemd service script"

cat >/etc/systemd/system/$SERVICE.service <<EOF
[Unit]
Description=NXDNReflector
Requires=network.target
After=syslog.target network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$INSTALL_DIR/NXDNReflector
ExecStart=$INSTALL_DIR/NXDNReflector/NXDNReflector $INI_FILE

# NXDNReflector daemon restart
RemainAfterExit=yes

Restart=on-failure

[Install]
WantedBy=multi-user.target
EOF

#############################################
# NXDN CSV UPDATE SCRIPT
#############################################

echo ">> NXDN database update script"

cat >$INSTALL_DIR/NXDNReflector/nxdnupdate.sh <<'EOF'
#!/bin/bash
set -e
systemctl stop nxdnreflector
cd /usr/local/bin/DVReflectors/NXDNReflector
mv nxdn.csv nxdn.old 2>/dev/null || true
wget -q -O nxdn.csv https://www.radioid.net/static/nxdn.csv
chown mmdvm:mmdvm nxdn.csv
systemctl start nxdnreflector
EOF

chmod +x $INSTALL_DIR/NXDNReflector/nxdnupdate.sh


#############################################
# SYSTEMD TIMER – NXDN CSV
#############################################

echo ">> systemd timer (NXDN CSV)"

cat >/etc/systemd/system/nxdn-db-update.service <<EOF
[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/NXDNReflector/nxdnupdate.sh
EOF

cat >/etc/systemd/system/nxdn-db-update.timer <<EOF
[Timer]
OnCalendar=*-*-* 05:30
Persistent=true
[Install]
WantedBy=timers.target
EOF


####################################################################
# update the NXDNReflector ini file with user settings
####################################################################

read -p "Which TG will you be using (you MUST enter a numerical TG #) ? (Example 56789): " NEWTG
read -p "What port will you be listening on (you MUST enter a numerical port #) ? (Example 41400): " NEWPORT

sudo sed -i "s/^[[:space:]]*TG[[:space:]]*=.*/TG=$NEWTG/g" /etc/NXDNReflector.ini

sudo sed -i "s/^[[:space:]]*TGEnable[[:space:]]*=.*/TGEnable=$NEWTG/g" /etc/NXDNReflector.ini

sudo sed -i "s/^Port[[:space:]]*=.*/Port=$NEWPORT/g" /etc/NXDNReflector.ini

echo "Port and TG have been updated to: $NEWPORT and $NEWTG"

# Set the Daemon = 0 so logging goes to the journal

sudo sed -i "s/^Daemon[[:space:]]*=.*/Daemon=0/g" /etc/NXDNReflector.ini

# Update FileLevel to 0

sudo sed -i "s/^FileLevel[[:space:]]*=.*/FileLevel=0/g" /etc/NXDNReflector.ini

#sudo sed -i "s|^[[:space:]]*FilePath[[:space:]]*=.*|FilePath=/var/log/|" /etc/NXDNReflector.ini
#sudo sed -i "s|^[[:space:]]*Name[[:space:]]*=.*|Name=/usr/local/bin/DVReflectors/NXDNReflector/nxdn.csv | " /etc/NXDNReflector.ini

echo ">> Download NXDN CSV file"
sudo -u mmdvm wget -O /usr/local/bin/DVReflectors/NXDNReflector/nxdn.csv \
https://www.radioid.net/static/nxdn.csv
chown mmdvm:mmdvm /usr/local/bin/DVReflectors/NXDNReflector/nxdn.csv
chmod 644 /usr/local/bin/DVReflectors/NXDNReflector/nxdn.csv
sudo sed -i "s|^Name=.*NXDN.csv|Name=/usr/local/bin/DVReflectors/NXDNReflector/nxdn.csv|" /etc/NXDNReflector.ini

#############################################
# ENABLE & START
#############################################

echo ">> Activating Services"

systemctl daemon-reload
systemctl enable nxdnreflector
systemctl start nxdnreflector
systemctl enable --now nxdn-db-update.timer

#############################################
# Give the www-data user access to the journal
#############################################
#
usermod -aG systemd-journal www-data

PHP_MAJOR_MINOR_CUT=$(php -v | head -n 1 | cut -d' ' -f2 | cut -f1-2 -d'.')

systemctl restart php$PHP_MAJOR_MINOR_CUT-fpm


#############################################
# Final Wrap-Up for NXDN
#############################################
echo ""
echo "=== INSTALLATION COMPLETE ==="
echo ""
echo "Reflector status : systemctl status nxdnreflector"
echo "Listening on      : UDP ${NEWPORT}"
echo "Logging available via the journal (systemctl -f -u nxdnreflector)"
echo ""
echo "To make configuration changes : sudo nano /etc/NXDNReflector.ini"
echo ""
echo ""

echo "After making configuration changes, please remember to:"
echo "  sudo systemctl restart nxdnreflector"

########################################################################################################################
### P25 Reflector Installation is optional - set the flag to 1 to install following the NXDN Reflector install.
### You cannot install the P25 Reflector alone (without the NXDN reflector, since this script assumes you will install
### the NXDN reflector as a minimum
#########################################################################################################################

if [[ $P25 -eq 1 ]]

then


#############################################
# P25Reflector INSTALLATION
#############################################

echo ">> Installing P25Reflector"

cd $INSTALL_DIR/P25Reflector

make clean
make -j 1
strip P25Reflector

chown -R $USER:$USER $INSTALL_DIR/P25Reflector
chmod +x P25Reflector

#############################################
# CONFIG FILE
#############################################

echo ">> Copying Configuration File"
if [[ ! -f $P25_INI_FILE ]]; then
  cp $INSTALL_DIR/P25Reflector/P25Reflector.ini $P25_INI_FILE
fi


#############################################
# SYSTEMD SERVICE (self-daemonizing!)
#############################################

echo ">> systemd service installation"

cat >/etc/systemd/system/$P25_SERVICE.service <<EOF
[Unit]
Description=P25Reflector
Requires=network.target
After=syslog.target network.target

[Service]
Type=simple
User=$USER
Group=$USER
WorkingDirectory=$INSTALL_DIR/P25Reflector
ExecStart=$INSTALL_DIR/P25Reflector/P25Reflector $P25_INI_FILE

# P25Reflector daemoniseert zichzelf
RemainAfterExit=yes

Restart=on-failure
#StandardOutput=append:/var/log/P25Reflector.log
#StandardError=append:/var/log/P25Reflector-error.log

[Install]
WantedBy=multi-user.target
EOF

#############################################
# P25 DMR ID UPDATE SCRIPT
#############################################
echo ">> P25 database update script"

cat >$INSTALL_DIR/P25Reflector/p25update.sh <<'EOF'
#!/bin/bash
set -e
systemctl stop p25nreflector
cd /usr/local/bin/DVReflectors/P25Reflector
mv dmrid.dat dmrid.old 2>/dev/null || true
wget -q -O nxdn.csv https://www.radioid.net/static/dmrid.dat
chown mmdvm:mmdvm dmrid.dat
systemctl start p25reflector
EOF

chmod +x $INSTALL_DIR/P25Reflector/p25update.sh

#############################################
# SYSTEMD TIMER – P25 DMRID Update
#############################################
echo ">> systemd timer (P25 db_update update)"

cat >/etc/systemd/system/p25-db-update.service <<EOF
[Service]
Type=oneshot
ExecStart=$INSTALL_DIR/P25Reflector/p25update.sh
EOF

cat >/etc/systemd/system/p25-db-update.timer <<EOF
[Timer]
OnCalendar=*-*-* 05:15
Persistent=true
[Install]
WantedBy=timers.target
EOF



####################################################################
# Update the P25Reflector.ini file
####################################################################

sudo sed -i "s/^Daemon[[:space:]]*=.*/Daemon=0/g" /etc/P25Reflector.ini
sudo sed -i "s/^FileLevel[[:space:]]*=.*/FileLevel=0/g" /etc/P25Reflector.ini

read -p "What port will you be listening on ? (Example 41400): " NEWP25PORT
sudo sed -i "s/^Port[[:space:]]*=.*/Port=$NEWP25PORT/g" /etc/P25Reflector.ini

echo "P25 Port set to: $NEWP25PORT"

echo ">> Download DMR ID DAT file"
sudo -u mmdvm wget -O /usr/local/bin/DVReflectors/P25Reflector/dmrid.dat \
https://www.radioid.net/static/dmrid.dat
chown mmdvm:mmdvm /usr/local/bin/DVReflectors/P25Reflector/dmrid.dat
chmod 644 /usr/local/bin/DVReflectors/P25Reflector/dmrid.dat
sudo sed -i "s|^Name=.*DMRIds.dat|Name=/usr/local/bin/DVReflectors/P25Reflector/dmrid.dat|" /etc/P25Reflector.ini

#############################################
# ENABLE & START
#############################################
echo ">> Activating Services"

systemctl daemon-reload
systemctl enable p25reflector
systemctl start p25reflector
systemctl enable --now p25-db-update.timer

#############################################
# Finished!
#############################################
echo ""
echo "=== INSTALLATION COMPLETE ==="
echo ""
echo "Reflector status : systemctl status p25reflector"
echo "Listening on      : UDP ${NEWP25PORT}"
echo "Logging available via the journal (systemctl -f -u p25reflector)"
echo ""
echo "To make configuration changes : sudo nano /etc/P25Reflector.ini"
echo ""
echo ""
echo "After making configuration changes, please remember to:"
echo "  sudo systemctl restart p25reflector"

else

   echo "P25 was not enabled / not installed"

fi
