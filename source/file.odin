package main

import "core:os"
import "web"

_ :: web 
_ :: os

// read and write files. Works with both desktop OS and also emscripten virtual
// file system.
@(require_results)
read_entire_file :: proc(name: string, allocator := context.allocator, loc := #caller_location) -> (data: []byte, success: bool) {
	when IS_WEB {
		return web.read_entire_file(name, allocator, loc)
	} else {
		return os.read_entire_file(name, allocator, loc)
	}
}

write_entire_file :: proc(name: string, data: []byte, truncate := true) -> (success: bool) {
	when IS_WEB {
		return web.write_entire_file(name, data, truncate)
	} else {
		return os.write_entire_file(name, data, truncate)
	}
}