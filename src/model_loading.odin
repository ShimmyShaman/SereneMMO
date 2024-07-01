package client

import "core:os"
import "core:fmt"
import "core:encoding"
import "core:strings"

import vk "vendor:vulkan"

import gltf "glTF2"

import vi "violin"
// import gltf "vendor:cgltf"

GLTFAsset :: struct {
  using _data: ^gltf.Data,

  // // Scene to render (if nil, render all scenes)
  // rendered_scene: Maybe(int),
  // all_scenes: []GLTFScene,
  // nodes: []GLTFNode,

  albedo_textures: map[int]vi.TextureResourceHandle,
  vertex_buffers: []vi.VertexBufferResourceHandle,
  index_buffers: []vi.IndexBufferResourceHandle,
  model_transform_buffers: []vi.BufferResourceHandle,
  render_programs: []vi.RenderProgramResourceHandle,
}

@(private) PositionNormalUVVertex :: struct {
  using pos: vec3,
  normal: vec3,
  uv: vec2,
}

load_model :: proc(vctx: ^vi.VkSDLContext, file_name: string) -> (asset: ^GLTFAsset, prs: ProcResult) {

  data, gl_err := gltf.load_from_file(file_name)
  if gl_err != nil {
    fmt.println("ERROR] Failed to load glTF file:", gl_err)
    prs = .AssetLoadError
    return
  }

  // Create the asset
  asset = new(GLTFAsset)
  asset._data = data
  
  // Load all meshes
  for node in data.nodes {
    if node.mesh != nil {
      // 
    }
  }

  // // fmt.println("\nLoaded glTF file:", file_name)
  // // fmt.println("data.asset:", data.asset)
  // // // fmt.println("data.accessors:", data.accessors)
  // // fmt.println("data.animations (len):", len(data.animations))
  // // fmt.println("data.animations[0]:", data.animations[0])
  // // // fmt.println("data.buffers:", data.buffers)
  // // fmt.println("data.buffer_views:", data.buffer_views)
  // // fmt.println("data.cameras:", data.cameras)
  // // fmt.println("data.images:", data.images)
  // // fmt.println("data.materials:", data.materials)
  // // fmt.println("data.meshes:", data.meshes)
  // // fmt.println("data.nodes:", data.nodes)
  // // fmt.println("data.nodes:")
  // // for node, i in data.nodes {
  // //   fmt.println("  ", i, ":", node)
  // // }
  // // // fmt.println("data.samplers:", data.samplers)
  // // fmt.println("")
  // // fmt.println("data.scene:", data.scene)
  // // fmt.println("data.scenes:", data.scenes)
  // // fmt.println("data.skins:", data.skins)
  // // fmt.println("data.textures:", data.textures)
  // // fmt.println("data.extensions_used:", data.extensions_used)
  // // fmt.println("data.extensions_required:", data.extensions_required)
  // // fmt.println("data.extensions:", data.extensions)
  // // fmt.println("data.extras:", data.extras)

  // // if len(data.nodes) != 1 {
  // //   fmt.println("ERROR-TODO] Please report encountering this. Can only handle 1 node, got:", len(data.nodes))
  // //   prs = .AssetLoadError
  // //   return
  // // }

  // // gltf.unload(data)

  // return
}

draw_model :: proc(rctx: ^vi.RenderContext, asset: ^GLTFAsset, transform: ^mat4) -> (prs: ProcResult)  {
  // // Determine the scene(s) to render
  // if asset.scene == nil {
  //   for scene in asset.scenes {
  //     draw_scene(rctx, asset, scene, transform)
  //   }
  // } else {
  //   draw_scene(rctx, asset, asset.scenes[asset.scene.(gltf.Integer)], transform)
  // }
  return
}

destroy_model :: proc(vctx: ^vi.VkSDLContext, asset: ^GLTFAsset) {
  for i, texture in asset.albedo_textures {
    vi.destroy_texture(vctx, texture)
  }

  // for node in asset.nodes {
  //   vi.destroy_resource(vctx, node.vb)
  //   vi.destroy_resource(vctx, node.ib)
  //   vi.destroy_resource(vctx, node.mb)
  // }

  gltf.unload(asset._data)
  free(asset)
}

/////////////////////////////////////////////
/////////////////  Loading //////////////////
/////////////////////////////////////////////

