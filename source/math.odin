// adapted from odin-windows-amd64-dev-2025-10-05\dist\core\math\linalg\specific.odin
package main

import math "core:math"

TAU :: 6.28318530717958647692528676655900576
PI  :: 3.14159265358979323846264338327950288

Vec2 :: [2]f32
Vec3 :: [3]f32
Mat4 :: matrix[4,4]f32

RAD_PER_DEG :: TAU/360.0
DEG_PER_RAD :: 360.0/TAU

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

@(require_results)
perspective_mat4 :: proc (fovy, aspect, near, far: f32, flip_z_axis := true) -> (m: Mat4) #no_bounds_check {
	tan_half_fovy := math.tan(0.5 * fovy)
	m[0, 0] = 1 / (aspect*tan_half_fovy)
	m[1, 1] = 1 / (tan_half_fovy)
	m[2, 2] = +(far + near) / (far - near)
	m[3, 2] = +1
	m[2, 3] = -2*far*near / (far - near)

	if flip_z_axis {
		m[2] = -m[2]
	}

	return
}

@(require_results)
lookat_mat4 :: proc (eye, centre, up: Vec3, flip_z_axis := true) -> (m: Mat4) {
	f := norm_vec3(centre - eye)
	s := norm_vec3(cross_vec3(f, up))
	u := cross_vec3(s, f)

	fe := dot_vec3(f, eye)

	return {
		+s.x, +s.y, +s.z, -dot_vec3(s, eye),
		+u.x, +u.y, +u.z, -dot_vec3(u, eye),
		-f.x, -f.y, -f.z, +fe if flip_z_axis else -fe,
		   0,    0,    0, 1,
	}
}

rotate_mat4 :: proc (angle_radians: f32, v: Vec3) -> Mat4 #no_bounds_check {
	c := math.cos(angle_radians)
	s := math.sin(angle_radians)

	a := norm_vec3(v)
	t := a * (1-c)

	rot := identity_mat4()

	rot[0][0] = c + t[0]*a[0]
	rot[0][1] = 0 + t[0]*a[1] + s*a[2]
	rot[0][2] = 0 + t[0]*a[2] - s*a[1]
	rot[0][3] = 0

	rot[1][0] = 0 + t[1]*a[0] - s*a[2]
	rot[1][1] = c + t[1]*a[1]
	rot[1][2] = 0 + t[1]*a[2] + s*a[0]
	rot[1][3] = 0

	rot[2][0] = 0 + t[2]*a[0] + s*a[1]
	rot[2][1] = 0 + t[2]*a[1] - s*a[0]
	rot[2][2] = c + t[2]*a[2]
	rot[2][3] = 0

	return rot
}

translate_mat4 :: proc (translation: Vec3) -> Mat4 #no_bounds_check {
	m := identity_mat4()
	m[3][0] = translation[0]
	m[3][1] = translation[1]
	m[3][2] = translation[2]
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
