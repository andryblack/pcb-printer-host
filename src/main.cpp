#include <iostream>
#include <string>

#include "lua/state.h"
#include "lua/embedded.h"
#include "lua/value.h"
#include "uv/loop.h"
#include "uv/handle.h"
#include "llae/app.h"
#include "llae/diag.h"
#include "uv/buffer.h"

#include <unistd.h>
#include <syslog.h>
#include <signal.h>
#include <sys/resource.h>

#include "become_daemon.h"

static void createargtable (lua::state& lua, char **argv, int argc) {
  	int narg = argc - 1;  /* number of positive indices */
	lua.createtable(narg,1);
	for (int i = 0; i < argc; i++) {
    	lua.pushstring(argv[i]);
    	lua.rawseti(-2, i);
  	}
}

static int err_handler(lua_State* L) {
	auto msg = lua_tostring(L,-1);
	luaL_traceback(L,L,msg,1);
	return 1;
}

static const char *SYSLOGNAME = "pcb-printer-host";
static const char *LOGFILENAME = "/var/log/pcb-printer-host.log";
static const char *PIDFILENAME = "/var/run/pcb-printer-host.pid";

int main(int argc,char** argv) {
	bool need_daemon = false;
	const char* logfile = LOGFILENAME;
	const char* pidfile = PIDFILENAME;
	for (int i=0;i<argc;++i) {
		if (strcmp(argv[i],"-b")==0)
			need_daemon = true;
		else if (strcmp(argv[i],"-l")==0) {
			if ((i+1)>=argc) {
				std::cout << "need log file argument" << std::endl;
				return 1;
			}
			logfile = argv[i+1];
			++i;
		}
		else if (strcmp(argv[i],"-p")==0) {
			if ((i+1)>=argc) {
				std::cout << "need pid file argument" << std::endl;
				return 1;
			}
			pidfile = argv[i+1];
			++i;
		}
	}
	if (need_daemon) {
		int ret = become_daemon();
		if(ret) {
		    syslog(LOG_USER | LOG_ERR, "error starting");
		    closelog();
		    return EXIT_FAILURE;
		}
		ret = redirect_log(logfile);
		if(ret) {
		    syslog(LOG_USER | LOG_ERR, "error redirect log");
		    closelog();
		    return EXIT_FAILURE;
		}
		write_pid(pidfile);
	}

	signal(SIGPIPE,SIG_IGN);

	// reduce uv threads stack size
	struct rlimit lim;
	if (0 == getrlimit(RLIMIT_STACK, &lim) && lim.rlim_cur != RLIM_INFINITY) {
		lim.rlim_cur = 1 << 20;
		setrlimit(RLIMIT_STACK,&lim);
	}

	auto loop = uv_default_loop();
	int retcode = 0;
    {
		llae::app app{loop};

		lua::state& L(app.lua());

		lua::attach_embedded_modules(L);

		lua::attach_embedded_scripts(L);

		L.pushcfunction(&err_handler);
		auto err = lua::load_embedded(L,"_main");
		if (err!=lua::status::ok) {
			app.show_error(L,err);
			retcode = 1;
		} else {
			createargtable(L,argv,argc);
			err = L.pcall(1,0,-3);
			if (err != lua::status::ok) {
				app.show_error(L,err);
                app.stop(1);
			}
            retcode = app.run();
		}
	}

	size_t wait_cnt = 0;
    while (uv_loop_close(loop) == UV_EBUSY) {
        uv_run(loop, UV_RUN_ONCE);
        uv_print_all_handles(loop, stderr);
        if (++wait_cnt > 31) {
        	break;
        }
    }

	LLAE_DIAG(std::cout << "meta objects:  " << meta::object::get_total_count() << std::endl;)
	LLAE_DIAG(std::cout << "buffers alloc: " << llae::named_alloc<uv::buffer>::get_allocated() << std::endl;)

	return retcode;
}
