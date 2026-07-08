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
# Tested with a proper card-design-specific GPU fan (blower) and a custom duct.
# The GPU fan is very effective at hotspot and VRM cooling, but also audible at higher speeds.
# With no other provision to cool the VRM (i.e. no second fan), VRM temperatures are well-controlled.
# - Hotspot and VRM rises FAST under compute
# - VRM runs up to 20°C hotter than edge (observed with GPU fan and custom duct)
# - VRM runs up to 10°C hotter than hotspot (at maximum load)
# - VRM best kept under 90°C for longevity.

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

# Temperature thresholds
T_C_STAGES=(
    0   # stage 0 is any lower temperature
    40  # stage 1 if at or above 40°C
    50  # stage 2 if at or above 50°C
    60  # stage 3 if at or above 60°C
    70  # stage 4 if at or above 70°C
    80  # stage 5 if at or above 80°C
    100 # (to simplify logic)
)

# Minimum temperature difference to trigger a stage change
DELTA_T_DECREASE=-3
DELTA_T_INCREASE=2

# Interval between checks
INTERVAL=1

# When do we want the next report?
when_next=0
# Interval between reports when stable.
PERIOD_REPORT=100

# Track current stage and last PWM value
stage=0                     # assume fan should be at the lowest stage
pwm_last=${PWM_STAGES[0]}   # will drop PWM to minimum at start
pwm_want=$pwm_last          # will be where wanted at start
temp_C_last=0               # assume the last known hotspot/VRM temperature

# Drop fan to lowest.
echo $pwm_last > $PWM || {
    echo "ERROR: Cannot write to $PWM"
    sleep 1 # Slow respawn
    # If the card is not ready, the write will fail.  
    # Wait a second and try again.
    exit 1
}

while true; do
    pwm_have=$(cat $PWM)

    temp1_read=$(cat $HWMON/temp1_input)  # edge
    temp2_read=$(cat $HWMON/temp2_input)  # hotspot
    temp3_read=$(cat $HWMON/temp3_input)  # vrm

    temp1_C=$((temp1_read/1000))
    temp2_C=$((temp2_read/1000))
    temp3_C=$((temp3_read/1000))

    # Control based on highest temperature (hotspot or VRM)
    temp_C_base=$temp2_C
    [ $temp3_C -gt $temp_C_base ] && temp_C_base=$temp3_C
    # Note: edge temperature is ignored for control (as typically low), but monitored for reporting.
    # If your edge temperature is high, your computer might be on fire, so not relevant. 

    # If the temperature has changed significantly, update the PWM
    delta_temp_C_base=$((temp_C_base - temp_C_last))
    
    want_adjust=false
    [ $pwm_last -ne $pwm_want ] && want_adjust=true
    [ $delta_temp_C_base -ge $DELTA_T_INCREASE ] && want_adjust=true
    [ $delta_temp_C_base -le $DELTA_T_DECREASE ] && want_adjust=true

    $want_adjust && {
        temp_C_last=$temp_C_base

        stage=0
        [ $temp_C_base -ge ${T_C_STAGES[1]} ] && stage=1
        [ $temp_C_base -ge ${T_C_STAGES[2]} ] && stage=2
        [ $temp_C_base -ge ${T_C_STAGES[3]} ] && stage=3
        [ $temp_C_base -ge ${T_C_STAGES[4]} ] && stage=4
        [ $temp_C_base -ge ${T_C_STAGES[5]} ] && stage=5

        pwm_range1=${PWM_STAGES[$stage]}
        pwm_range2=${PWM_STAGES[((stage + 1))]}

        t_range1=${T_C_STAGES[$stage]}
        t_range2=${T_C_STAGES[((stage + 1))]}

        # Want linear interpolation between the two stages.
        delta_pwm_range=$((pwm_range2 - pwm_range1))
        delta_temp_range=$((t_range2 - t_range1))
        delta_temp_C_base=$((temp_C_base - t_range1))
    
        pwm_adjust=$(((delta_pwm_range * delta_temp_C_base) / delta_temp_range))
        pwm_want=$((pwm_range1 + pwm_adjust))
    }

    
    # Final target = max of hotspot + VRM
    pwm_target=$pwm_want

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
