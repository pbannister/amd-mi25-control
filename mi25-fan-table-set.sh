#!/bin/bash

CARD=${CARD-1}

# Path to MI25 pp_table
PP_PATH="/sys/class/drm/card${CARD}/device/pp_table"

echo "
==== Reading current pp_table from GPU: $PP_PATH"


PP_BIN1="out/pp_table1.bin"
PP_TXT1="out/pp_table1.txt"
PP_BIN2="out/pp_table2.bin"
PP_TXT2="out/pp_table2.txt"
PP_BIN3="out/pp_table3.bin"
PP_TXT3="out/pp_table3.txt"

echo "
==== Copying MI25 PowerPlay Table to: $PP_BIN1"
sudo cat "$PP_PATH" > "$PP_BIN1"

echo "
==== Dumping binary pp_table to text format: $PP_TXT1" 
upp --pp-file "$PP_BIN1" dump > "$PP_TXT1"

echo "
==== Applying FanTable modifications..."
cp $PP_BIN1 $PP_BIN2
cp $PP_TXT1 $PP_TXT2
cp $PP_BIN1 $PP_BIN3
cp $PP_TXT1 $PP_TXT3

TMPFILE=$(mktemp)

apply() {
    FIELD=$1
    VALUE=$2
    echo "Setting $FIELD = $VALUE"
    upp --pp-file "$PP_BIN2" set "$FIELD=$VALUE" < "$PP_TXT2" > $TMPFILE && mv $TMPFILE "$PP_TXT2"
}

apply FanTable.RevId 11
apply FanTable.FanOutputSensitivity 8192

# Earlier and stronger ramp
apply FanTable.FanAcousticLimitRpm 6000
apply FanTable.ThrottlingRPM 4000

# Lower target temp (like hotspot control)
apply FanTable.TargetTemperature 40

# Higher minimum PWM equivalent
apply FanTable.MinimumPWMLimit 100

apply FanTable.TargetGfxClk 1500

# Higher gains = faster ramp
apply FanTable.FanGainEdge 2500
apply FanTable.FanGainHotspot 3500
apply FanTable.FanGainLiquid 2500
apply FanTable.FanGainVrVddc 2500
apply FanTable.FanGainVrMvdd 2500
apply FanTable.FanGainPlx 2500
apply FanTable.FanGainHbm 2500

# Disable ZeroRPM fully
apply FanTable.EnableZeroRPM 0
apply FanTable.FanStopTemperature 0
apply FanTable.FanStartTemperature 0
apply FanTable.FanParameters 2

# Wider RPM range
apply FanTable.FanMinRPM 1000
apply FanTable.FanMaxRPM 6000

cp $PP_TXT2 $PP_TXT3

echo "
==== Rebuilding modified pp_table binary: $PP_BIN3"
upp --pp-file "$PP_BIN3" undump --dump-filename "$PP_TXT3" --write

echo "Done."
echo "Modified text:  $PP_TXT3"
echo "Modified binary: $PP_BIN3"

echo "
==== Encoding as hex from modified binary"
xxd -p -c 32 "$PP_BIN3" > out/pp_table3.hex

echo "
==== Applying modified pp_table to GPU"
sudo sh -c 'cat out/pp_table3.bin > /sys/class/drm/card1/device/pp_table'

