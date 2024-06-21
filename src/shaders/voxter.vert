#version 450
// #extension GL_ARB_separate_shader_objects : enable

layout (std140, binding = 0) uniform UBO0 {
  mat4 vp;
} w;

layout (std140, binding = 1) uniform VoxelUBO {
  mat4 world;
  vec2 unscaled_offset;
} vxu;

// 0: top, 1: bottom(but it is only ever rendered as a floor), 2: left, 3: right, 4: front, 5: back
vec3 face_normals[6] = {vec3(0, 1, 0), vec3(0, 1, 0), vec3(-1, 0, 0), vec3(1, 0, 0), vec3(0, 0, 1), vec3(0, 0, -1)};

layout(location = 0) in vec3 in_position;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in uint in_face_index;
layout(location = 3) in float in_ao;
layout(location = 4) in uint in_cell_type;

layout(location = 0) out vec3 frag_pos;
layout(location = 1) out vec2 frag_uv;
layout(location = 2) out vec3 frag_normal;
layout(location = 3) out float frag_ao;
layout(location = 4) out uint frag_cell_type;

void main() {
  gl_Position = w.vp * vxu.world * vec4(in_position, 1.0);
  // gl_Position.y = -gl_Position.y;ww.offset + 
  // frag_tex_coord = in_tex_coord;

  // gl_Position = vec4(in_position.yx, 0.0, 0.0);
  // // gl_Position.xy *= element.scale.xy;
  // // gl_Position.xy += element.offset.xy;

  frag_pos = vec3(vxu.unscaled_offset.x, 0, vxu.unscaled_offset.y) + in_position;
  frag_uv = in_uv;
  frag_normal = face_normals[in_face_index];
  frag_ao = in_ao;
  frag_cell_type = in_cell_type;
}