// @(private="file") load_scene :: proc(vctx: ^vi.VkSDLContext, data: ^gltf.Data, asset: ^GLTFAsset, scene_index: int) -> (prs: ProcResult) {
//   asset_scene := &asset.all_scenes[scene_index]
  
//   // Initialize the scene node-list
//   asset_scene.nodes = make([]^GLTFNode, len(data.scenes[scene_index].nodes))

//   // Load the scene nodes
//   for node, node_index in data.scenes[scene_index].nodes {
//     prs = load_node(vctx, data, asset, i)
//     if prs != .Success {
//       fmt.eprintln("ERROR] Failed to load node:", i, "for scene:", scene_index, ":", prs)
//       fmt.eprintln("  TODO] Implement scene level cleanup")
//       return
//     }
//   }
  
//   return
// }

// @(private="file") load_node :: proc(vctx: ^vi.VkSDLContext, data: ^gltf.Data, asset: ^GLTFAsset, node_index: int) -> (prs: ProcResult) {
//   node := &data.nodes[node_index]

//   asset_node := create_node(vctx, data, asset, node) or_return
//   asset.all_scenes[asset.rendered_scene.? or_else 0].nodes = append(asset.all_scenes[asset.rendered_scene.? or_else 0].nodes, asset_node)
//   return
// }

// /////////////////////////////////////////////
// /////////////////  Drawing  /////////////////
// /////////////////////////////////////////////
// @(private="file") draw_scene :: proc(rctx: ^vi.RenderContext, asset: ^GLTFAsset, scene: ^gltf.Scene, transform: ^mat4) {
//   for node_index in scene.nodes {
//     draw_node(rctx, asset.nodes[node_index], transform) or_return
//   }
// }

// @(private="file") draw_node :: proc(rctx: ^vi.RenderContext, asset: ^GLTFAsset, node: ^gltf.Node, parent_transform: mat4) -> (prs: ProcResult) {
// //   if node.mesh != nil {
// //     // Check
// //     if node.camera != nil {
// //       fmt.println("ERROR-TODO] Please report encountering this. Expected node to only be mesh but has camera data")
// //       return .AssetProcessingError
// //     }
// //     if node.skin != nil {
// //       fmt.println("ERROR-TODO] Please report encountering this. Expected node to only be mesh but has skinning data")
// //       return .AssetProcessingError
// //     }

// //     // Draw the mesh
// //     draw_mesh(rctx, asset, asset.meshes[node.mesh.(gltf.Integer)], parent_transform * node.mat) or_return
// //   }
// //   else if node.camera != nil {
// //     // Check
// //     if node.skin != nil {
// //       fmt.println("ERROR-TODO] Please report encountering this. Expected node to only be camera but has skinning data")
// //       return .AssetProcessingError
// //     }

// //     fmt.eprintln("ERROR-TODO] Please report encountering this. Cannot handle drawing camera data")
// //     return .AssetProcessingError
// //   }
// //   else if node.skin != nil {
// //     fmt.eprintln("ERROR-TODO] Please report encountering this. Cannot handle drawing skinning data")
// //     return .AssetProcessingError
// //   }
// //   else {
// //     fmt.eprintln("ERROR-TODO] Please report encountering this. Expected node to have mesh, camera, or skinning data")
// //     return .AssetProcessingError
// //   }
// // }

// // // @(private="file") create_node :: proc(vctx: ^vi.VkSDLContext, data: ^gltf.Data, asset: ^GLTFAsset, node: gltf.Node) -> (
// // //     result: ^GLTFNode, prs: ProcResult) {
// // //   result = new(GLTFNode)
// // //   //  {
// // //   //   // name = auto_cast node.name,
// // //   //   // mesh: create_mesh(data, data.meshes[node.mesh]) or_return,
// // //   //   // children: [],
// // //   // }
  
// // //   // Load the mesh data
// // //   if node.mesh == nil {
// // //     fmt.println("ERROR-TODO] Please report encountering this. Expected node to have a mesh")
// // //     prs = .AssetLoadError
// // //     return
// // //   }
// // //   mesh_index := node.mesh.? or_else 0

// // //   if len(data.meshes[mesh_index].primitives) != 1 {
// // //     fmt.println("ERROR-TODO] Please report encountering this. Expected 1 primitive, got:", len(data.meshes[mesh_index].primitives))
// // //     prs = .AssetLoadError
// // //     return
// // //   }
// // //   load_mesh(vctx, data, &data.meshes[mesh_index].primitives[0], asset, result) or_return

// // //   // TODO Children
// // //   return
// // // }

