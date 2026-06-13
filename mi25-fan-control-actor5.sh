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

# ===== Fan curve parameters =====
# MI25 blower characteristics:
# - Hotspot rises FAST under compute
# - VRM runs 10–20°C hotter than edge (in theory, but not in practice, so far)
# - Best stability when PWM ramps early and smoothly

PWM_STAGES=(
    10   # minimum PWM setting
    50   # ~20% for stage 0
    75   # ~30% for stage 1
    100  # ~40% for stage 2
    150  # ~60% for stage 3
    200  # ~80% for stage 4
    255  # 100% for stage 5
    255  # maximum PWM setting
)

# Hotspot thresholds (temp2)
T2_STAGES=(
    0   # stage 0 is any lower temperature
    40  # stage 1 if at or above 40°C
    50  # stage 2 if at or above 50°C
    60  # stage 3 if at or above 60°C
    70  # stage 4 if at or above 70°C
    90  # stage 5 if at or above 90°C
    100 # (to simplify logic)
)

# Minimum temperature difference to trigger a stage change
DELTA_T2_DECREASE=-3
DELTA_T2_INCREASE=2

# VRM thresholds (temp3)
T3_STAGE1=55
T3_STAGE2=65
T3_STAGE3=75
T3_STAGE4=85
T3_STAGE5=95

# Interval between checks
INTERVAL=1

# When do we want the next report?
when_next=0
# Interval between reports when stable.
PERIOD_REPORT=100

# Track current stage and last PWM value
stage=0                     # assume fan should be at the lowest stage
pwm_last=${PWM_STAGES[0]}   # will drop PWM to minimum at start
pwm_want2=$pwm_last         # will be where wanted at start
temp2_C_last=0              # assume the last known hotspot temperature

# Drop fan to lowest.
echo $pwm_last > $PWM

while true; do
    pwm_have=$(cat $PWM)

    temp1_read=$(cat $HWMON/temp1_input)  # edge
    temp2_read=$(cat $HWMON/temp2_input)  # hotspot
    temp3_read=$(cat $HWMON/temp3_input)  # vrm

    temp1_C=$((temp1_read/1000))
    temp2_C=$((temp2_read/1000))
    temp3_C=$((temp3_read/1000))

    # ===== Hotspot-based curve =====

    # If the temperature has changed significantly, update the PWM
    delta_temp2_C=$((temp2_C - temp2_C_last))
    
    want_t2_adjust=false
    [ $pwm_last -ne $pwm_want2 ] && want_t2_adjust=true
    [ $delta_temp2_C -ge $DELTA_T2_INCREASE ] && want_t2_adjust=true
    [ $delta_temp2_C -le $DELTA_T2_DECREASE ] && want_t2_adjust=true

    $want_t2_adjust && {
        temp2_C_last=$temp2_C

        stage=0
        [ $temp2_C -ge ${T2_STAGES[1]} ] && stage=1
        [ $temp2_C -ge ${T2_STAGES[2]} ] && stage=2
        [ $temp2_C -ge ${T2_STAGES[3]} ] && stage=3
        [ $temp2_C -ge ${T2_STAGES[4]} ] && stage=4
        [ $temp2_C -ge ${T2_STAGES[5]} ] && stage=5

        pwm_range1=${PWM_STAGES[$stage]}
        pwm_range2=${PWM_STAGES[((stage + 1))]}

        t2_range1=${T2_STAGES[$stage]}
        t2_range2=${T2_STAGES[((stage + 1))]}

        # Want linear interpolation between the two stages.
        delta_pwm_range=$((pwm_range2 - pwm_range1))
        delta_temp2_range=$((t2_range2 - t2_range1))
        delta_temp2_C=$((temp2_C - t2_range1))
    
        pwm_adjust=$(((delta_pwm_range * delta_temp2_C) / delta_temp2_range))
        pwm_want2=$((pwm_range1 + pwm_adjust))
    }

    # ===== VRM override =====
    pwm_want3=${PWM_STAGES[0]}
    [ $temp3_C -ge $T3_STAGE1 ] && pwm_want3=${PWM_STAGES[1]}
    [ $temp3_C -ge $T3_STAGE2 ] && pwm_want3=${PWM_STAGES[2]}
    [ $temp3_C -ge $T3_STAGE3 ] && pwm_want3=${PWM_STAGES[3]}
    [ $temp3_C -ge $T3_STAGE4 ] && pwm_want3=${PWM_STAGES[4]}
    [ $temp3_C -ge $T3_STAGE5 ] && pwm_want3=${PWM_STAGES[5]}

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

    pwm_next=$pwm_last # if not adjusted

    $want_adjust && {
        pwm_next=$pwm_target
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
        FMT="edge:%3d°C hotspot:%3d°C vrm:%3d°C pwm have: %3d last: %3d next: %3d want: %3d\n" 
        printf "$FMT" $temp1_C $temp2_C $temp3_C $pwm_have $pwm_last $pwm_next $pwm_target
        when_next=$(date +%s)
        when_next=$(( when_next + PERIOD_REPORT ))
    }

    sleep $INTERVAL
done
