local api = {}

function api.wrap_function( func, obj )
	return function ( request )
		local data = request.json
		local status,res = pcall(func,obj,data)
		if status then
			request:write_json(res)
		else
			request:write_json{
				status = 'error',
				error = res
			}
		end
	end
end

function api.register( object ) 

	local prefix = object.prefix or '/'
	object.make_routes = function(server)

		for n,v in pairs(object) do
			if type(v) == 'function' then
				local method,name = string.match(n,'(%w+)_(.+)')
				if method and name and server[method] then
					local route = prefix .. name
					print('register route',method,route)
					server[method](server,route,api.wrap_function(v,object))
				else
					print('unexpected function',n)
				end
			end
		end

	end

end
	
return api