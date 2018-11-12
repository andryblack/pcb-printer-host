local class = require 'llae.class'

local Element = require 'svg.element'
local Generator = class(Element,'svg.generator')


function Generator:_init( width, height , vb, id)
	Element._init(self,{'svg',width = width,height=height,viewBox=vb,xmlns="http://www.w3.org/2000/svg",id=id})
	--table.insert(self._data,1,'<?xml version="1.0" ?>')
	--table.insert(self._data,2,'<!DOCTYPE svg PUBLIC "-//W3C//DTD SVG 1.0//EN"' ..
     --    ' "http://www.w3.org/TR/2001/REC-SVG-20010904/DTD/svg10.dtd">')
	self._width = tonumber(width)
	self._height = tonumber(height)
end

return Generator