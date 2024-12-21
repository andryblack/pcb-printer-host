#include "rasterizator_write.h"
#include <lua/bind.h>

META_OBJECT_INFO(RasterizatorWrite,meta::object)

void RasterizatorWrite::error_fn(png_structp png_ptr,
        png_const_charp error_msg) {
	printf("png error %s\n", error_msg);
}
void RasterizatorWrite::warning_fn(png_structp png_ptr,
    png_const_charp error_msg) {
	printf("png warning %s\n", error_msg);
}
RasterizatorWrite::RasterizatorWrite() : m_write(0),m_info(0) {
	m_write = png_create_write_struct(PNG_LIBPNG_VER_STRING,this,
		RasterizatorWrite::error_fn,
		RasterizatorWrite::warning_fn);
	m_info = png_create_info_struct(m_write);
	png_set_write_fn(m_write,this,&RasterizatorWrite::write_fn,&RasterizatorWrite::flush_fn);
}

RasterizatorWrite::~RasterizatorWrite() {
	png_destroy_write_struct(&m_write,&m_info);
}

lua::multiret RasterizatorWrite::lnew(lua::state& l) {
	lua::push(l,RasterizatorWritePtr(new RasterizatorWrite()));
	return {1};
}

void RasterizatorWrite::flush_fn(png_structp) {
	
}
void RasterizatorWrite::write_fn(png_structp write, png_bytep data, size_t size) {
	static_cast<RasterizatorWrite*>(png_get_io_ptr(write))->write_data(data,size);
}

void RasterizatorWrite::write_data(png_bytep data, size_t size) {
	size_t pos = 0;
	if (!m_png_data) {
		m_png_data = uv::buffer::alloc(size*2);
		m_png_data->set_len(0);
	} else {
		pos = m_png_data->get_len();
		m_png_data = m_png_data->realloc(pos+size*2);
	}
	memcpy(static_cast<uint8_t*>(m_png_data->get_base())+pos,data,size);
	m_png_data->set_len(pos+size);
}

void RasterizatorWrite::set_size(int64_t w,int64_t h) {
	png_set_IHDR(m_write,m_info,w,h,1,PNG_COLOR_TYPE_GRAY,
		PNG_INTERLACE_NONE,
		PNG_COMPRESSION_TYPE_DEFAULT,
		PNG_FILTER_TYPE_DEFAULT);
	png_write_info(m_write,m_info);
}

void RasterizatorWrite::write(lua::state& l) {
	size_t len = 0;
	const char* data = l.checklstring(2,len);
	png_byte* row_pointers[] = { const_cast<png_byte*>(reinterpret_cast<const png_byte*>(data)) };
    png_write_rows(m_write, row_pointers,
       1);
}

uv::buffer_ptr RasterizatorWrite::end_write(lua::state& l) {
	png_write_end(m_write, m_info);
	return std::move(m_png_data);
}

void RasterizatorWrite::lbind(lua::state& l) {
	lua::bind::function(l,"new",&RasterizatorWrite::lnew);
	lua::bind::function(l,"set_size",&RasterizatorWrite::set_size);
	lua::bind::function(l,"write",&RasterizatorWrite::write);
	lua::bind::function(l,"end_write",&RasterizatorWrite::end_write);
}