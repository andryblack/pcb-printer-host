#include "rpi_jpeg_encoder.h"

#include <stdarg.h>
#include <stdio.h>
#include <unistd.h>
#include <fcntl.h>

#define OMX_SKIP64BIT

#include <bcm_host.h>
#include <interface/vcos/vcos.h>
#include <IL/OMX_Broadcom.h>

#define JPEG_QUALITY 75 //1 .. 100
#define JPEG_EXIF_DISABLE OMX_FALSE
#define JPEG_IJG_ENABLE OMX_FALSE
#define JPEG_THUMBNAIL_ENABLE OMX_FALSE
#define JPEG_PREVIEW OMX_FALSE


#define DUMP_CASE(x) case x: return #x;

const char* dump_OMX_STATETYPE (OMX_STATETYPE state){
  switch (state){
    DUMP_CASE (OMX_StateInvalid)
    DUMP_CASE (OMX_StateLoaded)
    DUMP_CASE (OMX_StateIdle)
    DUMP_CASE (OMX_StateExecuting)
    DUMP_CASE (OMX_StatePause)
    DUMP_CASE (OMX_StateWaitForResources)
    default: return "unknown OMX_STATETYPE";
  }
}

const char* dump_OMX_ERRORTYPE (OMX_ERRORTYPE error){
  switch (error){
    DUMP_CASE (OMX_ErrorNone)
    DUMP_CASE (OMX_ErrorInsufficientResources)
    DUMP_CASE (OMX_ErrorUndefined)
    DUMP_CASE (OMX_ErrorInvalidComponentName)
    DUMP_CASE (OMX_ErrorComponentNotFound)
    DUMP_CASE (OMX_ErrorInvalidComponent)
    DUMP_CASE (OMX_ErrorBadParameter)
    DUMP_CASE (OMX_ErrorNotImplemented)
    DUMP_CASE (OMX_ErrorUnderflow)
    DUMP_CASE (OMX_ErrorOverflow)
    DUMP_CASE (OMX_ErrorHardware)
    DUMP_CASE (OMX_ErrorInvalidState)
    DUMP_CASE (OMX_ErrorStreamCorrupt)
    DUMP_CASE (OMX_ErrorPortsNotCompatible)
    DUMP_CASE (OMX_ErrorResourcesLost)
    DUMP_CASE (OMX_ErrorNoMore)
    DUMP_CASE (OMX_ErrorVersionMismatch)
    DUMP_CASE (OMX_ErrorNotReady)
    DUMP_CASE (OMX_ErrorTimeout)
    DUMP_CASE (OMX_ErrorSameState)
    DUMP_CASE (OMX_ErrorResourcesPreempted)
    DUMP_CASE (OMX_ErrorPortUnresponsiveDuringAllocation)
    DUMP_CASE (OMX_ErrorPortUnresponsiveDuringDeallocation)
    DUMP_CASE (OMX_ErrorPortUnresponsiveDuringStop)
    DUMP_CASE (OMX_ErrorIncorrectStateTransition)
    DUMP_CASE (OMX_ErrorIncorrectStateOperation)
    DUMP_CASE (OMX_ErrorUnsupportedSetting)
    DUMP_CASE (OMX_ErrorUnsupportedIndex)
    DUMP_CASE (OMX_ErrorBadPortIndex)
    DUMP_CASE (OMX_ErrorPortUnpopulated)
    DUMP_CASE (OMX_ErrorComponentSuspended)
    DUMP_CASE (OMX_ErrorDynamicResourcesUnavailable)
    DUMP_CASE (OMX_ErrorMbErrorsInFrame)
    DUMP_CASE (OMX_ErrorFormatNotDetected)
    DUMP_CASE (OMX_ErrorContentPipeOpenFailed)
    DUMP_CASE (OMX_ErrorContentPipeCreationFailed)
    DUMP_CASE (OMX_ErrorSeperateTablesUsed)
    DUMP_CASE (OMX_ErrorTunnelingUnsupported)
    DUMP_CASE (OMX_ErrorDiskFull)
    DUMP_CASE (OMX_ErrorMaxFileSize)
    DUMP_CASE (OMX_ErrorDrmUnauthorised)
    DUMP_CASE (OMX_ErrorDrmExpired)
    DUMP_CASE (OMX_ErrorDrmGeneral)
    default: return "unknown OMX_ERRORTYPE";
  }
}


