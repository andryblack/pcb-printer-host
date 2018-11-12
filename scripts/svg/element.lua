local class = require 'llae.class'

local Element = class(nil,'svg.element')

local function open_tag( data )
	local d = {'<' .. data[1]}
	for k,v in pairs(data) do
		if type(k)=='string' then
			table.insert(d,k..'="' .. tostring(v) .. '"')
		end
	end
	table.insert(d,'>')
	return table.concat(d,' ')
end

local function close_tag( tag )
	return '</' .. tag .. '>'
end

local function write_tag( data )
	local d = {'<' .. data[1]}
	for k,v in pairs(data) do
		if type(k)=='string' then
			table.insert(d,k..'="' .. tostring(v) .. '"')
		end
	end
	table.insert(d,'/>')
	return table.concat(d,' ')
end


function Element:_init( data )
	self._tag = data[1]
	self._data = { open_tag(data) }
end

function Element:build(  )
	self:close()
	for i,v in ipairs(self._data) do
		if type(v)~='string' then
			self._data[i] = v:build()
		end
	end
	return table.concat(self._data,'\n')
end

function Element:close(  )
	if self._tag then
		table.insert(self._data,close_tag(self._tag))
		self._tag = nil
	end
end

function Element:append( data )
	table.insert(self._data,data)
end

function Element:child( data )
	local el = Element.new(data)
	table.insert(self._data,el)
	return el
end

function Element:draw_contour( points , style)
	local poly = {}
	for _,p in ipairs(points) do
		table.insert(poly,p[1] ..',' ..p[2])
	end
	table.insert(self._data,write_tag{'polygon',points=table.concat(poly,' '),style=style})
end

function Element:draw_polygon( poly , style)
	local d = {}
	for _,p in ipairs(poly) do
		table.insert(d,'M')
		for i,v in ipairs(p) do
			if i~=1 then
				table.insert(d,'L')
			end
			table.insert(d,v[1])
			table.insert(d,v[2])
		end
		table.insert(d,'Z')
	end
	local res = write_tag{'path',d=table.concat(d,' '),style=style}
	table.insert(self._data,res)
	return res
end

function Element:draw_line( x1,y1,x2,y2, style )
	table.insert(self._data,write_tag{'line',x1=x1,y1=y1,x2=x2,y2=y2,style=style})
end

return Element