local class = require 'llae.class'
local llae = require 'llae'

local struct = require 'protocol.struct'
local Slip = require 'protocol.slip'
local CRC8 = require 'protocol.crc8'

local Protocol = class(nil,'printer.Protocol')

Protocol.header_t = {
	{'u8','seq'},
	{'u8','cmd'},
	{'u16','len'},
}
Protocol.header_t_size = struct.sizeof(Protocol.header_t)

local commands = {
	['CMD_PING'] = 0,
	['CMD_MOVE_X'] = 1,
	['CMD_STOP'] = 2,
	['CMD_READ_SPEED'] = 3,
	['CMD_ZERO_X'] = 4,
	['CMD_ZERO_Y'] = 5,
	['CMD_SETUP_PID'] = 6,
	['CMD_PRINT'] = 7,
	['CMD_MOVE_Y'] = 8,
	['CMD_SETUP_LASER'] = 9
}
Protocol._cmd_names = {}
for k,v in pairs(commands) do
	Protocol[k]=v
	Protocol._cmd_names[v]=k
end

Protocol.FLAG_WRITE_SPEED = 1
Protocol.FLAG_WAIT_MOVE = 2

Protocol.move_x_t = {
	{'i32','pos'},
	{'u16','speed'},
	{'u16','flags'},
}
Protocol.speed_sample_t = {
	{'u16','dt'},
	{'u16','pwm'}
}
Protocol.speed_sample_t_size = struct.sizeof(Protocol.speed_sample_t)

Protocol.setup_pid_t = {
	{'f32','P'},
	{'f32','I'},
	{'f32','D'}
}

Protocol.print_t = {
	{'u16','start'},
	{'u16','len'},
	{'u16','move_y'},
	{'u16','speed'},
}
Protocol.print_t_size = struct.sizeof(Protocol.print_t)

Protocol.move_y_t = {
	{'i32','pos'},
	{'u16','flags'},
}

Protocol.ping_resp_t = {
	{'i16','pos_x'},
	{'i32','pos_y'}
}

Protocol.LASER_MODE_PRINT = 0
Protocol.LASER_MODE_PWM = 1
Protocol.setup_laser_t = {
	{'u16','mode'},
	{'u16','param'}
}

function Protocol:_init( delegate )
	self._delegate = delegate
	self._encoder = Slip.encoder.new()
	self._decoder = Slip.decoder.new(self)
	self._timeout = llae.newTimer()
	self._timeout_cb = function ()
		self:_on_timeout()
	end
	self:reset()
	self._print_timeout = 1000*1000
end

function Protocol:reset(  )
	self._send_seq = 0
	self._recv_seq = nil
	self._scheduled = {}
	self._decoder:reset()
end

