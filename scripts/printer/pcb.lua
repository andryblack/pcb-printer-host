local class = require 'llae.class'
local log = require 'llae.log'
local async = require 'llae.async'

local PCB = class(nil,'printer.PCB')

local Parser = require 'gerber.parser'
local Bounds = require 'geom.bounds'
local SvgGenerator = require 'svg.generator'
local Geometry = require 'geom.geometry'
local DrilParser = require 'gerber.drill'
local Protocol = require 'printer.protocol'
local rasterizator = require 'rasterizator'

PCB.root = application.config.files

local resolution = 10000

function PCB:_init(  )
	self:reset()
end

function PCB:reset(  )
	local svg = SvgGenerator.new('10mm','10mm','0 0 10 10','pcb-svg')
	self._svg_content = ''
	self._svg = svg:build()
	self._config = {
		position_x = 10.0,
		position_y = 10.0,
		negative = application.printer.settings.pcb_negative,
		drill_kern_r = application.printer.settings.pcb_drill_kern_r,
		drill_kern_or = application.printer.settings.pcb_drill_kern_or,
		y_resolution = 180*4/25.4,
		speed = application.printer.settings.print_speed or 500.0,
		flash_time = application.printer.settings.flash_time or 50.0,
		flip_x = false,
		flip_y = false
	}
	self._layers = {
	}
	for k,v in pairs(self._config) do
		print('init settings:',k,v)
	end
end

function PCB:add_gerber_layer( polygons , name )
	print('PVB add_gerber_layer')
	local bounds = Bounds.new()
	for _,v in ipairs(polygons) do
		bounds:extend_points(v)
	end
	if bounds:is_empty() then
		log.error('empty layer',name)
	end
	local fname = string.match(name,'.+/(.+)')
	if fname then
		name = fname
	end
	table.insert(self._layers,{
		polygons=polygons,
		bounds=bounds,
		name=name,
		type='layer',
		invisible=false})
	self:build_print()
end

function PCB:get_layer( name )
	for _,v in ipairs(self._layers) do
		if v.name == name then
			return v
		end
	end
	return self['_' .. name .. '_layer']
end

function PCB:add_drill_layer( points, name )
	local bounds = Bounds.new()
	for _,p in ipairs(points) do
		bounds:extend(p.x-self._config.drill_kern_or,p.y-self._config.drill_kern_or)
		bounds:extend(p.x+self._config.drill_kern_or,p.y+self._config.drill_kern_or)
		if p.x2 then
			bounds:extend(p.x2-self._config.drill_kern_or,p.y2-self._config.drill_kern_or)
			bounds:extend(p.x2+self._config.drill_kern_or,p.y2+self._config.drill_kern_or)
		end
	end
	local fname = string.match(name,'.+/(.+)')
	if fname then
		name = fname
	end
	table.insert(self._layers,{
			points=points,
			bounds=bounds,
			name=name,
			type='drill',
			invisible=false})
	self:build_print()
end

function PCB:open_gerber( file )
	print('open_gerber',file)

	local p = Parser.new()
	local f = assert(io.open(self.root .. '/' .. file))

	local state = application.printer:start_state('pcb_processing')
	local sself = self

	async.run(function()
		local r,err = xpcall(function()
			for l in f:lines() do
				p:parse(l)
			end
			f:close()
			p:finish()
			f = nil
			sself:add_gerber_layer( p:polygons(1.0) , file )
			print('PCB processing complete')
			application.printer:end_state('pcb_processing',state)
		end,debug.traceback)
		
		if not r then
			application.printer:end_state('pcb_processing',state)
			print('PCB processing error',err)
		end
		if f then
			f:close()
		end
		collectgarbage('collect')
	end)


end


function PCB:open_drill( file )
	print('open_drill',file)

	local p = DrilParser.new()
	local f = assert(io.open(self.root .. '/' .. file))

	local state = application.printer:start_state('pcb_processing')
	local sself = self

	async.run(function()
		local r,err = xpcall(function()
			for l in f:lines() do
				p:parse(l)
			end
			f:close()
			p:finish()
			f = nil
			sself:add_drill_layer( p.points or {} , file )
			print('PCB drill processing complete')
			application.printer:end_state('pcb_processing',state)
		end,debug.traceback)
		
		if not r then
			application.printer:end_state('pcb_processing',state)
			print('Dril processing error',err)
		end

		if f then
			f:close()
		end

		collectgarbage('collect')
	end)

	