// Internal defines

#define OMX_INIT_STRUCTURE(a) \
    memset(&(a), 0, sizeof(a)); \
    (a).nSize = sizeof(a); \
    (a).nVersion.nVersion = OMX_VERSION; \
    (a).nVersion.s.nVersionMajor = OMX_VERSION_MAJOR; \
    (a).nVersion.s.nVersionMinor = OMX_VERSION_MINOR; \
    (a).nVersion.s.nRevision = OMX_VERSION_REVISION; \
    (a).nVersion.s.nStep = OMX_VERSION_STEP

enum Event {
  EVENT_ERROR = 					(1<<0),
  EVENT_PORT_ENABLE = 				(1<<1),
  EVENT_PORT_DISABLE = 				(1<<2),
  EVENT_STATE_SET = 				(1<<3),
  EVENT_FLUSH = 					(1<<4),
  EVENT_MARK_BUFFER = 				(1<<5),
  EVENT_MARK = 						(1<<6),
  EVENT_PORT_SETTINGS_CHANGED = 	(1<<7),
  EVENT_PARAM_OR_CONFIG_CHANGED = 	(1<<8),
  EVENT_BUFFER_FLAG = 				(1<<9),
  EVENT_RESOURCES_ACQUIRED = 		(1<<10),
  EVENT_DYNAMIC_RESOURCES_AVAILABLE = (1<<11),
  EVENT_FILL_BUFFER_DONE = 			(1<<12),
  EVENT_EMPTY_BUFFER_DONE = 		(1<<13),
};

