#version 450

layout(location = 0) out vec4 FragColor;

layout(location = 0) in vec3 in_world_pos;
layout(location = 1) in vec2 in_tex_uv;
layout(location = 2) in vec3 in_normal;
layout(location = 3) in vec3 in_cam_pos;
  
// uniform vec3  albedo;
// uniform float metallic;
// uniform float roughness;
// uniform float ao;
layout(binding = 2) uniform sampler2D albedo_sampler;
float metallic = 0.1;
float roughness = 1.0;
float ao = 1.0;

// lights
// uniform vec3 lightPositions[4];
// uniform vec3 lightColors[4];
vec3 lightPositions[4] = vec3[4](vec3(-100.0,  1000.0, 100.0),
                                 vec3( 10.0,  10.0, 10.0),
                                 vec3(-10.0, 10.0, 10.0),
                                 vec3( 10.0, 10.0, 10.0));
vec3 lightColors[4] = vec3[4](vec3(10000.0, 10000.0, 8000.0),
                                vec3(0.0, 0.0, 0.0),
                                vec3(0.0, 0.0, 0.0),
                                vec3(0.0, 0.0, 0.0));

const float PI = 3.14159265359;

float DistributionGGX(vec3 N, vec3 H, float roughness);
float GeometrySchlickGGX(float NdotV, float roughness);
float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness);
vec3 fresnelSchlick(float cosTheta, vec3 F0);

void main()
{		
    vec3 albedo = texture(albedo_sampler, in_tex_uv).bgr;
    vec3 N = normalize(in_normal);
    vec3 V = normalize(in_cam_pos - in_world_pos);

    vec3 F0 = vec3(0.04); 
    F0 = mix(F0, albedo, metallic);
	           
    // reflectance equation
    vec3 Lo = vec3(0.0);
    for(int i = 0; i < 4; ++i) 
    {
        // calculate per-light radiance
        vec3 L = normalize(lightPositions[i] - in_world_pos);
        vec3 H = normalize(V + L);
        float distance    = length(lightPositions[i] - in_world_pos);
        float attenuation = 1.0 / (distance * distance);
        vec3 radiance     = lightColors[i] * attenuation;        
        
        // cook-torrance brdf
        float NDF = DistributionGGX(N, H, roughness);        
        float G   = GeometrySmith(N, V, L, roughness);      
        vec3 F    = fresnelSchlick(max(dot(H, V), 0.0), F0);       
        
        vec3 kS = F;
        vec3 kD = vec3(1.0) - kS;
        kD *= 1.0 - metallic;	  
        
        vec3 numerator    = NDF * G * F;
        float denominator = 4.0 * max(dot(N, V), 0.0) * max(dot(N, L), 0.0) + 0.0001;
        vec3 specular     = numerator / denominator;  
            
        // add to outgoing radiance Lo
        float NdotL = max(dot(N, L), 0.0);                
        Lo += (kD * albedo / PI + specular) * radiance * NdotL; 
    }   
  
    vec3 ambient = vec3(0.03) * albedo * ao;
    vec3 color = ambient + Lo;
	
    color = color / (color + vec3(1.0));
    color = pow(color, vec3(1.0/2.2));  
   
    FragColor = vec4(color, 1.0);
    // FragColor = vec4(albedo, 1.0);
    // FragColor = vec4(0.0, 1.0, 1.0, 1.0);
}

float DistributionGGX(vec3 N, vec3 H, float roughness)
{
    float a      = roughness*roughness;
    float a2     = a*a;
    float NdotH  = max(dot(N, H), 0.0);
    float NdotH2 = NdotH*NdotH;
	
    float num   = a2;
    float denom = (NdotH2 * (a2 - 1.0) + 1.0);
    denom = PI * denom * denom;
	
    return num / denom;
}

float GeometrySchlickGGX(float NdotV, float roughness)
{
    float r = (roughness + 1.0);
    float k = (r*r) / 8.0;

    float num   = NdotV;
    float denom = NdotV * (1.0 - k) + k;
	
    return num / denom;
}

float GeometrySmith(vec3 N, vec3 V, vec3 L, float roughness)
{
    float NdotV = max(dot(N, V), 0.0);
    float NdotL = max(dot(N, L), 0.0);
    float ggx2  = GeometrySchlickGGX(NdotV, roughness);
    float ggx1  = GeometrySchlickGGX(NdotL, roughness);
	
    return ggx1 * ggx2;
}

vec3 fresnelSchlick(float cosTheta, vec3 F0)
{
    return F0 + (1.0 - F0) * pow(clamp(1.0 - cosTheta, 0.0, 1.0), 5.0);
}  