#include "serial.h"

#include <unistd.h>
#include <fcntl.h>   /* File control definitions */
#include <errno.h>
#include <termios.h>
#include <string.h>

#include <iostream>

static const char* mt_name = "app.Serial";

Serial::Serial(uv_loop_t* loop,int fd)  : m_need_stop(false) {
	int r = uv_poll_init(loop,&m_poll,fd);
	if (r < 0) {
		std::cerr << "failed set raw mode " << uv_strerror(r) << std::endl;
	}
	m_fd = fd;
	attach();
}

Serial::~Serial() {
	if (m_fd) {
		::close(m_fd);
		m_fd = 0;
	}
}


bool Serial::configure_baud(lua_State* L,int baud) {
	if (m_fd<0)
		return false;
	int ttyfd = m_fd;

	// int r = uv_fileno(get_handle(),&ttyfd);
	// lua_llae_handle_error(L,"Serial::configure_baud",r);

	// if (ttyfd<=0) {
	// 	luaL_error(L,"invalid fd");
	// }

	fcntl(ttyfd, F_SETFL, 0);
	fcntl(ttyfd, F_SETFL, FNDELAY);

	struct termios options;
	if (tcgetattr(ttyfd, &options)!= 0) {
		std::cerr << "failed tcgetattr " << errno << std::endl;
		return false;
	}
	int baud_val = 0;
	switch (baud) {
		case 9600: baud_val = B9600; break;
		case 19200: baud_val = B19200; break;
		case 38400: baud_val = B38400; break;
		case 57600: baud_val = B57600; break;
		case 115200: baud_val = B115200; break;
		case 230400: baud_val = B230400; break;
		//case 460800: baud_val = B460800; break;
		//case 500000: baud_val = B500000; break;
		// case 576000: baud_val = B576000; break;
		// case 921600: baud_val = B921600; break;
		// case 1000000: baud_val = B1000000; break;
		// case 1152000: baud_val = B1152000; break;
		// case 1500000: baud_val = B1500000; break;
		// case 2000000: baud_val = B2000000; break;
		// case 2500000: baud_val = B2500000; break;
		// case 3000000: baud_val = B3000000; break;
		// case 3500000: baud_val = B3500000; break;
		// case 4000000: baud_val = B4000000; break;
	};
	if (!baud_val) {
		std::cerr << "unsupported baudrate " << baud << std::endl;
		return false;
	}
	cfsetispeed(&options, baud_val);
	cfsetospeed(&options, baud_val);
	options.c_cflag |= (CLOCAL | CREAD);
	options.c_cflag &= ~PARENB;
	options.c_cflag &= ~CSTOPB; // 8n1
	options.c_cflag &= ~CSIZE;
	options.c_cflag |= CS8;
	options.c_cflag &= ~CRTSCTS;

	 options.c_iflag &= ~IGNBRK;
	 options.c_iflag &= ~(INLCR | IGNCR | ICRNL | IUCLC); // no char processing
	options.c_lflag = 0;                // no signaling chars, no echo,
 //                                        // no canonical processing
 	  options.c_oflag = 0;                // no remapping, no delays

    options.c_cc[VMIN]  = 0;            // read doesn't block
    options.c_cc[VTIME] = 0;            // 0.5 seconds read timeout

   options.c_iflag &= ~(IXON | IXOFF | IXANY); // shut off xon/xoff ctrl

	if (tcsetattr(ttyfd, TCSANOW, &options)!=0) {
		std::cerr << "failed tcsetattr " << errno << std::endl;
		return false;
	}
	return true;
}

void Serial::on_poll(int status,int events) {
	//std::cout << "on_poll" << std::endl;
	lua_State* L = llae_get_vm(get_handle());
	if (status < 0) {
		const char* err = uv_strerror(status);
		m_th.resumev(L,"Serial::on_poll",err);
	} else if (events & UV_READABLE) {
		ssize_t size = ::read(m_fd,m_buf,sizeof(m_buf));
		if (size < 0) {
			const char* err = strerror(errno);
			m_th.resumev(L,"Serial::on_poll",err);
		} else if (size) {
			lua_pushnil(L);
			lua_pushlstring(L,m_buf,size);
			m_th.resumevi(L,"Serial::on_poll",2);
		}
	}
}

void Serial::poll_cb(uv_poll_t* poll,int status,int events) {
	static_cast<Serial*>(poll->data)->on_poll(status,events);
}

void Serial::start_read(lua_State* L,const luabind::function& f) {
	m_th.starti(L,f,"Serial::start",lua_gettop(L)-2);
	int res = uv_poll_start(&m_poll,UV_READABLE|UV_DISCONNECT,&Serial::poll_cb);
	if (res < 0) {
		m_th.reset(L);
		lua_llae_handle_error(L,"Serial::start_read",res);
	} else {
		m_need_stop = true;
	}
}

void Serial::read(lua_State* L) {
	lua_yield(L,0);
}

void Serial::stop_read(lua_State* L) {
	if (m_need_stop) {
		m_need_stop = false;
		uv_poll_stop(&m_poll);
	}
	m_th.reset(L);
}

void Serial::write(lua_State* L) {
	//std::cout << "write >>" << std::endl;
	size_t size = 0;
	const char* data = lua_tolstring(L,2,&size);
	if (size) {
		std::cout << "write " << size << std::endl;
		int r = ::write(m_fd,data,size);
		if (r < size) {
			luaL_error(L,"failed write to setial %d",r);
		}
		::fsync(m_fd);
	} 
	//std::cout << "write <<" << std::endl;
}

void Serial::close(lua_State* L) {
	if (m_need_stop) {
		uv_poll_stop(&m_poll);
		m_need_stop = false;
	}
	m_th.reset(L);
	
}

int Serial::lopen(lua_State* L) {
	const char* path = luaL_checkstring(L,1);
	int fd = open(path,O_RDWR  | O_NOCTTY | O_NDELAY);
	if (fd < 0) {
		lua_pushnil(L);
		lua_pushfstring(L,"failed opening `%s`: %s",path,strerror(errno));
		return 2;
	}
	(new Serial(llae_get_loop(L),fd))->push(L);
	return 1;
}
void Serial::push(lua_State* L) {
	new (lua_newuserdata(L,sizeof(SerialRef))) SerialRef(this);
	UVHandleHolder::push(L);
	luaL_setmetatable(L,mt_name);
}
void Serial::lbind(lua_State* L) {
	luaL_newmetatable(L,mt_name);
	lua_newtable(L);
	luabind::bind(L,"configure_baud",&Serial::configure_baud);
	luabind::bind(L,"write",&Serial::write);
	luabind::bind(L,"start_read",&Serial::start_read);
	luabind::bind(L,"read",&Serial::read);
	luabind::bind(L,"close",&Serial::close);
	luabind::bind(L,"stop_read",&Serial::stop_read);
	// luaL_getmetatable(L,Stream::get_mt_name());
	// lua_setmetatable(L,-2);
	lua_setfield(L,-2,"__index");
	lua_pushcfunction(L,&UVHandleHolder::gc);
	lua_setfield(L,-2,"__gc");
	lua_pop(L,1);
}
