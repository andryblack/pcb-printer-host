local lpath = require 'llae.path'

local firmware = {}

function firmware:flash( req )
	if not req.multipart then
		return {
			status = 'error',
			error = 'need multipart'
		}
	end

	local file_part
	for _,v in ipairs(req.multipart) do
		if v.name == 'file' then
			file_part = v
			break
		end
	end

	if not file_part then
		return {
			status = 'error',
			error = 'need file'
		}
	end

	local res,err = application.printer:flash_firmware(file_part.data)
	if not res then
		return {
			status = 'error',
			error = err
		}
	end

	return {
		status = 'ok'
	}
end

function firmware:status( req )
	return {
		status = 'ok',
		firmware = application.printer:get_firmware_info()
	}
end

function firmware.make_routes( server )
	server:post('/api/firmware/flash', function( request, response )
		response:json(firmware:flash(request))
	end)
    server:post('/api/firmware/status', function( request, response )
		response:json(firmware:status(request))
	end)
end

return firmware
