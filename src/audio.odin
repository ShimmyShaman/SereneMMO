package client

import "core:fmt"
import mx "core:math"
import la "core:math/linalg"
import strs "core:strings"

import ma "vendor:miniaudio"
import "vendor:sdl2"

// AudioData :: struct {
//   engine: ma.engine,

//   _loaded_sfx: map[string]^ma.sound,
//   sfx_map: map[SoundEffectType]^ma.sound,

//   last_played_sound: ^ma.sound,
// }

// SoundEffectType :: enum {
//   Default,
//   Starving,
//   CollectBerry,
//   ArriveAtBerryStall,
//   DonateItem,
//   OreMiningStart,
//   OreMiningIntermediary,
//   OreMiningCompleted,
//   LumberjackingStart,
//   LumberjackingIntermediary,
//   LumberjackingCompleted,
//   ArriveAtFirePit,
// }

// @(private="file")
// load_sfx :: proc(using nmb: ^Nimb, path: string, attached_effects: ..SoundEffectType) -> (prs: ProcResult) {
//   using audio := &nmb.audio_data

//   sound, found := audio._loaded_sfx[path];
//   if !found {
//     path_cstr, aerr := strs.clone_to_cstring(path)
//     if aerr != .None {
//       fmt.println("Failed to clone to cstring")
//       return
//     }
//     defer delete(path_cstr)
  
//     sound = new(ma.sound)
//     ret := ma.sound_init_from_file(&engine, path_cstr, 0, nil, nil, sound)
//     if ret != .SUCCESS {
//       fmt.println("Failed to init sound")
//       return .AudioFileReadError
//     }
//     audio._loaded_sfx[path] = sound
//   }
//   // fmt.println("Loaded sound: ", path)

//   for effect in attached_effects {
//     audio.sfx_map[effect] = sound
//   }
  
//   return
// }

// init_audio_data :: proc(using nmb: ^Nimb) -> (prs: ProcResult) {
//   using audio := &nmb.audio_data

//   ret := ma.engine_init(nil, &engine)
//   if ret != .SUCCESS {
//     fmt.println("Failed to initialize engine")
//     return .AudioInitFailed
//   }
      
//   load_sfx(nmb, "sfx//alert1.wav", .Default)
//   load_sfx(nmb, "sfx//beat0.wav", .LumberjackingStart, .LumberjackingIntermediary, .LumberjackingCompleted)
//   load_sfx(nmb, "sfx//alert0.wav", .Starving)
  
//   return
// }

// destroy_audio_data :: proc(using nmb: ^Nimb) {
//   using audio := &nmb.audio_data

//   for path, sound in audio._loaded_sfx {
//     ma.sound_uninit(sound)
//     free(sound)
//   }

//   ma.engine_uninit(&engine)
// }

// update_audio_data :: proc(using nmb: ^Nimb) -> (prs: ProcResult) {

//   return
// }

// play_sound_effect :: proc(using nmb: ^Nimb, sound_effect_type: SoundEffectType) {
//   using audio := &nmb.audio_data

//   // Stop the last played sound
//   if audio.last_played_sound != nil && ma.sound_is_playing(audio.last_played_sound) {
//     ma.sound_stop(audio.last_played_sound)
//     ma.sound_seek_to_pcm_frame(audio.last_played_sound, 0)
//   }

//   sound, found := audio.sfx_map[sound_effect_type]
//   if !found {
//     sound = audio.sfx_map[.Default]
//   }
  
//   ret := ma.sound_start(sound)
//   if ret != .SUCCESS {
//     fmt.println("Failed to play sound")
//     return
//   }
//   audio.last_played_sound = sound
// }