local printer = {}

local api = require 'http.api.api'
printer.pcb = require 'http.api.pcb'

printer.prefix = '/api/'

function printer:get_state(  )
	local res = application.printer:get_state( )
	res.status = 'ok'
	return res
end
function printer:post_state( data )
	local res = application.printer:get_state( data )
	res.status = 'ok'
	return res
end


function printer:post_disconnect( )
	application.printer:disconnect()
	return self:get_state()
end

function printer:post_connect( )
	application.printer:connect()
	return self:get_state()
end

function printer:post_pause( )
	application.printer:pause()
	return self:get_state()
end

function printer:post_resume( )
	application.printer:resume()
	return self:get_state()
end

function printer:post_stop( )
	application.printer:print_stop()
	return self:get_state()
end

function printer:post_calibrate( )
	application.printer:calibrate()
	return self:get_state()
end

function printer:post_action( data )
	application.printer:action(data.action,data.data)
	return self:get_state()
end

api.register(printer)

return printer