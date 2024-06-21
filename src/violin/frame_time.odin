package violin

// import "core:os"
import "core:fmt"
// import "core:c/libc"
// import "core:mem"
// import "core:sync"
// import "core:strings"
import "core:time"

FrameTime :: struct {
  _prev_fps_check: f32,
  _nn_cache: [100]f32,
  _nnidx: int,

  init_time: time.Time,
  frame_time, previous_frame_time, _max5s_frame_time: time.Time,
  
  min_frame, max_frame, running_avg, max5s_frame, ninety_ninth: f32,
  historical_frame_count: int,
  frame_elapsed, total_elapsed: f32,
}

init_frame_time :: proc(using ft: ^FrameTime) {
  init_time = time.now()
  previous_frame_time = init_time
  frame_time = init_time

  min_frame = 1.0
  running_avg = 0.016
}

update_frame_time :: proc(using ft: ^FrameTime) {
  previous_frame_time = frame_time
  frame_time = time.now()

  frame_elapsed = auto_cast time.duration_seconds(time.diff(previous_frame_time, frame_time))
  total_elapsed = auto_cast time.duration_seconds(time.diff(init_time, frame_time))

  min_frame = min(min_frame, frame_elapsed)
  if frame_elapsed > max5s_frame {
    max5s_frame = frame_elapsed
    _max5s_frame_time = time.now()
    max_frame = max(max_frame, frame_elapsed)
  } else if time.diff(_max5s_frame_time, frame_time) > time.Second * 5 {
    max5s_frame = frame_elapsed
    _max5s_frame_time = time.now()
  }

  running_avg = (running_avg * 99.0 + frame_elapsed) / 100.0
  
  _nn_cache[_nnidx] = frame_elapsed
  _nnidx += 1
  if _nnidx == 100 {
    _nnidx = 0

    high, second_high: f32 = 0.0, 0.0
    for i in 0..<100 {
      if _nn_cache[i] > high {
        second_high = high
        high = _nn_cache[i]
      } else if _nn_cache[i] > second_high {
        second_high = _nn_cache[i]
      }
    }

    if historical_frame_count < 150 {
      ninety_ninth = second_high
      // fmt.printf("set ninety_ninth: %.5f\n", ninety_ninth)
    } else {
      LONG_AVG_PERIOD: f32 = 1.0 / (60.0 /* fps */ * 10.0 /* seconds */)
      factor := max(0.0, LONG_AVG_PERIOD / running_avg) + 1.0
      // fmt.printf("ninety_ninth: %.5f second_high: %.5f combined: %.5f factor: %f\n", ninety_ninth, second_high,
      //   (ninety_ninth + second_high) / 2.0, factor)
      ninety_ninth = (ninety_ninth + second_high * (factor - 1)) / factor
    }
  }
  
  historical_frame_count += 1
}