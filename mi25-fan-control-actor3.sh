#!/bin/bash

CARD=${CARD-1}
HWMON=$(readlink -f /sys/class/drm/card${CARD}/device/hwmon/hwmon*)
PWM=$HWMON/pwm1

# Enable manual control
echo 1 > $HWMON/pwm1_enable || {
    echo "Failed to enable manual PWM control."
    exit 1
}

# ===== Fan curve parameters =====
# MI25 blower characteristics:
# - Hotspot rises FAST under compute
# - VRM runs 10–20°C hotter than edge
# - Best stability when PWM ramps early and smoothly

PWM_MIN=90     # ~35%
PWM_LOW=130    # ~50%
PWM_MID=170    # ~67%
PWM_HIGH=210   # ~82%
PWM_MAX=255    # 100%

# Hotspot thresholds (temp2)
T2_LOW=40
T2_MID=50
T2_HIGH=60
T2_MAX=70

# VRM thresholds (temp3)
T3_WARN=75
T3_HIGH=85
T3_CRIT=95

INTERVAL=1

# When do we want the next report?
when_next=0
# Interval between reports when stable.
PERIOD_REPORT=100

# Track last PWM for hysteresis
pwm_last=$PWM_MIN

while true; do
    pwm_have=$(cat $PWM)

    temp1=$(cat $HWMON/temp1_input)  # edge
    temp2=$(cat $HWMON/temp2_input)  # hotspot
    temp3=$(cat $HWMON/temp3_input)  # vrm

    temp1_C=$((temp1/1000))
    temp2_C=$((temp2/1000))
    temp3_C=$((temp3/1000))

    # ===== Hotspot-based curve =====
    pwm_want2=$PWM_MIN
    [ $temp2_C -ge $T2_MAX  ] && pwm_want2=$PWM_MAX
    [ $temp2_C -ge $T2_HIGH ] && pwm_want2=$PWM_HIGH
    [ $temp2_C -ge $T2_MID  ] && pwm_want2=$PWM_MID
    [ $temp2_C -ge $T2_LOW  ] && pwm_want2=$PWM_LOW

    # ===== VRM override =====
    pwm_want3=$PWM_MIN
    [ $temp3_C -ge $T3_CRIT ] && pwm_want3=$PWM_MAX
    [ $temp3_C -ge $T3_HIGH ] && pwm_want3=$PWM_HIGH
    [ $temp3_C -ge $T3_WARN ] && pwm_want3=$PWM_MID

    # Final target = max of hotspot + VRM
    pwm_target=$pwm_want2
    [ $pwm_want3 -gt $pwm_want2 ] && pwm_target=$pwm_want3

    # Do nothing if on target.
    want_adjust=true
    want_report=true
    [ $pwm_last -eq $pwm_target ] && {
        want_adjust=false
        when_now=$(date +%s)
        [ $when_now -le $when_next ] && want_report=false
    }

    $want_adjust && {
        # ===== Smooth ramp logic =====
        [ $pwm_last -lt $pwm_target ] && {
            pwm_next=$((pwm_last + 10))
            [ $pwm_next -gt $pwm_target ] && pwm_next=$pwm_target
        }
        [ $pwm_last -gt $pwm_target ] && {
            pwm_next=$((pwm_last - 6))
            [ $pwm_next -lt $pwm_target ] && pwm_next=$pwm_target
        }

        echo $pwm_next > $PWM
        pwm_last=$pwm_next
    }

    $want_report && {
        FMT="edge:%3d°C hotspot:%3d°C vrm:%3d°C pwm_have: %3d pwm last: %3d next: %3d target: %3d\n" 
        printf "$FMT" $temp1_C $temp2_C $temp3_C $pwm_have $pwm_last $pwm_next $pwm_target
        when_next=$(date +%s)
        when_next=$(( when_next + PERIOD_REPORT ))
    }

    sleep $INTERVAL
done