// // @(private="file") load_mesh :: proc(vctx: ^vi.VkSDLContext, data: ^gltf.Data, primitive: ^gltf.Mesh_Primitive,
// //   gltf_asset: ^GLTFAsset, gltf_node: ^GLTFNode) -> (prs: ProcResult) {
  

// //   // // Process the glTF file
// //   // if len(data.meshes) != 1 {
// //   //   fmt.println("ERROR-TODO] Please report encountering this. Expected 1 mesh, got:", len(data.meshes))
// //   //   prs = .AssetLoadError
// //   //   return
// //   // }

// //   // if len(data.meshes[0].primitives) != 1 {
// //   //   fmt.println("ERROR-TODO] Please report encountering this. Expected 1 primitive, got:", len(data.meshes[0].primitives))
// //   //   prs = .AssetLoadError
// //   //   return
// //   // }

// //   // primitive := &data.meshes[0].primitives[0]
// //   if primitive.mode != .Triangles && primitive.indices != 3 {
// //     fmt.println("ERROR-TODO] Please report encountering this. Expected primitive mode TRIANGLES with 3 indices, got:",
// //     primitive.mode, primitive.indices)
// //     prs = .AssetLoadError
// //     return
// //   }
// //   if len(primitive.attributes) != 3 {
// //     fmt.println("ERROR-TODO] Please report encounting this. Expected 3 primitive attributes, got:", len(primitive.attributes))
// //     prs = .AssetLoadError
// //     return
// //   }
// //   if "POSITION" not_in primitive.attributes {
// //     fmt.println("ERROR-TODO] Please report encounting this. Expected primitive attribute POSITION")
// //     prs = .AssetLoadError
// //     return
// //   }
// //   if "NORMAL" not_in primitive.attributes {
// //     fmt.println("ERROR-TODO] Please report encounting this. Expected primitive attribute NORMAL")
// //     prs = .AssetLoadError
// //     return
// //   }
// //   if "TEXCOORD_0" not_in primitive.attributes {
// //     fmt.println("ERROR-TODO] Please report encounting this. Expected primitive attribute TEXCOORD_0")
// //     prs = .AssetLoadError
// //     return
// //   }

// //   // Get the accessor & buffer views
// //   pos_accessor := &data.accessors[primitive.attributes["POSITION"]]
// //   normal_accessor := &data.accessors[primitive.attributes["NORMAL"]]
// //   uv_accessor := &data.accessors[primitive.attributes["TEXCOORD_0"]]

// //   // Check that the buffer views are not nil
// //   if pos_accessor.buffer_view == nil || normal_accessor.buffer_view == nil || uv_accessor.buffer_view == nil {
// //     fmt.println("ERROR-TODO] Please report encountering this. Expected buffer views to be non-nil")
// //     prs = .AssetLoadError
// //     return
// //   }

// //   pos_bv := &data.buffer_views[pos_accessor.buffer_view.? or_else 0]
// //   normal_bv := &data.buffer_views[normal_accessor.buffer_view.? or_else 0]
// //   uv_bv := &data.buffer_views[uv_accessor.buffer_view.? or_else 0]

// //   // Create the Vertex Buffer
// //   vtx_count := data.accessors[primitive.attributes["POSITION"]].count
// //   vtcs := make([]PositionNormalUVVertex, vtx_count)
// //   gltf_node.vertices = auto_cast &vtcs[0]

// //   p_posv: [^]vec3 = auto_cast &data.buffers[pos_bv.buffer].uri.([]byte)[pos_bv.byte_offset]
// //   p_nrmv: [^]vec3 = auto_cast &data.buffers[normal_bv.buffer].uri.([]byte)[normal_bv.byte_offset]
// //   p_uvv: [^]vec2 = auto_cast &data.buffers[uv_bv.buffer].uri.([]byte)[uv_bv.byte_offset]
  
// //   for i in 0..<vtx_count {
// //     vtcs[i].pos = p_posv[i]
// //     vtcs[i].normal = p_nrmv[i]
// //     vtcs[i].uv = p_uvv[i]
// //   }

// //   gltf_node.vb = vi.create_vertex_buffer(vctx, &vtcs[0], size_of(PositionNormalUVVertex), auto_cast vtx_count) or_return

