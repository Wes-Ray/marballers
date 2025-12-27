@header package main
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
    float draw_mode;
    mat4 proj;
    mat4 view;
    mat4 model;
};

in vec4 position;
in vec3 normal;
in vec2 texcoord;
in vec4 color0;

out vec4 color;

void main() {
    vec4 world_pos = model * position;
    vec4 view_pos  = view  * world_pos;
    gl_Position    = proj  * view_pos;

    mat3 normal_mtx = mat3(model);
    vec3 model_normal = normalize(normal);
    vec3 world_normal = normalize(normal_mtx * normal);


    vec3 light_color = vec3(1.0, 1.0, 1.0);

    // ambient lighting
    float ambient_base = 0.05;
    vec3 ambient = vec3(ambient_base, ambient_base, ambient_base);

    //
    // diffuse lighting
    //
    vec3 light_dir = normalize(vec3(-.7, 1.0, -1.0));
    float diffuse_strength = max(0.0, dot(world_normal, light_dir));
    vec3 diffuse = diffuse_strength * light_color;

    //
    // specular lighting
    //
    vec3 camera_pos = vec3(1.0, -1.0, 0.2);
    vec3 camera_pos_normalized = normalize(camera_pos);
    vec3 reflect_pos = normalize(reflect(world_normal, -light_dir));
    float specular_strength = max(0.0, dot(camera_pos_normalized, reflect_pos));
    specular_strength = pow(specular_strength, 256.0);
    vec3 specular = specular_strength * light_color;

    //
    // split base color in two regions based on normal
    //
    vec3 color1 = vec3(0.9, 0.9, 0.9);
    vec3 color2 = vec3(0.2, 0.7, 0.2);

    vec3 base = (model_normal.y > 0.0) ? color1 : color2;
    // vec3 base = vec3(0.7, 0.7, 0.7);

    // combine lighting
    vec3 lighting = vec3(0.0, 0.0, 0.0);
    lighting = ambient + diffuse + specular;

    vec3 base_with_lighting = base * lighting;
    color = vec4(base_with_lighting, 1.0);
}
@end


//
// all of this is just for sampling texture, 
// leaving this now so the main.odin code compiles
//
@block fs_params
uniform fs_params {
    vec3 light_dir;
    float ambient;
};
@end

@fs fs
in vec4 color;
out vec4 frag_color;

void main() {
    frag_color = color;
}
@end

@program shapes vs fs
