## PCB printer host service

Host service source code for PCB laser printer.

## Installation on Raspberry Pi

* write image to sdcad

* place wpa_supplicant.conf to sdcadr boot partition

```
ctrl_interface=/var/run/wpa_supplicant
ctrl_interface_group=0
update_config=1

network={
    ssid="you-wifi-name"
	psk="you-wifi-pass"
}
```

* insert sdcard to Raspberry Pi, wait about 5 minutes for preparation complete

* open at browser http://pcbprint.local

* configure connection `/dev/ttyAMA0`

* configure camera `/dev/video0`

* configure video encoder `/dev/video10` 

## Development installation

dependencies:

* premake5
* llae

building

```bash
$ llae install
$ llae init
$ premake5 --file=build/premake5.lua gmake
$ make -C build
```

running
```bash
$ ./bin/pcb-printer-host --dev
```

open http://localhost:8080 at browser
