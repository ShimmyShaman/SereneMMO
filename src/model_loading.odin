package client

import "core:os"
import "core:fmt"
import "core:encoding"
import la "core:math/linalg"
import "core:strings"

import vk "vendor:vulkan"

import gltf "glTF2"

import vi "violin"
// import gltf "vendor:cgltf"

// ModelLoader :: struct {
//   render_programs: map[]
// }

GLTFAsset :: struct {
  using _data: ^gltf.Data,

  // // Scene to render (if nil, render all scenes)
  // rendered_scene: Maybe(int),
  // all_scenes: []GLTFScene,
  // nodes: []GLTFNode,

  albedo_textures: map[int]vi.TextureResourceHandle,
  // vertex_buffers: []vi.VertexBufferResourceHandle,
  // index_buffers: []vi.IndexBufferResourceHandle,
  // model_transform_buffers: []vi.BufferResourceHandle,
  render_programs: []vi.RenderProgramResourceHandle,
  mesh_buffers: []MeshPrimitiveBufferGroup,
}

@(private) PosNormUVVertex :: struct {
  using pos: vec3,
  normal: vec3,
  uv: vec2,
}

@(private) RenderParameterKey :: enum {
  CameraUBO,
  ModelTransformUBO,
  // LightDirection,
  // LightColor,
  AlbedoTexture,
}

@(private) ModelRenderProgram :: struct {
  render_program: vi.RenderProgramResourceHandle,
  parameter_keys: []RenderParameterKey,
}

MeshPrimitiveBufferGroup :: struct {
  raw_verts: []PosNormUVVertex,
  raw_indices: []u16,

  vertex_buffer: vi.VertexBufferResourceHandle,
  index_buffer: vi.IndexBufferResourceHandle,
  model_transform_buffer: vi.BufferResourceHandle,
  render_program: ModelRenderProgram,
}

load_model :: proc(pad: ^PropAppData, file_name: string) -> (asset: ^GLTFAsset, prs: ProcResult) {

  data, gl_err := gltf.load_from_file(file_name)
  if gl_err != nil {
    fmt.println("ERROR] Failed to load glTF file:", gl_err)
    prs = .AssetLoadError
    return
  }

  // Create the asset
  asset = new(GLTFAsset)
  asset._data = data
  
  // Check nodes (TODO necessary?)
  // for node in data.nodes {
  //   if node.mesh != nil {
  //     // Check
  //     if node.camera != nil {
  //       fmt.println("ERROR-TODO] Please report encountering this. Expected node to only be mesh but has camera data")
  //       prs = .AssetProcessingError
  //       return
  //     }
  //     if node.skin != nil {
  //       fmt.println("ERROR-TODO] Please report encountering this. Expected node to only be mesh but has skinning data")
  //       prs = .AssetProcessingError
  //       return
  //     }

  //     fmt.eprintln("ERROR-TODO] Please report encountering this. Cannot handle node with mesh")
  //   }
  //   else if node.camera != nil {
  //     // Check
  //     if node.skin != nil {
  //       fmt.println("ERROR-TODO] Please report encountering this. Expected node to only be camera but has skinning data")
  //       prs = .AssetProcessingError
  //       return
  //     }
  
  //     fmt.eprintln("ERROR-TODO] Please report encountering this. Cannot handle node with camera")
  //     prs = .AssetProcessingError
  //     return
  //   }
  //   else if node.skin != nil {
  //     fmt.eprintln("ERROR-TODO] Please report encountering this. Cannot handle node with skinning data")
  //     prs = .AssetProcessingError
  //     return
  //   }
  //   else {
  //     fmt.eprintln("ERROR-TODO] Please report encountering this. Expected node to have mesh, camera, or skinning data")
  //     fmt.eprintln("  node:", node)
  //     prs = .AssetProcessingError
  //     return
  //   }
  //   TODO -- can also be a skeleton node
  // }

  // Mesh Loading
  load_all_materials(pad, asset, data) or_return
  load_all_meshes(pad, asset, data) or_return

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

  return
}

