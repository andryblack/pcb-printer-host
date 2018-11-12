#include "rasterizator_write.h"
static const char* RasterizatorWrite_mt = "RasterizatorWrite";

void RasterizatorWrite::error_fn(png_structp png_ptr,
        png_const_charp error_msg) {
	printf("png error %s\n", error_msg);
}
void RasterizatorWrite::warning_fn(png_structp png_ptr,
    png_const_charp error_msg) {
	printf("png warning %s\n", error_msg);
}
RasterizatorWrite::RasterizatorWrite() : m_write(0),m_info(0),m_fp(0) {
	m_write = png_create_write_struct(PNG_LIBPNG_VER_STRING,this,
		RasterizatorWrite::error_fn,
		RasterizatorWrite::warning_fn);
	m_info = png_create_info_struct(m_write);
	if (m_fp) {
		fclose(m_fp);
	}
}

RasterizatorWrite::~RasterizatorWrite() {
	png_destroy_write_struct(&m_write,&m_info);
}

int RasterizatorWrite::lnew(lua_State* L) {
	(new RasterizatorWrite())->push(L);
	return 1;
}

void RasterizatorWrite::push(lua_State* L) {
	new (lua_newuserdata(L,sizeof(RasterizatorWriteRef))) RasterizatorWriteRef(this);
	luaL_setmetatable(L,RasterizatorWrite_mt);
}

void RasterizatorWrite::open(lua_State*L,const char* path) {
	m_fp = fopen(path,"wb");
	if (!m_fp) {
		luaL_error(L,"failed opening %s",path);
	}
	if (setjmp(png_jmpbuf(m_write)))
    {
    	luaL_error(L,"failed");
    	return;
    }
    png_init_io(m_write,m_fp);
}

void RasterizatorWrite::set_size(lua_State*L,int64_t w,int64_t h) {
	if (setjmp(png_jmpbuf(m_write)))
    {
    	luaL_error(L,"failed");
    	return;
    }
	png_set_IHDR(m_write,m_info,w,h,1,PNG_COLOR_TYPE_GRAY,
		PNG_INTERLACE_NONE,
		PNG_COMPRESSION_TYPE_DEFAULT,
		PNG_FILTER_TYPE_DEFAULT);
	png_write_info(m_write,m_info);
}

void RasterizatorWrite::write(lua_State* L) {
	size_t len = 0;
	const char* data = luaL_checklstring(L,2,&len);
	if (setjmp(png_jmpbuf(m_write)))
    {
    	luaL_error(L,"failed");
    	return;
    }
    png_byte* row_pointers[] = { const_cast<png_byte*>(reinterpret_cast<const png_byte*>(data)) };
    png_write_rows(m_write, row_pointers,
       1);
}

void RasterizatorWrite::close(lua_State*L) {
	if (setjmp(png_jmpbuf(m_write)))
    {
    	luaL_error(L,"failed");
    	return;
    }
    png_write_end(m_write, m_info);
    if (m_fp) {
    	fclose(m_fp);
    	m_fp = 0;
    }
}

int RasterizatorWrite::lbind(lua_State* L) {
	luaL_newmetatable(L,RasterizatorWrite_mt);
	lua_newtable(L);
	luabind::bind(L,"new",&RasterizatorWrite::lnew);
	luabind::bind(L,"set_size",&RasterizatorWrite::set_size);
	luabind::bind(L,"open",&RasterizatorWrite::open);
	luabind::bind(L,"write",&RasterizatorWrite::write);
	luabind::bind(L,"close",&RasterizatorWrite::close);
	lua_setfield(L,-2,"__index");
	lua_pushcfunction(L,&RasterizatorWriteRef::gc);
	lua_setfield(L,-2,"__gc");
	lua_pop(L,1);
	return 0;
}