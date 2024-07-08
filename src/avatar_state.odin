package client

import "core:fmt"
import rand "core:math/rand"
import mx "core:math"
import la "core:math/linalg"

AvatarState :: struct {
  pos: vec3,
  rot: f32,

  hitpoints: int,

  look_dir: vec2,

  npc_target: ^NPCState,

  global_cooldown: f32,
  power_cooldown: f32,

  power_strike_queued: bool,
}

init_avatar_state :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {
  avs := &world.avatar_state

  avs.pos = vec3{0, 0, 0}
  avs.rot = 0
  avs.hitpoints = 24

  return
}

update_avatar_state :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {
  // Update the Avatar State
  avs := &world.avatar_state
  pin := &player_input

  // Handle Movement
  
  // Update the Avatar Look Direction
  avs.look_dir = la.normalize(vec2{mx.cos(avs.rot), -mx.sin(avs.rot)})

  movement_speed := ft.frame_elapsed * 2.0

  delta := vec3{0, 0, 0}
  if .Forward in pin.down {
    delta += vec3{avs.look_dir.x, 0, avs.look_dir.y} * movement_speed
  }
  if .Backward in pin.down {
    delta -= vec3{avs.look_dir.x, 0, avs.look_dir.y} * movement_speed
  }

  avs.pos += delta

  // Attacks
  avs.global_cooldown -= ft.frame_elapsed
  avs.power_cooldown -= ft.frame_elapsed
  if avs.power_cooldown <= 0 && .PowerStrike in pin.down {
    avs.power_strike_queued = true
  }

  if avs.npc_target != nil {
    dist := la.length(avs.pos - avs.npc_target.pos)
    if dist < 1.0 {
      if avs.global_cooldown <= 0 {
        avs.global_cooldown = 1.5

        if avs.power_strike_queued {
          avs.power_strike_queued = false
          avs.power_cooldown = 2.8

          dmg := 2 + (0 if rand.int_max(4) < 3 else 1 + (0 if rand.int_max(3) < 2 else 1))

          fmt.println("Avatar Power Attacks NPC for", dmg, "damage!")
          avs.npc_target.hitpoints -= dmg
        } else {
          // Auto-attack
          dmg := 1 + (0 if rand.int_max(4) < 3 else 1)

          fmt.println("Avatar Auto-attacks NPC for", dmg, "damage!")
          avs.npc_target.hitpoints -= dmg
        }

        if avs.npc_target.hitpoints <= 0 {
          fmt.println("NPC has died!")
          avs.npc_target = nil
          kill_npc(pad)
        }
      }
    }
  }

  return
}