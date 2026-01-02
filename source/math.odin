//------------------------------------------------------------------------------
//  math.odin
//
//  The Odin glsl math package doesn't use the same conventions as
//  HandmadeMath in the original sokol samples, so just replicate
//  HandmadeMath to be consistent.
//------------------------------------------------------------------------------
package main

import math "core:math"

TAU :: 6.28318530717958647692528676655900576
PI  :: 3.14159265358979323846264338327950288

Vec2 :: [2]f32
Vec3 :: [3]f32
Mat4 :: matrix[4,4]f32

WORLD_UP :: Vec3{0.0, 1.0, 0.0}

radians :: proc (degrees: f32) -> f32 { return degrees * TAU / 360.0 }

dot_vec3 :: proc(v0, v1: Vec3) -> f32 { return v0.x*v1.x + v0.y*v1.y + v0.z*v1.z }

len_vec3 :: proc(v: Vec3) -> f32 { return math.sqrt(dot_vec3(v, v)) }

norm_vec3 :: proc(v: Vec3) -> Vec3 {
    l := len_vec3(v)
    if (l != 0) {
        return { v.x/l, v.y/l, v.z/l }
    } else {
        return {}
    }
}

cross_vec3 :: proc(v0, v1: Vec3) -> Vec3 {
    return {
        (v0.y * v1.z) - (v0.z * v1.y),
        (v0.z * v1.x) - (v0.x * v1.z),
        (v0.x * v1.y) - (v0.y * v1.x),
    }
}

identity_mat4 :: proc() -> Mat4 {
    m : Mat4 = {}
    m[0][0] = 1.0
    m[1][1] = 1.0
    m[2][2] = 1.0
    m[3][3] = 1.0
    return m
}

persp_mat4 :: proc(fov, aspect, near, far: f32) -> Mat4 {
    m := identity_mat4()
    t := math.tan(fov * (PI / 360))
    m[0][0] = 1.0 / t
    m[1][1] = aspect / t
    m[2][3] = -1.0
    m[2][2] = (near + far) / (near - far)
    m[3][2] = (2.0 * near * far) / (near - far)
    m[3][3] = 0
    return m
}

lookat_mat4 :: proc(eye, center, up: Vec3) -> Mat4 {
    m := Mat4 {}
    f := norm_vec3(center - eye)
    s := norm_vec3(cross_vec3(f, up))
    u := cross_vec3(s, f)

    m[0][0] = s.x
    m[0][1] = u.x
    m[0][2] = -f.x

    m[1][0] = s.y
    m[1][1] = u.y
    m[1][2] = -f.y

    m[2][0] = s.z
    m[2][1] = u.z
    m[2][2] = -f.z

    m[3][0] = -dot_vec3(s, eye)
    m[3][1] = -dot_vec3(u, eye)
    m[3][2] = dot_vec3(f, eye)
    m[3][3] = 1.0

    return m
}

rotate_mat4 :: proc (angle: f32, axis_unorm: Vec3) -> Mat4 {
    m := identity_mat4()

    axis := norm_vec3(axis_unorm)
    sin_theta := math.sin(radians(angle))
    cos_theta := math.cos(radians(angle))
    cos_value := 1.0 - cos_theta

    m[0][0] = (axis.x * axis.x * cos_value) + cos_theta
    m[0][1] = (axis.x * axis.y * cos_value) + (axis.z * sin_theta)
    m[0][2] = (axis.x * axis.z * cos_value) - (axis.y * sin_theta)
    m[1][0] = (axis.y * axis.x * cos_value) - (axis.z * sin_theta)
    m[1][1] = (axis.y * axis.y * cos_value) + cos_theta
    m[1][2] = (axis.y * axis.z * cos_value) + (axis.x * sin_theta)
    m[2][0] = (axis.z * axis.x * cos_value) + (axis.y * sin_theta)
    m[2][1] = (axis.z * axis.y * cos_value) - (axis.x * sin_theta)
    m[2][2] = (axis.z * axis.z * cos_value) + cos_theta

    return m
}

translate_mat4 :: proc (translation: Vec3) -> Mat4 {
    m := identity_mat4()
    m[3][0] = translation.x
    m[3][1] = translation.y
    m[3][2] = translation.z
    return m
}

mul_mat4 :: proc (left, right: Mat4) -> Mat4 {
    m := Mat4 {}
    for col in 0..<4 {
        for row in 0..<4 {
            m[col][row] = left[0][row] * right[col][0] +
                          left[1][row] * right[col][1] +
                          left[2][row] * right[col][2] +
                          left[3][row] * right[col][3]
        }
    }
    return m
}
