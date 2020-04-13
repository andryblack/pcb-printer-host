## PCB printer host service

Host service source code for PCB laser printer.

## Installation on Raspberry Pi

* install Raspbian Stretch Lite https://www.raspberrypi.org/downloads/raspbian/

* configure wifi and ssh https://raspberrypi.stackexchange.com/questions/10251/prepare-sd-card-for-wifi-on-headless-pi

* connect to raspberry:
```bash
$ ssh pi@raspberrypi.local
 password: raspberry
```

* install dependencies
```bash
$ sudo sudo apt-get update
$ sudo apt-get upgrade
$ sudo apt-get install wget libyajl2 lua5.3 libuv1 openssl
```

* download printer software
```bash
$ wget https://... -o pcb-laser-printer.deb
```

* install printer software
```bash
$ sudo dpkg -I pcb-laser-printer.deb
```

## Development installation

dependencies:
```bash
$ sudo apt-get install build-essential git 
$ sudo apt-get install liblua5.3-dev libuv1-dev libyajl-dev libpng-dev libssl-dev

$ # premake5
$ cd ~
$ git clone https://github.com/premake/premake-core.git
$ cd premake-core/
$ make -f Bootstrap.mak linux
$ # install at $HOME/bin
$ mkdir -p ~/bin
$ cp bin/release/premake5 ~/bin/
```
host
```bash
$ cd ~
$ git clone https://github.com/andryblack/pcb-printer-host.git
$ cd pcb-printer-host
$ # download modules
$ git submodule init
$ git submodule update
$ make local-modules
$ make project 
$ make 
$ # run local instance
$ make run
```

open http://localhost:8080 at browser


Raspberry Pi:
use BOARD=rpi at each make command
```bash
# free uart
echo "dtoverlay=pi3-disable-bt" >> /boot/config.txt
```