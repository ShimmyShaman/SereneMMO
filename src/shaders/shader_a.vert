#version 450
// #extension GL_ARB_separate_shader_objects : enable

layout (std140, binding = 0) uniform UBO0 {
  mat4 vp;
} w;

// layout (std140, binding = 0) uniform UBO0 {
//   mat4 vp;
// } ww;

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec2 in_tex_coord;
// layout(location = 2) in vec3 in_normal;

// layout(location = 1) out vec3 frag_pos;
layout(location = 2) out vec2 frag_tex_coord;
// layout(location = 3) out vec3 frag_normal;

void main() {
  gl_Position = w.vp * vec4(in_position, 1.0);
  // gl_Position.y = -gl_Position.y;ww.offset + 
  // frag_tex_coord = in_tex_coord;

  // gl_Position = vec4(in_position.yx, 0.0, 0.0);
  // // gl_Position.xy *= element.scale.xy;
  // // gl_Position.xy += element.offset.xy;

  // frag_pos = in_position;
  frag_tex_coord = in_tex_coord;
//   frag_normal = in_normal;
}