end

function PCB:flip_bounds( bounds )
	if not self._config.flip_x and 
		not self._config.flip_y then
		return bounds
	end
	local b = bounds:copy()
	if self._config.flip_x then
		b:flip_x()
	end
	if self._config.flip_y then
		b:flip_y()
	end
	return b
end

function PCB:flip_polygons( polygons )
	if not self._config.flip_x and 
		not self._config.flip_y then
		return polygons
	end
	local r = {}
	local sx = self._config.flip_x and -1 or 1
	local sy = self._config.flip_y and -1 or 1
	for _,c in ipairs(polygons) do
		local ac = {}
		for _,p in ipairs(c) do
			table.insert(ac,{sx*p[1],sy*p[2]})
		end
		table.insert(r,ac)
	end
	return r
end

function PCB:flip_point( pnt )
	if not self._config.flip_x and 
		not self._config.flip_y then
		return pnt
	end
	local sx = self._config.flip_x and -1 or 1
	local sy = self._config.flip_y and -1 or 1
	return {x=pnt.x * sx, y=pnt.y * sy}
end

function PCB:flip_points( points )
	if not self._config.flip_x and 
		not self._config.flip_y then
		return points
	end
	local res = {}
	local sx = self._config.flip_x and -1 or 1
	local sy = self._config.flip_y and -1 or 1
	for _,p in ipairs(points) do
		table.insert(res,{x=sx*p.x,y=sy*p.y})
	end
	return res
end

function PCB:difference_layer( canvas , g )
	if self._config.negative then
		canvas:union(g)
	else
		canvas:difference(g)
	end
end

function PCB:union_layer( canvas , g )
	if not self._config.negative then
		canvas:union(g)
	else
		canvas:difference(g)
	end
end

