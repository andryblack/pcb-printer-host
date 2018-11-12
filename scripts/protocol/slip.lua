local class = require 'llae.class'
local struct = require 'protocol.struct'

local SLIP_SOF = 0xc0
local SLIP_DB = 0xdb
local SLIP_DC = 0xdc
local SLIP_DD = 0xdd

local SLIP_DECODER_UNKNOWN = 'unknow'
local SLIP_DECODER_X_DB = 'x_db'
local SLIP_DECODER_ACTIVE = 'active'

local SlipDecoder = class(nil,'protocol.SlipDecoder')
function SlipDecoder:_init( delegate )
	self._delegate = delegate
	self:reset()
end
function SlipDecoder:reset(  )
	self._state = SLIP_DECODER_UNKNOWN
	self._data = {}
end
function SlipDecoder:on_byte( b )
	if self._state == SLIP_DECODER_UNKNOWN then
		if b ~= SLIP_SOF then
			-- skip byte
			return
		end
		self:reset()
		self._state = SLIP_DECODER_ACTIVE
	elseif self._state == SLIP_DECODER_X_DB then
		if b == SLIP_DC then
			self:store_byte(SLIP_SOF)
			self._state = SLIP_DECODER_ACTIVE
		elseif b == SLIP_DD then
			self:store_byte(SLIP_DB)
			self._state = SLIP_DECODER_ACTIVE
		else
			self:on_error(b)
		end
	elseif self._state == SLIP_DECODER_ACTIVE then
		if b == SLIP_SOF then
			if #self._data == 0 then
				self:on_error('empty packet')
				self._state = SLIP_DECODER_ACTIVE
			else
				self:on_end()
			end
		elseif b == SLIP_DB then
			self._state = SLIP_DECODER_X_DB 
		else
			self:store_byte(b)
		end
	end
end

function SlipDecoder:store_byte( b )
	table.insert(self._data,struct.writeu8(b))
end
function SlipDecoder:on_error( b )
	print('slip decoder error')
	self:reset()
end
function SlipDecoder:on_end( )
	local packet = table.concat(self._data,'')
	self:reset()
	self._delegate:on_packet(packet)
end


local SlipEncoder = class(nil,'protocol.SlipEncoder')
function SlipEncoder:_init(  )
	self:reset()
end
function SlipEncoder:reset(  )
	self._data = {}
end
function SlipEncoder:encode( data )
	self:encode_start(data)
	return self:encode_end()
end

function SlipEncoder:encode_start( data )
	self:reset()
	table.insert(self._data,struct.writeu8(SLIP_SOF))
	self:encode_write(data)
end

function SlipEncoder:encode_write( data )
	local o = 0
	local l = #data
	local b
	while o < l do
		b,o = struct.readu8(data,o)
		if b == SLIP_SOF then
			table.insert(self._data,struct.writeu8(SLIP_DB))
			table.insert(self._data,struct.writeu8(SLIP_DC))
		elseif b == SLIP_DB then
			table.insert(self._data,struct.writeu8(SLIP_DB))
			table.insert(self._data,struct.writeu8(SLIP_DD))
		else
			table.insert(self._data,struct.writeu8(b))
		end
	end
end

function SlipEncoder:encode_end(  )
	table.insert(self._data,struct.writeu8(SLIP_SOF))
	local packet = table.concat(self._data,'')
	self:reset()
	return packet
end

return {
	encoder = SlipEncoder,
	decoder = SlipDecoder
}