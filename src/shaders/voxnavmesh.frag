#version 450
// #extension GL_ARB_separate_shader_objects : enable

layout(location = 0) out vec4 out_color;

layout(location = 0) in vec2 frag_tex_coord;


void main() {
    // Brown
    out_color = vec4(0.95, 0.93, 0.1, 0.4);

    if (frag_tex_coord.x < 0.01 || frag_tex_coord.x > 0.99 || frag_tex_coord.y < 0.01 || frag_tex_coord.y > 0.99) {
        out_color = vec4(0.0, 0.0, 1.0, 0.5);
    }

}