class Component {
protected:
	OMX_HANDLETYPE m_handle;
	VCOS_EVENT_FLAGS_T m_flags;
	const char* m_name;
	static OMX_ERRORTYPE event_handler (
	    OMX_IN OMX_HANDLETYPE hComponent,
	    OMX_IN OMX_PTR pAppData,
	    OMX_IN OMX_EVENTTYPE eEvent,
	    OMX_IN OMX_U32 nData1,
	    OMX_IN OMX_U32 nData2,
	    OMX_IN OMX_PTR pEventData);
	static OMX_ERRORTYPE fill_buffer_done (
	    OMX_IN OMX_HANDLETYPE hComponent,
	    OMX_IN OMX_PTR pAppData,
	    OMX_IN OMX_BUFFERHEADERTYPE* pBuffer);
	static OMX_ERRORTYPE empty_buffer_done (
	    OMX_IN OMX_HANDLETYPE hComponent,
	    OMX_IN OMX_PTR pAppData,
	    OMX_IN OMX_BUFFERHEADERTYPE* pBuffer);
	explicit Component(const char* name) : m_name(name) {}
public:
	const char* name() const { return m_name; }
	OMX_HANDLETYPE handle() const { return m_handle; }
	void init() {
		OMX_ERRORTYPE error;
  
		  //Create the event flags
		  if (vcos_event_flags_create (&m_flags, "component")){
		    fprintf (stderr, "error: vcos_event_flags_create\n");
		    exit (1);
		  }
  
	  //Each component has an event_handler and fill_buffer_done functions
	  OMX_CALLBACKTYPE callbacks_st;
	  callbacks_st.EventHandler = &Component::event_handler;
	  callbacks_st.FillBufferDone = &Component::fill_buffer_done;
	  callbacks_st.EmptyBufferDone = &Component::empty_buffer_done;
  
  	  OMX_STRING handle_name = (OMX_STRING)m_name;
	  //Get the handle
	  if ((error = OMX_GetHandle (&m_handle, handle_name, this,
	      &callbacks_st))){
	    fprintf (stderr, "error: OMX_GetHandle: %s\n", dump_OMX_ERRORTYPE (error));
	    exit (1);
	  }
  
	  //Disable all the ports
	  OMX_INDEXTYPE types[] = {
	    OMX_IndexParamAudioInit,
	    OMX_IndexParamVideoInit,
	    OMX_IndexParamImageInit,
	    OMX_IndexParamOtherInit
	  };
	  OMX_PORT_PARAM_TYPE ports_st;
	  OMX_INIT_STRUCTURE (ports_st);

	  for (size_t i=0; i<4; i++){
	    if ((error = OMX_GetParameter (m_handle, types[i], &ports_st))){
	      fprintf (stderr, "error: OMX_GetParameter: %s\n",
	          dump_OMX_ERRORTYPE (error));
	      exit (1);
	    }
	    
	    for (OMX_U32 port=ports_st.nStartPortNumber;
	        port<ports_st.nStartPortNumber + ports_st.nPorts; port++){
	      //Disable the port
	      disable_port (port);
	      //Wait to the event
	      wait ( EVENT_PORT_DISABLE, 0);
	    }
	  }
	}
	void deinit() {
		OMX_ERRORTYPE error;
  
  		vcos_event_flags_delete (&m_flags);

		if ((error = OMX_FreeHandle (m_handle))){
		    fprintf (stderr, "error: OMX_FreeHandle: %s\n", dump_OMX_ERRORTYPE (error));
		    exit (1);
		}
	}
	void enable_port(OMX_U32 port) {
		OMX_ERRORTYPE error;
  
	  if ((error = OMX_SendCommand (m_handle, OMX_CommandPortEnable,
	      port, 0))){
	    fprintf (stderr, "error: OMX_SendCommand OMX_CommandPortEnable: %s\n",
	        dump_OMX_ERRORTYPE (error));
	    exit (1);
	  }
	}
	void disable_port(OMX_U32 port) {
		OMX_ERRORTYPE error;
  
	  if ((error = OMX_SendCommand (m_handle, OMX_CommandPortDisable,
	      port, 0))){
	    fprintf (stderr, "error: OMX_SendCommand OMX_CommandPortDisable: %s\n",
	        dump_OMX_ERRORTYPE (error));
	    exit (1);
	  }
	}
	void wake( VCOS_UNSIGNED event) {
		vcos_event_flags_set (&m_flags, event, VCOS_OR);
	}
	void wait( VCOS_UNSIGNED events,
	    VCOS_UNSIGNED* retrieves_events) {
		VCOS_UNSIGNED set;
		if (vcos_event_flags_get (&m_flags, events | EVENT_ERROR,
			  VCOS_OR_CONSUME, VCOS_SUSPEND, &set)){
			fprintf (stderr, "error: vcos_event_flags_get\n");
			exit (1);
		}
		if (set & EVENT_ERROR){
			fprintf (stderr, "error: wait\n");
			exit (1);
		}
		if (retrieves_events){
			*retrieves_events = set;
		}
	}
	VCOS_UNSIGNED peek( VCOS_UNSIGNED events ) {
		VCOS_UNSIGNED set;
		if (vcos_event_flags_get (&m_flags, events | EVENT_ERROR,
			  VCOS_OR_CONSUME, 0, &set)){
			return 0;
		}
		if (set & EVENT_ERROR){
			fprintf (stderr, "error: peek\n");
			exit (1);
		}
		return set;
	}
	void change_state ( OMX_STATETYPE state){
		OMX_ERRORTYPE error;

		if ((error = OMX_SendCommand (m_handle, OMX_CommandStateSet, state,0))){
			fprintf (stderr, "error: OMX_SendCommand OMX_CommandStateSet: %s\n",
			dump_OMX_ERRORTYPE (error));
			exit (1);
		}
	}	
};


class EncoderComponent : public Component {
protected:
	OMX_BUFFERHEADERTYPE* m_input_buffer;
	OMX_BUFFERHEADERTYPE* m_output_buffer;
public:
	EncoderComponent() : Component("OMX.broadcom.image_encode"),m_input_buffer(0),m_output_buffer(0) {}

