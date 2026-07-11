local lpath = require 'llae.path'

local settings_api = {}

function settings_api:import( req )
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

	local res,err = application.printer.settings:import_data(file_part.data)
	if not res then
		return {
			status = 'error',
			error = err
		}
	end

	application.printer:save_settings()
	return {
		status = 'ok'
	}
end

function settings_api.make_routes( server )
	server:get('/api/settings/export', function( request, response )
		local data = application.printer.settings:export_data()
		response:set_header('Content-Type', 'application/json')
		response:set_header('Content-Disposition', 'attachment; filename="settings.json"')
		response:finish(data)
	end)
	server:post('/api/settings/import', function( request, response )
		response:json(settings_api:import(request))
	end)
end

return settings_api
