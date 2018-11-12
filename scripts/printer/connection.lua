local class = require 'llae.class'
local app = require 'app'

local Connection = class(nil,'printer.Connection')

function Connection:_init( delegate)
	self._delegate = delegate
end

function Connection:read_function(  )
	while true do
		local e,ch = self._serial:read()
		if e then
			print('error read',e)
			break
		end
		if not ch then
			break
		end
		self._delegate:on_data( ch )
	end
	print('read complete')
	self:close()
	self._delegate:on_close()
end

function Connection:open( path , baudrate )
	self:close()
	self._serial = assert(app.openSerial( path ));
	self._serial:configure_baud(baudrate)
	self._serial:start_read(self.read_function,self) 
	return true
end

function Connection:close( )
	if self._serial then
		self._serial:close()
		self._serial = nil
	end
end

function Connection:is_opened(  )
	return self._serial
end

function Connection:write( data )
	local r,err = pcall(self._serial.write,self._serial,data)
	if not r then
		print('failed write: ',err)
	end
	return r
end


return Connection