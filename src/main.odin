package client

import "core:fmt"
import "core:time"

import mx "core:math"

import "vendor:sdl2"
import vi "violin"

// The main procedure is the entry point of the game.
main :: proc() {
  pad := PropAppData {}

  prs := init_main(&pad)
  defer destroy_main(&pad)
  if prs != .Success {
    return
  }

  prs = game_loop(&pad)
  if prs != .Success {
    fmt.eprintln("Game loop failed:", prs)
    return
  }
}

init_main :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {

  // Vulkan-SDL
  vctx = new(vi.VkSDLContext)
  vi.init_vksdl(vctx, 1440, 900, window_bordered = false, init_sdl2_audio = false) or_return

  // Maximize the window
  // sdl2.MaximizeWindow(vctx.window)
  vi.init_frame_time(&ft)

  // Stamp Resources
  stamp_shaders := vi.load_stamp_shaders("shaders") or_return
  defer vi.destroy_stamp_shaders(&stamp_shaders)

  stamprr, prs = vi.init_stamp_batch_renderer(vctx, stamp_shaders, { .HasPreviousColorPass, .IsPresent })
  if prs != .Success {
    vi.destroy_resource(vctx, stamprr)
    return
  }

  pad.default_font = vi.load_font(vctx, "c:\\Windows\\Fonts\\RAVIE.TTF", 24) or_return
  pad.small_font = vi.load_font(vctx, "c:\\Windows\\Fonts\\SEGUISB.TTF", 24) or_return

  // Game
  init_player_input(pad) or_return
  init_game_camera(pad) or_return
  init_world(pad) or_return

  return
}

destroy_main :: proc(using pad: ^PropAppData) {
  // Game
  destroy_world(pad)
  destroy_game_camera(pad)

  // Stamp Resources
  vi.destroy_font(vctx, pad.default_font)
  vi.destroy_font(vctx, pad.small_font)
  vi.destroy_resource(vctx, stamprr)

  // Vulkan-SDL
  vi.destroy_vksdl(vctx)
}

game_loop :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {
  FPS_PRINT_PERIOD :: 32500
  @(static) fps_print_time: time.Time
  fps_print_time = time.time_add(time.now(), -time.Millisecond * (FPS_PRINT_PERIOD - 2000))
  do_break_loop: bool

  second: int = 0

  loop: for {
    if ft.frame_elapsed < 0.00068 do time.sleep(time.Microsecond * 1400)
    vi.update_frame_time(&ft)

    // Handle input
    do_end_loop := update_input(pad) or_return
    if do_end_loop do break

    // Update game
    update_world(pad) or_return

    // // Update render data
    // update_world_render_data(pad) or_return

    // Render game
    render_game(pad) or_return

    // Print FPS
    if time.diff(fps_print_time, time.now()) > time.Millisecond * FPS_PRINT_PERIOD {
      fps_print_time = time.now()
      print_fps(&ft)
    }

    // if ft.total_elapsed > 6.0 {
    //   print_fps(&ft)
    //   break
    // }
  }

  return
}

print_fps :: proc(ft: ^vi.FrameTime) {
  fmt.println(args={"fps:", cast(int) (1.0 / ft.running_avg), " 99%:",
    cast(int) (1.0 / ft.ninety_ninth), " max5:", cast(int) (ft.max5s_frame * 1000), "ms"}, sep="")
}

update_input :: proc(using pad: ^PropAppData) -> (do_end_loop: bool, prs: ProcResult) {

  reset_player_frame_input(pad)

  // Handle SDL Events (incl. Input)
  event: sdl2.Event
  for sdl2.PollEvent(&event) {
    #partial switch event.type {
      case .QUIT:
        do_end_loop = true
        return
      case .KEYDOWN, .KEYUP:
        #partial switch event.key.keysym.sym {
          case .ESCAPE, .F4:
            do_end_loop = true
            return
          case:
        }
        fallthrough
      case .KEYMAPCHANGED, .TEXTINPUT:
        fallthrough
      case .MOUSEMOTION, .MOUSEWHEEL, .MOUSEBUTTONDOWN, .MOUSEBUTTONUP:
        // handled, verr := handle_gui_event(gs.gui.root, &event)
        // if !handled {
        // Send the event to the world
        handle_player_input_event(pad, event) or_return
        // }
        // // fmt.println(".TEXTINPUT:", event.text.text)
      case .TEXTEDITING, .CLIPBOARDUPDATE:
        // Do nothing...
      case .WINDOWEVENT:
        #partial switch event.window.event {
          case .RESIZED, .RESTORED, .SIZE_CHANGED:
            // fmt.println("Window resized:", event.window.data1, event.window.data2)
            // vi.handle_resized_presentation(ctx)
            vctx.framebuffer_resized = true
            // TODO -- resize GUI
          case .CLOSE:
            do_end_loop = true
            return
          case:
            // fmt.println("Window event:", event.window.event)
        }
    }
  }

  // collate_player_frame_input(pad)

  return
}

render_game :: proc(using pad: ^PropAppData) -> (prs: ProcResult) {
  rctx := vi.begin_present(vctx) or_return

  render_world(pad, rctx) or_return

  render_ui(pad, rctx) or_return

  vi.end_present(rctx) or_return
  return
}

render_ui :: proc(using pad: ^PropAppData, rctx: ^vi.RenderContext) -> (prs: ProcResult) {
  
  vi.stamp_begin(rctx, stamprr) or_return

  fps_str := fmt.tprintf("fps:%d", cast(int) (1.0 / ft.running_avg))
  vi.stamp_text(rctx, stamprr, default_font, fps_str, 4, 28, &vi.COLOR_Gold) or_return
  // gs_str := fmt.tprintf("pos:%.1f,%.1f  time:%.1f (%d)", 0.0, 0.0, ft.total_elapsed, 1)
  // vi.stamp_text(rctx, stamprr, pad.default_font, gs_str, 4, 56, &vi.COLOR_Gold) or_return

  return
}