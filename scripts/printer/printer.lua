local class = require 'llae.class'
local log = require 'llae.log'
local async = require 'llae.async'

local printer = class()

printer.settings = require 'printer.settings_mgmt'



local llae = require 'llae'
local Connection = require 'printer.connection'
local Protocol = require 'printer.protocol'

local state_disconnected = 'disconnected'
local state_idle = 'idle'
local state_printing = 'printing'
local state_paused = 'paused'

function printer:init(  )
	self._settings_file = application.config.files .. '/.printer/settings.json'
	self._state = state_disconnected
	self._speed_samples = {}
	self._auto_connect = 5

	self._position_x = nil
	self._position_y = nil

	self.settings:init()
	if not self.settings:load( self._settings_file ) then
		print('failed loading settings from ',self._settings_file)
	end
	self:update_settings()
	self.pcb = (require 'printer.pcb').new()
	local connection_delegate = {printer=self}
	function connection_delegate:on_data( data )
		self._protocol:on_data(data)
	end
	function connection_delegate:on_close(  )
		self.printer:on_connection_close()
	end
	local protocol_delegate = { printer = self }
	function protocol_delegate:write( data )
		self._connection:write(data)
	end
	function protocol_delegate:update_pos( pos_x, pos_y )
		self.printer._position_x = pos_x
		self.printer._position_y = pos_y
	end
	function protocol_delegate:add_speed_sample( sample )
		if sample.pwm == 0 then
			print('SPEED end')
			self.printer:on_speed_read_end()
		else
			table.insert(self.printer._speed_samples, {
				speed=(1000000 / (sample.dt*self.printer._resolution_x)), -- cnt / us,  / ctnt/mm = mm/us = mm/s
				pwm=sample.pwm})
			print('SPEED',sample.dt,sample.pwm)
		end
	end
	self._connection = Connection.create( self.settings.device , connection_delegate )
	self._connection:configure_baud(self.settings.baudrate)
	self._protocol = Protocol.new(protocol_delegate)
	connection_delegate._protocol = self._protocol
	protocol_delegate._connection = self._connection
end

function printer:calc_speed( s )
	return math.ceil(1000000/(self._resolution_x * s)) -- (cnt/mm) * (mm/s) = cnt / s
end

function printer:get_idle_speed_x( )
	return self:calc_speed(25.0) -- @todo
end

printer._actions = {}
printer._actions['pid-move'] = function(self,data) 
	self._speed_samples= {}
	local speed = self:calc_speed(data.s)
	print('>>>>>>> START',speed)
	self._target_speed = data.s
	self._protocol:move_x(
		math.ceil(data.p * self._resolution_x),
		math.ceil(speed),
		Protocol.FLAG_WRITE_SPEED);


	if not self._read_speed then
		self._read_speed = llae.newTimer()
	else
		self._read_speed:stop()
	end

	self._read_speed:start(function()
		self._protocol:read_speed()
	end,100,100)

	
end
printer._actions['move-stop']=function(self,data) 
	self:on_speed_read_end()
	self._protocol:stop();
end
printer._actions['zero-x']=function(self,data) 
	self._protocol:zero_x();
end
printer._actions['zero-y']=function(self,data) 
	self._protocol:zero_y();
end
printer._actions['setup-pid']=function(self,data) 
	self._protocol:setup_motor(data.P,data.I,data.D,
		self.settings.motor_pwm_min,
		self.settings.motor_pwm_max);
end

printer._actions['move-x']=function(self,data) 
	local target = self._position_x + data.x * self._resolution_x
	self._position_x = math.ceil(target)
	self._protocol:move_x(self._position_x,self:get_idle_speed_x(),Protocol.FLAG_WAIT_MOVE)
end
printer._actions['move-y']=function(self,data) 
	local target = self._position_y + data.y * self._resolution_y
	self._position_y = math.ceil(target)
	self._protocol:move_y(self._position_y)
end
printer._actions['setup-laser-pwm']=function(self,data) 
	self._protocol:setup_laser(Protocol.LASER_MODE_PWM,math.ceil(data.v))
end


function printer:on_speed_read_end(  )
	if self._read_speed then
		self._read_speed:stop()
	end
	self._read_speed = nil
end

function printer:stop(  )
	self:disconnect()
end

function printer:update_settings(  )
	self._resolution_x = self.settings.printer_encoder_resolution * 4 / 25.4
	self._resolution_y = self.settings.printer_y_steps 
	if self._state == state_idle then
		self:upload_settings()
	end
end

function printer:get_resolution_x( )
	return self._resolution_x
end

function printer:get_resolution_y( )
	return self._resolution_y
end

function printer:disconnect(  )
	self._connection:close()
	self:on_connection_close()
end

function printer:connect(  )
	self._protocol:reset()
	local res,err = self._connection:open()

	if res then
		self._state = state_idle
		self:upload_settings()
	else
		log.error('failed open connection',err)
		self._auto_connect = 30
	end
end

