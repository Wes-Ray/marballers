package main

import "base:runtime"
import "core:log"
import "web"
import sdtx "sokol/debugtext"
import sapp "sokol/app"
import sg "sokol/gfx"
import sglue "sokol/glue"
import slog "sokol/log"
import sshape "sokol/shape"

IS_WEB :: ODIN_ARCH == .wasm32 || ODIN_ARCH == .wasm64p32

SMP_smp :: 0

FONT_KC854 :: 0
FONT_C64   :: 1
FONT_ORIC  :: 2
NUM_FONTS  :: 3

MOUSE_SENSITIVITY: f32 = 1.0
MOUSE_SENSITIVITY_MULTIPLIER: f32 = 0.4
MOUSE_PITCH_MAX_ANGLE: f32 = 55.0

Shape :: struct {
	pos: Vec3,
	draw: sshape.Element_Range,
}

state: struct {
	pass_action: 			sg.Pass_Action,
	pipeline: 				sg.Pipeline,
	bind: 					sg.Bindings,
	marble_shape: 			Shape,
	level_shape: 			Shape,
	rx, ry: 				f32,
	input_mouse_left_down:	bool,
	input_mouse_dx: 		f32,
	input_mouse_dy: 		f32,
	input_left: 			bool,
	input_right: 			bool,
	input_up: 				bool,
	input_down: 			bool,
	camera_yaw: 			f32,
	camera_pitch: 			f32,
}

custom_context: runtime.Context

