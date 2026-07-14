local log = require 'llae.log'
local pcb = {}

pcb.prefix = '/api/'

local type_to_icon = {
	['layer'] = 'cpu',
	['drill'] = 'crosshair'
}
function pcb:svg(  )
	return application.printer.pcb:get_svg()
end

function pcb:get_svg(  )
	return application.printer.pcb:get_svg()
end

function pcb:get_config(  )
	return application.printer.pcb:get_config()
end

function pcb:get_layers(  )
	local layers = {}
	for i,v in ipairs(application.printer.pcb:get_layers()) do
		table.insert(layers,{name=v.name,icon=type_to_icon[v.type],type=v.type,visible=not v.invisible})
	end
	return layers
end

function pcb:select_pnt( data )
	local res = application.printer.pcb:select_pnt(data)
	return {
		status = 'ok',
		pnt = res
	}
end


local function format_pnt( pnt )
	if not pnt then
		return nil
	end
	return {
		x = pnt.x,
		y = pnt.y,
		px = pnt.px,
		py = pnt.py,
	}
end

function pcb:get_pnts(  )
	return {
		status = 'ok',
		pnts = {
			pnt1 = format_pnt(application.printer.pcb:get_pnt('pnt1')),
			pnt2 = format_pnt(application.printer.pcb:get_pnt('pnt2')),
		}
	}
end


function pcb:offset_pnt( data )
	local res, err = pcall(function()
		application.printer.pcb:offset_pnt(data)
	end)
	if not res then
		return { status = 'error', error = tostring(err) }
	end
	local pnt = application.printer.pcb:get_pnt(data.pnt)
	return {
		status = 'ok',
		pnt = format_pnt(pnt)
	}
end



function pcb:get_pnt( pnt )
	return application.printer.pcb[pnt]
end


function pcb:open_gerber( file )
	local res,err = pcall(function()
		application.printer.pcb:open_gerber(file)
	end)
	if res then
		log.info('gerber loaded')
		return {status='ok',redirect='/pcb'}
	end
	log.error('failed open gerber:', err)
	return {status='error',error=err}
end

function pcb:open_drill( file )
	local res,err = pcall(function()
		application.printer.pcb:open_drill(file)
	end)
	if res then
		log.info('drill loaded')
		return {status='ok',redirect='/pcb'}
	end
	log.error('failed open drill:', err)
	return {status='error',error=err}
end

function pcb:print( config )
	local res,err = pcall(function()
		application.printer:print( config )
	end)
	if res then
		log.info('print started')
		return {status='ok',redirect='/home'}
	end
	log.error('failed print gerber:', err)
	return {status='error',error=err}
end

function pcb:preview(  )
	local res,err = pcall(function()
		application.printer:preview()
	end)
	if res then
		log.info('preview started')
		local state = application.printer:get_state()
		state.status = 'ok'
		return state
	end
	log.error('failed preview gerber:', err)
	return {status='error',error=err}
end


function pcb.make_routes( server )
	server:post('/api/open_gerber',function( request, response )
    	response:json(pcb:open_gerber(request.query.file))
	end)
	server:post('/api/open_drill',function( request , response )
    	response:json(pcb:open_drill(request.query.file))
	end)
	server:get('/api/pcb.svg',function( request , response )
    	--response:write_data(application.printer.pcb:get_svg(),'image/svg+xml')
    	response:set_header('Content-Type','image/svg+xml')
    	response:finish(application.printer.pcb:get_svg())
	end)
	server:get('/api/pcb/preview.png',function( request , response )
		local preview = application.printer.pcb:get_preview()
		if not preview then
			response:set_header('Content-Type','text/plain')
			response:finish('preview not found')
			return
		end
		response:set_header('Content-Type','image/png')
		response:set_header('Pragma','no-cache')
		response:set_header('Cache-Control','no-store, no-cache, must-revalidate')
		if request.query.download then
			response:set_header('Content-Disposition','attachment; filename="preview.png"')
		end
		response:finish(preview)
	end)
	server:post('/api/pcb/layers',function( request , response )
		response:json({status='ok',layers=pcb:get_layers()})
	end)
	server:post('/api/pcb/remove_layer',function( request , response)
		application.printer.pcb:remove_layer(request.json.layer)
		local res = application.printer:get_state( )
		res.status = 'ok'
		res.layers = pcb:get_layers()
		response:json(res)
	end)
	server:post('/api/pcb/visible_layer',function( request , response)
		application.printer.pcb:visible_layer(request.json.layer,request.json.visible)
		local res = application.printer:get_state( )
		res.status = 'ok'
		res.layers = pcb:get_layers()
		response:json(res)
	end)
	server:post('/api/pcb/update',function( request , response)
		application.printer.pcb:update(request.json)
		local res = application.printer:get_state( )
		res.status = 'ok'
		response:json(res)
	end)
	server:post('/api/pcb/print',function( request , response)
		response:json(pcb:print(request.json))
	end)
	server:post('/api/pcb/preview',function( request , response )
		response:json(pcb:preview())
	end)
	server:post('/api/pcb/select_pnt',function( request , response)
		response:json(pcb:select_pnt(request.json))
	end)
	server:post('/api/pcb/pnts',function( request , response)
		response:json(pcb:get_pnts())
	end)
	server:post('/api/pcb/offset_pnt',function( request , response)
		response:json(pcb:offset_pnt(request.json))
	end)

	
	
end

return pcb