# Fan control for the AMD Instinct MI25

The MI25 does not come with a GPU fan.
There are mounting holes and a fan header on the card for a GPU fan.
I designed and 3D printed a custom duct, then installed with an appropriate-size GPU fan.

However - at it turns out - the MI25 BIOS *cannot* be persuaded to properly control the fan.

# Short version - install service to control the fan

Run the script **install.sh**, which:

1. Writes the executable file: ``/usr/local/bin/mi25-fan-control.sh``
2. Writes the *systemctl** service file for the **mi25-fanctl** fan control service.
3. Enables and starts the fan control service.

That's it, you are done. Feel free to ignore the remainder of this file.

# Show fan-related values

Run the script:
```sh
sh mi25-fan-show.sh
```
Note all the scripts assume the MI25 is "card1".
To override and use (for example) "card0":
```sh
CARD=0 sh mi25-fan-show.sh
```

# Monitor and control the MI25 fan

Scripts to monitor the MI25 and control the fan:
* mi25-fan-control-actor1.sh
* mi25-fan-control-actor2.sh
* mi25-fan-control-actor3.sh

The either script can be run from the command line.
The first is somewhat simpler - and works.
The second is fancier.
The third is yet fancier, and is also used for the fan control service.

# Experiments with the MI25 BIOS and fan control

Scripts:
* mi25-fan-table-set.sh
* mi25-fan-table-boot.sh

First off, you do not want to go here.
All my experiments ended up with the MI25 (eventually) overheating, and rebooting the computer.
(Not what you want, presumably.)

When the proper **amdgpu** driver is loaded, it is possible to inspect and modify the AMD ATOMBIOS pp_table values, which includes fan control.
Though in the end, fan control in the MI25 BIOS just does not work.

You need **upp** installed. Expect this to cause you some grief.

Running **mi25-fan-table-set.sh** will extract, modify, and apply FanTable parameters in the pp_table.
There is a hex-encoded dump of the modified pp_table that can be pasted into **mi25-fan-table-boot.sh**.

The hope was to run **mi25-fan-table-boot.sh** at boot, and have the card running with proper fan control.

(Also tried modifying an MI25 BIOS and flashing - but could not flash the modified BIOS.)

As it seems fan control in the MI25 BIOS just does not work, this was all a dead end.

