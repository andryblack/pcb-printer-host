#ifndef _OSX_CAMERA_SERVICE_H_INCLUDED_
#define _OSX_CAMERA_SERVICE_H_INCLUDED_

#include "../video_source.h"

#import <Foundation/Foundation.h>
#import <AVKit/AVKit.h>

@interface CameraService : NSObject<AVCaptureVideoDataOutputSampleBufferDelegate> {
	AVCaptureSession* 	captureSession;
	AVCaptureDevice* 	captureDevice;
	AVCaptureDeviceInput* captureInput;
	AVCaptureVideoDataOutput* outputData;
	dispatch_queue_t	captureSessionQueue;
	VideoSource* m_source;
}
@end

class OSXCameraService : public VideoSource {
private:
	CameraService* m_service;
public:
	OSXCameraService();
	~OSXCameraService();


	virtual void start() override;
	virtual void stop() override;

	virtual bool open(lua::state& l) override;
	virtual void close() override;
};

#endif /*_OSX_CAMERA_SERVICE_H_INCLUDED_*/