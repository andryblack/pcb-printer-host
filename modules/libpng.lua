name = 'libpng'
version = '1.6.40'
archive = 'libpng-' .. version .. '.tar.gz'
url = 'https://deac-riga.dl.sourceforge.net/project/libpng/libpng16/'..version..'/' .. archive
hash = 'ec4b597c3a9b1f8d2826575f530367b7'
dir = name .. '-' .. version

function install()
	download(url,archive,hash)

	unpack_tgz(archive)

	preprocess{
		src = dir .. '/scripts/pnglibconf.h.prebuilt',
		dst = 'build/include/pnglibconf.h',
		comment = {
			['PNG_STDIO_SUPPORTED'] = true,
			['PNG_SIMPLIFIED_WRITE_STDIO_SUPPORTED'] = true,
			['PNG_CONSOLE_IO_SUPPORTED'] = true,
			['PNG_SIMPLIFIED_READ_SUPPORTED'] = true,
			['PNG_SIMPLIFIED_WRITE_SUPPORTED'] = true,
			['PNG_SETJMP_SUPPORTED'] = true,
		}
	}
	move_files{
		['build/include/png.h'] = 		dir..'/png.h',
		['build/include/pngconf.h'] = 	dir..'/pngconf.h',
	}
end

dependencies = {
	'zlib'
}

build_lib = {


	components = {
			'png','pngmem','pngerror','pngset','pngwrite','pngwutil','pngwio','pngwtran','pngtrans',
			'pngrio','pngrtran','pngrutil','pngpread','pngget','pngread'
	},
	project = [[
		includedirs {
			'include'
		}
		files {
			<% for _,f in ipairs(lib.components) do %>
				<%= format_file(module.dir,f .. '.c') %>,<% end %>
		}
		defines      { "Z_HAVE_UNISTD_H" , "PNG_ARM_NEON_OPT=0" }
]]
}