function PCB:build_print(  )
	log.info('PCB build_print')
	
	
	
	local xpos = self._config.position_x 
	local ypos = self._config.position_y
	
	
	

	local bounds = Bounds.new()
	local obounds = Bounds.new()

	for i,layer in ipairs(self._layers) do
		bounds:intersect(self:flip_bounds(layer.bounds))
		obounds:intersect(layer.bounds)
	end


	local svg = SvgGenerator.new(
		-- bounds:width() .. 'mm',
		-- bounds:height() .. 'mm',
		'100%','100%',
		bounds:x() .. ' ' .. bounds:y() .. ' '.. bounds:width() .. ' ' .. bounds:height(),
		'pcb-svg'
	)

	local pcb = svg:child{'g',
		id="pcb-tr"}


	pcb:draw_line(-2,0,2,0,
			'stroke:#aa0000;stroke-width:0.1;')
	pcb:draw_line(0,-2,0,2,
			'stroke:#aa0000;stroke-width:0.1;')

	if not bounds:is_empty() then
		pcb:child{'rect',x=bounds:x(),y=bounds:y(),
				width=bounds:width(),
				height=bounds:height(),
				style="fill:none;stroke:#0000ff;stroke-width:0.1;"}
	else
		bounds:extend(0,0)
	end

	

	local canvas
	if self._config.negative and not bounds:is_empty() then
		local s = resolution
		canvas = Geometry.new_polygon({
			{bounds:x()*s, bounds:y()*s },
			{bounds:x()*s, (bounds:y()+bounds:height())*s },
			{(bounds:x()+bounds:width())*s, (bounds:y()+bounds:height())*s },
			{(bounds:x()+bounds:width())*s, bounds:y()*s },
			})
	else
		canvas = Geometry.new{}
	end

	for _,layer in ipairs(self._layers) do
		if layer.invisible then
		else
			if layer.type == 'layer' then
				local g = Geometry.import(self:flip_polygons(layer.polygons),resolution)
				self:union_layer(canvas,g)
			elseif layer.type == 'drill' then
				local g = Geometry.new{}
				local go = Geometry.new{}
				for _,p in ipairs(self:flip_points(layer.points)) do
					if p.x2 then
						local path = {
							{p.x*resolution, p.y*resolution},
							{p.x2*resolution, p.y2*resolution}
						}
						local pg = Geometry.new_path_buffer(path,self._config.drill_kern_r*resolution*2)
						g:union(pg)
						local po = Geometry.new_path_buffer(path,self._config.drill_kern_or*resolution*2)
						go:union(po)
					else
						local pg = Geometry.new_circle(p.x*resolution,
								p.y*resolution,self._config.drill_kern_r*resolution)
						g:union(pg)
						local po = Geometry.new_circle(p.x*resolution,
								p.y*resolution,self._config.drill_kern_or*resolution)
						go:union(po)
					end
				end
				self:union_layer(canvas,go)
				self:difference_layer(canvas,g)
			end
			
		end
	end

	local polygons = canvas:export(1.0/resolution)
	
	self._svg_content = pcb:draw_polygon(polygons,
			'stroke:none;fill:#00aa00;fill-rule:nonzero')

	local points_g = svg:child{'g',
		id="points",visibility='hidden'}


	local function add_points_layer( layer  ) 
		for i,p in ipairs(self:flip_points(layer.points)) do
			local x = p.x
			local y = p.y
			points_g:child{'circle',id='pnt-'..i,cx=x,cy=y,r=1.5,class='point-select',
				['data-idx']=i,
				['data-layer']=layer.name}
		end
	end
	for _,layer in ipairs(self._layers) do
		if layer.invisible then
		else
			if layer.type == 'drill' then
				add_points_layer( layer )
			end
		end
	end

	self._bounds_layer = {
		name = 'bounds',
		type = 'select-points',
		points = {
			{ x = obounds:x(), y = obounds:y() },
			{ x = obounds:x() + obounds:width(), y = obounds:y() },
			{ x = obounds:x(), y = obounds:y() + obounds:height() },
			{ x = obounds:x() + obounds:width(), y = obounds:y() + obounds:height() }
		}
	}
	add_points_layer( self._bounds_layer  )

	self._polygons = polygons
	self._bounds = bounds
	
	-- pcb:child{
	-- 	'rect',
	-- 	id='pcb',
	-- 	x=self._bounds:x(),
	-- 	y=self._bounds:y(),
	-- 	width=math.abs(self._bounds:width()),
	-- 	height=math.abs(self._bounds:height()),
	-- 	style="fill:#ffff00",
	-- }


	--pcb:draw_polygon(polygons,'stroke:none;fill:#00aa00;fill-rule:nonzero',application.printer.settings.printer_height)

	do
		local p = pcb:child{'g',id='pnt1-pos',transform=self.pnt1 and 'translate(' .. self.pnt1.x..','..self.pnt1.y..')'}
		p:draw_line(-1,0,1,0,
			'stroke:#0000aa;stroke-width:0.1;')
		p:draw_line(0,-1,0,1,
			'stroke:#0000aa;stroke-width:0.1;')
	end

	do
		local p = pcb:child{'g',id='pnt2-pos',transform=self.pnt2 and 'translate(' .. self.pnt2.x..','..self.pnt2.y..')'}
		p:draw_line(-1,0,1,0,
			'stroke:#0000aa;stroke-width:0.1;')
		p:draw_line(0,-1,0,1,
			'stroke:#0000aa;stroke-width:0.1;')
	end
	
	self._svg = svg:build()
	
	print('PCB build_print end')
end

function PCB:get_left( )
	return self._config.position_x + (self._bounds and self._bounds:x() or 0)
end
function PCB:get_right( )
	return self._config.position_x + (self._bounds and (self._bounds:x()+self._bounds:width()) or 0)
end

function PCB:update( config )
	for k,v in pairs(config or {}) do
		self._config[k] = v
		print('set config value:',k,v,type(v))
	end
	local sself = self
	local state = application.printer:start_state('pcb_processing')

	async.run(function()
		local r,err = pcall(function()
			sself:build_print()
			print('PCB update complete')
			application.printer:end_state('pcb_processing',state)
		end)
		if not r then
			application.printer:end_state('pcb_processing',state)
			print('PCB update error',err)
		end
		collectgarbage('collect')
	end)

end


function PCB:get_svg( )
	return self._svg
end

function PCB:get_svg_content(  )
	return self._svg_content
end

function PCB:get_config( )
	return self._config
end

function PCB:get_layers() 
	return self._layers
end

function PCB:remove_layer( i )
	local l = table.remove(self._layers,i)
	if l then
		self:update()
	end
end

function PCB:visible_layer( i , v)

	local l = self._layers[i]

	if l then
		l.invisible = not v
		self:update()
	end
end