	void configure() {
		OMX_ERRORTYPE error;
  
	  //Quality
	  OMX_IMAGE_PARAM_QFACTORTYPE quality;
	  OMX_INIT_STRUCTURE (quality);
	  quality.nPortIndex = 341;
	  quality.nQFactor = JPEG_QUALITY;
	  if ((error = OMX_SetParameter (m_handle, OMX_IndexParamQFactor,
	      &quality))){
	    fprintf (stderr, "error: OMX_SetParameter: %s\n",
	        dump_OMX_ERRORTYPE (error));
	    exit (1);
	  }
  
	  //Disable EXIF tags
	  OMX_CONFIG_BOOLEANTYPE exif;
	  OMX_INIT_STRUCTURE (exif);
	  exif.bEnabled = JPEG_EXIF_DISABLE;
	  if ((error = OMX_SetParameter (m_handle, OMX_IndexParamBrcmDisableEXIF,
	      &exif))){
	    fprintf (stderr, "error: OMX_SetParameter: %s\n",
	        dump_OMX_ERRORTYPE (error));
	    exit (1);
	  }
  
	  //Enable IJG table
	  OMX_PARAM_IJGSCALINGTYPE ijg;
	  OMX_INIT_STRUCTURE (ijg);
	  ijg.nPortIndex = 341;
	  ijg.bEnabled = JPEG_IJG_ENABLE;
	  if ((error = OMX_SetParameter (m_handle,
	      OMX_IndexParamBrcmEnableIJGTableScaling, &ijg))){
	    fprintf (stderr, "error: OMX_SetParameter: %s\n",
	        dump_OMX_ERRORTYPE (error));
	    exit (1);
	  }
  
	  //Thumbnail
	  OMX_PARAM_BRCMTHUMBNAILTYPE thumbnail;
	  OMX_INIT_STRUCTURE (thumbnail);
	  thumbnail.bEnable = JPEG_THUMBNAIL_ENABLE;
	  thumbnail.bUsePreview = JPEG_PREVIEW;
	  thumbnail.nWidth = 32;
	  thumbnail.nHeight = 32;
	  if ((error = OMX_SetParameter (m_handle, OMX_IndexParamBrcmThumbnail,
	      &thumbnail))){
	    fprintf (stderr, "error: OMX_SetParameter: %s\n",
	        dump_OMX_ERRORTYPE (error));
	    exit (1);
	  }
	}

	void enable_input_port() {
		OMX_ERRORTYPE error;
		enable_port (340);
		OMX_PARAM_PORTDEFINITIONTYPE def_st;
		OMX_INIT_STRUCTURE (def_st);
		def_st.nPortIndex = 340;
		if ((error = OMX_GetParameter (m_handle, OMX_IndexParamPortDefinition,
				&def_st))){
			fprintf (stderr, "error: OMX_GetParameter OMX_IndexParamPortDefinition: %s\n",
			dump_OMX_ERRORTYPE (error));
			exit (1);
		}
		printf ("allocating %s input buffer\n", m_name);
		if ((error = OMX_AllocateBuffer (m_handle, &m_input_buffer, 340,
				0, def_st.nBufferSize))){
			fprintf (stderr, "error: OMX_AllocateBuffer: %s\n",
			dump_OMX_ERRORTYPE (error));
			exit (1);
		}

		wait (EVENT_PORT_ENABLE, 0);
	}
	void disable_input_port() {
		OMX_ERRORTYPE error;
  
		disable_port ( 340);

		//Free encoder output buffer
		printf ("releasing '%s' input buffer\n", m_name);
		if ((error = OMX_FreeBuffer (m_handle, 340, m_input_buffer))){
			fprintf (stderr, "error: OMX_FreeBuffer: %s\n", dump_OMX_ERRORTYPE (error));
			exit (1);
		}

		wait ( EVENT_PORT_DISABLE, 0);
	}
	void enable_output_port() {
		OMX_ERRORTYPE error;
		enable_port (341);
		OMX_PARAM_PORTDEFINITIONTYPE def_st;
		OMX_INIT_STRUCTURE (def_st);
		def_st.nPortIndex = 341;
		if ((error = OMX_GetParameter (m_handle, OMX_IndexParamPortDefinition,
				&def_st))){
			fprintf (stderr, "error: OMX_GetParameter OMX_IndexParamPortDefinition: %s\n",
			dump_OMX_ERRORTYPE (error));
			exit (1);
		}
		printf ("allocating %s output buffer\n", m_name);
		if ((error = OMX_AllocateBuffer (m_handle, &m_output_buffer, 341,
				0, def_st.nBufferSize))){
			fprintf (stderr, "error: OMX_AllocateBuffer: %s\n",
			dump_OMX_ERRORTYPE (error));
			exit (1);
		}

		wait (EVENT_PORT_ENABLE, 0);
	}
	void disable_output_port() {
		OMX_ERRORTYPE error;
  
		disable_port ( 341);

		//Free encoder output buffer
		printf ("releasing '%s' output buffer\n", m_name);
		if ((error = OMX_FreeBuffer (m_handle, 341, m_output_buffer))){
			fprintf (stderr, "error: OMX_FreeBuffer: %s\n", dump_OMX_ERRORTYPE (error));
			exit (1);
		}

		wait ( EVENT_PORT_DISABLE, 0);
	}

