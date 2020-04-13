#ifndef _RPI_JPEG_ENCODER_H_INCLUDED_
#define _RPI_JPEG_ENCODER_H_INCLUDED_

#include <cstring>

#if defined(USE_VC_HW_ENCODING)

size_t rpi_jpeg_encode(const void* src_data,void* dst_data);
bool rpi_jpeg_encoder_init(size_t img_width, size_t img_height);
void rpi_jpeg_encoder_finish();

#endif /*USE_VC_HW_ENCODING*/

#endif /*_RPI_JPEG_ENCODER_H_INCLUDED_*/
