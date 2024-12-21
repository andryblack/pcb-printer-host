local class = require 'llae.class'
local log = require 'llae.log'
local async = require 'llae.async'

local Protocol = require 'printer.protocol'
local CRC8 = require 'protocol.crc8'
local struct = require 'protocol.struct'
local Slip = require 'protocol.slip'


local FakePrinter = class()

function FakePrinter:_init( delegate )
	self._delegate = delegate
	self._encoder = Slip.encoder.new()
	self._decoder = Slip.decoder.new(self)
	self._pos_x = 0
	self._pos_y = 0
	self._responses = {}
end

function FakePrinter:start()
	async.run(function()
		while(true) do
			local d = table.remove(self._responses)
			if d then
				self._delegate:on_data(d)
			end
			async.pause(100)
		end
	end)
end

function FakePrinter:_response(conf)
	local header = struct.new(Protocol.header_t,{
		seq = self._seq,
		cmd = conf.cmd,
		len = conf.data and #conf.data or 0
		})
	local packet = table.concat({
		header:build(),(conf.data and conf.data or '')
	},'')
	packet = packet .. struct.writeu8(CRC8.calc(packet,#packet))
	local raw = self._encoder:encode(packet)
	table.insert(self._responses,raw)
end

function FakePrinter:on_packet(data)
	if #data < (Protocol.header_t_size + 1) then
		return false,'invalid'
	end
	local len = #data
	local header,o = struct.read(data,Protocol.header_t)
	if len ~= (Protocol.header_t_size + 1 + header.len) then
		log.error('invalid packet len')
		return false, 'invalid size'
	end
	if not CRC8.check(data,len-1,string.byte(data,len)) then
		log.error('packet',struct.format_bytes(data))
		log.error('invalid packet crc',string.format('%02x/%02x',string.byte(data,len),CRC8.calc(data,len-1)))
		return false, 'invalid crc'
	end
	self._seq = header.seq
	if header.cmd == Protocol.CMD_PING then
		self:_response{
			cmd = Protocol.CMD_PING,
			data = struct.new(Protocol.ping_resp_t,{
				pos_x = self._pos_x,
				pos_y = self._pos_y
			}):build()
		}
	elseif header.cmd == Protocol.CMD_SETUP_MOTOR then
		self:_response{
			cmd = Protocol.CMD_SETUP_MOTOR,
			data = struct.new(Protocol.status_resp_t,{
				status = Protocol.CODE_OK
			}):build()
		}
	elseif header.cmd == Protocol.CMD_SET_STEPPER_PARAM then
		self:_response{
			cmd = Protocol.CMD_SET_STEPPER_PARAM,
			data = struct.new(Protocol.status_resp_t,{
				status = Protocol.CODE_OK
			}):build()
		}
	end
	return true
end
function FakePrinter:write(data)
	local len = #data
	local o = 0
	local b
	while o < len do
		b,o = struct.readu8(data,o)
		self._decoder:on_byte(b)
	end
	return true
end

return FakePrinter