@(private="file") load_all_materials :: proc(pad: ^PropAppData, asset: ^GLTFAsset, data: ^gltf.Data) -> (prs: ProcResult) {
  // Load the albedo texture
  asset.albedo_textures = make(map[int]vi.TextureResourceHandle, len(data.textures))
  for texture, index in data.textures {
    if texture.source == nil {
      fmt.println("ERROR-TODO] Please report encountering this. Expected texture to have a source")
      prs = .AssetLoadError
      return
    }
    source_index := texture.source.(gltf.Integer) or_else 0

    if source_index >= auto_cast len(data.images) {
      fmt.println("ERROR-TODO] Please report encountering this. Expected image index to be less than", len(data.images),
        "got:", source_index)
      prs = .AssetLoadError
      return
    }
    image := &data.images[source_index]

    if image.buffer_view == nil {
      fmt.println("ERROR-TODO] Please report encountering this. Expected image to have a buffer view")
      prs = .AssetLoadError
      return
    }
    img_bv := &data.buffer_views[image.buffer_view.? or_else 0]

    // Load the texture from file
    img_th := vi.load_texture_from_memory(pad.vctx, &data.buffers[img_bv.buffer].uri.([]byte)[img_bv.byte_offset],
      auto_cast img_bv.byte_length) or_return

    // Set
    asset.albedo_textures[index] = img_th
  }

  return

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
}

