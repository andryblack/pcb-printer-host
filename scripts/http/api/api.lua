local log = require 'llae.log'
local api = {}

function api.wrap_function( func, obj )
	return function( request , res )
		local data = request.json
		local status,rres = pcall(func,obj,data)
		if status then
			return res:json(rres)
		else
			return res:json{
				status = 'error',
				error = rres
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
					log.info('register route',method,route)
					server[method](server,route,api.wrap_function(v,object))
				else
					log.error('unexpected function',n)
				end
			end
		end

	end

end
	
return api