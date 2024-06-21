package violin


import "core:fmt"
import mx "core:math"
import "core:math/rand"
import la "core:math/linalg"

import vk "vendor:vulkan"
import "vendor:sdl2"

vec2 :: la.Vector2f32
vec2i :: [2]i32
vec3 :: la.Vector3f32
vec4 :: la.Vector4f32
mat4 :: la.Matrix4f32

// Transform Matrix + Color
UtilityMeshUBO :: struct {
  transform: mat4,
  color: vec4,
}

@(private="file") UtilityMeshVertex :: struct {
  using pos: vec3,
  uv: vec2,
  // normal: vec3,
}

UtilityMesh :: struct {
  vb: VertexBufferResourceHandle,
  ib: IndexBufferResourceHandle,
  rp: RenderProgramResourceHandle,
}

destroy_utility_mesh :: proc(vctx: ^VkSDLContext, sqm: UtilityMesh) {
  destroy_vertex_buffer(vctx, sqm.vb)
  destroy_index_buffer(vctx, sqm.ib)
  destroy_render_program(vctx, sqm.rp)
}

construct_square_mesh :: proc(vctx: ^VkSDLContext, render_pass: RenderPassResourceHandle,
  vert_shader_path := "shaders/utility_mesh.vert.spv",
  frag_shader_path := "shaders/utility_mesh.frag.spv") -> (sqm: UtilityMesh, prs: ProcResult) {

  // Declarations
  descriptor_bindings := [?]vk.DescriptorSetLayoutBinding {
    vk.DescriptorSetLayoutBinding {
      binding = 0,
      descriptorType = .UNIFORM_BUFFER,
      stageFlags = { .VERTEX },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
    vk.DescriptorSetLayoutBinding {
      binding = 1,
      descriptorType = .UNIFORM_BUFFER,
      stageFlags = { .VERTEX },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
    // vk.DescriptorSetLayoutBinding {
    //   binding = 2,
    //   descriptorType = .COMBINED_IMAGE_SAMPLER,
    //   stageFlags = { .FRAGMENT },
    //   descriptorCount = 1,
    //   pImmutableSamplers = nil,
    // },
  }
  input_attributes := [?]InputAttribute {
    InputAttribute {
      format = .R32G32B32_SFLOAT,
      location = 0,
      offset = auto_cast offset_of(UtilityMeshVertex, pos),
    },
    InputAttribute {
      format = .R32G32_SFLOAT,
      location = 1,
      offset = auto_cast offset_of(UtilityMeshVertex, uv),
    },
    // InputAttribute {
    //   format = .R32G32B32_SFLOAT,
    //   location = 2,
    //   offset = auto_cast offset_of(TerrainVertex, normal),
    // },
  }

  // Terrain Mesh
  EXT :: 1.0
  vertices: [4]UtilityMeshVertex
  vertices[0].pos = vec3{-EXT, 0.0, -EXT}
  vertices[0].uv = vec2{0.0, 0.0}
  vertices[1].pos = vec3{EXT, 0.0, -EXT}
  vertices[1].uv = vec2{1.0, 0.0}
  vertices[2].pos = vec3{EXT, 0.0, EXT}
  vertices[2].uv = vec2{1.0, 1.0}
  vertices[3].pos = vec3{-EXT, 0.0, EXT}
  vertices[3].uv = vec2{0.0, 1.0}

  sqm.vb = create_vertex_buffer(vctx, &vertices[0], size_of(UtilityMeshVertex), len(vertices)) or_return

  // Indices
  indices: [6]u16 = {0, 1, 2, 2, 3, 0}

  sqm.ib = create_index_buffer(vctx, &indices[0], len(indices)) or_return
  // fmt.println("Index Buffer loaded:", murkies.index_buffer)

  // albedo_create_options := DefaultTextureCreateOptions
  // albedo_create_options.addressModeU = .MIRRORED_REPEAT
  // albedo_create_options.addressModeV = .MIRRORED_REPEAT
  // murkies.albedo = load_texture_from_file(vctx, ASSET_PATH_TerrainAlbedo, albedo_create_options) or_return

  // Render Program
  // fmt.println("render_pass_3d:", render_pass_3d)
  // Load the asset
  vs_data := _load_binary_file(vert_shader_path) or_return
  fs_data := _load_binary_file(frag_shader_path) or_return
  rpci := RenderProgramCreateInfo {
    pipeline_config = PipelineCreateConfig {
      render_pass = render_pass,
      vertex_shader_binary = vs_data,
      fragment_shader_binary = fs_data,
    },
    vertex_size = size_of(UtilityMeshVertex),
    buffer_bindings = descriptor_bindings[:],
    input_attributes = input_attributes[:],
  }
  sqm.rp = create_render_program(vctx, &rpci) or_return

  return
}

construct_circle_mesh :: proc(vctx: ^VkSDLContext, segments: int, render_pass: RenderPassResourceHandle,
    vert_shader_path := "shaders/utility_mesh.vert.spv",
    frag_shader_path := "shaders/utility_mesh.frag.spv") -> (ccm: UtilityMesh, prs: ProcResult) {
  // Descriptor Declarations
  descriptor_bindings := [?]vk.DescriptorSetLayoutBinding {
    vk.DescriptorSetLayoutBinding {
      binding = 0,
      descriptorType = .UNIFORM_BUFFER,
      stageFlags = { .VERTEX },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
    vk.DescriptorSetLayoutBinding {
      binding = 1,
      descriptorType = .UNIFORM_BUFFER,
      stageFlags = { .VERTEX },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
    // vk.DescriptorSetLayoutBinding {
    //   binding = 2,
    //   descriptorType = .COMBINED_IMAGE_SAMPLER,
    //   stageFlags = { .FRAGMENT },
    //   descriptorCount = 1,
    //   pImmutableSamplers = nil,
    // },
  }
  input_attributes := [?]InputAttribute {
    InputAttribute {
      format = .R32G32B32_SFLOAT,
      location = 0,
      offset = auto_cast offset_of(UtilityMeshVertex, pos),
    },
    InputAttribute {
      format = .R32G32_SFLOAT,
      location = 1,
      offset = auto_cast offset_of(UtilityMeshVertex, uv),
    },
    // InputAttribute {
    //   format = .R32G32B32_SFLOAT,
    //   location = 2,
    //   offset = auto_cast offset_of(TerrainVertex, normal),
    // },
  }

  vertices: [dynamic]UtilityMeshVertex
  defer delete(vertices)
  indices: [dynamic]u16
  defer delete(indices)

  // Generate vertices
  for i in 0..<segments {
    angle: f32 = 2.0 * mx.PI * f32(i) / f32(segments)
    x := mx.cos(angle)
    y := mx.sin(angle)
    append(&vertices, UtilityMeshVertex {
      pos = vec3{x, 0.0, y},
      uv = vec2{x / 2.0 + 0.5, y / 2.0 + 0.5},
    })
  }

  // Generate indices for triangles
  for i in 0..<segments-2 {
    append(&indices, 0)
    append(&indices, u16(i + 1))
    append(&indices, u16(i + 2))
  }

  // Add the last triangle
  append(&indices, 0)
  append(&indices, u16(segments - 1))
  append(&indices, 1)

  ccm.vb = create_vertex_buffer(vctx, &vertices[0], size_of(UtilityMeshVertex), len(vertices)) or_return  
  ccm.ib = create_index_buffer(vctx, &indices[0], len(indices)) or_return

  // albedo_create_options := DefaultTextureCreateOptions
  // albedo_create_options.addressModeU = .MIRRORED_REPEAT
  // albedo_create_options.addressModeV = .MIRRORED_REPEAT
  // murkies.albedo = load_texture_from_file(vctx, ASSET_PATH_TerrainAlbedo, albedo_create_options) or_return

  // Render Program
  // fmt.println("render_pass_3d:", render_pass_3d)
  // Load the asset
  vs_data := _load_binary_file(vert_shader_path) or_return
  fs_data := _load_binary_file(frag_shader_path) or_return
  rpci := RenderProgramCreateInfo {
    pipeline_config = PipelineCreateConfig {
      render_pass = render_pass,
      vertex_shader_binary = vs_data,
      fragment_shader_binary = fs_data,
    },
    vertex_size = size_of(UtilityMeshVertex),
    buffer_bindings = descriptor_bindings[:],
    input_attributes = input_attributes[:],
  }
  ccm.rp = create_render_program(vctx, &rpci) or_return

  return
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////
// UBO Pool
UBOPool :: struct {
  ubos: [dynamic]BufferResourceHandle,
  ubo_size_in_bytes: vk.DeviceSize,
  _index: int,
}

init_ubo_pool :: proc(vctx: ^VkSDLContext, pool: ^UBOPool, ubo_size_in_bytes: vk.DeviceSize, capacity: int) -> (prs: ProcResult) {
  pool.ubo_size_in_bytes = ubo_size_in_bytes
  pool._index = 0

  for i in 0..<capacity {
    get_ubo_from_pool(vctx, pool) or_return
  }
  reset_ubo_pool(pool)
  return
}

destroy_ubo_pool :: proc(vctx: ^VkSDLContext, pool: ^UBOPool) {
  for ubo in pool.ubos {
    destroy_buffer(vctx, ubo)
  }
  delete(pool.ubos)
  return
}

reset_ubo_pool :: proc(pool: ^UBOPool) {
  pool._index = 0
  return
}

get_ubo_from_pool :: proc(vctx: ^VkSDLContext, pool: ^UBOPool) -> (ubo: BufferResourceHandle, prs: ProcResult) {
  if pool._index >= len(pool.ubos) {
    ubo = create_uniform_buffer(vctx, pool.ubo_size_in_bytes, .Dynamic) or_return
    append(&pool.ubos, ubo)
  } else {
    ubo = pool.ubos[pool._index]
  }

  pool._index += 1
  return
}

///////////////////////////////////////////////////////////////////////////////////////////////////////////////