@(private="file") load_all_meshes :: proc(pad: ^PropAppData, asset: ^GLTFAsset, data: ^gltf.Data) -> (prs: ProcResult) {
  asset.mesh_buffers = make([]MeshPrimitiveBufferGroup, len(data.meshes))
  for mesh, index in data.meshes {
    // Create the MeshPrimitiveBufferGroup
    mbi := &asset.mesh_buffers[index]
    // asset.mesh_buffers[index].vertex_buffer = make(vi.VertexBufferResourceHandle, len(mesh.primitives))
    // asset.mesh_buffers[index].index_buffer = make(vi.IndexBufferResourceHandle, len(mesh.primitives))
    // asset.mesh_buffers[index].model_transform_buffer = make(vi.BufferResourceHandle, len(mesh.primitives))
    // asset.mesh_buffers[index].render_program = make(vi.RenderProgramResourceHandle, len(mesh.primitives))

    if len(mesh.primitives) != 1 {
      fmt.println("ERROR-TODO] Please report encountering this. Only support 1 primitive, got:", len(mesh.primitives))
      prs = .AssetLoadError
      return
    }

    for primitive, p_index in mesh.primitives {
      // Check
      if primitive.mode != .Triangles {
        fmt.println("ERROR-TODO] Please report encountering this. Only supporting TRIANGLES right now:", primitive.mode)
        prs = .AssetProcessingError
        return
      }
      if len(primitive.attributes) != 3 {
        fmt.println("WARN-TODO] Please report encounting this. Expected 3 primitive attributes, got:", len(primitive.attributes), primitive.attributes)
        // prs = .AssetLoadError
        // return
      }
      if "POSITION" not_in primitive.attributes {
        fmt.println("ERROR-TODO] Please report encounting this. Expected primitive attribute POSITION")
        prs = .AssetLoadError
        return
      }
      if "NORMAL" not_in primitive.attributes {
        fmt.println("ERROR-TODO] Please report encounting this. Expected primitive attribute NORMAL")
        prs = .AssetLoadError
        return
      }
      if "TEXCOORD_0" not_in primitive.attributes {
        fmt.println("ERROR-TODO] Please report encounting this. Expected primitive attribute TEXCOORD_0")
        prs = .AssetLoadError
        return
      }
  
      fmt.println("primitive:", primitive)
      fmt.println("material:", asset.materials[primitive.material.(gltf.Integer)])

      // Find the Render Program corresponding to the material
      mbi.render_program = get_render_program(pad, primitive, asset.materials[primitive.material.(gltf.Integer)]) or_return

      // Get the accessor & buffer views
      pos_accessor := &data.accessors[primitive.attributes["POSITION"]]
      normal_accessor := &data.accessors[primitive.attributes["NORMAL"]]
      uv_accessor := &data.accessors[primitive.attributes["TEXCOORD_0"]]

      // Check that the buffer views are not nil
      if pos_accessor.buffer_view == nil || normal_accessor.buffer_view == nil || uv_accessor.buffer_view == nil {
        fmt.println("ERROR-TODO] Please report encountering this. Expected buffer views to be non-nil")
        prs = .AssetLoadError
        return
      }

      pos_bv := &data.buffer_views[pos_accessor.buffer_view.? or_else 0]
      normal_bv := &data.buffer_views[normal_accessor.buffer_view.? or_else 0]
      uv_bv := &data.buffer_views[uv_accessor.buffer_view.? or_else 0]

      // fmt.println("pos_bv:", pos_bv)
      // fmt.println("normal_bv:", normal_bv)
      // fmt.println("uv_bv:", uv_bv)

      // Create the Vertex Buffer
      vtx_count := data.accessors[primitive.attributes["POSITION"]].count
      mbi.raw_verts = make([]PosNormUVVertex, vtx_count)

      p_posv: [^]vec3 = auto_cast &data.buffers[pos_bv.buffer].uri.([]byte)[pos_bv.byte_offset]
      p_nrmv: [^]vec3 = auto_cast &data.buffers[normal_bv.buffer].uri.([]byte)[normal_bv.byte_offset]
      p_uvv: [^]vec2 = auto_cast &data.buffers[uv_bv.buffer].uri.([]byte)[uv_bv.byte_offset]

      for i in 0..<vtx_count {
        mbi.raw_verts[i].pos = p_posv[i]
        mbi.raw_verts[i].normal = p_nrmv[i]
        mbi.raw_verts[i].uv = p_uvv[i]
      }

      mbi.vertex_buffer = vi.create_vertex_buffer(pad.vctx, &mbi.raw_verts[0], size_of(PosNormUVVertex), auto_cast vtx_count) or_return

      // Create the Index Buffer
      if primitive.indices == nil {
        fmt.println("ERROR-TODO] Please report encountering this. Expected primitive to have indices")
        prs = .AssetLoadError
        return
      }
      idx_accessor := &data.accessors[primitive.indices.? or_else 0]
      if idx_accessor.buffer_view == nil {
        fmt.println("ERROR-TODO] Please report encountering this. Expected buffer view to be non-nil")
        prs = .AssetLoadError
        return
      }
      if idx_accessor.component_type != .Unsigned_Short && idx_accessor.component_type != .Unsigned_Int {
        fmt.println("ERROR-TODO] Please report encountering this. Expected index component type UNSIGNED_SHORT or UNSIGNED_INT, got:",
          idx_accessor.component_type)
        prs = .AssetLoadError
        return
      }
      idx_bv := &data.buffer_views[idx_accessor.buffer_view.? or_else 0]

      idx_count := idx_accessor.count
      mbi.raw_indices = make([]u16, idx_count)

      p_idxv: [^]u16 = auto_cast &data.buffers[idx_bv.buffer].uri.([]byte)[idx_bv.byte_offset]
      for i in 0..<idx_count {
        mbi.raw_indices[i] = p_idxv[i]
      }

      mbi.index_buffer = vi.create_index_buffer(pad.vctx, &mbi.raw_indices[0], auto_cast idx_count) or_return

      mbi.model_transform_buffer = vi.create_uniform_buffer(pad.vctx, size_of(mat4), .Dynamic) or_return
    }

    // fmt.println("mbi:", mbi)
  }
  return
}

