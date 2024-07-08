package client

import fmt "core:fmt"
import mx "core:math"
import la "core:math/linalg"
import rand "core:math/rand"

import vi "violin"

WorldData :: struct {
  render_pass: RenderPassResourceHandle,

  lumin_ubo: BufferResourceHandle,

  // terrain: vi.UtilityMesh,
  // terrain_ubo: BufferResourceHandle,

  avatar_model: ^GLTFAsset,
  alternate_model: ^GLTFAsset,

  avatar_state: AvatarState,

  npc: NPCState,

  terrain: Terrain,
}

NPCState :: struct {
  model: ^GLTFAsset,
  pos: vec3,
  rot: f32,
  hitpoints: int,
  global_cooldown: f32,
  poke_cooldown: f32,
  
  target_avatar: bool,
}

init_world :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {

  world.render_pass = vi.create_render_pass(vctx, { .HasDepthBuffer, }, clear_color = vi.Color {0.0, 0.0, 0.0, 1.0}) or_return

  // world.terrain = vi.construct_square_mesh(vctx, world.render_pass) or_return
  // world.terrain_ubo = vi.create_uniform_buffer(vctx, size_of(vi.UtilityMeshUBO), .Dynamic) or_return

  init_avatar_state(pad) or_return
  world.avatar_model = load_model(pad, "models/dwarfking.glb") or_return

  world.npc.model = load_model(pad, "models/pillbug1.glb") or_return
  world.npc.pos = vec3{15, 0, -4}
  world.npc.hitpoints = 20

  world.alternate_model = load_model(pad, "models/nullcube.glb") or_return
  // world.alternate_model = load_model(pad, "models/checkeredcube.glb") or_return
  // world.alternate_model = load_model(pad, "models/dwarfking.glb") or_return
  // world.alternate_model = load_model(pad, "models/alternate_model.glb") or_return

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

  destroy_model(vctx, world.alternate_model)
  destroy_model(vctx, world.avatar_model)
  destroy_model(vctx, world.npc.model)

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

  update_npcs(pad) or_return

  if world.avatar_state.hitpoints <= 0 {
    fmt.println("Avatar has died!")
    world.avatar_state.hitpoints = 24
    world.avatar_state.pos = vec3{0, 0, 0}
  }

  return
}

update_npcs :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {
  npc := &world.npc
  avs := &world.avatar_state

  if npc.hitpoints <= 0 {
    npc.global_cooldown -= ft.frame_elapsed
    if npc.global_cooldown <= 0 {
      fmt.println("NPC Revived!")
      npc.hitpoints = 20
    }
    return
  }

  delta := world.avatar_state.pos - npc.pos
  delta_dist := la.length(delta)
  if npc.target_avatar {
    npc.global_cooldown -= ft.frame_elapsed
    npc.poke_cooldown -= ft.frame_elapsed
    if delta_dist > 0.7 {
      npc.pos += la.normalize(delta) * ft.frame_elapsed * 0.8
    } else {
      if npc.global_cooldown <= 0 {
        npc.global_cooldown = 1.5
        
        if npc.poke_cooldown <= 0 && rand.int_max(3) > 1 {
          npc.poke_cooldown = 2.3

          dmg := 2 + (0 if rand.int_max(4) < 3 else 1 + (0 if rand.int_max(3) < 2 else 1))
          
          fmt.println("NPC Pokes Avatar for", dmg, "damage!")
          avs.hitpoints -= dmg
        } else {
          // Auto-attack
          dmg := 1 + (0 if rand.int_max(4) < 3 else 1)

          fmt.println("NPC Auto-attacks Avatar for", dmg, "damage!")
          avs.hitpoints -= dmg
        }
      }
    }

    // Rotate to Avatar
    {
      dir_to_avatar := la.normalize(vec3{avs.pos.x - npc.pos.x, 0, avs.pos.z - npc.pos.z})
      rot_to_avatar := mx.wrap(mx.atan2(dir_to_avatar.z, dir_to_avatar.x), mx.PI * 2.0)
      // fmt.println("Rot to Avatar:", rot_to_avatar, "NPC Rot:", npc.rot)

      // angle_dist := rot_to_avatar - npc.rot
      // if mx.abs(angle_dist) > 0.01 {
      //   rot_speed := ft.frame_elapsed * 1.5
      //   if mx.abs(angle_dist) < rot_speed {
      //     npc.rot = rot_to_avatar
      //   // } else if angle_dist > mx.PI {
      //   //   npc.rot += ft.frame_elapsed * 1.5
      //   // } else {
      //   //   npc.rot -= ft.frame_elapsed * 1.5
      //   // }

        npc.rot = mx.wrap(rot_to_avatar, mx.PI * 2.0)
      // }
    }
  } else if delta_dist < 5.0 {
    npc.target_avatar = true
    if avs.npc_target == nil {
      avs.npc_target = npc
    }
    fmt.println("NPC Targeting Avatar!")
  }
  return
}

kill_npc :: proc(using pad: ^PropAppData) {
  npc := &world.npc

  npc.hitpoints = 0
  npc.pos = vec3{15, 0, -4}
  npc.target_avatar = false
  world.avatar_state.npc_target = nil

  npc.global_cooldown = 8.0
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
  draw_model(pad, rctx, world.alternate_model, &transform) or_return

  if world.npc.hitpoints > 0 {
    transform = la.matrix4_translate_f32(world.npc.pos + vec3{0, 0.4, 0}) *
    la.matrix4_rotate_f32(-world.npc.rot + 0.5 * mx.PI, vec3{0, 1, 0}) * la.matrix4_scale_f32(vec3{2.5, 3, 1.5})
    draw_model(pad, rctx, world.npc.model, &transform) or_return
  }

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