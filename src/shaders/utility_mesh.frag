#version 450
// #extension GL_ARB_separate_shader_objects : enable

layout(location = 0) out vec4 out_color;

layout(location = 0) in vec2 frag_tex_coord;
layout(location = 1) in vec4 frag_color;


void main() {
    // Brown
    out_color = frag_color;

    if (distance(frag_tex_coord, vec2(0.5, 0.5)) >= 0.45) {
        // frag_tex_coord.x < 0.01 || frag_tex_coord.x > 0.95 || frag_tex_coord.y < 0.01 || frag_tex_coord.y > 0.95) {
        out_color = vec4(0.0, 0.0, 0.0, 1.0);
    }
    // out_color = vec4(0.0, 1.0, 0.0, 1.0);
}