package client

import "core:fmt"

import sdl2 "vendor:sdl2"

AvatarControlMode :: enum {
  Default_Move,
  PanMode,
  MoveAndPanMode,
}

InputCode :: enum {
  Forward,
  Backward,
  // Left,
  // Right,
  // Jump,
  // Crouch,
  // Sprint,
  // Interact,
  // Inventory,
  // Menu,
  // Debug,
  // Console,
  // Chat,
  // Screenshot,
  // Fullscreen,
  // Exit,

  SetMoveAndPanMode,
  SetPanMode,
}

InputConfig :: struct {
  mouse_x_sensitivity: f32,
  mouse_y_sensitivity: f32,
  mouse_wheel_sensitivity: f32,
}

PlayerInput :: struct {
  config: InputConfig,

  mouse_locked: bool,
  control_mode: AvatarControlMode,

  // Frame Input
  mouse_delta: vec2i,
  mouse_wheel: i32,

  keyboard_map: map[sdl2.Scancode]InputCode,
  mouse_map: map[u8]InputCode,

  pressed: map[InputCode]bool,
  released: map[InputCode]bool,
  down: map[InputCode]bool,
}

init_player_input :: proc(pad: ^PropAppData) -> (prs: ProcResult) {
  using _pin := &pad.player_input

  keyboard_map = make_map(map[sdl2.Scancode]InputCode, 32)
  keyboard_map[.SEMICOLON] = .Forward
  keyboard_map[.W] = .Forward
  keyboard_map[.D] = .Backward

  mouse_map = make_map(map[u8]InputCode, 4)
  mouse_map[sdl2.BUTTON_LEFT] = .SetPanMode
  mouse_map[sdl2.BUTTON_RIGHT] = .SetMoveAndPanMode

  config = InputConfig {
    mouse_x_sensitivity = 0.004,
    mouse_y_sensitivity = 0.004,
    mouse_wheel_sensitivity = 0.5,
  }

  return
}

reset_player_frame_input :: proc(pad: ^PropAppData) {
  pin := &pad.player_input

  pin.mouse_delta = vec2i{0, 0}
  pin.mouse_wheel = 0

  clear(&pin.pressed)
  clear(&pin.released)
}

handle_player_input_event :: proc(using pad: ^PropAppData, event: sdl2.Event) -> (prs: ProcResult) {
  pin := &pad.player_input

  #partial switch event.type {
    case .MOUSEMOTION:
      pin.mouse_delta += vec2i{event.motion.xrel, event.motion.yrel}
    case .MOUSEBUTTONDOWN:
      if event.button.button in pin.mouse_map {
        pin.pressed[pin.mouse_map[event.button.button]] = true
        pin.down[pin.mouse_map[event.button.button]] = true
      }
    case .MOUSEBUTTONUP:
      if event.button.button in pin.mouse_map {
        pin.released[pin.mouse_map[event.button.button]] = true
        delete_key(&pin.down, pin.mouse_map[event.button.button])
      }
    case .MOUSEWHEEL:
      pin.mouse_wheel += event.wheel.y
    case .KEYDOWN:
      if event.key.keysym.scancode in pin.keyboard_map {
        pin.pressed[pin.keyboard_map[event.key.keysym.scancode]] = true
        pin.down[pin.keyboard_map[event.key.keysym.scancode]] = true
      }
    case .KEYUP:
      if event.key.keysym.scancode in pin.keyboard_map {
        pin.released[pin.keyboard_map[event.key.keysym.scancode]] = true
        delete_key(&pin.down, pin.keyboard_map[event.key.keysym.scancode])
      }

    case .TEXTINPUT:
      // fmt.println("TEXTINPUT:", event.text.text)
    case:
      fmt.println("handle_player_input_event: Unhandled event type: ", event.type)
  }

  return
}