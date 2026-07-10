project 'pcb-printer-host'

-- @modules@
module 'llae'
module 'libpng'

-- @lock@
lock_module{"llae","93884b3996abc71cc183e2406390552b9abbc721"}
-- @endlock@

config('llae','extern_main',true)

cmodule 'clipperlib'
cmodule 'rasterizator'
cmodule 'camera'

premake{
	project = [[
		files{
			<%= format_file('src','*.cpp')%>,
			<%= format_file('src','*.h')%>,

			<%= format_file('src/clipperlib','*.cpp')%>,
			<%= format_file('src/clipperlib','*.h')%>,

			<%= format_file('src/camera','*.cpp')%>,
			<%= format_file('src/camera','*.h')%>,
		}
		filter{'system:linux'}
		files {
			<%= format_file('src/camera/linux','*.cpp')%>,
			<%= format_file('src/camera/linux','*.h')%>,
		}
		filter{'system:macosx'}
		files {
			<%= format_file('src/camera/osx','*.cpp')%>,
			<%= format_file('src/camera/osx','*.mm')%>,
			<%= format_file('src/camera/osx','*.h')%>,
		}
		links {
			'ImageIO.framework',
			'CoreGraphics.framework',
			'CoreMedia.framework',
			'CoreVideo.framework',
			'AVFoundation.framework',
			'Foundation.framework',
			'VideoToolbox.framework'
		}
		filter{}
	]]
}