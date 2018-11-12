local multipart = {}

multipart.__index = multipart



local function get_boundary(header)
    if not header then
        return nil,'empty header'
    end

    local m = string.match(header, ";%s*boundary=\"([^\"]+)\"")
    if m then
        return m
    end

    return string.match(header, ";%s*boundary=([^\",;]+)")
end


function multipart.new( content_type , reader)

	local boundary,err = get_boundary(content_type)
	if not boundary then
        error(err or 'failed parse boundary')
	end

	return setmetatable({
		_boundary = boundary,
		_boundary_size = #boundary,
		_reader = reader,
		_data = '',
		_items = {}
		},multipart)
end

function multipart:receive_until( str )
	local data = ''
	local last_pos = 1
	while true do
		local d = self._tail or self._reader()
		self._tail = nil
		if not d then
			return nil,'unexpected end on receive_until'
		end
		data = data .. d
		local ms,me = string.find(data,str,last_pos,true)
		if ms then
			self._tail = string.sub(data,me+1)
			return string.sub(data,1,ms-1)
		end
		last_pos = #data
	end
end

function multipart:receive_item_until( str )
	local data = ''
	local last_pos = 1
	local plen = #str
	while true do
		local d = self._tail or self._reader()
		self._tail = nil
		if not d then
			return nil,'unexpected end on receive_item_until'
		end
		data = data .. d
		local ms,me = string.find(data,str,1,true)
		if ms then
			self._tail = string.sub(data,me+1)
			if ms > 1 then
				local r,e = self._item:on_data(string.sub(data,1,ms-1),true)
				if not r then
					return nil,e
				end
			end
			return true
		end
		local dlen = #data
		if dlen > plen then
			local left = dlen-plen
			local r,e = self._item:on_data(string.sub(data,1,left))
			if not r then
				return nil,e
			end
			data = string.sub(data,left+1)
		end
	end
end

function multipart:read_cnt( num )
	if not self._tail then
		self._tail = self._reader()
		if not self._tail then
			return nil,'unexpected end on read_cnt'
		end
	end
	while #self._tail < num do
		local d = self._reader
		if not d then
			return nil,'unexpected end'
		end
		self._tail = self._tail .. d
	end	
	local r = string.sub(self._tail,1,num)
	self._tail = string.sub(self._tail,num+1)
	return r
end

function multipart:read_headers(  )
	local headers = {}
	while true do
		local line = self:receive_until('\r\n')
		if line == '' then
			return headers
		end
		local k,v = string.match(line,'([^: \t]+)%s*:%s*(.+)')
		if not k then
			return nil,'invalid header "' .. line .. '"'
		end
		print('found header:','|'..k..'|','|'..v..'|')
		headers[k]=v
	end
end

function multipart:parse_content_disposition( cd )
	local attrs = {}
	local idx = 1
	for w in string.gmatch(cd,"[^;]+") do 
		local k,v = string.match(w,'%s*([^=]+)%s*=%s*"(.+)"%s*')
		if k then
			print('found attr','|'..k..'|','|'..v..'|')
			attrs[k] = v
		else
			local s = string.match(w,'%s*(.+)%s*')
			print('simple attr','|'..s..'|')
			attrs[idx] = s
			idx = idx + 1
		end
	end
	return attrs
end

function multipart:on_item( item )
	table.insert(self._items,item)
	item.data = ''
	function item:on_data( data , isend)
		self.data = self.data .. data
		if isend then
			print('data:','|' .. self.data .. '|')
		end
		return true
	end
	self._item = item
	return true
end

function multipart:read( )
	local item_boundary = "--" .. self._boundary
	local preamble, err = self:receive_until(item_boundary..'\r\n')
    if not preamble then
        return nil, err
    end
	while true do
		
	    local item = {}
	    print('found item')
	    item.header,err = self:read_headers(item)
	    if not item.header then
	    	return nil, err
	    end
	    local content_disposition = item.header['Content-Disposition']
	    if not content_disposition then
	    	return nil, 'not found Content-Disposition'
	    end
	    item.attributes = self:parse_content_disposition(content_disposition)
	    item.name = item.attributes.name
	    if not item.name then
	    	return nil, 'not found field name'
	    end
	    print('name:',item.name)

	    local data, err = self:on_item(item)
	    if not data then
	    	print('failed handle item',err)
	    	return nil, err
	    end
	    local data, err = self:receive_item_until('\r\n'..item_boundary)
	    if not data then
	    	print('failed recive data',err)
	        return nil, err
	    end
	    local tail,err = self:read_cnt(2)
	    if not tail then
	        return nil, err
	    end
	    if tail == '--' then
	    	-- read rest
	    	-- while self._reader() do
	    		
	    	-- end
	    	local res = {}
	    	for _,v in ipairs(self._items) do
	    		res[v.name] = v.data
	    	end
	    	return res
	    elseif tail ~= '\r\n' then
	    	return nil,'invalid boundary "' .. tail .. '" (' .. tostring(#tail) .. ')'
	    end
	end
	
end

return multipart