get_render_program :: proc(pad: ^PropAppData, primitive: gltf.Mesh_Primitive, material: gltf.Material) -> (rp: ModelRenderProgram, prs: ProcResult) {
      // input_attributes: []vi.InputAttribute
      // for attrib_name, attrib_index in primitive.attributes {
      //   switch attrib {
      //     case "POSITION":
      //   //     input_attributes = append(input_attributes, vi.InputAttribute {
      //   //       format: .R32G32B32_SFLOAT,
      //   //       location: 0,
      //   //       offset: auto_cast offset_of(PosNormUVVertex, pos),
      //   //     })
      //   //   case "NORMAL":
      //   //     input_attributes = append(input_attributes, vi.InputAttribute {
      //   //       format: .R32G32B32_SFLOAT,
      //   //       location: 1,
      //   //       offset: auto_cast offset_of(PosNormUVVertex, normal),
      //   //     })
      //   //   // case "TEXCOORD_0":
      //   //   //   input_attributes = append(input_attributes, vi.InputAttribute {
      //   //   //     format: .R32G32_SFLOAT,
      //   //   //     location: 2,
      //   //   //     offset: auto_cast offset_of(PosNormUVVertex, uv),
      //   //   //   })
      //   //   else {
      //   //     fmt.println("ERROR-TODO] Please report encountering this. Unexpected primitive attribute:", attrib)
      //   //     prs = .AssetProcessingError
      //   //     return
      //   //   }
      //   // }
      // }
  // Temp only-render-program check
  if len(primitive.attributes) != 3 {
    fmt.println("WARN-TODO] Please report encountering this. Expected 3 primitive attributes, got:", len(primitive.attributes), primitive.attributes)
    // prs = .AssetProcessingError
    // return
  }
      
  // Declarations
  input_attributes := [?]vi.InputAttribute {
    vi.InputAttribute {
      format = .R32G32B32_SFLOAT,
      location = 0,
      offset = auto_cast offset_of(PosNormUVVertex, pos),
    },
    vi.InputAttribute {
      format = .R32G32B32_SFLOAT,
      location = 1,
      offset = auto_cast offset_of(PosNormUVVertex, normal),
    },
    vi.InputAttribute {
      format = .R32G32_SFLOAT,
      location = 2,
      offset = auto_cast offset_of(PosNormUVVertex, uv),
    },
  }
  descriptor_bindings := [?]vk.DescriptorSetLayoutBinding {
    // Camera UBO
    vk.DescriptorSetLayoutBinding {
      binding = 0,
      descriptorType = .UNIFORM_BUFFER,
      stageFlags = { .VERTEX },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
    // Model Transform UBO
    vk.DescriptorSetLayoutBinding {
      binding = 1,
      descriptorType = .UNIFORM_BUFFER,
      stageFlags = { .VERTEX },
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
  rp.parameter_keys = make([]RenderParameterKey, 3)
  rp.parameter_keys[0] = .CameraUBO
  rp.parameter_keys[1] = .ModelTransformUBO
  rp.parameter_keys[2] = .AlbedoTexture

  // Load the asset
  vs_data := vi.load_binary_file("shaders/pbr0.vert.spv") or_return
  fs_data := vi.load_binary_file("shaders/pbr0.frag.spv") or_return
  rpci := vi.RenderProgramCreateInfo {
    vertex_size = size_of(PosNormUVVertex),
    buffer_bindings = descriptor_bindings[:],
    input_attributes = input_attributes[:],
    pipeline_config = vi.PipelineCreateConfig {
      render_pass = pad.world.render_pass,
      vertex_shader_binary = vs_data,
      fragment_shader_binary = fs_data,
    },
  }
  rp.render_program = vi.create_render_program(pad.vctx, &rpci) or_return

  return
}

draw_model :: proc(pad: ^PropAppData, rctx: ^vi.RenderContext, asset: ^GLTFAsset, transform: ^mat4) -> (prs: ProcResult)  {
  // Determine the scene(s) to render
  if asset.scene == nil {
    for scene in asset.scenes {
      draw_scene(pad, rctx, asset, scene, transform)
    }
  } else {
    draw_scene(pad, rctx, asset, asset.scenes[asset.scene.(gltf.Integer)], transform)
  }
  return
}

destroy_model :: proc(vctx: ^vi.VkSDLContext, asset: ^GLTFAsset) {
  for i, texture in asset.albedo_textures {
    vi.destroy_texture(vctx, texture)
  }

  for mbi in asset.mesh_buffers {
    vi.destroy_resource(vctx, mbi.vertex_buffer)
    vi.destroy_resource(vctx, mbi.index_buffer)
    vi.destroy_resource(vctx, mbi.model_transform_buffer)
    vi.destroy_resource(vctx, mbi.render_program.render_program)
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
@(private="file") draw_scene :: proc(pad: ^PropAppData, rctx: ^vi.RenderContext, asset: ^GLTFAsset, scene: gltf.Scene, transform: ^mat4) -> (prs: ProcResult) {
  for node_index in scene.nodes {
    draw_node(pad, rctx, asset, asset.nodes[node_index], transform^) or_return
  }
  return
}


@(private="file") draw_node :: proc(pad: ^PropAppData, rctx: ^vi.RenderContext, asset: ^GLTFAsset, node: gltf.Node, parent_transform: mat4) -> (prs: ProcResult) {
  // @(static) depth := 0
  // for i in 0..<depth {
  //   fmt.print("- ")
  // }
  // fmt.println("draw_node] node:", node)

  if node.camera != nil {
    @(static) reported := false
    if reported == false {
      fmt.println("ERROR-TODO] Please report encountering this. Cannot draw node with camera data")
      fmt.println("  node:", node)
      reported = true
    }
  }

  transform: mat4 = parent_transform * node.transform

  if node.mesh != nil {
    mbi := asset.mesh_buffers[node.mesh.(gltf.Integer)]

    // fmt.println("mbi:", mbi)

    // Draw the mesh
    parameters: [12]vi.ResourceHandle
    for key, idx in mbi.render_program.parameter_keys {
      switch key {
        case .CameraUBO:
          parameters[idx] = auto_cast pad.game_camera.ubo
        case .ModelTransformUBO:
          // tsfm := la.matrix4_translate_f32(vec3{0, 0, 0})
          vi.write_to_buffer(pad.vctx, mbi.model_transform_buffer, &transform, size_of(mat4)) or_return
          
          parameters[idx] = auto_cast mbi.model_transform_buffer
        // case .LightDirection:
        //   parameters[key] = asset.light_direction_ubo
        // case .LightColor:
        //   parameters[key] = asset.light_color_ubo
        case .AlbedoTexture:
          // TODO -- make this more robust
          mesh := &asset.meshes[node.mesh.(gltf.Integer)]
          primitive := &mesh.primitives[0]
          mat := &asset.materials[primitive.material.(gltf.Integer)]
          albedo_index := mat.metallic_roughness.(gltf.Material_Metallic_Roughness).base_color_texture.(gltf.Texture_Info).index
      
          parameters[key] = auto_cast asset.albedo_textures[auto_cast albedo_index]
        case:
          fmt.println("ERROR-TODO] Please report encountering this. Unexpected RenderParameterKey:", key)
          return .NotYetImplemented
      }
    }

    vi.draw_indexed(rctx, mbi.render_program.render_program, mbi.vertex_buffer, mbi.index_buffer, parameters[0:len(mbi.render_program.parameter_keys)]) or_return
  }

  for child_index in node.children {
    // depth += 1
    draw_node(pad, rctx, asset, asset.nodes[child_index], transform) or_return
    // depth -= 1
  }
  
  return
}

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
// //   vtcs := make([]PosNormUVVertex, vtx_count)
// //   gltf_node.vertices = auto_cast &vtcs[0]

// //   p_posv: [^]vec3 = auto_cast &data.buffers[pos_bv.buffer].uri.([]byte)[pos_bv.byte_offset]
// //   p_nrmv: [^]vec3 = auto_cast &data.buffers[normal_bv.buffer].uri.([]byte)[normal_bv.byte_offset]
// //   p_uvv: [^]vec2 = auto_cast &data.buffers[uv_bv.buffer].uri.([]byte)[uv_bv.byte_offset]
  
// //   for i in 0..<vtx_count {
// //     vtcs[i].pos = p_posv[i]
// //     vtcs[i].normal = p_nrmv[i]
// //     vtcs[i].uv = p_uvv[i]
// //   }

// //   gltf_node.vb = vi.create_vertex_buffer(vctx, &vtcs[0], size_of(PosNormUVVertex), auto_cast vtx_count) or_return

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
//       offset = auto_cast offset_of(PosNormUVVertex, pos),
//     },
//     vi.InputAttribute {
//       format = .R32G32_SFLOAT,
//       location = 1,
//       offset = auto_cast offset_of(PosNormUVVertex, uv),
//     },
//     vi.InputAttribute {
//       format = .R32G32B32_SFLOAT,
//       location = 2,
//       offset = auto_cast offset_of(PosNormUVVertex, normal),
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
//     vertex_size = size_of(PosNormUVVertex),
//     buffer_bindings = descriptor_bindings[:],
//     input_attributes = input_attributes[:],
//   }

//   render_program = vi.create_render_program(vctx, &rpci) or_return

//   return
// }