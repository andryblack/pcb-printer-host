local class = require 'llae.class'
local Protocol = require 'printer.protocol'

local calibration = class(nil,'printer.calibration')

local width = 100

function calibration:_init(  )
	self:setup({})
end

function calibration:setup( data )
	self._flash_time = data.flash or application.printer.settings.flash_time
	self._print_speed = data.speed or application.printer.settings.print_speed
end

function calibration:prepare_print( protocol , position_x)

	self._start_r = math.ceil(position_x)
	self._start_l = self._start_r + width * 8
	protocol:move_x(self._start_r-5,application.printer:get_idle_speed_x())
	llae.sleep(1000)
	self._dir = 'r'
	self._pos_y = 0
	self._prev_y = 0
	protocol:setup_laser(Protocol.LASER_MODE_PRINT,self._flash_time)
	self._complete = false
	self._progress = 0
	self._mode = 'p0'
	self._step = 0
	self._step_y = (1.0/application.printer:get_resolution_x()) * application.printer:get_resolution_y()
	
end



function calibration:print_complete(  )
	return self._complete
end

function calibration:process_print( protocol )
	local speed = application.printer:calc_speed(self._print_speed)
	local start = self._start_r
	local pl = ''
	if self._mode == 'p0' then
		if self._dir == 'l' then
			pl = string.rep(string.pack('I1',0),width)
		else
			pl = string.rep(string.pack('I1',1),width)
		end
	elseif self._mode == 'p1' then
		if self._dir == 'l' then
			pl = string.rep(string.pack('I1',0x80),width)
		else
			pl = string.rep(string.pack('I1',0),width)
		end
	elseif self._mode == 'p2' then
		if self._dir == 'l' then
			pl = string.rep(string.pack('I1',0x80),width)
		else
			pl = string.rep(string.pack('I1',0x01),width)
		end
	end
	if self._dir == 'l' then
		start = self._start_l
		self._dir = 'r'
	else
		self._dir = 'l'
	end
	self._pos_y = self._step_y * self._step
	local pos_y = math.ceil(self._pos_y)
	local dy = pos_y -  self._prev_y
	print('Y:',dy)
	protocol:print(start,speed, dy,pl)
	self._prev_y = pos_y
	self._step = self._step + 1
	if self._step >= 80 then
		self._complete = true
	elseif self._step >= 60 then
		self._mode = 'p1'
	elseif self._step >= 40 then
		self._mode = 'p2'
	elseif self._step >= 20 then
		self._mode = 'p1'
	end
end
function calibration:get_progress(  )
	return self._step,80
end


return calibration