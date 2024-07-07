#version 450
// #extension GL_ARB_separate_shader_objects : enable

layout (std140, binding = 0) uniform UBO0 {
  mat4 vp;
  vec3 camera_pos;
} cam;

layout (std140, binding = 1) uniform UBO1 {
  mat4 transform;
} model;

// Input
layout(location = 0) in vec3 in_position;
layout(location = 1) in vec3 in_normal;
layout(location = 2) in vec2 in_tex_coord;

// Output
layout(location = 0) out vec3 frag_pos;
layout(location = 1) out vec2 frag_tex_coord;
layout(location = 2) out vec3 frag_normal;
layout(location = 3) out vec3 frag_cam_pos;

void main() {
  gl_Position = cam.vp * model.transform * vec4(in_position, 1.0);
  
  frag_pos = (model.transform * vec4(in_position, 0.0)).xyz;
  frag_tex_coord = in_tex_coord;
  frag_normal = in_normal;
  frag_cam_pos = cam.camera_pos;
}