	size_t encode(const uint8_t* src_data, uint8_t* dst_data) {
		VCOS_UNSIGNED retrieves_events;
  		OMX_ERRORTYPE error;
  		// Get buffer size
  		OMX_PARAM_PORTDEFINITIONTYPE def_st;
		OMX_INIT_STRUCTURE(def_st);
		def_st.nPortIndex=340;
		if((error=OMX_GetParameter(m_handle, OMX_IndexParamPortDefinition, &def_st)) != OMX_ErrorNone) {
			fprintf (stderr, "error: OMX_GetParameter OMX_IndexParamPortDefinition: %s\n", dump_OMX_ERRORTYPE (error));
			exit (1);
		}	
		size_t writed = 0;
		size_t image_size = def_st.format.image.nFrameWidth * def_st.format.image.nFrameHeight * 2;
		size_t slice_size = def_st.format.image.nFrameWidth*def_st.format.image.nSliceHeight*2;
		size_t readed = 0;
		bool buffer_requested = false;
		bool buffer_queued = false;
		bool write_done = false;
		while (true) {
			if (!buffer_queued) {
				if(writed != image_size) {
					size_t data_size = image_size - writed;;
					if (data_size > slice_size) {
						data_size = slice_size;
					}
					memcpy(m_input_buffer->pBuffer, src_data, data_size);
					m_input_buffer->nOffset = 0;
					m_input_buffer->nFilledLen = data_size;
					src_data += data_size;
					writed += data_size;
					if((error=OMX_EmptyThisBuffer(m_handle, m_input_buffer)) != OMX_ErrorNone) {
						fprintf (stderr, "error: OMX_EmptyThisBuffer: %s\n", dump_OMX_ERRORTYPE (error));
						exit (1);
					}	
					//fprintf(stderr, "write buffer %d/%d\n",int(writed),int(image_size));
					buffer_queued = true;
				} else {
					write_done = true;
				}
			}

			if (!buffer_requested) {
				//fprintf(stderr, "request buffer\n");
				//Get the buffer data (a slice of the image)
			    if ((error = OMX_FillThisBuffer (m_handle, m_output_buffer))){
			      fprintf (stderr, "error: OMX_FillThisBuffer: %s\n",
			          dump_OMX_ERRORTYPE (error));
			      exit (1);
			    }
			    buffer_requested = true;
			} 

			if (buffer_requested && (buffer_queued || write_done))  {
				wait(EVENT_FILL_BUFFER_DONE | EVENT_BUFFER_FLAG | EVENT_EMPTY_BUFFER_DONE,&retrieves_events);
				if (retrieves_events & EVENT_FILL_BUFFER_DONE) {
					size_t data_size = m_output_buffer->nFilledLen;
				    //fprintf(stderr, "got buffer %d\n",int(data_size));
					
				    if (data_size) {
				    	memcpy(dst_data,m_output_buffer->pBuffer+m_output_buffer->nOffset,data_size);
				    	dst_data += data_size;
				    	readed += data_size;
				    }
				    buffer_requested = false;

				    if((m_output_buffer->nFlags&OMX_BUFFERFLAG_ENDOFFRAME)) {
				    	//fprintf(stderr, "EOF\n");
				    	if (buffer_queued && !(retrieves_events&EVENT_EMPTY_BUFFER_DONE)) {
				    		wait(EVENT_EMPTY_BUFFER_DONE,0);
				    	}
		    			break;
				    }
			   	}
				if (retrieves_events & EVENT_EMPTY_BUFFER_DONE) {
					//fprintf(stderr, "write buffer done\n");
					buffer_queued = false;
				}
				if (retrieves_events & EVENT_BUFFER_FLAG ) {
			    	fprintf(stderr, "frame done\n");
			    	break;
			    }
			}
		}

		return readed;
	}
};

