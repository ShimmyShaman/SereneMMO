package client

import "core:fmt"
import mx "core:math"
import la "core:math/linalg"

AvatarState :: struct {
  pos: vec3,
  rot: f32,

  look_dir: vec2,
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

  return
}