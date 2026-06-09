#!/bin/sh
# Has hysteresis, possibly. 
# Derived from (3) by Microsoft Copilot.

CARD=${CARD-1}
HWMON=`readlink -f /sys/class/drm/card${CARD}/device/hwmon/hwmon*`
PWM=$HWMON/pwm1

# Enable manual control
echo 1 > $HWMON/pwm1_enable || {
    echo "Failed to enable manual PWM control."
    exit 1
}

# ===== Fan curve parameters =====
PWM_MIN=90
PWM_LOW=130
PWM_MID=170
PWM_HIGH=210
PWM_MAX=255

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

# Reporting cadence
when_next=0
PERIOD_REPORT=100

# ===== Hysteresis thresholds =====
B0_UP=$T2_LOW
B1_DOWN=`expr $T2_LOW - 2`

B1_UP=$T2_MID
B2_DOWN=`expr $T2_MID - 2`

B2_UP=$T2_HIGH
B3_DOWN=`expr $T2_HIGH - 2`

B3_UP=$T2_MAX
B4_DOWN=`expr $T2_MAX - 2`

band=0
pwm_last=$PWM_MIN

while true; do
    pwm_have=`cat $PWM`

    temp1=`cat $HWMON/temp1_input`
    temp2=`cat $HWMON/temp2_input`
    temp3=`cat $HWMON/temp3_input`

    temp1_C=`expr $temp1 / 1000`
    temp2_C=`expr $temp2 / 1000`
    temp3_C=`expr $temp3 / 1000`

    # ===== Hotspot hysteresis band update =====

    # 4 → 3
    [ $band -eq 4 ] && [ $temp2_C -lt $B4_DOWN ] && band=3

    # 3 → 4
    [ $band -lt 4 ] && [ $temp2_C -ge $B3_UP ] && band=4

    # 3 → 2
    [ $band -eq 3 ] && [ $temp2_C -lt $B3_DOWN ] && band=2

    # 2 → 3
    [ $band -lt 3 ] && [ $temp2_C -ge $B2_UP ] && band=3

    # 2 → 1
    [ $band -eq 2 ] && [ $temp2_C -lt $B2_DOWN ] && band=1

    # 1 → 2
    [ $band -lt 2 ] && [ $temp2_C -ge $B1_UP ] && band=2

    # 1 → 0
    [ $band -eq 1 ] && [ $temp2_C -lt $B1_DOWN ] && band=0

    # 0 → 1
    [ $band -lt 1 ] && [ $temp2_C -ge $B0_UP ] && band=1

    # ===== Map band → PWM =====
    pwm_want2=$PWM_MIN
    [ $band -eq 1 ] && pwm_want2=$PWM_LOW
    [ $band -eq 2 ] && pwm_want2=$PWM_MID
    [ $band -eq 3 ] && pwm_want2=$PWM_HIGH
    [ $band -eq 4 ] && pwm_want2=$PWM_MAX

    # ===== VRM override =====
    pwm_want3=$PWM_MIN
    [ $temp3_C -ge $T3_CRIT ] && pwm_want3=$PWM_MAX
    [ $temp3_C -ge $T3_HIGH ] && pwm_want3=$PWM_HIGH
    [ $temp3_C -ge $T3_WARN ] && pwm_want3=$PWM_MID

    # Final target = max(hotspot, VRM)
    pwm_target=$pwm_want2
    [ $pwm_want3 -gt $pwm_want2 ] && pwm_target=$pwm_want3

    # ===== Determine if we adjust or report =====
    want_adjust=true
    want_report=true

    [ $pwm_last -eq $pwm_target ] && {
        want_adjust=false
        now=`date +%s`
        [ $now -le $when_next ] && want_report=false
    }

    # ===== Smooth ramp logic =====
    if $want_adjust; then
        if [ $pwm_last -lt $pwm_target ]; then
            pwm_next=`expr $pwm_last + 10`
            [ $pwm_next -gt $pwm_target ] && pwm_next=$pwm_target
        else
            pwm_next=`expr $pwm_last - 6`
            [ $pwm_next -lt $pwm_target ] && pwm_next=$pwm_target
        fi

        echo $pwm_next > $PWM
        pwm_last=$pwm_next
    fi

    # ===== Reporting =====
    if $want_report; then
        printf "edge:%3d°C hotspot:%3d°C vrm:%3d°C pwm have:%3d last:%3d next:%3d want:%3d band:%d\n" \
            $temp1_C $temp2_C $temp3_C $pwm_have $pwm_last $pwm_next $pwm_target $band

        when_next=`date +%s`
        when_next=`expr $when_next + $PERIOD_REPORT`
    fi

    sleep $INTERVAL
done
