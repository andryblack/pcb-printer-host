#include <iostream>
#include <string>

extern "C" {
#include <lua.h>
#include <lauxlib.h>
#include <lualib.h>
}


#include <signal.h>
#include <string.h>

#include "serial.h"
#include "rasterizator.h"
#include "rasterizator_write.h"

#include "camera/video_source.h"

extern "C" int luaopen_clipperlib(lua_State* L);


static int luaopen_app(lua_State* L) {
	Serial::lbind(L);
  Rasterizator::lbind(L);
  RasterizatorWrite::lbind(L);
  VideoSource::lbind(L);
	luaL_Reg reg[] = {
        { "openSerial", &Serial::lopen },
        { "newRasterizator", &Rasterizator::lnew },
        { "newRasterizatorWrite", &RasterizatorWrite::lnew },
        { "newCameraSource", &VideoSource::lnew },
        { NULL, NULL }
    };
    lua_newtable(L);
    luaL_setfuncs(L, reg, 0);
    return 1;
}

extern "C" void llae_register_modules(lua_State *L) {
  static const luaL_Reg loadedlibs[] = {
        {"llae",luaopen_llae},
        {"clipperlib",luaopen_clipperlib},
        {"app",luaopen_app},
        {NULL, NULL}
    };
    
    const luaL_Reg *lib;
    /* call open functions from 'loadedlibs' and set results to global table */
    for (lib = loadedlibs; lib->func; lib++) {
        luaL_requiref(L, lib->name, lib->func, 1);
        lua_pop(L, 1);  /* remove lib */
    }
}

