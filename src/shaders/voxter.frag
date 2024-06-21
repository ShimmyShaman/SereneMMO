#version 450
// #extension GL_ARB_separate_shader_objects : enable

// Parameters
layout (std140, binding = 2) uniform LumenUBO {
    vec4 light_dir;
    vec4 light_color;
} av;

layout (std140, binding = 3) uniform RadinUBO {
    float time;
    float radiant_flux;
    float twilight_multiplier;
    // vec4 player_beacon; 
    vec4[4] beacon_pos;
} rdn;

// From vertex shader
layout(location = 0) in vec3 in_pos;
layout(location = 1) in vec2 in_uv;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in float in_ao;
layout(location = 4) flat in uint in_cell_type;

layout(location = 0) out vec4 out_color;

// 0: top, 1: bottom(but it is only ever rendered as a floor), 2: left, 3: right, 4: front, 5: back
vec3 cell_type_colours[3] = {vec3(0.1, 0.8, 0.1), vec3(0.8, 0.8, 0.8), vec3(0.45, 0.45, 0.1)};


// float get_radiance(vec2 xz, vec2 beacon_pos, float beacon_rad) {
//     float dist = distance(beacon_pos, xz);
//     if (dist < beacon_rad) {
//         return 0.6 - 0.12 * max(0, 1.0 - in_pos.y);
//     } else if  (dist < beacon_rad + 0.4) {
//         return max(0.01, 0.01 + (beacon_rad + 0.4 - dist) * 0.5);
//     }
//     return 0.01;
// }

void main() {
    // out_color = in_color;
	// outColor = vec4(fragTexCoord.x, fragTexCoord.y, 0.2, 1.0);
    // out_color = vec4(1.0, 1.0, 1.0, 1.0);
    float diff = max(dot(in_normal, av.light_dir.xyz), 0.0);
    vec3 diffuse = diff * av.light_color.xyz;

    float radiance = 0.00;
    for (int i = 0; i < 4; i++) {
        float dist = distance(rdn.beacon_pos[i].xy, in_pos.xz);
        // radiance += 1.0 / dist;
        if (dist < rdn.beacon_pos[i].z) {
            // radiance = max(rdn.beacon_pos[i].z, radiance);(rdn.beacon_pos[i].z)
            radiance += 0.6 - 0.12 * max(0, 1.0 - in_pos.y);
        } else if (dist < rdn.beacon_pos[i].z + 0.4) {
            radiance += max(radiance, 0.01 + (rdn.beacon_pos[i].z + 0.4 - dist) * 0.5);
        } else if (dist < rdn.beacon_pos[i].z * rdn.twilight_multiplier) {
            radiance = max(radiance, 0.01);
        }
        // radiance = max(rdn.beacon_pos[i].z, radiance);
    }
    // radiance = (0.01 + distance(rdn.beacon_pos[0].xy, in_pos));
    // radiance = rdn.beacon_pos[1].z;
    // radiance = min(0.6, radiance);

    // out_color = vec4(/*av.light_color.xyz * diffuse * (0.1 + 2.8 * radiance) * (0.1 + 3.7 */ vec3(in_ao), 1.0);
    vec3 difamb = av.light_color.xyz * diffuse + in_ao;

    float alpha = 1.0;
    if (radiance == 0.0) {
        alpha = 0.0;
    }

    out_color = vec4(difamb * radiance * cell_type_colours[in_cell_type], alpha);

    // out_color = vec4(vec3(in_pos.x / 32.0, in_pos.y / 32.0, 0.0), 1.0);
    // out_color = vec4(1.0, 1.0, 1.0, 1.0);
}