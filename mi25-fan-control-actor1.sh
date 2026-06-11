#!/bin/bash


CARD=${CARD-1}
HWMON=${HWMON-$(readlink -f /sys/class/drm/card${CARD}/device/hwmon/hwmon*)}

# Sanity check
test -e $HWMON/pwm1_enable || {
    echo "ERROR cannot find PWM1 control file for card ${CARD}!"
    echo "Please check that the card is properly installed and the driver is loaded."
    echo "Checking: $HWMON/pwm1_enable"
    exit 1
}

echo 1 | sudo tee $HWMON/pwm1_enable

while true; do
    temp1=$(cat $HWMON/temp1_input) # edge
    temp2=$(cat $HWMON/temp2_input) # hotspot
    temp3=$(cat $HWMON/temp3_input) # vrm

    temp1=$((temp1 / 1000))
    temp2=$((temp2 / 1000))
    temp3=$((temp3 / 1000))

    digit=$(($temp2 % 10))

    case $((temp2 / 10)) in
        0) pwm=0 ;;
        1) pwm=5 ;;
        2) pwm=10 ;;
        3) pwm=$(( 60 + (2*digit))) ;;
        4) pwm=$(( 80 + (2*digit))) ;;
        5) pwm=$((100 + (5*digit))) ;;
        6) pwm=$((150 + (5*digit))) ;;
        7) pwm=$((200 + (5*digit))) ;;
        *) pwm=255 ;;
    esac

    echo $pwm | sudo tee $HWMON/pwm1 > /dev/null
    pwm2=$(cat $HWMON/pwm1)
    echo "temp1: $temp1 temp2: $temp2 temp3: $temp3 pwm want: $pwm have: $pwm2"

    sleep 2
done

