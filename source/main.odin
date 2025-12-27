package main

import "base:runtime"
// import "core:image/png"
import "core:log"
import "core:math/linalg"
import "core:os"
// import "core:slice"
import "web"
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"
import sshape "sokol/shape"

_ :: web 
_ :: os

IS_WEB :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32
Mat4 :: matrix[4,4]f32
Vec3 :: [3]f32

SMP_smp :: 0

Shape :: struct {
	pos: Vec3,
	draw: sshape.Element_Range,
}

state: struct {
	pass_action: sg.Pass_Action,
	pip: sg.Pipeline,
	bind: sg.Bindings,
	shape: Shape,
	rx, ry: f32,
}

custom_context: runtime.Context

Vertex :: struct {
	x, y, z: f32,
	color: u32,
	u, v: u16,
}



// vertices: [6 * 1024]sshape.Vertex
// indices: [16 * 1024]u16
vertices: [12 * 1024]sshape.Vertex
indices: [32 * 1024]u16

main :: proc() {
	when IS_WEB {
		// The WASM allocator doesn't seem to work properly in combination with
		// emscripten. There is some kind of conflict with how they manage
		// memory. So this sets up an allocator that uses emscripten's malloc.
		context.allocator = web.emscripten_allocator()

		// Make temp allocator use new `context.allocator` by re-initing it.
		runtime.init_global_temporary_allocator(1*runtime.Megabyte)
	}

	context.logger = log.create_console_logger(lowest = .Info, opt = {.Level, .Short_File_Path, .Line, .Procedure})
	custom_context = context
	
	sapp.run({
		init_cb = init,
		frame_cb = frame,
		cleanup_cb = cleanup,
		width = 1280,
		height = 720,
		sample_count = 4,
		window_title = IS_WEB ? "Marballers" : "Non-Web Marballers",
		icon = { sokol_default = true },
		logger = { func = slog.func },
		html5_update_document_title = true,
	})
}

init :: proc "c" () {
	context = custom_context
	sg.setup({
		environment = sglue.environment(),
		logger = { func = slog.func },
	})

	//
	// add sphere
	// 

	state.shape.pos = {0.0, 0.0, 0.0}
	
    buf := sshape.Buffer {
        vertices = { buffer = { ptr = &vertices, size = size_of(vertices) } },
        indices  = { buffer = { ptr = &indices, size = size_of(indices) } },
    }

	buf = sshape.build_sphere(buf, {
        radius = 0.75,
        slices = 72,
        stacks = 40,
        random_colors = true,
    })
    state.shape.draw = sshape.element_range(buf)

	state.bind.vertex_buffers[0] = sg.make_buffer(sshape.vertex_buffer_desc(buf))
	state.bind.index_buffer      = sg.make_buffer(sshape.index_buffer_desc(buf))

    // shader and pipeline object for sphere
    state.pip = sg.make_pipeline({
        shader = sg.make_shader(shapes_shader_desc(sg.query_backend())),
        layout = {
            buffers = {
                0 = sshape.vertex_buffer_layout_state(),
            },
            attrs = {
                ATTR_shapes_position = sshape.position_vertex_attr_state(),
                ATTR_shapes_normal   = sshape.normal_vertex_attr_state(),
                ATTR_shapes_texcoord = sshape.texcoord_vertex_attr_state(),
                ATTR_shapes_color0   = sshape.color_vertex_attr_state(),
            },
        },
        index_type = .UINT16,
        cull_mode = .NONE,
        depth = {
            compare = .LESS_EQUAL,
            write_enabled = true,
        },
    })


	// default pass action, clear to blue-ish
	state.pass_action = {
		colors = {
			0 = { load_action = .CLEAR, clear_value = { 0.11, 0.28, 0.53, 1 } },
		},
	}
}

frame :: proc "c" () {
	context = custom_context
	dt := f32(sapp.frame_duration())
	state.rx += 60.0 * dt
	state.ry += 120.0 * dt

	// 
	// calculate world camera and world objects
	//
	// calculating mat4 of camera lens with 60deg FOV, 0.01 to 10.0 depth range
	proj := linalg.matrix4_perspective(60.0 * linalg.RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 10.0)
	// camera transform, transforms world to camera space
	view := linalg.matrix4_look_at_f32({0.0, -1.5, -6.0}, {}, {0.0, 1.0, 0.0})
	// combines to go from world to clip space
	// view_proj := proj * view

	// applying rotations
	rxm := linalg.matrix4_rotate_f32(state.rx * linalg.RAD_PER_DEG, {1.0, 0.0, 0.0})
	rym := linalg.matrix4_rotate_f32(state.ry * linalg.RAD_PER_DEG, {0.0, 1.0, 0.0})

	model := rxm * rym

	// sending params
	vs_params := Vs_Params {
		proj = proj,
		view = view,
		model = model,
	}

	sg.begin_pass({ action = state.pass_action, swapchain = sglue.swapchain() })
	sg.apply_pipeline(state.pip)
	sg.apply_bindings(state.bind)
	sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })

	// draw sphere
	sg.draw(int(state.shape.draw.base_element), int(state.shape.draw.num_elements), 1)

	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
}

cleanup :: proc "c" () {
	context = custom_context
	sg.shutdown()

	// This is "the end of the program": sokol is shutting down. When on web
	// there is no definitive point to run all procs tagged with @(fini). This
	// will run those procedures now.
	when IS_WEB {
		runtime._cleanup_runtime()
	}
}

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