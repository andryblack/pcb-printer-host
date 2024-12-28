local class = require 'llae.class'
local log = require 'llae.log'
local async = require 'llae.async'
local serial = require 'posix.serial'

local Connection = class(nil,'printer.Connection')


function Connection:_init( path  )
	self._path = path
end

function Connection:open( )
	return false
end

function Connection:close( )
	-- body
end

function Connection:configure_baud( baudrate )
	return true
end

function Connection:is_opened(  )
	return false
end

function Connection:write( data )
	-- body
end

local SerialConnection = class(Connection,'printer.SerialConnection')

function SerialConnection:_init( path , delegate)
	Connection._init(self,path)
	self._delegate = delegate
end

function SerialConnection:read_function(  )
	local data = ''
	while true do
		local ch, e = self._serial:read()
		
		if not ch then
			if e then
				log.error('read serial failed',e)
			end
			break
		end
		--print('>',ch)
		data = data .. ch
		while true do
			local l,t = string.match(data,'^([^\r\n]*)[\r\n]+(.*)$')
			if l then
				data = t
				self._delegate:on_data( l )
			else
				break
			end
		end
		--
	end
	log.info('read complete',self._path)
end

function SerialConnection:open(  )
	--local err
	--self._serial,err = app.openSerial(self._path);
	--return self._serial,err
	return self:open_serial()
end

function SerialConnection:close( )
	if self._serial then
		self._serial:close()
		self._serial = nil
	end
end

function SerialConnection:open_serial()
	if self._baudrate and self._path then
		if not self._serial then
			local s,err = serial.open(self._path,{baudrate=self._baudrate })
			if not s then
				return nil,err
			end
			self._serial = s
			async.run(function()
				self:read_function()
			end)

		end
	end
	return true
end

function SerialConnection:configure_baud( baudrate )
	self._baudrate = baudrate
	return self:open_serial()
end

function SerialConnection:is_opened(  )
	return self._serial
end

function SerialConnection:write( data )
	local r,err = pcall(self._serial.write,self._serial,data)
	if not r then
		print('failed write: ',err)
	end
	return r
end

local FakeConnection = class(Connection,'printer.FakeConnection')

local FakePrinter = require 'printer.fake_printer'

function FakeConnection:_init( path , delegate)
	Connection._init(self,path)
	self._delegate = delegate
	self._opened = false
	self._printer = FakePrinter.new(delegate)
end

function FakeConnection:open( )
	self._opened = true
	self._printer:start()
	return true
end

function FakeConnection:close( )
	self._opened = false
	self._printer:stop()
end

function FakeConnection:is_opened(  )
	return self._opened
end

function FakeConnection:write( data )
	return self._printer:write(data)
end



function Connection.create( path , delegate)
	if path == 'fake' then
		return FakeConnection.new(path,delegate)
	end
	return SerialConnection.new(path,delegate)
end

return Connection

-- local class = require 'llae.class'
-- local app = require 'app'

-- local Connection = class(nil,'printer.Connection')

-- function Connection:_init( delegate)
-- 	self._delegate = delegate
-- end

-- function Connection:read_function(  )
-- 	while true do
-- 		local e,ch = self._serial:read()
-- 		if e then
-- 			print('error read',e)
-- 			break
-- 		end
-- 		if not ch then
-- 			break
-- 		end
-- 		self._delegate:on_data( ch )
-- 	end
-- 	print('read complete')
-- 	self:close()
-- 	self._delegate:on_close()
-- end

-- function Connection:open( path , baudrate )
-- 	self:close()
-- 	self._serial = assert(app.openSerial( path ));
-- 	self._serial:configure_baud(baudrate)
-- 	self._serial:start_read(self.read_function,self) 
-- 	return true
-- end

-- function Connection:close( )
-- 	if self._serial then
-- 		self._serial:close()
-- 		self._serial = nil
-- 	end
-- end

-- function Connection:is_opened(  )
-- 	return self._serial
-- end

-- function Connection:write( data )
-- 	local r,err = pcall(self._serial.write,self._serial,data)
-- 	if not r then
-- 		print('failed write: ',err)
-- 	end
-- 	return r
-- end


-- return Connection