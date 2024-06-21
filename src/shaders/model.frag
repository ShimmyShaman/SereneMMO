#version 450
#extension GL_ARB_separate_shader_objects : enable

// Parameters
layout (std140, binding = 2) uniform UBO1 {
    vec4 light_dir;
    vec4 light_color;
} av;

layout(binding = 3) uniform sampler2D tex_sampler;

// From vertex shader
layout(location = 0) out vec4 out_color;
// layout(location = 1) in vec3 frag_pos;
layout(location = 2) in vec2 frag_tex_coord;
layout(location = 3) in vec3 frag_normal;

void main() {
    // Ambient
    float ambient_strength = 0.07;
    vec3 ambient = vec3(ambient_strength * av.light_color.rgb);
  	
    // Diffuse
    // vec3 norm = normalize(frag_normal);
    // vec3 light_dir = normalize(av.light_pos - frag_pos);
    float diff = max(dot(frag_normal, av.light_dir.rgb), 0.0);
    vec3 diffuse = max(ambient_strength, diff) * texture(tex_sampler, frag_tex_coord).bgr * av.light_color.rgb;

    // outColor = texture(texSampler, fragTexCoord);
	// outColor = vec4(fragTexCoord.x, fragTexCoord.y, 0.2, 1.0);
    // vec3 objectColor = vec3(0.2, 0.8, 0.01);

    // Color Output
    vec3 result = (ambient + diffuse);
    // vec3 result = frag_normal;
    out_color = vec4(diffuse, 1.0);
    // out_color = vec4(0.9, 0.4, 0.2, 1.0);
}