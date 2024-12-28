local class = require 'llae.class'
local fs = require 'llae.fs'
local log = require 'llae.log'

local lvideo = class()
local camera = require 'camera'


function lvideo:_init(  )
	self._timeout = 0
	self._source = camera.VideoSource.new()
end

function lvideo:open(  )
	if not self._video_opened then
		if self._source:open(application.printer.settings.camera_device) then
			self._video_opened = true
		else
			log.error('failed open video source')
		end
	end
	if self._video_opened and not 
		self._video_started then
		self._source:start()
		self._video_started = true
	end
	return self._video_opened
end


function lvideo:process_request( req, res )
	self._timeout = 0
	res:set_header('Content-Type','image/jpeg')
	res:set_header('Pragma','no-cache')
	res:set_header('Cache-Control','no-store, no-cache, must-revalidate, pre-check=0, post-check=0, max-age=0')
	if self:open() then
		local frame = self._source:get_frame()
		if frame then
			res:finish(frame)
			return
		else
			log.error('no frame')
		end
	end

	if not self._stub_image then
		--local f = assert(io.open(application.config.http_root .. '/img/camera.jpg'))
		local fn = (application.config.rootdir or fs.pwd()) .. '/public/img/camera.jpg'
		self._stub_image = fs.load_file(fn)
		--f:close()
	end
	res:finish(self._stub_image)
end

function lvideo:on_timer(  )
	self._timeout = self._timeout + 1
	if self._timeout > 5 then
		if self._video_started then
			self._source:stop()
			self._video_started = false
			return
		end
	end
	if self._timeout > 10 then
		if self._video_opened then
			self._source:close()
			self._video_opened = false
		end
	end
end

return lvideo