function Protocol:on_data( data )
	--print('on data',#data)
	local len = #data
	local o = 0
	local b
	while o < len do
		b,o = struct.readu8(data,o)
		self._decoder:on_byte(b)
	end
end

function Protocol:on_packet( data )
	--print('on_packet',#data)
	if not self._recv_seq then
		print('unexpected packet')
		return
	end
	self._timeout:stop()
	self:_process_packet(data)
	self:_check_next()
end

function Protocol:_check_next(  )
	if not self._recv_seq then
		local next_cmd = table.remove(self._scheduled,1)
		if next_cmd then
			self:_cmd_impl(next_cmd.cmd,next_cmd.data,next_cmd.wait)
		end
	end
end

function Protocol:_process_packet( data )
	local seq = self._recv_seq 
	self._recv_seq = nil
	local len = #data
	if len < (Protocol.header_t_size + 1) then
		print('too short packet')
		return
	end
	local header,o = struct.read(data,self.header_t)
	if len ~= (Protocol.header_t_size + 1 + header.len) then
		print('invalid packet len')
		return
	end
	if not CRC8.check(data,len-1,string.byte(data,len)) then
		print('packet',struct.format_bytes(data))
		print('invalid packet crc',string.format('%02x/%02x',string.byte(data,len),CRC8.calc(data,len-1)))
		return
	end
	if header.seq ~= seq then
		print('invalid packet seq')
		return
	end
	--print('on packet',header.cmd)
	
	self:on_response(header,string.sub(data,Protocol.header_t_size+1,len-1))
end

function Protocol:is_ready(  )
	return not self._recv_seq and (#self._scheduled == 0)
end

function Protocol:on_response( header, data )
	print('<',self._cmd_names[header.cmd],#data)
	if header.cmd == Protocol.CMD_PING then
		local o,s = struct.read(data,Protocol.ping_resp_t,0)
		self._delegate:update_pos(o.pos_x,o.pos_y)
	elseif header.cmd == Protocol.CMD_MOVE_X then
	elseif header.cmd == Protocol.CMD_MOVE_Y then
	elseif header.cmd == Protocol.CMD_ZERO_X then
	elseif header.cmd == Protocol.CMD_STOP then
	elseif header.cmd == Protocol.CMD_READ_SPEED then
		local samples_cnt = header.len / Protocol.speed_sample_t_size
		local o = 0
		local s 
		for i=1,samples_cnt do
			s,o = struct.read(data,Protocol.speed_sample_t,o)
			self._delegate:add_speed_sample(s)
		end
	elseif header.cmd == Protocol.CMD_SETUP_PID then
	elseif header.cmd == Protocol.CMD_PRINT then
	elseif header.cmd == Protocol.CMD_SETUP_LASER then
	else
		print('unknown response:',header.cmd)
	end
end

function Protocol:_cmd_impl( cmd, data , wait)
	self._recv_seq = self._send_seq
	local header = struct.new(self.header_t,{
		seq = self._send_seq,
		cmd = cmd,
		len = data and #data or 0
		})
	self._send_seq = (self._send_seq + 1) & 0xff
	local packet = table.concat({
		header:build(),data
	},'')
	packet = packet .. struct.writeu8(CRC8.calc(packet,#packet))
	local raw = self._encoder:encode(packet)
	print('>',self._cmd_names[cmd],#raw)
	self._delegate:write(raw)
	local to = 1000
	if cmd == Protocol.CMD_PRINT then
		to = self._print_timeout
	end
	if not wait then
		self._timeout:start(self._timeout_cb,to,0)
	else
		print('wait cmd')
	end
end

function Protocol:cmd( cmd, data , wait)
	--print('send cmd',cmd)
	if self:is_ready() then
		self:_cmd_impl(cmd,data,wait)
	else
		table.insert(self._scheduled,{cmd=cmd,data=data,wait=wait})
	end
end

function Protocol:ping(  )
	self:cmd(self.CMD_PING)
end
function Protocol:move_x( pos , speed , flags )

	local data = struct.new(self.move_x_t,{
		pos = pos,
		speed = speed,
		flags = flags or 0
	}):build()
	self:cmd(self.CMD_MOVE_X,data, ((flags or 0) & Protocol.FLAG_WAIT_MOVE) ~= 0)
end
function Protocol:move_y( pos , flags )
	local data = struct.new(self.move_y_t,{
		pos = pos,
		flags = flags or 0
	}):build()
	self:cmd(self.CMD_MOVE_Y,data, ((flags or 0) & Protocol.FLAG_WAIT_MOVE) ~= 0)
end
function Protocol:read_speed( )
	self:cmd(self.CMD_READ_SPEED)
end
function Protocol:stop(  )
	self:cmd(self.CMD_STOP)
end
function Protocol:zero_x(  )
	self:cmd(self.CMD_ZERO_X)
end
function Protocol:zero_y(  )
	self:cmd(self.CMD_ZERO_Y)
end
function Protocol:print( start, speed, move_y, data )
	local data_hdr = struct.new(self.print_t,{
		start = start,
		speed = speed,
		move_y = move_y,
		len = #data
	}):build()
	self:cmd(self.CMD_PRINT,data_hdr .. data)
end
function Protocol:setup_pid( P,I,D )
	local data = struct.new(self.setup_pid_t,{
		P = P,
		I = I, 
		D = D
	}):build()
	self:cmd(self.CMD_SETUP_PID,data)
end
function Protocol:setup_laser( mode, param )
	local data = struct.new(self.setup_laser_t,{
		mode = mode,
		param = param
	}):build()
	self:cmd(self.CMD_SETUP_LASER,data)
end
function Protocol:_on_timeout(  )
	if self._recv_seq then
		print('cmd_timeout')
		self._recv_seq = nil
		self:_check_next()
	end
end

function Protocol:wait(  )
	while not self:is_ready() do
		llae.sleep(100)
	end
end

return Protocol