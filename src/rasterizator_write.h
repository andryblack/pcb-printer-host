#ifndef _RASTERIZATOR_WRITE_H_INCLUDED_
#define _RASTERIZATOR_WRITE_H_INCLUDED_

#include "rasterizator.h"
#include <uv/buffer.h>
#include <png.h>

class RasterizatorWrite : public meta::object {
	META_OBJECT
private:
	png_structp m_write;
	png_infop	m_info;
	static void error_fn(png_structp png_ptr,
        png_const_charp error_msg);
	static void warning_fn(png_structp png_ptr,
        png_const_charp error_msg);
	static void write_fn(png_structp write, png_bytep data, size_t size);
	static void flush_fn(png_structp);
	void write_data(png_bytep data, size_t size);
	uv::buffer_ptr m_png_data;
public:
	RasterizatorWrite();
	~RasterizatorWrite();
	static void lbind(lua::state& l);
	static lua::multiret lnew(lua::state& l);


	void set_size(int64_t width,int64_t height);
	void write(lua::state& l);
	uv::buffer_ptr end_write(lua::state& l);
};
typedef common::intrusive_ptr<RasterizatorWrite> RasterizatorWritePtr; 

#endif /*_RASTERIZATOR_WRITE_H_INCLUDED_*/