function PCB:prepare_print( protocol )

	self:setup_rasterizator()

	protocol:setup_laser(Protocol.LASER_MODE_PRINT,self._config.flash_time)
	protocol:wait()
	
	print('paths added,start')
	self._rasterizator:start()
	print('started')
	local res = application.printer:get_resolution_x()
	self._start_r = math.ceil(self._config.position_x * res) + self._rasterizator:get_left()
	print('left pos:',self._start_r,self._rasterizator:get_left())
	self._start_l = self._start_r + self._rasterizator:get_width()
	print('right pos:',self._start_l,self._rasterizator:get_width())
	
	protocol:move_x(self._start_r-5,application.printer:get_idle_speed_x(),protocol.FLAG_WAIT_MOVE)
	protocol:wait()
	local y_pos = math.ceil((self._config.position_y + self._rasterizator:get_y_start()) * application.printer:get_resolution_y())
	print('y_start:',y_pos)
	protocol:move_y(y_pos,
		protocol.FLAG_WAIT_MOVE)
	protocol:wait()
	self._dir = 'r'
	self._pos_y = 0
	self._prev_y = 0
	
end

function PCB:print_complete(  )
	return self._rasterizator:complete()
end

function PCB:process_print( protocol )
	self._rasterizator:process()
	local l = self._rasterizator:get_line()
	local speed = application.printer:calc_speed(self._config.speed)
	local start = self._start_r
	local pl = l
	if self._dir == 'l' then
		start = self._start_l
		self._rasterizator:inverse()
		pl = self._rasterizator:get_line()
		self._dir = 'r'
	else
		self._dir = 'l'
	end
	self._pos_y = (self._rasterizator:get_y_pos() - self._rasterizator:get_y_start()) * application.printer:get_resolution_y()
	local pos_y = math.ceil(self._pos_y)
	local dy = pos_y -  self._prev_y
	log.debug('Y:',dy)
	protocol:print(start,speed, dy,pl)
	self._prev_y = pos_y
end
function PCB:get_progress(  )
	return self._rasterizator:get_y_pos() - self._rasterizator:get_y_start(),self._rasterizator:get_y_len()
end

function PCB:setup_rasterizator(  )
	self._rasterizator = rasterizator.Rasterizator.new()
	local res = application.printer:get_resolution_x()
	self._rasterizator:set_scale(res,
		self._config.y_resolution)

	if self.pnt1 and 
		self.pnt2 and
		self.pnt1.px and
		self.pnt2.px then
		self._rasterizator:setup_transform(self.pnt1,self.pnt2)
	end

	self._rasterizator:add_paths(self._polygons)
end

function PCB:prepare_preview(  )

	

	self:setup_rasterizator()

	self._write = rasterizator.RasterizatorWrite.new()
	log.info('paths added,start')
	self._rasterizator:start()
	log.info('started')
	self._write:set_size(self._rasterizator:get_width(),self._rasterizator:get_height())
	
end

function PCB:process_preview(  )
	self._rasterizator:process()
	local l = self._rasterizator:get_line()
	self._write:write(l)
	if self._rasterizator:complete() then
		self._preview = self._write:end_write()
	end
end

function PCB:select_pnt( data )
	local layer = self:get_layer(data.layer)
	if not layer then
		error('not found layer ' .. tostring(data.layer))
	end
	if layer.type ~= 'drill' and layer.type ~= 'select-points' then
		error('invalid layer ' .. tostring(data.layer))
	end
	local pnt = layer.points[tonumber(data.idx)]
	if not pnt then
		error('not found point ' .. tostring(data.idx))
	end
	pnt = self:flip_point(pnt)
	print('set',data.pnt,pnt.x,pnt.y)
	self[data.pnt] = pnt
	return pnt
end

function PCB:offset_pnt( data )
	local pnt = self[data.pnt]
	if not pnt then
		error('invalid point ' .. tostring(data.pnt))
	end
	pnt.px = data.x / application.printer:get_resolution_x()
	pnt.py = data.y / application.printer:get_resolution_y()
	if data.pnt == 'pnt1' then
		self._config.position_x = pnt.px - pnt.x
		self._config.position_y = pnt.py - pnt.y 
	end
	print('offset',data.pnt,pnt.px,pnt.py)
	self:update_transform()
end

function PCB:update_transform(  )
	if not self.pnt2 then
		return
	end
	if not self.pnt2.px then
		return
	end

end

function PCB:get_pnt( pnt )
	return self[pnt]
end
return PCB
