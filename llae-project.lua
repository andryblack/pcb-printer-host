project 'pcb-printer-host'

-- @modules@
module 'llae'
module 'libpng'
module 'git://github.com/andryblack/gerber-parser.git;proto=https'

-- @lock@
-- @endlock@

config('llae','extern_main',true)

cmodule 'rasterizator'
cmodule 'camera'

premake{
	project = [[
		includedirs{
			'include'
		}
		files{
			<%= format_file('src','*.cpp')%>,
			<%= format_file('src','*.h')%>,

			
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