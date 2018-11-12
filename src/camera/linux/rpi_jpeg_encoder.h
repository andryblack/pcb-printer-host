#ifndef _RPI_JPEG_ENCODER_H_INCLUDED_
#define _RPI_JPEG_ENCODER_H_INCLUDED_

#include <cstring>

size_t rpi_jpeg_encode(const void* src_data,void* dst_data);
bool rpi_jpeg_encoder_init(size_t img_width, size_t img_height);
void rpi_jpeg_encoder_finish();

#endif /*_RPI_JPEG_ENCODER_H_INCLUDED_*/
