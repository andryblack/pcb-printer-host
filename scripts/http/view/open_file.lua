
local _M = {}

_M.page = 'open_file'

local function wildcards(pattern)
	-- Escape characters that have special meanings in Lua patterns
	pattern = pattern:gsub("([%+%.%-%^%$%(%)%%])", "%%%1")

	-- Replace wildcard patterns with special placeholders so I don't
	-- have competing star replacements to worry about
	pattern = pattern:gsub("%*%*", "\001")
	pattern = pattern:gsub("%*", "\002")

	-- Replace the placeholders with their Lua patterns
	pattern = pattern:gsub("\001", ".*")
	pattern = pattern:gsub("\002", "[^/]*")

	return pattern
end

function _M.fill(ctx,env)
	local root = server_config.files
	
	local basedir = env.QUERY.path or ''
	while basedir:sub(1,1) == '/' do
		basedir = string.sub(basedir,2)
	end
	print('root:',root,'basedir:',basedir)
	if basedir ~= '' then
		root = path.join(root,basedir)
	end
	local mask = env.QUERY.mask or '*.*'
	local wildcard = path.join(root , "*")

	local path_list = { {name='root', path=''} }
	if true then
		local d = basedir
		local n
		while d and d~='/' and d~='' do
			d,n = path.getdirectory_and_name(d)
			if d and d~='/' and d~='' then	
				table.insert(path_list,2,{name=n,path=path.join(d,n)})
			else
				table.insert(path_list,2,{name=n,path=path.join(n)})
			end
		end
	end

	local files = {}
	local folders = {}

	print('find at',wildcard,mask)

	mask = wildcards(mask)

	-- retrieve files from OS and test against mask
	local m = os.matchstart(wildcard)
	while os.matchnext(m) do
		local fname = os.matchname(m)
		print(fname)
		local isfile = os.matchisfile(m)
		if not string.startswith(fname, ".") then
			if isfile then
				if fname:match(mask) == fname then
					table.insert(files, fname)
				end
			else
				table.insert(folders, fname)
			end
		end
	end
	os.matchdone(m)

	ctx.path_list = path_list
	ctx.basedir = basedir
	ctx.folders = folders
	ctx.files = files
	ctx.path = path
end

return _M