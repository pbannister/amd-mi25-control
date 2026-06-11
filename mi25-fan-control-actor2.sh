#!/bin/bash

CARD=${CARD-1}
HWMON=${HWMON-$(readlink -f /sys/class/drm/card${CARD}/device/hwmon/hwmon*)}

PWM=$HWMON/pwm1

# Sanity check
test -e $HWMON/pwm1_enable || {
    echo "ERROR cannot find PWM1 control file for card ${CARD}!"
    echo "Please check that the card is properly installed and the driver is loaded."
    echo "Checking: $HWMON/pwm1_enable"
    exit 1
}

# Enable manual control
echo 1 | tee $HWMON/pwm1_enable > /dev/null || {
    echo "Failed to enable manual PWM control. Are you sure you have the right card number and permissions?"
    exit 1
}

# Fan curve parameters
PWM_MIN=70
PWM_MID=140
PWM_HIGH=190
PWM_MAX=255

TEMP2_C_LOW=45
TEMP2_C_MID=60
TEMP2_C_HIGH=75

TEMP3_C_MID=85
TEMP3_C_HIGH=95

INTERVAL=2

while true; do
    temp1=$(cat $HWMON/temp1_input) # edge
    temp2=$(cat $HWMON/temp2_input) # hotspot
    temp3=$(cat $HWMON/temp3_input) # vrm

    pwm_have=$(cat $PWM)

    temp1_C=$((temp1/1000))
    temp2_C=$((temp2/1000))
    temp3_C=$((temp3/1000))

    # Base PWM from hotspot
    pwm_want2=$PWM_MIN
    [ $temp2_C -ge $TEMP2_C_LOW ]   && pwm_want2=$PWM_MID
    [ $temp2_C -ge $TEMP2_C_MID ]   && pwm_want2=$PWM_HIGH
    [ $temp2_C -ge $TEMP2_C_HIGH ]  && pwm_want2=$PWM_MAX

    # VRM override (slow-burn protection)
    pwm_want3=$PWM_MIN
    [ $temp3_C -ge $TEMP3_C_MID ]   && pwm_want3=$PWM_HIGH
    [ $temp3_C -ge $TEMP3_C_HIGH ]  && pwm_want3=$PWM_MAX

    # Final target is max of both
    pwm_want=$pwm_want2
    [ $pwm_want2 -lt $pwm_want3 ] && pwm_want=$pwm_want3

    # Smooth transitions (anti-oscillation)
    [ $pwm_have -eq $pwm_want ] && continue
    [ $pwm_have -lt $pwm_want ] && {
        pwm_next=$((pwm_have + 8))
        [ $pwm_next -gt $pwm_want ] && pwm_next=$((pwm_want + 1))
    }
    [ $pwm_have -gt $pwm_want ] && {
        pwm_next=$((pwm_have - 4))
        [ $pwm_next -lt $pwm_want ] && pwm_next=$pwm_want
    }

    echo $pwm_next | tee $PWM > /dev/null

    printf "temp edge: %3d°C hotspot: %3d°C vrm: %3d°C pwm have: %3d next: %3d want: %3d\n" $temp1_C $temp2_C $temp3_C $pwm_have $pwm_next $pwm_want

    sleep $INTERVAL
done
