local pcb = {}

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


function pcb:offset_pnt( data )
	local res = application.printer.pcb:offset_pnt(data)
	return {
		status = 'ok',
		tr = res
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
		print('gerber loaded')
		return {status='ok',redirect='/pcb'}
	end
	print('failed open gerber:', err)
	return {status='error',error=err}
end

function pcb:open_drill( file )
	local res,err = pcall(function()
		application.printer.pcb:open_drill(file)
	end)
	if res then
		print('drill loaded')
		return {status='ok',redirect='/pcb'}
	end
	print('failed open drill:', err)
	return {status='error',error=err}
end

function pcb:print(  )
	local res,err = pcall(function()
		application.printer:print()
	end)
	if res then
		print('print started')
		return {status='ok',redirect='/home'}
	end
	print('failed print gerber:', err)
	return {status='error',error=err}
end

function pcb:preview(  )
	local res,err = pcall(function()
		application.printer:preview()
	end)
	if res then
		print('preview started')
		return {status='ok'}
	end
	print('failed preview gerber:', err)
	return {status='error',error=err}
end


function pcb.make_routes( server )
	server:post('/api/open_gerber',function( request )
    	request:write_json(pcb:open_gerber(request.file))
	end)
	server:post('/api/open_drill',function( request )
    	request:write_json(pcb:open_drill(request.file))
	end)
	server:get('/api/pcb.svg',function( request )
    	request:write_data(application.printer.pcb:get_svg(),'image/svg+xml')
	end)
	server:post('/api/pcb/layers',function( request )
		request:write_json({status='ok',layers=pcb:get_layers()})
	end)
	server:post('/api/pcb/remove_layer',function( request )
		application.printer.pcb:remove_layer(request.json.layer)
		local res = application.printer:get_state( )
		res.status = 'ok'
		res.layers = pcb:get_layers()
		request:write_json(res)
	end)
	server:post('/api/pcb/visible_layer',function( request )
		application.printer.pcb:visible_layer(request.json.layer,request.json.visible)
		local res = application.printer:get_state( )
		res.status = 'ok'
		res.layers = pcb:get_layers()
		request:write_json(res)
	end)
	server:post('/api/pcb/update',function( request )
		application.printer.pcb:update(request.json)
		local res = application.printer:get_state( )
		res.status = 'ok'
		request:write_json(res)
	end)
	server:post('/api/pcb/print',function( request )
		request:write_json(pcb:print())
	end)
	server:post('/api/pcb/preview',function( request )
		request:write_json(pcb:preview())
	end)
	server:post('/api/pcb/select_pnt',function( request )
		request:write_json(pcb:select_pnt(request.json))
	end)
	server:post('/api/pcb/offset_pnt',function( request )
		request:write_json(pcb:offset_pnt(request.json))
	end)

	
	
end

return pcb