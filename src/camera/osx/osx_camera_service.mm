#include "osx_camera_service.h"

#include <iostream>
#import <ImageIO/ImageIO.h>


@implementation CameraService {
	uint64_t m_start_timestamp_value;
}


-(id)initWithSource:(VideoSource*) source {
	if (self = [super init]) {
		m_source = source;
		captureSession = [[AVCaptureSession alloc] init];
		captureDevice = nil;
		captureInput = nil;
		outputData = [[AVCaptureVideoDataOutput alloc] init];
		outputData.alwaysDiscardsLateVideoFrames = YES; 
		//@{ (id)kCVPixelBufferPixelFormatTypeKey : [NSNumber numberWithInteger:kCVPixelFormatType_32BGRA]};
		outputData.videoSettings = @{ 
			(id)kCVPixelBufferPixelFormatTypeKey: [NSNumber numberWithInteger:kCVPixelFormatType_32ARGB]
		}; 
		captureSessionQueue = dispatch_queue_create("CameraSessionQueue",0);//[[NSDispatchQueue] alloc] initWithLabel:];
		[outputData setSampleBufferDelegate:self queue: captureSessionQueue];
		m_start_timestamp_value = 0;
	}
	return self;
}

-(void)dealloc {
	[outputData release];
	[captureInput release];
	[captureDevice release];
	[captureSession release];
	dispatch_release(captureSessionQueue);
	[super dealloc];
}

-(void)close {
	[captureSession removeInput:captureInput];
	[captureSession removeOutput:outputData];
	[captureInput release];
	captureInput = nil;
	[captureDevice release];
	captureDevice = nil;
	std::cout << "osx video source close" << std::endl;
}

-(bool)open {
	[self close];
	std::cout << "osx video source open" << std::endl;
	NSArray<AVCaptureDevice *> * devices = [AVCaptureDevice devicesWithMediaType:AVMediaTypeVideo];
	for (AVCaptureDevice* dev : devices) {
		NSLog(@"device transportType: %d",dev.transportType);
		NSLog(@"device model: %@",dev.modelID);
	}
	captureDevice = [[AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo] retain];
		

	NSError* err = nil;
	captureInput = [[AVCaptureDeviceInput alloc] initWithDevice: captureDevice error:&err];
	if (err) {
		std::cout << "failed create input" << std::endl;
		NSLog(@"failed create input: %@",err);
		return false;
	}
	//[captureSession beginConfiguration];
	[captureSession addInput:captureInput];
	[captureSession addOutput:outputData];
	//[captureSession commitConfiguration];
	std::cout << "osx video source opened" << std::endl;
	return true;
}


-(void)start {
	m_start_timestamp_value = 0;
	[captureSession startRunning];
}

-(void)stop {
	[captureSession stopRunning];
}

- (void)captureOutput:(AVCaptureOutput *)output 
didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer 
       fromConnection:(AVCaptureConnection *)connection {
       	//std::cout << "frame1" << std::endl;

       	CVImageBufferRef imageBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
       	if (!imageBuffer) {
       		return;
       	}

       	CMTime bufferTime = CMSampleBufferGetDecodeTimeStamp(sampleBuffer);

       	//std::cout << "frame" << std::endl;
    	 /*Lock the image buffer*/
    	CVPixelBufferLockBaseAddress(imageBuffer,0); 

    	uint8_t *baseAddress = (uint8_t *)CVPixelBufferGetBaseAddress(imageBuffer); 
    	if (!baseAddress) {
    		std::cout << "failed get baseAddress" << std::endl;
    	}
    	size_t bytesPerRow = CVPixelBufferGetBytesPerRow(imageBuffer);

       	int width = CVPixelBufferGetWidth(imageBuffer);
		int height = CVPixelBufferGetHeight(imageBuffer);

		CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB(); 
		if (!colorSpace) {
			std::cout << "failed create colorSpace" << std::endl;
		}
    	CGContextRef newContext = CGBitmapContextCreate(baseAddress, 
    		width, height, 8, bytesPerRow, colorSpace,
    	 kCGBitmapByteOrder32Big | kCGImageAlphaNoneSkipFirst);
    	if (!newContext) {
    		std::cout << "failed create context " << width << "x" << height << std::endl;
    	}
    	CGImageRef newImage = CGBitmapContextCreateImage(newContext); 
    	if (!newImage) {
    		std::cout << "failed create image" << std::endl;
    	}
		CGColorSpaceRelease(colorSpace);

		CFMutableDataRef jpegData = CFDataCreateMutable(kCFAllocatorDefault,0);

		CGImageDestinationRef jpegDest =  CGImageDestinationCreateWithData(jpegData, CFSTR("public.jpeg"), 1, 0);
		CGImageDestinationAddImage(jpegDest,newImage,nil);
		
		CGImageDestinationFinalize(jpegDest);

		struct timeval timestamp;
		if (!m_start_timestamp_value) {
			m_start_timestamp_value = bufferTime.value;
		}
		uint64_t timestamp_value = bufferTime.value - m_start_timestamp_value;

		timestamp.tv_sec = timestamp_value / 1000000;
		timestamp.tv_usec = timestamp_value % 1000000;
		m_source->put_frame(CFDataGetMutableBytePtr(jpegData),CFDataGetLength(jpegData),timestamp);

		CFRelease(jpegDest);
		CFRelease(jpegData);

		CGImageRelease(newImage);

		/*We release some components*/
    	CGContextRelease(newContext); 
    	

		CVPixelBufferUnlockBaseAddress(imageBuffer,0);

}

// - (void)captureOutput:(AVCaptureOutput *)output 
//   didDropSampleBuffer:(CMSampleBufferRef)sampleBuffer 
//        fromConnection:(AVCaptureConnection *)connection {
//        	std::cout << "frame2" << std::endl;
// }
@end



OSXCameraService::OSXCameraService() {
	m_service = [[CameraService alloc] initWithSource:this];
}

OSXCameraService::~OSXCameraService() {
	[m_service release];
}

bool OSXCameraService::open(lua_State* L) {
	return [m_service open];
}

void OSXCameraService::close() {
	[m_service close];
}

void OSXCameraService::start() {
	[m_service start];
}

void OSXCameraService::stop() {
	[m_service stop];
}


int VideoSource::lnew(lua_State* L) {
	(new OSXCameraService())->push(L);
	return 1;
}


