#version 450
// #extension GL_ARB_separate_shader_objects : enable

layout (std140, binding = 0) uniform UBO0 {
  mat4 vp;
} cam;

// layout (std140, binding = 1) uniform UBO1 {
//   mat4 transform;
// } world;

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec2 in_tex_coord;
// layout(location = 2) in vec3 in_normal;

// layout(location = 1) out vec3 frag_pos;
layout(location = 0) out vec2 frag_tex_coord;
// layout(location = 3) out vec3 frag_normal;

void main() {
  gl_Position = cam.vp * vec4(in_position + vec3(0.0, 0.1, 0.0), 1.0);

  frag_tex_coord = in_tex_coord;
  // frag_normal = in_normal;
}