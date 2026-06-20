#!/bin/sh

MI25_FANCTL_SERVICE_NAME=mi25-fanctl.service
MI25_FANCTL_SERVICE_FILE=/etc/systemd/system/$MI25_FANCTL_SERVICE_NAME
MI25_FANCTL_SCRIPT=/usr/local/bin/mi25-fan-control.sh
MI25_FANCTL_SCRIPT_SOURCE=mi25-fan-control-actor6.sh

echo "
==== Test for PWM1 control: /sys/class/drm/card*/device/hwmon/hwmon*/pwm1_enable"
FOUND=false
for HWMON in /sys/class/drm/card*/device/hwmon/hwmon* ; do
    echo "Checking: $HWMON"
    test -f "$HWMON/pwm1_enable" && {
        FOUND=true
        break
    }
done

$FOUND || { 
    echo "ERROR: No suitable HWMON found!"
    exit 1
}
echo "Using: $HWMON"

HWMON=$(readlink -f $HWMON)

echo 1 | sudo tee $HWMON/pwm1_enable

echo "
==== Stopping mi25-fanctl.service (if present)"
sudo systemctl stop $MI25_FANCTL_SERVICE_NAME    

echo "
==== Installing MI25 Fan Control Script to: $MI25_FANCTL_SCRIPT"

sudo cp $MI25_FANCTL_SCRIPT_SOURCE $MI25_FANCTL_SCRIPT
sudo chmod +x $MI25_FANCTL_SCRIPT

echo "
==== Installing systemd service to: $MI25_FANCTL_SERVICE_FILE"

sudo tee $MI25_FANCTL_SERVICE_FILE > /dev/null <<XXXX
[Unit]
Description=MI25 Hotspot/VRM Fan Controller
After=multi-user.target
After=default.target
After=graphical.target
After=systemd-udevd.service
After=drm.service
After=modprobe@amdgpu.service

[Service]
Type=simple
Environment="HWMON=${HWMON}"
ExecStart=$MI25_FANCTL_SCRIPT
Restart=always
RestartSec=2
User=root
Nice=-5
IOSchedulingClass=best-effort
IOSchedulingPriority=0

# Ensure GPU hwmon path exists before starting
ExecStartPre=/bin/sh -c 'sleep 3'

# Prevent systemd from killing the script on shutdown
KillMode=process
TimeoutStopSec=5

[Install]
WantedBy=multi-user.target
XXXX

echo "
==== Enabling and starting mi25-fanctl.service"
sudo systemctl daemon-reload
sudo systemctl enable $MI25_FANCTL_SERVICE_NAME
sudo systemctl start $MI25_FANCTL_SERVICE_NAME

echo "
==== Status of mi25-fanctl.service"
sudo systemctl status $MI25_FANCTL_SERVICE_NAME --no-pager

