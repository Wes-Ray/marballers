// adapted from https://github.com/Pawel82S/glTF2/blob/master/gltf.odin

package main

import "core:encoding/json"
import "core:log"
import "core:mem"

GLB_MAGIC :: 0x46546c67
GLB_HEADER_SIZE :: size_of(GLB_Header)
GLB_CHUNK_HEADER_SIZE :: size_of(GLB_Chunk_Header)
GLTF_MIN_VERSION :: 2

CHUNK_TYPE_JSON :: 0x4e4f534a
CHUNK_TYPE_BIN :: 0x004e4942

MESHES_KEY :: "meshes"
BUFFERS_KEY :: "buffers"
BUFFER_VIEWS_KEY :: "bufferViews"
ACCESSORS_KEY :: "accessors"

GLB_Header :: struct {
    magic, version, length: u32le,
}

GLB_Chunk_Header :: struct {
    length, type: u32le,
}

GLB_Data :: struct {
    json_value:         json.Value,
    accessors:          []Accessor,            
    meshes:             []Mesh,
    buffers:            []Buffer,
    buffer_views:       []Buffer_View,
}

Accessor :: struct {
    byte_offset:        u32,
    component_type:     Component_Type,
    count:              u32,
    type:               Accessor_Type,
    buffer_view:        Maybe(u32),
}

Component_Type :: enum u16 {
    Byte = 5120,
    Unsigned_Byte,
    Short,
    Unsigned_Short,
    Unsigned_Int = 5125,
    Float,
}

Accessor_Type :: enum {
    Scalar,
    Vector2,
    Vector3,
    Vector4,
    Matrix2,
    Matrix3,
    Matrix4,
}

Mesh :: struct {
    primitives: []Mesh_Primitive,
    weights:    []f32,
    name:       Maybe(string),
    // extensions: Extensions,
    // extras:     Extras,
}

Mesh_Primitive :: struct {
    attributes:        map[string]u32, // Required
    mode:              Mesh_Primitive_Mode, // Default Triangles(4)
    indices, material: Maybe(u32),
    // targets:           []Mesh_Target,
    // extensions:        Extensions,
    // extras:            Extras,
}

Mesh_Primitive_Mode :: enum {
    Points,
    Lines,
    Line_Loop,
    Line_Strip,
    Triangles, // Default
    Triangle_Strip,
    Triangle_Fan,
}

Buffer :: struct {
    byte_length: u32,
    name:        Maybe(string),
    uri:         Uri,
    // extensions:  Extensions,
    // extras:      Extras,
}

Uri :: union {
    string,
    []byte,
}

Buffer_View :: struct {
    buffer, byte_offset, byte_length: u32,
    // byte_stride:                      Maybe(Integer),
    // target:                           Maybe(Buffer_Type_Hint),
    // name:                             Maybe(string),
    // extensions:                       Extensions,
    // extras:                           Extras,  
}

unload_glb_data :: proc(data: ^GLB_Data) {
    if data == nil {
        return
    }

    json.destroy_value(data.json_value)
    // TODO: free meshes
    free(data)
}