// //   // Create the Index Buffer
// //   if primitive.indices == nil {
// //     fmt.println("ERROR-TODO] Please report encountering this. Expected primitive to have indices")
// //     prs = .AssetLoadError
// //     return
// //   }
// //   idx_accessor := &data.accessors[primitive.indices.? or_else 0]
// //   if idx_accessor.buffer_view == nil {
// //     fmt.println("ERROR-TODO] Please report encountering this. Expected buffer view to be non-nil")
// //     prs = .AssetLoadError
// //     return
// //   }
// //   if idx_accessor.component_type != .Unsigned_Short && idx_accessor.component_type != .Unsigned_Int {
// //     fmt.println("ERROR-TODO] Please report encountering this. Expected index component type UNSIGNED_SHORT or UNSIGNED_INT, got:",
// //       idx_accessor.component_type)
// //     prs = .AssetLoadError
// //     return
// //   }
// //   idx_bv := &data.buffer_views[idx_accessor.buffer_view.? or_else 0]

// //   idx_count := idx_accessor.count
// //   indices := make([]u16, idx_count)
// //   gltf_node.indices = auto_cast &indices[0]

// //   p_idxv: [^]u16 = auto_cast &data.buffers[idx_bv.buffer].uri.([]byte)[idx_bv.byte_offset]
// //   for i in 0..<idx_count {
// //     indices[i] = p_idxv[i]
// //   }

// //   gltf_node.ib = vi.create_index_buffer(vctx, &indices[0], auto_cast idx_count) or_return

// //   // Model Uniform Buffer
// //   gltf_node.mb = vi.create_uniform_buffer(vctx, size_of(mat4) + size_of(vec3), .Dynamic) or_return

// //   // Load the material
// //   if primitive.material == nil {
// //     fmt.println("ERROR-TODO] Please report encountering this. Expected primitive to have a material")
// //     prs = .AssetLoadError
// //     return
// //   }
// //   material_index := primitive.material.? or_else 0
// //   if material_index >= auto_cast len(data.materials) {
// //     fmt.println("ERROR-TODO] Please report encountering this. Expected material index to be less than", len(data.materials),
// //       "got:", material_index)
// //     prs = .AssetLoadError
// //     return
// //   }
// //   material: ^gltf.Material = &data.materials[material_index]

// //   // Load the albedo texture
// //   if material.metallic_roughness == nil {
// //     fmt.println("ERROR-TODO] Please report encountering this. Expected material to exist and have a base color texture")
// //     prs = .AssetLoadError
// //     return
// //   }
// //   mmr: ^gltf.Material_Metallic_Roughness = &material.metallic_roughness.(gltf.Material_Metallic_Roughness)
// //   if mmr.base_color_texture == nil {
// //     // No material
// //     // fmt.println("ERROR-TODO] Please report encountering this. Expected material to have a base color texture")
// //     // prs = .AssetLoadError
// //     // return
// //   } else {
// //     albedo_index: int = auto_cast mmr.base_color_texture.(gltf.Texture_Info).index

// //     if cast(int)albedo_index not_in gltf_asset.albedo_textures {
// //       // Load the texture
// //       if albedo_index >= len(data.textures) {
// //         fmt.println("ERROR-TODO] Please report encountering this. Expected texture index to be less than", len(data.textures),
// //           "got:", albedo_index)
// //         prs = .AssetLoadError
// //         return
// //       }
// //       texture := &data.textures[albedo_index]
  
// //       if texture.source == nil {
// //         fmt.println("ERROR-TODO] Please report encountering this. Expected texture to have a source")
// //         prs = .AssetLoadError
// //         return
// //       }
// //       source_index := texture.source.? or_else 0
  
// //       if source_index >= auto_cast len(data.images) {
// //         fmt.println("ERROR-TODO] Please report encountering this. Expected image index to be less than", len(data.images),
// //           "got:", source_index)
// //         prs = .AssetLoadError
// //         return
// //       }
// //       image := &data.images[source_index]
  
// //       if image.buffer_view == nil {
// //         fmt.println("ERROR-TODO] Please report encountering this. Expected image to have a buffer view")
// //         prs = .AssetLoadError
// //         return
// //       }
// //       img_bv := &data.buffer_views[image.buffer_view.? or_else 0]
  
// //       // Load the texture from file
// //       img_th := vi.load_texture_from_memory(vctx, auto_cast &data.buffers[img_bv.buffer].uri.([]byte)[img_bv.byte_offset],
// //         auto_cast img_bv.byte_length) or_return
  
// //       // Set
// //       gltf_asset.albedo_textures[albedo_index] = img_th
// //       gltf_node.albedo_index = albedo_index
  
