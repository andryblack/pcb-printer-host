
local llae = require 'extlib/llae/premake/llae'
llae.root = 'extlib/llae'

solution 'pcb-printer'
	configurations { 'debug', 'release' }
	language 'c++'
	objdir 'build' 
	location 'build'
	targetdir 'bin'
	cppdialect "C++11"

	configuration{ 'debug'}
		symbols "On"
	configuration{ 'release'}
		optimize "On"
	configuration{}

	llae.lib()

	project 'clipperlib'
		kind 'StaticLib'
		targetdir 'lib'
		buildoptions{ 
			llae.pkgconfig('lua-5.3','cflags'),
		}
		linkoptions { 
			llae.pkgconfig('lua-5.3','libs'),
		}
		files {
			path.join('src/clipperlib','clipper*.cpp'),
			path.join('src/clipperlib','clipper*.h')
		}

	project 'pcb-printer'
		kind 'ConsoleApp'
		includedirs {
			'src',
			'extlib/llae/src'
		}
		llae.link()
		buildoptions{ 
			llae.pkgconfig('libpng','cflags'),
			llae.pkgconfig('lua-5.3','cflags'),
			llae.pkgconfig('libuv','cflags'),
		}
		
		linkoptions { 
			llae.pkgconfig('libpng','libs'),
		}
		links {
			'clipperlib',
		}
		files {
			'src/serial.*',
			'src/main.cpp',
			'src/clipper_uv.cpp',
			'src/rasterizator.cpp',
			'src/rasterizator_write.cpp',
			'src/*.h',
			'src/camera/*.h',
			'src/camera/*.cpp'
		}
		if os.istarget('macosx') then
			
			files {
				path.join('src/camera/osx','*.mm'),
				path.join('src/camera/osx','*.h')
			}
			links {
				'ImageIO.framework',
				'CoreGraphics.framework',
				'CoreMedia.framework',
				'CoreVideo.framework',
				'AVFoundation.framework',
				'Foundation.framework'
			}
		elseif os.istarget('linux') then
			includedirs{'$(STAGING_DIR)/opt/vc/include'}
			files {
				path.join('src/camera/linux','*.cpp'),
				path.join('src/camera/linux','*.h')
			}
			libdirs { '$(STAGING_DIR)/opt/vc/lib' }
			links {
				'bcm_host','vcos','openmaxil'
			}
		end
	
