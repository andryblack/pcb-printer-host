#ifndef _RASTERIZATOR_WRITE_H_INCLUDED_
#define _RASTERIZATOR_WRITE_H_INCLUDED_

#include "rasterizator.h"
#include <png.h>

class RasterizatorWrite : public RefCounter {
private:
	png_structp m_write;
	png_infop	m_info;
	static void error_fn(png_structp png_ptr,
        png_const_charp error_msg);
	static void warning_fn(png_structp png_ptr,
        png_const_charp error_msg);
	FILE* m_fp;
public:
	RasterizatorWrite();
	~RasterizatorWrite();
	static int lbind(lua_State* L);
	static int lnew(lua_State* L);

	void push(lua_State*L);

	void open(lua_State*L,const char* path);
	void set_size(lua_State*L, int64_t width,int64_t height);
	void write(lua_State* L);
	void close(lua_State*L);
};
typedef Ref<RasterizatorWrite> RasterizatorWriteRef; 

#endif /*_RASTERIZATOR_WRITE_H_INCLUDED_*/