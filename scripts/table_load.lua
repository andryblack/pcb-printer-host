local _M = {}

function _M.get_path( file )
	local dir = string.match(args[0],'(.*)/.*')
	return dir .. '/' .. file
end

function _M.load( file , env_)
	local env = env_ or {}
	local chunk = assert(loadfile(file,'t',env))
	chunk()
	return env
end

function _M.load_string( string , env_)
	local env = env_ or {}
	local chunk = assert(load(string, 'load_string','t',env))
	chunk()
	return env
end

return _M