Vertex :: struct {
	x, y, z: f32,
	color: u32,
	u, v: u16,
}

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
		event_cb = event,
		cleanup_cb = cleanup,
		width = 1280,
		height = 720,
		sample_count = 4,
		window_title = IS_WEB ? "Marballers" : "Non-Web Marballers",
		icon = { sokol_default = true },  // favicon
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

    sdtx.setup({
        fonts = {
            FONT_KC854 = sdtx.font_kc854(),
            FONT_C64 = sdtx.font_c64(),
            FONT_ORIC = sdtx.font_oric(),
        },
        logger = { func = slog.func },
    })

	sdtx.canvas(sapp.widthf() * 0.5, sapp.heightf() * 0.5)
	sdtx.origin(1.0, 3.0)
	sdtx.font(FONT_KC854)
	sdtx.color3f(1, 1, 1)

	//
	// load gltf
	//
	level, ok := read_gltf("assets/box2.glb")
	// _, ok := read_gltf("assets/box_ref.glb.json")
	log.infof("gltf read status: %t\n", ok)

	if ok && len(level.meshes) > 0 {
        log.error("--- DEBUGGING GEOMETRY ---")
        
        // 1. Get the first Primitive of the first Mesh
        mesh := level.meshes[0]
        prim := mesh.primitives[0]
        
        // 2. Find the accessor index for POSITION
        if "POSITION" in prim.attributes {
            acc_idx := prim.attributes["POSITION"]
            accessor := level.accessors[acc_idx]
            
            // 3. Get the BufferView and Buffer
            // Note: In a robust loader, check for nil on buffer_view
            view_idx := accessor.buffer_view.?
            view := level.buffer_views[view_idx]
            buffer := level.buffers[view.buffer]
            
            // 4. Calculate the pointer to the data
            // Access the []byte stored in the URI (which your loader uses for the binary body)
            bin_data := buffer.uri.([]byte) 
            base_ptr := raw_data(bin_data)
            
            // Total Offset = View Offset + Accessor Offset
            total_offset := uintptr(view.byte_offset) + uintptr(accessor.byte_offset)
            data_ptr := uintptr(base_ptr) + total_offset
            
            // 5. Cast to float array and print first 3 vertices
            floats := ([^]f32)(data_ptr)
            
            log.infof("Accessor Count: %d", accessor.count)
            log.infof("Vertex 0: %f, %f, %f", floats[0], floats[1], floats[2])
            log.infof("Vertex 1: %f, %f, %f", floats[3], floats[4], floats[5])
            log.infof("Vertex 2: %f, %f, %f", floats[6], floats[7], floats[8])
        }
    }

	//
	// add cube practice
	//

	// see sokol-odin\examples\shapes\main.odin for how to apply position per frame
	// need to port the math library as well
	state.level_shape.pos = {-5.0, -5.0, -2.0}

	buf := sshape.Buffer {
		vertices = { buffer = { ptr = &vertices, size = size_of(vertices) } },
		indices = { buffer = { ptr = &indices, size = size_of(indices) } },
	}

	buf = sshape.build_box(buf, {
		width = 0.5,
		height = 3.5,
		depth = 0.5,
		random_colors = true,
	})

	state.level_shape.draw = sshape.element_range(buf)

	//
	// add sphere
	// 

	// see sokol-odin\examples\shapes\main.odin for how to apply positions
	state.marble_shape.pos = {0.0, 0.0, 0.0}
	
	buf = sshape.build_sphere(buf, {
        radius = 0.75,
        slices = 72,
        stacks = 40,
        random_colors = true,
    })
    state.marble_shape.draw = sshape.element_range(buf)

	state.bind.vertex_buffers[0] = sg.make_buffer(sshape.vertex_buffer_desc(buf))
	state.bind.index_buffer      = sg.make_buffer(sshape.index_buffer_desc(buf))

    // shader and pipeline object loading
    state.pipeline = sg.make_pipeline({
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

event :: proc "c" (e: ^sapp.Event) {
	context = custom_context

	// mouse
	{
		if e.type == .MOUSE_DOWN && e.mouse_button == .LEFT {
			state.input_mouse_left_down = true
		}

		if e.type == .MOUSE_UP && e.mouse_button == .LEFT {
			state.input_mouse_left_down = false
		}

		if e.type == .MOUSE_MOVE {
			state.input_mouse_dx = e.mouse_dx
			state.input_mouse_dy = e.mouse_dy
		}
	}

	// keys
	{
		// TODO: refactor to wait until key up? can maybe use .KEY_UP but need to figure out why
		// it is already setting to false with each frame
		if e.type == .KEY_DOWN && e.key_code == .A {
			state.input_left = true
		}
		// } else {
		// 	state.input_left = false
		// }

		if e.type == .KEY_DOWN && e.key_code == .D {
			state.input_right = true
		}

		if e.type == .KEY_DOWN && e.key_code == .W {
			state.input_up = true
		}

		if e.type == .KEY_DOWN && e.key_code == .S {
			state.input_down = true
		}
	}
}

frame :: proc "c" () {
	context = custom_context
	dt := f32(sapp.frame_duration())

	// debug text
	sdtx.printf("DEBUG\n")

	// TODO: refactor so user inputs at least once first
	// browser has that as a promise. Could just be done with
	// a main menu
	if !sapp.mouse_locked() {
		sapp.lock_mouse(true)
	}
	sdtx.printf("MOUSE LOCK: %t\n", sapp.mouse_locked())

	// apply inputs from state (which is updated by events)
	camera_rotation_input := Vec2{}
	if sapp.mouse_locked() {
		if state.input_mouse_left_down {
			sdtx.printf("left mouse DOWN\n")
		} else {
			sdtx.printf("left mouse up\n")
		}

		// mouse movement input
		sdtx.printf("mouse move: (%v, %v)\n", state.input_mouse_dx, state.input_mouse_dy)
		camera_rotation_input.x = state.input_mouse_dx * MOUSE_SENSITIVITY * MOUSE_SENSITIVITY_MULTIPLIER
		camera_rotation_input.y = state.input_mouse_dy * MOUSE_SENSITIVITY * MOUSE_SENSITIVITY_MULTIPLIER

		state.input_mouse_dx = 0.0
    	state.input_mouse_dy = 0.0

		// sdtx.printf("INPUT:")
		// if state.input_left {
		// 	sdtx.printf(" left")
		// 	// camera_rotation_input.x = 1.0
		// 	sapp.lock_mouse(true)
		// } 

		// if state.input_right {
		// 	sdtx.printf(" right")
		// 	sapp.lock_mouse(false)
		// 	// camera_rotation_input.x = -1.0
		// } 

		// if state.input_up {
		// 	sdtx.printf(" up")
		// 	camera_rotation_input.y = 1.0
		// } 

		// if state.input_down {
		// 	sdtx.printf(" down")
		// 	camera_rotation_input.y = -1.0
		// }
		// sdtx.printf("\n")
	}

	// update camera rotation state (not the actual camera view)
	{
		sdtx.printf("camera_rotation_input: (%f, %f)\n", camera_rotation_input.x, camera_rotation_input.y)
		// TODO: add dt
		state.camera_yaw += camera_rotation_input.x
		state.camera_pitch -= camera_rotation_input.y
		if state.camera_yaw >= 360.0 {
			state.camera_yaw = 0.0
		}
		if state.camera_yaw <= -360.0 {
			state.camera_yaw = 0.0
		}
		state.camera_pitch = clamp(state.camera_pitch, -MOUSE_PITCH_MAX_ANGLE, MOUSE_PITCH_MAX_ANGLE)
		sdtx.printf("roll, pitch: (%f, %f)\n", state.camera_yaw, state.camera_pitch)
	}

	// camera transforms
	proj: Mat4
	view: Mat4
	{
		// calculating mat4 of camera lens with 60deg FOV, 0.01 to 10.0 depth range
		proj = perspective_mat4(60.0 * RAD_PER_DEG, sapp.widthf() / sapp.heightf(), 0.01, 10.0)

		// camera transform, transforms world to camera space
		view = lookat_mat4({0.0, -1.5, -6.0}, {}, WORLD_UP)

		// spin camera left/right
		yaw := rotate_mat4(state.camera_yaw * RAD_PER_DEG, WORLD_UP)

		// spin camera up/down
		pitch := rotate_mat4(state.camera_pitch * RAD_PER_DEG, {1.0, 0.0, 0.0})

		view = view * pitch * yaw
	}

	// world transforms
	model: Mat4
	{
		// applying rotation to object
		state.rx += 60.0 * dt
		state.ry += 120.0 * dt
		// applying rotations to sphere
		// rxm := rotate_mat4(state.rx * RAD_PER_DEG, {1.0, 0.0, 0.0})
		// rym := rotate_mat4(state.ry * RAD_PER_DEG, {0.0, 1.0, 0.0})
		rxm := rotate_mat4(1.0 * RAD_PER_DEG, {1.0, 0.0, 0.0})
		rym := rotate_mat4(1.0 * RAD_PER_DEG, {0.0, 1.0, 0.0})
		model = rxm * rym
		// model := Mat4{}

		// TODO: need to send multiple different models to gpu somehow?
		
	}

	shapes: [2]Shape
	shapes[0] = state.level_shape
	shapes[1] = state.marble_shape

	// send gfx to gpu, apply and end frame
	sg.begin_pass({ action = state.pass_action, swapchain = sglue.swapchain() })

	// sending params
	vs_params := Vs_Params {
		proj = proj,
		view = view,
		model = model,
	}
	
	for s in shapes {
		// 3d draw
		sg.apply_pipeline(state.pipeline)
		sg.apply_bindings(state.bind)
		sg.apply_uniforms(UB_vs_params, { ptr = &vs_params, size = size_of(vs_params) })

		// draw objects
		// sg.draw(int(state.marble_shape.draw.base_element), int(state.marble_shape.draw.num_elements), 1)
		// sg.draw(int(state.level_shape.draw.base_element), int(state.level_shape.draw.num_elements), 1)
		sg.draw(int(s.draw.base_element), int(s.draw.num_elements), 1)
	}

	// commit graphics and debug text
	sdtx.draw()
	sg.end_pass()
	sg.commit()

	free_all(context.temp_allocator)
}

cleanup :: proc "c" () {
	context = custom_context

	sdtx.shutdown()
	sg.shutdown()

	// This is "the end of the program": sokol is shutting down. When on web
	// there is no definitive point to run all procs tagged with @(fini). This
	// will run those procedures now.
	when IS_WEB {
		runtime._cleanup_runtime()
	}
}
