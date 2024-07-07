package client

import fmt "core:fmt"
import mx "core:math"
import la "core:math/linalg"

import vi "violin"

WorldData :: struct {
  render_pass: RenderPassResourceHandle,

  lumin_ubo: BufferResourceHandle,

  // terrain: vi.UtilityMesh,
  // terrain_ubo: BufferResourceHandle,

  avatar_model: ^GLTFAsset,

  castle_guard: ^GLTFAsset,

  avatar_state: AvatarState,

  terrain: Terrain,
}

init_world :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {

  world.render_pass = vi.create_render_pass(vctx, { .HasDepthBuffer, }, clear_color = vi.Color {0.0, 0.0, 0.0, 1.0}) or_return

  // world.terrain = vi.construct_square_mesh(vctx, world.render_pass) or_return
  // world.terrain_ubo = vi.create_uniform_buffer(vctx, size_of(vi.UtilityMeshUBO), .Dynamic) or_return

  // Update the World Matrix UBO
  ubo_data: vi.UtilityMeshUBO
  ubo_data.transform = la.matrix4_scale_f32(vec3{5,1,3})
  ubo_data.color = vi.to_vec4(vi.COLOR_DarkGreen)
  vi.write_to_buffer(vctx, world.terrain_ubo, &ubo_data, size_of(vi.UtilityMeshUBO)) or_return

  world.avatar_model = load_model(pad, "models/dwarfking.glb") or_return

  // world.npc_bug = load_model(vctx, "models/castle_guard.glb") or_return
  // world.npc_rp = load_model_render_program(vctx, world.render_pass, world.npc_bug, "shaders/model.vert.spv", "shaders/model.frag.spv") or_return
  // for i in 0..<3 {
  //   ubo := vi.create_uniform_buffer(vctx, size_of(vi.UtilityMeshUBO), .Dynamic) or_return
  //   append(&world.bug_ubos, ubo)
  // }

  world.castle_guard = load_model(pad, "models/nullcube.glb") or_return
  // world.castle_guard = load_model(pad, "models/checkeredcube.glb") or_return
  // world.castle_guard = load_model(pad, "models/dwarfking.glb") or_return
  // world.castle_guard = load_model(pad, "models/castle_guard.glb") or_return

  // Lighting
  world.lumin_ubo = vi.create_uniform_buffer(vctx, size_of(vec4) * 2, .Dynamic) or_return
  frag_data := [2]vec4 {
    la.normalize(vec4{-0.18, 1.0, -0.3, 1.0}), // Light direction
    vec4{0.98, 0.99, 0.74, 1.0}, // Light color
  }
  vi.write_to_buffer(vctx,  world.lumin_ubo, &frag_data[0], size_of(vec4) * 2) or_return

  world.avatar_state.rot = 3.14

  init_terrain(pad) or_return

  return
}

destroy_world :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {

  destroy_terrain(pad)

  vi.destroy_buffer(vctx, world.lumin_ubo)

  vi.destroy_render_pass(vctx, world.render_pass)

  destroy_model(vctx, world.castle_guard)
  destroy_model(vctx, world.avatar_model)

  // vi.destroy_render_program(vctx, world.npc_rp)
  // destroy_model(vctx, world.npc_bug)

  return
}

update_world :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {

  // process_player_input(pad) or_return

  process_game_camera_input(pad) or_return

  // Input
  update_avatar_state(pad) or_return

  // View
  update_game_camera(pad) or_return

  update_terrain(pad) or_return

  return
}

render_world :: proc(using pad: ^PropAppData, rctx: ^vi.RenderContext) -> (prs: ProcResult) {
  vi.begin_render_pass(rctx, world.render_pass) or_return

  // vi.draw_indexed(rctx, world.terrain.rp, world.terrain.vb, world.terrain.ib,
  //   []vi.ResourceHandle{auto_cast game_camera.ubo, auto_cast world.terrain_ubo})



  transform := la.matrix4_translate_f32(world.avatar_state.pos + vec3{0, 0.43, 0}) *
    la.matrix4_rotate_f32(world.avatar_state.rot + mx.PI * 0.5, vec3{0, 1, 0}) * la.matrix4_scale_f32(vec3{1, 1, 1})
  draw_model(pad, rctx, world.avatar_model, &transform) or_return

  transform = la.matrix4_translate_f32(vec3{3, 0.43, 3})
  draw_model(pad, rctx, world.castle_guard, &transform) or_return

  render_terrain(pad, rctx) or_return

  return
}

// draw_model :: proc(using pad: ^PropAppData, rctx: ^vi.RenderContext, model: ^GLTFAsset, rp: RenderProgramResourceHandle, transform: ^mat4) -> (prs: ProcResult) {
//   for node in model.nodes {
//     vi.write_to_buffer(vctx, node.mb, transform, size_of(mat4)) or_return
//     vi.draw_indexed(rctx, rp, node.vb, node.ib,
//       []ResourceHandle{auto_cast game_camera.ubo, auto_cast node.mb, auto_cast world.lumin_ubo,
//         auto_cast model.albedo_textures[node.albedo_index]}) or_return
//   }
//   return
// }