// //       // TODO Sampler?
// //     }
//   }

//   // fmt.println("copied indices:", indices)


//   // // chunk.vertex_buffer, verr = create_vertex_buffer(vctx, &vtx_cache[0], size_of(TerrainVertex), len(vtx_cache))
//   // // if verr != .Success do return auto_cast verr


//   // // terrain.index_buffer, verr = create_index_buffer(vctx, &indices[0], len(indices))
//   // // if verr != .Success do return auto_cast verr
//   // // // fmt.println("Index Buffer loaded:", terrain.index_buffer)

//   // // // Uniform Buffer
//   // // // terrain.uniform_buffer, verr = create_uniform_buffer(vctx, chunk_dim_size_of(mat4) + chunk_dim_size_of(vec3), .Dynamic)
//   // // // if verr != .Success do return auto_cast verr

//   // // terrain.frag_ubo, verr = create_uniform_buffer(vctx, size_of(vec3) * 2, .Dynamic)
//   // // if verr != .Success do return auto_cast verr
//   // // frag_data := [2]vec3 {
//   // //   la.normalize(vec3{0.18, 1.0, 0.3}),
//   // //   vec3{1.0, 0.9, 0.4},
//   // // }
//   // // verr = write_to_buffer(vctx, terrain.frag_ubo, &frag_data[0], size_of(vec3) * 2)
//   // // if verr != .Success do return auto_cast verr

//   // // terrain.albedo, verr = load_texture_from_file(vctx, ASSET_PATH_TerrainAlbedo)
//   // // if verr != .Success do return auto_cast verr


// //   return
// // }

// load_model_render_program :: proc(using vctx: ^vi.VkSDLContext, render_pass_3d: RenderPassResourceHandle, asset: ^GLTFAsset,
//     vert_shader_path: string, frag_shader_path: string) -> (render_program: RenderProgramResourceHandle, prs: ProcResult) {

//   // Declarations
//   descriptor_bindings := [?]vk.DescriptorSetLayoutBinding {
//     vk.DescriptorSetLayoutBinding {
//       binding = 0,
//       descriptorType = .UNIFORM_BUFFER,
//       stageFlags = { .VERTEX },
//       descriptorCount = 1,
//       pImmutableSamplers = nil,
//     },
//     vk.DescriptorSetLayoutBinding {
//       binding = 1,
//       descriptorType = .UNIFORM_BUFFER,
//       stageFlags = { .VERTEX },
//       descriptorCount = 1,
//       pImmutableSamplers = nil,
//     },
//     vk.DescriptorSetLayoutBinding {
//       binding = 2,
//       descriptorType = .UNIFORM_BUFFER,
//       stageFlags = { .FRAGMENT },
//       descriptorCount = 1,
//       pImmutableSamplers = nil,
//     },
//     vk.DescriptorSetLayoutBinding {
//       binding = 3,
//       descriptorType = .COMBINED_IMAGE_SAMPLER,
//       stageFlags = { .FRAGMENT },
//       descriptorCount = 1,
//       pImmutableSamplers = nil,
//     },
//   }
//   input_attributes := [?]vi.InputAttribute {
//     vi.InputAttribute {
//       format = .R32G32B32_SFLOAT,
//       location = 0,
//       offset = auto_cast offset_of(PositionNormalUVVertex, pos),
//     },
//     vi.InputAttribute {
//       format = .R32G32_SFLOAT,
//       location = 1,
//       offset = auto_cast offset_of(PositionNormalUVVertex, uv),
//     },
//     vi.InputAttribute {
//       format = .R32G32B32_SFLOAT,
//       location = 2,
//       offset = auto_cast offset_of(PositionNormalUVVertex, normal),
//     },
//   }

//   // Render Program
//   vs_data := vi._load_binary_file(vert_shader_path) or_return
//   fs_data := vi._load_binary_file(frag_shader_path) or_return
//   rpci := vi.RenderProgramCreateInfo {
//     pipeline_config = vi.PipelineCreateConfig {
//       render_pass = render_pass_3d,
//       vertex_shader_binary = vs_data,
//       fragment_shader_binary = fs_data,
//     },
//     vertex_size = size_of(PositionNormalUVVertex),
//     buffer_bindings = descriptor_bindings[:],
//     input_attributes = input_attributes[:],
//   }

//   render_program = vi.create_render_program(vctx, &rpci) or_return

//   return
// }