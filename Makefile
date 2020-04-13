
DEPMODULES= \
	lua-resty-template\
	router\
	llae

LOCALTREE=local
BOARD?=generic

.PHONY: all src-distr

all: build

files:
		mkdir -p local/var/files

project: premake5.lua 
		premake5 gmake --board=$(BOARD)

build: project
		make -C build verbose=1

release: project
		make -C build config=release verbose=1

run: all files
		./bin/pcb-printer scripts/main.lua

$(LOCALTREE):
		mkdir -p $(LOCALTREE)


local-module-lua-resty-template:
		mkdir -p $(LOCALTREE)/share/pcb-laser-printer/resty
		cp -r extlib/lua-resty-template/lib/resty/* $(LOCALTREE)/share/pcb-laser-printer/resty

local-module-router:
		mkdir -p $(LOCALTREE)/share/pcb-laser-printer/
		cp -r extlib/router.lua/router.lua $(LOCALTREE)/share/pcb-laser-printer/

local-module-llae:
		mkdir -p $(LOCALTREE)/share/pcb-laser-printer/llae
		mkdir -p $(LOCALTREE)/share/pcb-laser-printer/net
		mkdir -p $(LOCALTREE)/share/pcb-laser-printer/db
		cp -r extlib/llae/scripts/llae/* $(LOCALTREE)/share/pcb-laser-printer/llae
		cp -r extlib/llae/scripts/net/* $(LOCALTREE)/share/pcb-laser-printer/net
		cp -r extlib/llae/scripts/db/* $(LOCALTREE)/share/pcb-laser-printer/db


local-modules: $(LOCALTREE) $(patsubst %,local-module-%,$(DEPMODULES))

clean:
		rm -rf bin/*
		rm -rf build/*
		rm -rf lib/*


src-distr:
		git archive --prefix=pcb-laser-printer/ -o pcb-laser-printer-src.tar.gz master
		cd extlib/llae && git archive --prefix=pcb-laser-printer/extlib/llae/ -o ../../llae-src.tar.gz HEAD

debian-distr:
		dpkg-buildpackage -b

		
debian-package:
		fakeroot debian/rules binary


		
