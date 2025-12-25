@header package main
@header import sg "sokol/gfx"
@ctype mat4 Mat4

@vs vs
layout(binding=0) uniform vs_params {
    float draw_mode;
    mat4 mvp;
};

in vec4 position;
in vec3 normal;
in vec2 texcoord;
in vec4 color0;

out vec4 color;

void main() {
    gl_Position = mvp * position;
    // if (draw_mode == 0.0) {
    //     color = vec4((normal + 1.0) * 0.5, 1.0);
    // }
    // else if (draw_mode == 1.0) {
    //     color = vec4(texcoord, 0.0, 1.0);
    // }
    // else {
    //     color = color0;
    // }

    vec3 N = normalize(normal);
    //vec3 base = (N.x > 0.0) ? vec3(1.0, 0.2, 0.2) : vec3(0.2, 0.4, 1.0);

    vec3 color1 = vec3(0.9, 0.9, 0.9);
    vec3 color2 = vec3(0.2, 0.7, 0.2);

    vec3 base = (N.x > 0.0) ? color1 : color2;

    color = vec4(base, 1.0);
}
@end

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
