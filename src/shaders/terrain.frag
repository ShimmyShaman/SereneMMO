#version 450
#extension GL_ARB_separate_shader_objects : enable

// Parameters
layout (std140, binding = 1) uniform UBO1 {
    vec4 light_dir;
    vec4 light_color;
} av;

layout(binding = 2) uniform sampler2D tex_sampler;

// From vertex shader
layout(location = 0) out vec4 out_color;
// layout(location = 1) in vec3 frag_pos;
layout(location = 2) in vec2 frag_tex_coord;
layout(location = 3) in vec3 frag_normal;

void main() {
    // Ambient
    float ambient_strength = 0.1;
    vec3 ambient = vec3(0.0);//ambient_strength * av.light_color;
  	
    // Diffuse
    // vec3 norm = normalize(frag_normal);
    // vec3 light_dir = normalize(av.light_pos - frag_pos);
    float diff = max(dot(frag_normal, av.light_dir.bgr), 0.0);
    vec3 diffuse = texture(tex_sampler, frag_tex_coord).xyz * diff * diff * av.light_color.rgb;

    // outColor = texture(texSampler, fragTexCoord);
	// outColor = vec4(fragTexCoord.x, fragTexCoord.y, 0.2, 1.0);
    vec3 objectColor = vec3(0.2, 0.8, 0.05);

    // Color Output
    vec3 result = (ambient + diffuse) * objectColor;
    // vec3 result = frag_normal;
    out_color = vec4(result, 1.0);
    out_color = texture(tex_sampler, frag_tex_coord).bgra;
}