static EncoderComponent encoder;



bool rpi_jpeg_encoder_init(size_t img_width, size_t img_height) {
	bcm_host_init ();
	
	OMX_ERRORTYPE error;
	//Initialize OpenMAX IL
	if ((error = OMX_Init ())){
	    fprintf (stderr, "error: OMX_Init: %s\n", dump_OMX_ERRORTYPE (error));
	    exit (1);
	}
  	encoder.init();

  	
  	OMX_PARAM_PORTDEFINITIONTYPE port_def;

  	OMX_INIT_STRUCTURE(port_def);
	port_def.nPortIndex=340; // Input port
	if ((error = OMX_GetParameter (encoder.handle(), OMX_IndexParamPortDefinition,
	      &port_def))){
	    fprintf (stderr, "error: OMX_SetParameter: %s\n",
	        dump_OMX_ERRORTYPE (error));
	    exit (1);
	}
	port_def.format.image.nFrameWidth=img_width;
	port_def.format.image.nFrameHeight=img_height;
	port_def.format.image.nSliceHeight=16;
	port_def.format.image.nStride=0;
	port_def.format.image.bFlagErrorConcealment=OMX_FALSE;
	port_def.format.image.eColorFormat=OMX_COLOR_FormatYCbYCr;
	port_def.format.image.eCompressionFormat=OMX_IMAGE_CodingUnused;
	port_def.nBufferSize=img_width*port_def.format.image.nSliceHeight*2;
	if ((error = OMX_SetParameter (encoder.handle(), OMX_IndexParamPortDefinition,
	  &port_def))){
		fprintf (stderr, "error: OMX_SetParameter: %s\n",
	    	dump_OMX_ERRORTYPE (error));
		exit (1);
	}

	// configure output port
  	OMX_INIT_STRUCTURE (port_def);
  	port_def.nPortIndex = 341;
	if ((error = OMX_GetParameter (encoder.handle(), OMX_IndexParamPortDefinition,
	      &port_def))){
	    fprintf (stderr, "error: OMX_SetParameter: %s\n",
	        dump_OMX_ERRORTYPE (error));
	    exit (1);
	}

	port_def.format.image.nFrameWidth = img_width;
	port_def.format.image.nFrameHeight = img_height;
	port_def.format.image.eCompressionFormat = OMX_IMAGE_CodingJPEG;
	port_def.format.image.eColorFormat = OMX_COLOR_FormatUnused;
	port_def.nBufferSize=img_width*port_def.format.image.nSliceHeight*2;
	if ((error = OMX_SetParameter (encoder.handle(), OMX_IndexParamPortDefinition,
	  &port_def))){
		fprintf (stderr, "error: OMX_SetParameter: %s\n",
	    	dump_OMX_ERRORTYPE (error));
		exit (1);
	}

	encoder.configure();


	encoder.change_state (OMX_StateIdle);
 	encoder.wait (EVENT_STATE_SET, 0);


 	encoder.enable_input_port();
 	encoder.enable_output_port();

 	encoder.change_state (OMX_StateExecuting);
 	encoder.wait (EVENT_STATE_SET, 0);
 	

  	return true;
}
void rpi_jpeg_encoder_finish() {
	encoder.change_state (OMX_StateIdle);
  	encoder.wait (EVENT_STATE_SET, 0);

	encoder.disable_output_port();
	encoder.disable_input_port();

	encoder.change_state ( OMX_StateLoaded);
  	encoder.wait (EVENT_STATE_SET, 0);

	encoder.deinit();

	OMX_ERRORTYPE error;
	if ((error = OMX_Deinit ())){
    	fprintf (stderr, "error: OMX_Deinit: %s\n", dump_OMX_ERRORTYPE (error));
    	exit (1);
  	}

	bcm_host_deinit ();
}

size_t rpi_jpeg_encode(const void* src_data,void* dst_data) {

	
  	const uint8_t* src_buf = static_cast<const uint8_t*>(src_data);
  	uint8_t* dst_buf = static_cast<uint8_t*>(dst_data);

  	return encoder.encode(src_buf,dst_buf);
}


