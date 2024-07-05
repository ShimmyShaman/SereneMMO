package client

import "core:fmt"
import la "core:math/linalg"
import mx "core:math"

import sdl2 "vendor:sdl2"

import vi "violin"

GameCamera :: struct {
  view_rot: f32,
  pos: vec3,
  avatar_target_look_height_offset: f32,
  distance_from_avatar: f32,
  pitch: f32,

  up: vec3,
  fov: f32,

  view, proj, view_proj: mat4,

  ubo: vi.BufferResourceHandle,
}

@(private="file") CameraUBO :: struct {
  view_proj: mat4,
  pos: vec3,
}

init_game_camera :: proc(using pad: ^PropAppData) -> (ppr: ProcResult) {
  cam := &pad.game_camera
    
  cam.avatar_target_look_height_offset = 1.0
  cam.distance_from_avatar = 10.0
  cam.up = vec3{0, 1, 0}
  cam.fov = 0.7
  cam.pitch = -0.5

  // View Project Buffer
  cam.ubo = vi.create_uniform_buffer(vctx, size_of(CameraUBO), .Dynamic) or_return

  return
}

destroy_game_camera :: proc(using pad: ^PropAppData) -> (ppr: ProcResult) {
  cam := &pad.game_camera

  vi.destroy_resource(vctx, cam.ubo) or_return

  return
}

process_game_camera_input :: proc(pad: ^PropAppData) -> (ppr: ProcResult) {
  cam := &pad.game_camera
  using pin := &pad.player_input

  // Determine Avatar Control Mode
  if .SetMoveAndPanMode in pin.down {
    control_mode = .MoveAndPanMode
  } else if .SetPanMode in pin.down {
    control_mode = .PanMode
  } else {
    control_mode = .Default_Move
  }
      
  // Lock/Unlock Mouse Appropriately
  if mouse_locked == (control_mode == .Default_Move) {
    // Lock/Unlock appropriately
    if mouse_locked {
      // Disengage the world -- Unlock the mouse from the screen and show the cursor
      sdl2.CaptureMouse(false)
      sdl2.SetRelativeMouseMode(false)
      sdl2.SetWindowGrab(pad.vctx.window, false)
      mouse_locked = false
    } else {
      // Engage the world -- Lock the mouse to the screen and hide the cursor
      // TODO ? -- Check Return Value for functions that can fail
      sdl2.CaptureMouse(true)
      sdl2.SetRelativeMouseMode(true)
      sdl2.SetWindowGrab(pad.vctx.window, true)
      mouse_locked = true
    }
  }
  
  // Manage Camera Rotation
  avs := &pad.world.avatar_state
  #partial switch control_mode {
    case .PanMode, .MoveAndPanMode:
      // Rotate the camera
      if mouse_delta.x != 0 {
        cam.view_rot = mx.wrap(cam.view_rot - cast(f32)mouse_delta.x * config.mouse_x_sensitivity, mx.PI * 2.0)
      }

      if mouse_delta.y != 0 {
        mdy := cast(f32)mouse_delta.y * config.mouse_y_sensitivity
        MinPitch :: mx.PI * -0.94
        MaxPitch :: mx.PI * -0.03

        cam.pitch = mx.clamp(cam.pitch - mdy, MinPitch, MaxPitch)
      }

      // Set the Avatar Rotation if in MoveAndPanMode
      if control_mode == .MoveAndPanMode {
        avs.rot = cam.view_rot
      }
  }

  // Camera Distance
  if mouse_wheel != 0 {
    cam.distance_from_avatar = mx.clamp(cam.distance_from_avatar - cast(f32)mouse_wheel * config.mouse_wheel_sensitivity, 1.0, 20.0)
  }

  return
}

update_game_camera :: proc(using pad: ^PropAppData) -> (ppr: ProcResult) {
  cam := &pad.game_camera
  avs := &pad.world.avatar_state

  // Calculate cam position
  cam_offset := la.vector_normalize(vec3{mx.cos_f32(cam.view_rot), cam.pitch, -mx.sin_f32(cam.view_rot)})
  // cam_offset.y = 
  // fmt.println("cam_offset:", cam_offset)
  cam.pos = avs.pos - cam_offset * cam.distance_from_avatar

  // Update view/proj
  cam.view = la.matrix4_look_at(cam.pos, avs.pos + vec3{0, cam.avatar_target_look_height_offset, 0}, cam.up)
  cam.proj = la.matrix4_perspective(cam.fov, cast(f32)vctx.swap_chain.extent.width / cast(f32)vctx.swap_chain.extent.height,
            0.1, 10000)
  cam.view_proj = cam.proj * cam.view

  // Update UBO
  ubo_data := CameraUBO{
    view_proj = cam.view_proj,
    pos = cam.pos,
  }
  vi.write_to_buffer(vctx, cam.ubo, &ubo_data, size_of(CameraUBO)) or_return

  return
}