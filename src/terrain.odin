package client

import "core:fmt"
import la "core:math/linalg"

import vk "vendor:vulkan"
import vi "violin"

@(private="file") CHUNK_DIM_SIZE :: 16

Terrain :: struct {
  albedo: vi.TextureResourceHandle,
  render_program: vi.RenderProgramResourceHandle,
  frag_ubo: vi.BufferResourceHandle,

  vertex_ary: [CHUNK_DIM_SIZE * CHUNK_DIM_SIZE]TerrainVertex,

  vertex_buffer: vi.VertexBufferResourceHandle,
  index_buffer: vi.IndexBufferResourceHandle,
}

@(private) TerrainVertex :: struct {
  using pos: vec3,
  uv: vec2,
  normal: vec3,
}

init_terrain :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {
  terrain := &pad.world.terrain

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
      stageFlags = { .FRAGMENT },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
    vk.DescriptorSetLayoutBinding {
      binding = 2,
      descriptorType = .COMBINED_IMAGE_SAMPLER,
      stageFlags = { .FRAGMENT },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
  }
  input_attributes := [?]vi.InputAttribute {
    vi.InputAttribute {
      format = .R32G32B32_SFLOAT,
      location = 0,
      offset = auto_cast offset_of(TerrainVertex, pos),
    },
    vi.InputAttribute {
      format = .R32G32_SFLOAT,
      location = 1,
      offset = auto_cast offset_of(TerrainVertex, uv),
    },
    vi.InputAttribute {
      format = .R32G32B32_SFLOAT,
      location = 2,
      offset = auto_cast offset_of(TerrainVertex, normal),
    },
  }

  // Vertex Array Cache
  SCALE: f32: 8.0
  for i in 0..<(CHUNK_DIM_SIZE*CHUNK_DIM_SIZE) {
    terrain.vertex_ary[i].pos = vec3{auto_cast (i % CHUNK_DIM_SIZE - CHUNK_DIM_SIZE / 2) * SCALE, 0,
      auto_cast (i / CHUNK_DIM_SIZE - CHUNK_DIM_SIZE / 2) * SCALE}
    terrain.vertex_ary[i].uv = vec2{auto_cast (i % CHUNK_DIM_SIZE) / auto_cast (CHUNK_DIM_SIZE - 1),
      auto_cast (i / CHUNK_DIM_SIZE) / auto_cast (CHUNK_DIM_SIZE - 1)} * SCALE * 2.0
  }
  terrain.vertex_buffer = vi.create_vertex_buffer(vctx, &terrain.vertex_ary[0], size_of(TerrainVertex), len(terrain.vertex_ary)) or_return

  // Indices
  indices: [(CHUNK_DIM_SIZE - 1) * (CHUNK_DIM_SIZE - 1) * 6]u16
  {
    i: u16 = 0
    for x in 0..<(CHUNK_DIM_SIZE - 1) {
      for y in 0..<(CHUNK_DIM_SIZE - 1) {
        indices[i] = auto_cast (y * CHUNK_DIM_SIZE + x)
        indices[i + 2] = auto_cast (y * CHUNK_DIM_SIZE + x + 1)
        indices[i + 1] = auto_cast ((y + 1) * CHUNK_DIM_SIZE + x)

        indices[i + 4] = auto_cast ((y + 1) * CHUNK_DIM_SIZE + x)
        indices[i + 3] = auto_cast (y * CHUNK_DIM_SIZE + x + 1)
        indices[i + 5] = auto_cast ((y + 1) * CHUNK_DIM_SIZE + x + 1)

        i += 6
      }
    }
  }

  terrain.index_buffer = vi.create_index_buffer(vctx, &indices[0], len(indices)) or_return
  // fmt.println("Index Buffer loaded:", terrain.index_buffer)

  // Uniform Buffer
  // terrain.uniform_buffer = vi.create_uniform_buffer(vctx, chunk_dim_size_of(mat4) + chunk_dim_size_of(vec3), .Dynamic)

  terrain.frag_ubo = vi.create_uniform_buffer(vctx, size_of(vec3) * 2, .Dynamic) or_return
  frag_data := [2]vec3 {
    la.normalize(vec3{0.18, 1.0, 0.3}),
    vec3{1.0, 0.9, 0.4},
  }
  vi.write_to_buffer(vctx, terrain.frag_ubo, &frag_data[0], size_of(vec3) * 2) or_return

  // Texture
  albedo_options := vi.DefaultTextureCreateOptions
  albedo_options.generate_mipmaps = true
  terrain.albedo = vi.load_texture_from_file(vctx, "textures/grass_tex.png", albedo_options) or_return

  // Render Program
  // vs := load_asset(asset_manager, ASSET_PATH_TerrainShaderVert) or_return
  // fs := load_asset(asset_manager, ASSET_PATH_TerrainShaderFrag) or_return
  vs_data := vi.load_binary_file("shaders/terrain.vert.spv") or_return
  fs_data := vi.load_binary_file("shaders/terrain.frag.spv") or_return
  rpci := vi.RenderProgramCreateInfo {
    pipeline_config = vi.PipelineCreateConfig {
      render_pass = world.render_pass,
      vertex_shader_binary = vs_data,
      fragment_shader_binary = fs_data,
    },
    vertex_size = size_of(TerrainVertex),
    buffer_bindings = descriptor_bindings[:],
    input_attributes = input_attributes[:],
  }
  terrain.render_program = vi.create_render_program(vctx, &rpci) or_return

  return
}

destroy_terrain :: proc(using pad: ^PropAppData) {
  
}

update_terrain :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {
  return
}

render_terrain :: proc(using pad: ^PropAppData, rctx: ^vi.RenderContext) -> (prs: ProcResult) {
  terrain := &pad.world.terrain

  // fmt.println("Rendering terrain", terrain.render_program, terrain.vertex_buffer, terrain.index_buffer, terrain.albedo)
  vi.draw_indexed(rctx, terrain.render_program, terrain.vertex_buffer, terrain.index_buffer,
    []vi.ResourceHandle{auto_cast game_camera.ubo, auto_cast world.lumin_ubo, auto_cast terrain.albedo}) or_return

  return
}