OMX_ERRORTYPE Component::event_handler (
	    OMX_IN OMX_HANDLETYPE hComponent,
	    OMX_IN OMX_PTR pAppData,
	    OMX_IN OMX_EVENTTYPE event,
	    OMX_IN OMX_U32 data1,
	    OMX_IN OMX_U32 data2,
	    OMX_IN OMX_PTR pEventData) {

	Component* component = (Component*)pAppData;

	switch (event){
    case OMX_EventCmdComplete:
      switch (data1){
        case OMX_CommandStateSet:
          printf ("event: %s, OMX_CommandStateSet, state: %s\n",
              component->name(), dump_OMX_STATETYPE(static_cast<OMX_STATETYPE>(data2)));
          component->wake ( EVENT_STATE_SET);
          break;
        case OMX_CommandPortDisable:
          printf ("event: %s, OMX_CommandPortDisable, port: %d\n",
              component->name(), data2);
          component->wake ( EVENT_PORT_DISABLE);
          break;
        case OMX_CommandPortEnable:
          printf ("event: %s, OMX_CommandPortEnable, port: %d\n",
              component->name(), data2);
          component->wake ( EVENT_PORT_ENABLE);
          break;
        case OMX_CommandFlush:
          printf ("event: %s, OMX_CommandFlush, port: %d\n",
              component->name(), data2);
          component->wake (EVENT_FLUSH);
          break;
        case OMX_CommandMarkBuffer:
          printf ("event: %s, OMX_CommandMarkBuffer, port: %d\n",
              component->name(), data2);
          component->wake (EVENT_MARK_BUFFER);
          break;
      }
      break;
    case OMX_EventError:
      printf ("event: %s, %s\n", component->name(), dump_OMX_ERRORTYPE (
      	static_cast<OMX_ERRORTYPE>(data1)));
      component->wake ( EVENT_ERROR);
      break;
    case OMX_EventMark:
      printf ("event: %s, OMX_EventMark\n", component->name());
      component->wake (EVENT_MARK);
      break;
    case OMX_EventPortSettingsChanged:
      printf ("event: %s, OMX_EventPortSettingsChanged, port: %d\n",
          component->name(), data1);
      component->wake (EVENT_PORT_SETTINGS_CHANGED);
      break;
    case OMX_EventParamOrConfigChanged:
      printf ("event: %s, OMX_EventParamOrConfigChanged, data1: %d, data2: "
          "%X\n", component->name(), data1, data2);
      component->wake (EVENT_PARAM_OR_CONFIG_CHANGED);
      break;
    case OMX_EventBufferFlag:
      printf ("event: %s, OMX_EventBufferFlag, port: %d\n",
          component->name(), data1);
      component->wake (EVENT_BUFFER_FLAG);
      break;
    case OMX_EventResourcesAcquired:
      printf ("event: %s, OMX_EventResourcesAcquired\n", component->name());
      component->wake (EVENT_RESOURCES_ACQUIRED);
      break;
    case OMX_EventDynamicResourcesAvailable:
      printf ("event: %s, OMX_EventDynamicResourcesAvailable\n",
          component->name());
      component->wake (EVENT_DYNAMIC_RESOURCES_AVAILABLE);
      break;
    default:
      //This should never execute, just ignore
      printf ("event: unknown (%X)\n", event);
      break;
  }

  return OMX_ErrorNone;
}

OMX_ERRORTYPE Component::fill_buffer_done (
	    OMX_IN OMX_HANDLETYPE hComponent,
	    OMX_IN OMX_PTR pAppData,
	    OMX_IN OMX_BUFFERHEADERTYPE* pBuffer) {
	Component* component = (Component*)pAppData;
  
  //printf ("event: %s, fill_buffer_done\n", component->name());
  component->wake (EVENT_FILL_BUFFER_DONE);
  
  return OMX_ErrorNone;
}

OMX_ERRORTYPE Component::empty_buffer_done (
	    OMX_IN OMX_HANDLETYPE hComponent,
	    OMX_IN OMX_PTR pAppData,
	    OMX_IN OMX_BUFFERHEADERTYPE* pBuffer) {
	Component* component = (Component*)pAppData;
  
  //printf ("event: %s, empty_buffer_done\n", component->name());
  component->wake (EVENT_EMPTY_BUFFER_DONE);
  
  return OMX_ErrorNone;
}