read_gltf :: proc (filepath: string) -> (data: ^GLB_Data, success: bool) {
    context = custom_context

    log.infof("reading gltf at '%s'\n", filepath)

    data = new(GLB_Data)
    defer if success != true {
        unload_glb_data(data)
    }

    file, ok := read_entire_file(filepath, context.temp_allocator)
    if !ok do return nil, false

    offset: u32
    header := (cast(^GLB_Header)(raw_data(file[:GLB_HEADER_SIZE])))
    offset += GLB_HEADER_SIZE

    // headers
    {
        if header.magic != GLB_MAGIC {
            log.errorf("glb magic header mismatch: %H\n", header.magic)
            return nil, false
        }
        if header.version < GLTF_MIN_VERSION {
            log.errorf("reading gltf version too low, expected '%d', got '%d'", GLTF_MIN_VERSION, header.version)
            return nil, false
        }

        // GLB file format expects 1 JSON chunk right after header
        json_header := (cast(^GLB_Chunk_Header)(raw_data(file[offset:offset + GLB_CHUNK_HEADER_SIZE])))
        if json_header.type != CHUNK_TYPE_JSON {
            log.errorf("first chunk not json type: %d", json_header.type)
            return nil, false
        }

        offset += GLB_CHUNK_HEADER_SIZE
        json_data := file[offset:offset + u32(json_header.length)]
        offset += u32(json_header.length)

        json_parser := json.make_parser(json_data)
        parsed_object, json_err := json.parse_object(&json_parser)
        if json_err != .None && json_err != .EOF {
            log.errorf("json error reading gltf: %v", json_err)
            return nil, false
        }
        data.json_value = parsed_object
    }
    
    object := data.json_value.(json.Object)

    // meshes
    {
        if MESHES_KEY not_in object {
            log.error("can't find meshes key in gltf")
            return nil, false
        }

        meshes_array := object[MESHES_KEY].(json.Array)
        meshes := make([]Mesh, len(meshes_array))

        for mesh, i in meshes_array {
            for k, v in mesh.(json.Object) {
                switch k {
                case "name":
                    meshes[i].name = v.(string)
                case "primitives":
                    meshes[i].primitives = mesh_primitives_parse(v.(json.Array)) or_return
                case "weights":
                    meshes[i].weights = make([]f32, len(v.(json.Array)))
                    for num, i2 in v.(json.Array) {
                        meshes[i].weights[i2] = f32(num.(f64))
                    }
                case:
                    log.errorf("unexpected data in mesh parsing: %v, %v, %v", k, v, i)
                    return nil, false
                }
            }
        }

        data.meshes = meshes
    }

    // accessor
    {
        if ACCESSORS_KEY not_in object {
            log.error("can't find accessors key in gltf")
            return nil, false
        }

        accessors_array := object[ACCESSORS_KEY].(json.Array)
        accessors := make([]Accessor, len(accessors_array))

        for access, i in accessors_array {
            component_type_set, count_set, type_set: bool

            for k, v in access.(json.Object) {
                switch k {
                case "bufferView":
                    accessors[i].buffer_view = u32(v.(f64))
                case "byteOffset":
                    accessors[i].byte_offset = u32(v.(f64))
                case "componentType":
                    accessors[i].component_type = Component_Type(v.(f64))
                    component_type_set = true
                case "normalized":
                    // not implemented
                case "count":
                    accessors[i].count = u32(v.(f64))
                    count_set = true
                case "type":
                    switch v.(string) {
                    case "SCALAR":
                        accessors[i].type = .Scalar
                        type_set = true
                    case "VEC2":
                        accessors[i].type = .Vector2
                        type_set = true
                    case "VEC3":
                        accessors[i].type = .Vector3
                        type_set = true
                    case "VEC4":
                        accessors[i].type = .Vector4
                        type_set = true
                    case "MAT2":
                        accessors[i].type = .Matrix2
                    case "MAT3":
                        accessors[i].type = .Matrix3
                    case "MAT4":
                        accessors[i].type = .Matrix4
                    case:
                        log.error("unexpected type when parsing accessor type")
                        return nil, false
                    }
                case "max", "min", "sparse", "name", "extensions", "extras":
                    // not implemented
                case:
                    log.error("parsing got unexpected accessor value: %v, %v, %v", k, v, i)
                    return nil, false
                }
            }

            if !component_type_set {
                log.error("no component type set when parsing gltf")
                return nil, false
            }
            if !count_set {
                log.error("no count set when parsing gltf")
                return nil, false
            }
            if !type_set {
                log.error("no type set when parsing gltf")
                return nil, false
            }
        }

        data.accessors = accessors
    }

    // buffers
    {
        if BUFFERS_KEY not_in object {
            log.error("can't find buffers key in object")
            return nil, false
        }

        bufs_array := object[BUFFERS_KEY].(json.Array)
        bufs := make([]Buffer, len(bufs_array))

        for b, i in bufs_array {
            byte_length_set: bool
            for k, v in b.(json.Object) {
                switch k {
                case "byteLength":
                    bufs[i].byte_length = u32(v.(f64))
                    byte_length_set = true
                case "name":
                    bufs[i].name = v.(string)
                case "uri", "extensions", "extras":
                    // not implemented
                case:
                    log.errorf("unexpected data in buffer parsing: %v, %v, %v", k, v, i)
                }
            }

            if !byte_length_set {
                log.errorf("missing byte length param when parsing buffer: %v", i)
                return nil, false
            }
        }

        data.buffers = bufs

        // Load remaining binary chunks from glb
        for buf_idx := 0; buf_idx < len(data.buffers) && int(offset) < len(file); buf_idx += 1 {
            chunk_header := (cast(^GLB_Chunk_Header)(raw_data(file[offset:offset + GLB_CHUNK_HEADER_SIZE])))
            offset += GLB_CHUNK_HEADER_SIZE

            data.buffers[buf_idx].uri = make([]byte, chunk_header.length)
            mem.copy(raw_data(data.buffers[buf_idx].uri.([]byte)), raw_data(file[offset:]), int(chunk_header.length))
            offset += u32(chunk_header.length)
            log.errorf("mem copies bin data: %d", offset)
        }
    }

    // buffer views
    {
        if BUFFER_VIEWS_KEY not_in object {
            log.error("buffer views key not found in object")
            return nil, false
        }

        views_array := object[BUFFER_VIEWS_KEY].(json.Array)
        res_views := make([]Buffer_View, len(views_array))

        buffer_set, byte_length_set: bool
        for view, i in views_array {

            for k, v in view.(json.Object) {
                switch k {
                case "buffer":
                    res_views[i].buffer = u32(v.(f64))
                    buffer_set = true
                case "byteLength":
                    res_views[i].byte_length = u32(v.(f64))
                    byte_length_set = true
                case "byteOffset":
                    res_views[i].byte_offset = u32(v.(f64))
                case "byteStride", "name", "target", "extensions", "extras":
                    // not implemented
                case:
                    log.errorf("unexpected data in buffer view parsing: %v, %v, %v", k, v, i)
                    return nil, false
                }
            }
        }

        if !buffer_set {
            log.errorf("buffer not set when parsing buffer view")
            return nil, false
        }
        if !byte_length_set {
            log.errorf("byte length not set when parsing buffer view")
            return nil, false
        }

        data.buffer_views = res_views
    }


    log.infof("json: %s\n", data.json_value)

    log.infof("printing meshes\n")
    for m, i in data.meshes {
        log.infof("[%d] %v", i, m)
        for p, i2 in m.primitives {
            log.infof("\t[%d] %v", i2, p)
        }
    }

    for b, i in data.buffers{
        log.infof("buf[%d] %s len(%d)", i, b.name, b.byte_length)
    }

    return data, true
}

mesh_primitives_parse :: proc(arr: json.Array) -> (res: []Mesh_Primitive, success: bool) {
    res = make([]Mesh_Primitive, len(arr))

    for prim, idx in arr {
        res[idx].mode = .Triangles

        for k, v in prim.(json.Object) {
            switch k {
            case "attributes":
                res[idx].attributes = make(map[string]u32)
                for k2, v2 in v.(json.Object) {
                    res[idx].attributes[k2] = u32(v2.(f64))
                }
            case "indices":
                res[idx].indices = u32(v.(f64))
            case "material":
                res[idx].material = u32(v.(f64))
            case "mode":
                res[idx].mode = Mesh_Primitive_Mode(v.(f64))
            case "targets", "extensions", "extras":
                // do nothing for now
            case:
                log.errorf("unexpected data in mesh primitive parsing: %v, %v, %v", k, v, idx)
                return nil, false
            }
        }
    }

    return res, true
}

// TODO: free buffers
// TODO: free primitives (and attributes map within that)
// TODO: free meshes
// TODO: free buffer views
