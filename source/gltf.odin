// adapted from https://github.com/Pawel82S/glTF2/blob/master/gltf.odin

package main

import "core:encoding/json"
import "core:log"

GLB_MAGIC :: 0x46546c67
GLB_HEADER_SIZE :: size_of(GLB_Header)
GLB_CHUNK_HEADER_SIZE :: size_of(GLB_Chunk_Header)
GLTF_MIN_VERSION :: 2

CHUNK_TYPE_JSON :: 0x4e4f534a

GLB_Header :: struct {
    magic, version, length: u32le,
}

GLB_Chunk_Header :: struct {
    length, type: u32le,
}

GLB_Data :: struct {
    json_value:          json.Value,
    meshes:              []Mesh,
}

MESHES_KEY :: "meshes"

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

    //
    // headers
    //

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
    
    // meshes
    {
        object := data.json_value.(json.Object)
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


    // log.infof("json: %s\n", data.json_value)
    // log.errorf("primitive: %s\n", data.meshes)

    log.errorf("printing meshes\n")
    for m, i in data.meshes {
        log.infof("[%d] %v", i, m)
        for p, i2 in m.primitives {
            log.infof("\t[%d] %v", i2, p)
        }
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
