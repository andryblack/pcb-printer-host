
local llae = require 'llae'

function os.isdir(path)
	local s,err = llae.file.stat(path)
	return s and s.isdir
end

function os.mkdir(path)
	local s,err = llae.file.mkdir(path)
	print('os.mkdir',s,err)
	return s,err
end