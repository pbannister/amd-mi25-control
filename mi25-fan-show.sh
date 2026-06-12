#!/bin/bash

for PWM1 in /sys/class/drm/card*/device/hwmon/hwmon*/pwm1; do
    HWMON=$(readlink -f $(dirname $PWM1))
    
    echo "=== MI25 Fan / Thermal Status ==="
    echo "hwmon path: $HWMON"
    echo

    echo "Fan RPM:"
    cat $HWMON/fan1_input 2>/dev/null

    echo
    echo "Fan Min / Max RPM:"
    cat $HWMON/fan1_min 2>/dev/null
    cat $HWMON/fan1_max 2>/dev/null

    echo
    echo "PWM (Fan Duty Cycle):"
    echo -n "pwm1:        "; cat $HWMON/pwm1 2>/dev/null
    echo -n "pwm1_min:    "; cat $HWMON/pwm1_min 2>/dev/null
    echo -n "pwm1_max:    "; cat $HWMON/pwm1_max 2>/dev/null
    echo -n "pwm1_enable: "; cat $HWMON/pwm1_enable 2>/dev/null

    echo
    echo "Temperatures:"
    echo -n "Edge temp:    "; cat $HWMON/temp1_input 2>/dev/null
    echo -n "Hotspot temp: "; cat $HWMON/temp2_input 2>/dev/null
    echo -n "HBM temp:     "; cat $HWMON/temp3_input 2>/dev/null

    echo
    echo "Temperature Limits:"
    echo -n "temp1_crit:        "; cat $HWMON/temp1_crit 2>/dev/null
    echo -n "temp1_emergency:   "; cat $HWMON/temp1_emergency 2>/dev/null
    echo -n "temp2_crit:        "; cat $HWMON/temp2_crit 2>/dev/null
    echo -n "temp3_crit:        "; cat $HWMON/temp3_crit 2>/dev/null
    echo -n "temp3_emergency:   "; cat $HWMON/temp3_emergency 2>/dev/null

    echo
    echo "=== End ==="

done