function printer:upload_settings() 
	self._protocol:setup_motor(self.settings.motor_pid_P,
			self.settings.motor_pid_I,
			self.settings.motor_pid_D,
			self.settings.motor_pwm_min,
			self.settings.motor_pwm_max);
	self._protocol:set_param(Protocol.PARAM_STEPPER_MAX_SPEED,
		math.ceil(self.settings.printer_y_max_speed * self.settings.printer_y_steps))
	self._protocol:set_param(Protocol.PARAM_STEPPER_START_SPEED,
		math.ceil(self.settings.printer_y_min_speed * self.settings.printer_y_steps))
	self._protocol:set_param(Protocol.PARAM_STEPPER_ACCEL,
		math.ceil(self.settings.printer_y_accel * self.settings.printer_y_steps))
	self._protocol:set_param(Protocol.PARAM_STEPPER_DECCEL,
		math.ceil(self.settings.printer_y_deccel  * self.settings.printer_y_steps))
	self._protocol:set_param(Protocol.PARAM_STEPPER_STOP_STEPS,
		math.ceil(self.settings.printer_y_stop_steps * self.settings.printer_y_steps))
	
end

function printer:on_connection_close(  )
	if self._read_speed then
		self._read_speed:stop()
		self._read_speed = nil
	end
	self._protocol:reset()
	self._state = state_disconnected
end

function printer:pause(  )
	self._resume_state = self:start_state(state_paused)
end

function printer:resume(  )
	self:end_state(state_paused,self._resume_state)
	self._resume_state = nil
end

function printer:print_stop(  )
	self:end_state(state_paused,state_idle)
	self._resume_state = nil
	self._progress = 0
end

function printer:on_connected(  )
	self._state = state_idle
	self._delay = 10
end

function printer:start_state( state )
	local res = self._state
	self._state = state
	return res
end

function printer:end_state( state , new_state)
	if self._state == state then
		self._state = new_state
	end
end

function printer:save_settings(  )
	self.settings:store(self._settings_file )
	self:update_settings()
end


function printer:action( action , data)
	local fn = self._actions[action]
	if fn then
		fn(self,data)
	else
		error('unknown action ' .. action)
	end
end


function printer:get_state( data )
	local res = {
		state = self._state,
		progress = self._progress,
		pos_x = self._position_x,
		pos_y = self._position_y,
	}
	if data and data.need_speed_info then
		res.speed_info = self._speed_samples
		res.target_speed = self._target_speed
	end
	return res
end

function printer:is_connected(  )
	return self._state == state_idle
end

function printer:on_timer(  )
	if self._delay then
		self._delay = self._delay - 1 
		if self._delay > 0 then
			return
		end
		self._delay = nil
	end

	if self._auto_connect then
		self._auto_connect = self._auto_connect - 1
		if self._auto_connect < 0 then
			log.info('auto connect')
			self._auto_connect = nil
			self:connect()
			return
		end
	end

	if ( (self._state == state_idle) or
		 (self._state == state_paused) ) 
		and self._connection:is_opened() and 
		self._protocol:is_ready() and 
		not self._read_speed then
		self._protocol:ping()
	end
	
end

function printer:print(  )
	local state = self:start_state(state_printing)
	local sself = self
	self._progress = 0

	local coro = coroutine.create(function()
		local r,err = xpcall(function()
			print('start prepare print')
			sself.pcb:prepare_print(self._protocol)
			print('complete prepare print')
			while (not sself.pcb:print_complete())  do
				if self._protocol:is_ready() and (self._state == state_printing) then
					sself.pcb:process_print( sself._protocol )
				else
					llae.sleep(100)
				end
				if self._state ~= state_printing and
					self._state ~= state_paused then
					break
				end
				local crnt,all = sself.pcb:get_progress()
				self._progress = crnt / all
			end
			print('complete process print')
			sself:end_state(state_printing,state)
		end,debug.traceback)
		
		if not r then
			sself:end_state(state_printing,state)
			print('PCB processing error',err)
		end
		collectgarbage('collect')
	end)

	assert(coroutine.resume(coro))
end

function printer:preview(  )
	local state = self:start_state(state_printing)
	local sself = self
	self._progress = 0

	async.run(function()
		local r,err = xpcall(function()
			log.info('start prepare preview')
			sself.pcb:prepare_preview()
			log.info('complete prepare preview')
			while (not sself.pcb:print_complete())  do
				if (self._state == state_printing) then
					sself.pcb:process_preview(  )
				end
				if self._state ~= state_printing and
					self._state ~= state_paused then
					break
				end
				local crnt,all = sself.pcb:get_progress()
				self._progress = crnt / all
			end
			log.info('complete process preview')
			sself:end_state(state_printing,state)
		end,debug.traceback)
		
		if not r then
			sself:end_state(state_printing,state)
			log.info('PCB processing error',err)
		end
		collectgarbage('collect')
	end)

end

function printer:calibrate( data  )
	local state = self:start_state(state_printing)
	local sself = self
	self._progress = 0
	local calibrate = (require 'printer.calibration').new()
	calibrate:setup( data )
	local coro = coroutine.create(function()
		local r,err = xpcall(function()
			print('start calibrate prepare print')
			calibrate:prepare_print(self._protocol, self._position_x)
			print('complete calibrate prepare print')
			while (not calibrate:print_complete())  do
				if self._protocol:is_ready() and (self._state == state_printing) then
					calibrate:process_print( sself._protocol )
				else
					llae.sleep(100)
				end
				if self._state ~= state_printing and
					self._state ~= state_paused then
					break
				end
				local crnt,all = calibrate:get_progress()
				self._progress = crnt / all
			end
			print('complete calibrate process print')
			sself:end_state(state_printing,state)
		end,debug.traceback)
		
		if not r then
			sself:end_state(state_printing,state)
			print('calibrate processing error',err)
		end
		collectgarbage('collect')
	end)

	assert(coroutine.resume(coro))
end



return printer