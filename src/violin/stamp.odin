package violin

import "core:os"
import "core:fmt"
import "core:c/libc"
import "core:mem"
import "core:sync"
import "core:strings"

import vk "vendor:vulkan"
// import stb "vendor:stb/lib"
import stbi "vendor:stb/image"
import stbtt "vendor:stb/truetype"

import vma "odin-vma"

Rect :: struct {
  x: i32,
  y: i32,
  w: i32,
  h: i32,
}

Rectf :: struct {
  x, y, width, height: f32,
}

Color :: struct {
  r, g, b, a: f32,
}

// Premade Colors
COLOR_White := Color {r = 1.0, g = 1.0, b = 1.0, a = 1.0}
COLOR_WhiteSmoke := Color {r = 0.96, g = 0.96, b = 0.96, a = 1.0}
COLOR_LightGray := Color {r = 0.75, g = 0.75, b = 0.75, a = 1.0}
COLOR_Gray := Color {r = 0.5, g = 0.5, b = 0.5, a = 1.0}
COLOR_DarkGray := Color {r = 0.25, g = 0.25, b = 0.25, a = 1.0}
COLOR_DimGray := Color {r = 0.17, g = 0.17, b = 0.17, a = 1.0}
COLOR_Black := Color {r = 0.0, g = 0.0, b = 0.0, a = 1.0}
COLOR_Red := Color {r = 1.0, g = 0.0, b = 0.0, a = 1.0}
COLOR_Green := Color {r = 0.0, g = 1.0, b = 0.0, a = 1.0}
COLOR_Blue := Color {r = 0.0, g = 0.0, b = 1.0, a = 1.0}
COLOR_Yellow := Color {r = 1.0, g = 1.0, b = 0.0, a = 1.0}
COLOR_Magenta := Color {r = 1.0, g = 0.0, b = 1.0, a = 1.0}
COLOR_Cyan := Color {r = 0.0, g = 1.0, b = 1.0, a = 1.0}
COLOR_Transparent := Color {r = 0.0, g = 0.0, b = 0.0, a = 0.0}

COLOR_Azure := Color {r = 0.0, g = 0.5, b = 1.0, a = 1.0}
COLOR_Bisque := Color {r = 1.0, g = 0.89, b = 0.77, a = 1.0}
COLOR_BlanchedAlmond := Color {r = 1.0, g = 0.92, b = 0.8, a = 1.0}
COLOR_Cornsilk := Color {r = 1.0, g = 0.97, b = 0.86, a = 1.0}
COLOR_Orange := Color {r = 1.0, g = 0.5, b = 0.0, a = 1.0}
COLOR_Purple := Color {r = 0.5, g = 0.0, b = 0.5, a = 1.0}
COLOR_Brown := Color {r = 0.6, g = 0.4, b = 0.2, a = 1.0}
COLOR_Lime := Color {r = 0.0, g = 1.0, b = 0.0, a = 1.0}
COLOR_Pink := Color {r = 1.0, g = 0.0, b = 1.0, a = 1.0}
COLOR_Gold := Color {r = 1.0, g = 0.8, b = 0.0, a = 1.0}
COLOR_SkyBlue := Color {r = 0.0, g = 0.8, b = 1.0, a = 1.0}
COLOR_Violet := Color {r = 0.5, g = 0.0, b = 1.0, a = 1.0}
COLOR_Beige := Color {r = 0.96, g = 0.96, b = 0.86, a = 1.0}
COLOR_Mint := Color {r = 0.0, g = 1.0, b = 0.5, a = 1.0}
COLOR_Chocolate := Color {r = 0.82, g = 0.41, b = 0.12, a = 1.0}
COLOR_Coral := Color {r = 1.0, g = 0.5, b = 0.31, a = 1.0}
COLOR_Lavender := Color {r = 0.9, g = 0.9, b = 0.98, a = 1.0}
COLOR_Maroon := Color {r = 0.5, g = 0.0, b = 0.0, a = 1.0}
COLOR_Rose := Color {r = 1.0, g = 0.0, b = 0.5, a = 1.0}
COLOR_Tan := Color {r = 0.9, g = 0.6, b = 0.4, a = 1.0}
COLOR_Khaki := Color {r = 0.94, g = 0.9, b = 0.55, a = 1.0}
COLOR_Peach := Color {r = 1.0, g = 0.85, b = 0.73, a = 1.0}
COLOR_Eggshell := Color {r = 0.94, g = 0.9, b = 0.81, a = 1.0}
COLOR_Honeydew := Color {r = 0.94, g = 1.0, b = 0.94, a = 1.0}
COLOR_LavenderBlush := Color {r = 1.0, g = 0.94, b = 0.96, a = 1.0}
COLOR_LemonChiffon := Color {r = 1.0, g = 0.98, b = 0.8, a = 1.0}
COLOR_Linen := Color {r = 0.98, g = 0.94, b = 0.9, a = 1.0}
COLOR_MintCream := Color {r = 0.96, g = 1.0, b = 0.98, a = 1.0}
COLOR_MistyRose := Color {r = 1.0, g = 0.89, b = 0.88, a = 1.0}
COLOR_Moccasin := Color {r = 1.0, g = 0.89, b = 0.71, a = 1.0}
COLOR_NavajoWhite := Color {r = 1.0, g = 0.87, b = 0.68, a = 1.0}
COLOR_OldLace := Color {r = 0.99, g = 0.96, b = 0.9, a = 1.0}
COLOR_PapayaWhip := Color {r = 1.0, g = 0.94, b = 0.84, a = 1.0}
COLOR_PeachPuff := Color {r = 1.0, g = 0.85, b = 0.73, a = 1.0}
COLOR_SeaShell := Color {r = 1.0, g = 0.96, b = 0.93, a = 1.0}
COLOR_Snow := Color {r = 1.0, g = 0.98, b = 0.98, a = 1.0}
COLOR_Thistle := Color {r = 0.85, g = 0.75, b = 0.85, a = 1.0}
COLOR_Turquoise := Color {r = 0.25, g = 0.88, b = 0.82, a = 1.0}
COLOR_Wheat := Color {r = 0.96, g = 0.87, b = 0.7, a = 1.0}
COLOR_YellowGreen := Color {r = 0.6, g = 0.8, b = 0.2, a = 1.0}
COLOR_DarkBlue := Color {r = 0.0, g = 0.0, b = 0.55, a = 1.0}
COLOR_DarkCyan := Color {r = 0.0, g = 0.55, b = 0.55, a = 1.0}
COLOR_DarkGoldenrod := Color {r = 0.72, g = 0.53, b = 0.04, a = 1.0}
COLOR_DarkGreen := Color {r = 0.0, g = 0.39, b = 0.0, a = 1.0}
COLOR_DarkKhaki := Color {r = 0.74, g = 0.72, b = 0.42, a = 1.0}
COLOR_DarkMagenta := Color {r = 0.55, g = 0.0, b = 0.55, a = 1.0}
COLOR_DarkOliveGreen := Color {r = 0.33, g = 0.42, b = 0.18, a = 1.0}
COLOR_DarkOrange := Color {r = 1.0, g = 0.55, b = 0.0, a = 1.0}
COLOR_DarkOrchid := Color {r = 0.6, g = 0.2, b = 0.8, a = 1.0}
COLOR_DarkRed := Color {r = 0.55, g = 0.0, b = 0.0, a = 1.0}
COLOR_DarkSalmon := Color {r = 0.91, g = 0.59, b = 0.48, a = 1.0}
COLOR_DarkSeaGreen := Color {r = 0.56, g = 0.74, b = 0.56, a = 1.0}
COLOR_DarkSlateBlue := Color {r = 0.28, g = 0.24, b = 0.55, a = 1.0}
// RGB(46, 87, 87)
COLOR_DarkSlateGray := Color {r = 0.18, g = 0.31, b = 0.31, a = 1.0}

to_vec4 :: proc(color: Color) -> [4]f32 {
  return [4]f32{color.r, color.g, color.b, color.a}
}

Vertex2 :: struct {
  pos: [2]f32,
}

Vertex2UV :: struct {
  pos: [2]f32,
  uv: [2]f32,
}

// typedef struct mcr_font_resource {
//   const char *name;
//   float height;
//   float draw_vertical_offset;
//   mcr_texture_image *texture;
//   void *char_data;
// } mcr_font_resource;

StampShaders :: struct {
  colored_rect_vert: []u8,
  colored_rect_frag: []u8,
  textured_rect_vert: []u8,
  textured_rect_frag: []u8,
  stb_font_vert: []u8,
  stb_font_frag: []u8,
}

_load_binary_file :: proc(file_path: string) -> (data: []u8, prs: ProcResult) {
  success: bool
  data, success = os.read_entire_file_from_filename(file_path)
  if !success {
    prs = .NotYetDetailed
    fmt.eprintln("Error: load_binary_file>Could not load file:", file_path)
    return
  }
  
  return
}

@(private="file")
_load_shader :: proc(shader_directory: string, filename: string) -> (shader: []u8, prs: ProcResult) {
  file_path: string
  aerr: mem.Allocator_Error
  if shader_directory[len(shader_directory) - 1] == '/' {
    file_path, aerr = strings.join({shader_directory, filename}, "")
  } else {
    file_path, aerr = strings.join({shader_directory, filename}, "/")
  }
  if aerr != .None {
    prs = .AllocationFailed
    fmt.eprintln("Error: load_binary_file>Could not join strings:", shader_directory, filename)
    return
  }

  return _load_binary_file(file_path)
}

load_stamp_shaders :: proc(shader_directory: string) -> (shaders: ^StampShaders, prs: ProcResult) {
  shaders = new(StampShaders)
  shaders.colored_rect_vert = _load_shader(shader_directory, "colored_rect.vert.spv") or_return
  shaders.colored_rect_frag = _load_shader(shader_directory, "colored_rect.frag.spv") or_return
  shaders.textured_rect_vert = _load_shader(shader_directory, "textured_rect.vert.spv") or_return
  shaders.textured_rect_frag = _load_shader(shader_directory, "textured_rect.frag.spv") or_return
  shaders.stb_font_vert = _load_shader(shader_directory, "stb_font.vert.spv") or_return
  shaders.stb_font_frag = _load_shader(shader_directory, "stb_font.frag.spv") or_return
  return
}

destroy_stamp_shaders :: proc(shaders: ^^StampShaders) {
  ps := shaders^
  if ps == nil do return 

  if ps.colored_rect_vert != nil do delete_slice(ps.colored_rect_vert)
  if ps.colored_rect_frag != nil do delete_slice(ps.colored_rect_frag)
  if ps.textured_rect_vert != nil do delete_slice(ps.textured_rect_vert)
  if ps.textured_rect_frag != nil do delete_slice(ps.textured_rect_frag)
  if ps.stb_font_vert != nil do delete_slice(ps.stb_font_vert)
  if ps.stb_font_frag != nil do delete_slice(ps.stb_font_frag)

  mem.free(ps)
  shaders^ = nil
}

init_stamp_batch_renderer :: proc(using ctx: ^VkSDLContext, shaders: ^StampShaders, render_pass_config: RenderPassConfigFlags,
  uniform_buffer_size := 128 * 256) -> (stamph: StampRenderResourceHandle, prs: ProcResult) {
  // Create the resource
  stamph = auto_cast _create_resource(&resource_manager, .StampRenderResource) or_return
  stampr: ^StampRenderResource = auto_cast get_resource(&resource_manager, stamph) or_return

  // Create the render pass
  // HasPreviousColorPass = 0,
	// IsPresent            = 1,
  if .HasDepthBuffer in render_pass_config {
    prs = .NotYetDetailed
    fmt.eprintln("Error: init_stamp_batch_renderer>Depth buffer not supported in stamp batch renderer")
    return
  }
  // draw_rp_config, present_rp_config: RenderPassConfigFlags
  // draw_rp_config = {.HasPreviousColorPass}
  // if .HasPreviousColorPass not_in render_pass_config {
  //   stampr.clear_render_pass = create_render_pass(ctx, {}) or_return
  // }
  // if .IsPresent in render_pass_config {
  //   present_rp_config = {.HasPreviousColorPass, .IsPresent}
  // }
  // stampr.draw_render_pass = create_render_pass(ctx, draw_rp_config) or_return
  // fmt.println("created draw render pass:", stampr.draw_render_pass, "with config:", draw_rp_config)
  // if present_rp_config != nil {
  //   stampr.present_render_pass = create_render_pass(ctx, present_rp_config) or_return
  //   fmt.println("created present render pass:", stampr.present_render_pass, "with config:", present_rp_config)
  // }
  stampr.render_pass = create_render_pass(ctx, render_pass_config) or_return
  
  // Create the render programs
  vertices := [?]Vertex2 {
    {{0.0, 0.0},},
    {{1.0, 0.0},},
    {{0.0, 1.0},},
    {{1.0, 1.0},},
  }
  
  vertices_uv := [?]Vertex2UV{
    {{0.0, 0.0}, {0.0, 0.0}},
    {{1.0, 0.0}, {1.0, 0.0}},
    {{0.0, 1.0}, {0.0, 1.0}},
    {{1.0, 1.0}, {1.0, 1.0}},
  }
  
  indices := [?]u16{
    0, 1, 2,
    2, 1, 3,
  }

  // Bindings
  ubo_only_binding := [?]vk.DescriptorSetLayoutBinding {
    vk.DescriptorSetLayoutBinding {
      binding = 1,
      descriptorType = .UNIFORM_BUFFER,
      stageFlags = { .VERTEX },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
  }

  ubo_and_texture_binding := [?]vk.DescriptorSetLayoutBinding {
    ubo_only_binding[0],
    vk.DescriptorSetLayoutBinding {
      binding = 2,
      descriptorType = .COMBINED_IMAGE_SAMPLER,
      stageFlags = { .FRAGMENT },
      descriptorCount = 1,
      pImmutableSamplers = nil,
    },
  }

  // Colored Rect Render Program
  vertex2_inputs := [?]InputAttribute {
    {
      format = .R32G32_SFLOAT,
      location = 0,
      offset = auto_cast offset_of(Vertex2, pos),
    },
  }
  render_program_create_info := RenderProgramCreateInfo {
    pipeline_config = PipelineCreateConfig {
      vertex_shader_binary = shaders.colored_rect_vert,
      fragment_shader_binary = shaders.colored_rect_frag,
      render_pass = stampr.render_pass,
    },
    vertex_size = size_of(Vertex2),
    buffer_bindings = ubo_only_binding[:],
    input_attributes = vertex2_inputs[:],
  }
  stampr.colored_rect_render_program = create_render_program(ctx, &render_program_create_info) or_return

  // Textured Rect Render Program
  vertex2UV_inputs := [?]InputAttribute {
    {
      format = .R32G32_SFLOAT,
      location = 0,
      offset = auto_cast offset_of(Vertex2UV, pos),
    },
    {
      format = .R32G32_SFLOAT,
      location = 1,
      offset = auto_cast offset_of(Vertex2UV, uv),
    },
  }
  render_program_create_info = RenderProgramCreateInfo {
    pipeline_config = PipelineCreateConfig {
      vertex_shader_binary = shaders.textured_rect_vert,
      fragment_shader_binary = shaders.textured_rect_frag,
      render_pass = stampr.render_pass,
    },
    vertex_size = size_of(Vertex2UV),
    buffer_bindings = ubo_and_texture_binding[:],
    input_attributes = vertex2UV_inputs[:],
  }
  stampr.textured_rect_render_program = create_render_program(ctx, &render_program_create_info) or_return

  render_program_create_info = RenderProgramCreateInfo {
    pipeline_config = PipelineCreateConfig {
      vertex_shader_binary = shaders.stb_font_vert,
      fragment_shader_binary = shaders.stb_font_frag,
      render_pass = stampr.render_pass,
    },
    vertex_size = size_of(Vertex2UV),
    buffer_bindings = ubo_and_texture_binding[:],
    input_attributes = vertex2UV_inputs[:],
  }
  stampr.stb_font_render_program = create_render_program(ctx, &render_program_create_info) or_return
  
  // Uniform Buffer
  stampr.uniform_buffer.capacity = auto_cast (size_of(f32) * uniform_buffer_size) // TODO -- appropriate size
  stampr.uniform_buffer.rh = create_uniform_buffer(ctx, stampr.uniform_buffer.capacity, .Dynamic) or_return

  // Ensure the created uniform buffer is HOST_VISIBLE for dynamic copying
  {
    ubr: ^Buffer = auto_cast get_resource(&resource_manager, stampr.uniform_buffer.rh) or_return
    mem_property_flags: vk.MemoryPropertyFlags
    vma.GetAllocationMemoryProperties(vma_allocator, ubr.allocation, &mem_property_flags)
    if vk.MemoryPropertyFlag.HOST_VISIBLE not_in mem_property_flags {
      fmt.eprintln("init_stamp_batch_renderer>buffer memory is not HOST_VISIBLE. Invalid Call")
      prs = .NotYetDetailed
      return
    }

    props: vk.PhysicalDeviceProperties;
    vk.GetPhysicalDeviceProperties(physical_device, &props);
    stampr.uniform_buffer.device_min_block_alignment = props.limits.minUniformBufferOffsetAlignment
  }

  // TODO use triangle-fan? test performance difference
  stampr.colored_rect_vertex_buffer = create_vertex_buffer(ctx, auto_cast &vertices[0], size_of(Vertex2), 4) or_return
  stampr.textured_rect_vertex_buffer = create_vertex_buffer(ctx, auto_cast &vertices_uv[0], size_of(Vertex2UV), 4) or_return
  stampr.rect_index_buffer = create_index_buffer(ctx, auto_cast &indices[0], 6) or_return

  // parameter_data := [8]f32 {
  //   auto_cast 100 / cast(f32)ctx.swap_chain.extent.width,
  //   auto_cast 100 / cast(f32)ctx.swap_chain.extent.height,
  //   auto_cast 320 / cast(f32)ctx.swap_chain.extent.width,
  //   auto_cast 200 / cast(f32)ctx.swap_chain.extent.height,
  //   auto_cast 245 / 255.0,
  //   auto_cast 252 / 255.0,
  //   auto_cast 1 / 255.0,
  //   auto_cast 255 / 255.0,
  // }
  // write_to_buffer(ctx, stampr.uniform_buffer, auto_cast &parameter_data[0], auto_cast (size_of(f32) * 8)) or_return

  return
}

// Internal Function :: Use destroy_resource() instead
__release_stamp_render_resource :: proc(using ctx: ^VkSDLContext, tdr: ^StampRenderResource) {
  destroy_index_buffer(ctx, tdr.rect_index_buffer)
  destroy_vertex_buffer(ctx, tdr.colored_rect_vertex_buffer)
  destroy_vertex_buffer(ctx, tdr.textured_rect_vertex_buffer)
  destroy_buffer(ctx, tdr.uniform_buffer.rh)

  destroy_render_program(ctx, tdr.stb_font_render_program)
  destroy_render_program(ctx, tdr.textured_rect_render_program)
  destroy_render_program(ctx, tdr.colored_rect_render_program)

  // if tdr.clear_render_pass != 0 do destroy_render_pass(ctx, tdr.clear_render_pass)
  destroy_render_pass(ctx, tdr.render_pass)
  // if tdr.present_render_pass != 0 do destroy_render_pass(ctx, tdr.present_render_pass)
}

stamp_begin :: proc(using rctx: ^RenderContext, stamp_handle: StampRenderResourceHandle) -> ProcResult {
  stampr: ^StampRenderResource = auto_cast get_resource(&rctx.ctx.resource_manager, stamp_handle) or_return

  // if stampr.clear_render_pass != auto_cast 0 {
  //   _begin_render_pass(rctx, stampr.clear_render_pass) or_return
  // }

  // Delegate
  begin_render_pass(rctx, stampr.render_pass) or_return

  // Redefine status
  rctx.status = .StampRenderPass
  // rctx.followup_render_pass = stampr.present_render_pass

  // Reset Uniform Buffer Tracking
  stampr.uniform_buffer.utilization = 0

  return .Success
}

// @(private) _stamp_restart_render_pass :: proc(using rctx: ^RenderContext, stampr: ^StampRenderResource) -> ProcResult {
//   if rctx.status != .StampRenderPass {
//     fmt.eprintln("_stamp_restart_render_pass>invalid status. Invalid Call")
//     return .InvalidState
//   }

//   // // End the current
//   // vk.CmdEndRenderPass(command_buffer)

//   // Delegate
//   begin_render_pass(rctx, stampr.draw_render_pass) or_return

//   // Redefine status
//   rctx.status = .StampRenderPass

//   // Reset Uniform Buffer Tracking
//   stampr.uniform_buffer.utilization = 0

//   return .Success
// }

stamp_colored_rect :: proc(using rctx: ^RenderContext, stamp_handle: StampRenderResourceHandle, rect: ^Rectf, color: ^Color) -> ProcResult {
  // Obtain the resources
  stampr: ^StampRenderResource = auto_cast get_resource(&rctx.ctx.resource_manager, stamp_handle) or_return
  vbuf: ^VertexBuffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.colored_rect_vertex_buffer) or_return
  ibuf: ^IndexBuffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.rect_index_buffer) or_return
  ubuf: ^Buffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.uniform_buffer.rh) or_return
  rprog: ^RenderProgram = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.colored_rect_render_program) or_return

  // Write the input to the uniform buffer
  parameter_data := [8]f32 {
    rect.x / cast(f32)rctx.ctx.swap_chain.extent.width,
    rect.y / cast(f32)rctx.ctx.swap_chain.extent.height,
    rect.width / cast(f32)rctx.ctx.swap_chain.extent.width,
    rect.height / cast(f32)rctx.ctx.swap_chain.extent.height,
    auto_cast color.r,
    auto_cast color.g,
    auto_cast color.b,
    auto_cast color.a,
  }
  // fmt.println("stamp_colored_rect>rect:", rect)
  // fmt.println("stamp_colored_rect>color:", color)
  // fmt.println("stamp_colored_rect>parameter_data:", parameter_data)

  // Write to the HOST_VISIBLE memory
  ubo_offset: vk.DeviceSize = auto_cast stampr.uniform_buffer.utilization
  ubo_range: int : size_of(f32) * 8

  if ubo_offset + auto_cast ubo_range > stampr.uniform_buffer.capacity {
    fmt.eprintln("Error] stamp_colored_rect> stamp uniform buffer is full (1). Too many calls for initial buffer size.",
      "Consider increasing the buffer size")
    fmt.eprintln("Error] stamp_colored_rect> ubo_offset:", ubo_offset, "ubo_range:", ubo_range, "capacity:", stampr.uniform_buffer.capacity)
    return .NotYetDetailed
  }
  
  // Update the uniform buffer utilization
  stampr.uniform_buffer.utilization += max(cast(vk.DeviceSize) ubo_range, stampr.uniform_buffer.device_min_block_alignment)
  
  // Write to the buffer
  copy_dst: rawptr = auto_cast (cast(uintptr)ubuf.allocation_info.pMappedData + auto_cast ubo_offset)
  mem.copy(copy_dst, auto_cast &parameter_data[0], ubo_range)

  // Setup viewport and clip --- TODO this ain't true
  // if rctx.ctx.__settings.support_negative_viewport_heights {
  //   _set_viewport_cmd(command_buffer, 0, auto_cast ctx.swap_chain.extent.height, auto_cast ctx.swap_chain.extent.width,
  //     -auto_cast ctx.swap_chain.extent.height)
  //   _set_scissor_cmd(command_buffer, 0, 0, ctx.swap_chain.extent.width, ctx.swap_chain.extent.height)
  // } else {
    _set_viewport_cmd(command_buffer, 0, 0, auto_cast ctx.swap_chain.extent.width,
      auto_cast ctx.swap_chain.extent.height)
    _set_scissor_cmd(command_buffer, 0, 0, ctx.swap_chain.extent.width, ctx.swap_chain.extent.height)
  // }

  // Queue Buffer Write
  MAX_DESC_SET_WRITES :: 8
  writes: [MAX_DESC_SET_WRITES]vk.WriteDescriptorSet
  buffer_infos: [1]vk.DescriptorBufferInfo
  buffer_info_index := 0
  write_index := 0
  
  // Allocate the descriptor set from the pool
  descriptor_set_index := descriptor_sets_index

  set_alloc_info := vk.DescriptorSetAllocateInfo {
    sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
    // Use the descriptor pool we created earlier (the one dedicated to this frame)
    descriptorPool = descriptor_pool,
    descriptorSetCount = 1,
    pSetLayouts = &rprog.descriptor_layout,
  }
  vkres := vk.AllocateDescriptorSets(ctx.device, &set_alloc_info, &descriptor_sets[descriptor_set_index])
  if vkres != .SUCCESS {
    fmt.eprintln("vkAllocateDescriptorSets failed:", vkres)
    return .NotYetDetailed
  }
  desc_set := descriptor_sets[descriptor_set_index]
  descriptor_sets_index += set_alloc_info.descriptorSetCount

  // Describe the uniform buffer binding
  buffer_infos[0].buffer = ubuf.buffer
  buffer_infos[0].offset = ubo_offset
  buffer_infos[0].range = auto_cast ubo_range

  // Element Vertex Shader Uniform Buffer
  write := &writes[write_index]
  write_index += 1

  write.sType = .WRITE_DESCRIPTOR_SET
  write.dstSet = desc_set
  write.descriptorCount = 1
  write.descriptorType = .UNIFORM_BUFFER
  write.pBufferInfo = &buffer_infos[0]
  write.dstArrayElement = 0
  write.dstBinding = rprog.layout_bindings[0].binding
  
  vk.UpdateDescriptorSets(ctx.device, auto_cast write_index, &writes[0], 0, nil)

  vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, rprog.pipeline.layout, 0, 1, &desc_set, 0, nil)

  vk.CmdBindPipeline(command_buffer, .GRAPHICS, rprog.pipeline.handle)

  vk.CmdBindIndexBuffer(command_buffer, ibuf.buffer, 0, ibuf.index_type) // TODO -- support other index types

  // const VkDeviceSize offsets[1] = {0};
  // vkCmdBindVertexBuffers(command_buffer, 0, 1, &cmd->render_program.data->vertices->buf, offsets);
  // // vkCmdDraw(command_buffer, 3 * 2 * 6, 1, 0, 0);
  // int index_draw_count = cmd->render_program.data->specific_index_draw_count;
  // if (!index_draw_count)
  //   index_draw_count = cmd->render_program.data->indices->capacity;
  offsets: vk.DeviceSize = 0
  vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vbuf.buffer, &offsets)
  // TODO -- specific index draw count

  // // printf("index_draw_count=%i\n", index_draw_count);
  // // printf("cmd->render_program.data->indices->capacity=%i\n", cmd->render_program.data->indices->capacity);
  // // printf("cmd->render_program.data->specific_index_draw_count=%i\n",
  // //        cmd->render_program.data->specific_index_draw_count);

  // vkCmdDrawIndexed(command_buffer, index_draw_count, 1, 0, 0, 0);
  vk.CmdDrawIndexed(command_buffer, auto_cast ibuf.index_count, 1, 0, 0, 0) // TODO -- index_count as u32?
  // fmt.print("ibuf.index_count:", ibuf.index_count)

  return .Success
}

stamp_textured_rect :: proc(using rctx: ^RenderContext, stamp_handle: StampRenderResourceHandle, txh: TextureResourceHandle,
  rect: ^Rectf, tint: ^Color = nil, sub_uv_coords: [4]f32 = {0.0, 0.0, 1.0, 1.0}) -> ProcResult {
  // Obtain the resources
  stampr: ^StampRenderResource = auto_cast get_resource(&rctx.ctx.resource_manager, stamp_handle) or_return
  texture: ^Texture = auto_cast get_resource(&rctx.ctx.resource_manager, txh) or_return
  vbuf: ^VertexBuffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.textured_rect_vertex_buffer) or_return
  ibuf: ^IndexBuffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.rect_index_buffer) or_return
  ubuf: ^Buffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.uniform_buffer.rh) or_return
  rprog: ^RenderProgram = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.textured_rect_render_program) or_return

  // Write the input to the uniform buffer
  tint_ := tint
  if tint_ == nil {
    tint_ = &COLOR_White
  }
  PARAM_COUNT :: 12
  parameter_data := [PARAM_COUNT]f32 {
    rect.x / cast(f32)rctx.ctx.swap_chain.extent.width,
    rect.y / cast(f32)rctx.ctx.swap_chain.extent.height,
    rect.width / cast(f32)rctx.ctx.swap_chain.extent.width,
    rect.height / cast(f32)rctx.ctx.swap_chain.extent.height,
    tint_.r,
    tint_.g,
    tint_.b,
    tint_.a,
    sub_uv_coords[0],
    sub_uv_coords[1],
    sub_uv_coords[2] - sub_uv_coords[0],
    sub_uv_coords[3] - sub_uv_coords[1],
  }

  // Write to the HOST_VISIBLE memory
  ubo_offset: vk.DeviceSize = auto_cast stampr.uniform_buffer.utilization
  ubo_range: int : size_of(f32) * PARAM_COUNT

  if ubo_offset + auto_cast ubo_range > stampr.uniform_buffer.capacity {
    fmt.eprintln("Error] stamp_colored_rect> stamp uniform buffer is full (2). Too many calls for initial buffer size.",
      "Consider increasing the buffer size")
    fmt.eprintln("Error] stamp_colored_rect> ubo_offset:", ubo_offset, "ubo_range:", ubo_range, "capacity:", stampr.uniform_buffer.capacity)
    return .NotYetDetailed
  }
  
  // Update the uniform buffer utilization
  stampr.uniform_buffer.utilization += max(cast(vk.DeviceSize) ubo_range, stampr.uniform_buffer.device_min_block_alignment)
  
  // Write to the buffer
  copy_dst: rawptr = auto_cast (cast(uintptr)ubuf.allocation_info.pMappedData + auto_cast ubo_offset)
  mem.copy(copy_dst, auto_cast &parameter_data[0], ubo_range)

  // Setup viewport and clip --- TODO this ain't true
  _set_viewport_cmd(command_buffer, 0, 0, auto_cast ctx.swap_chain.extent.width, auto_cast ctx.swap_chain.extent.height)
  _set_scissor_cmd(command_buffer, 0, 0, ctx.swap_chain.extent.width, ctx.swap_chain.extent.height)

  // Queue Buffer Write
  MAX_DESC_SET_WRITES :: 8
  writes: [MAX_DESC_SET_WRITES]vk.WriteDescriptorSet
  buffer_infos: [1]vk.DescriptorBufferInfo
  image_sampler_infos: [1]vk.DescriptorImageInfo
  write_index := 0
  
  // Allocate the descriptor set from the pool
  descriptor_set_index := descriptor_sets_index

  set_alloc_info := vk.DescriptorSetAllocateInfo {
    sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
    // Use the descriptor pool we created earlier (the one dedicated to this frame)
    descriptorPool = descriptor_pool,
    descriptorSetCount = 1,
    pSetLayouts = &rprog.descriptor_layout,
  }
  vkres := vk.AllocateDescriptorSets(ctx.device, &set_alloc_info, &descriptor_sets[descriptor_set_index])
  if vkres != .SUCCESS {
    fmt.eprintln("vkAllocateDescriptorSets failed:", vkres)
    return .NotYetDetailed
  }
  desc_set := descriptor_sets[descriptor_set_index]
  descriptor_sets_index += set_alloc_info.descriptorSetCount

  // Describe the Vertex Shader Uniform Buffer
  {
    buffer_infos[0].buffer = ubuf.buffer
    buffer_infos[0].offset = ubo_offset
    buffer_infos[0].range = auto_cast ubo_range

    write := &writes[write_index]
    write_index += 1

    write.sType = .WRITE_DESCRIPTOR_SET
    write.dstSet = desc_set
    write.descriptorCount = 1
    write.descriptorType = .UNIFORM_BUFFER
    write.pBufferInfo = &buffer_infos[0]
    write.dstArrayElement = 0
    write.dstBinding = rprog.layout_bindings[0].binding
  }

  // Describe the Fragment Shader Combined Image Sampler
  {
    image_sampler: ^Texture = auto_cast get_resource(&rctx.ctx.resource_manager, txh) or_return

    image_sampler_info := &image_sampler_infos[0]
    image_sampler_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
    image_sampler_info.imageView = image_sampler.image_view
    image_sampler_info.sampler = image_sampler.sampler
    
    write := &writes[write_index]
    write_index += 1

    write.sType = .WRITE_DESCRIPTOR_SET
    write.dstSet = desc_set
    write.descriptorCount = 1
    write.descriptorType = .COMBINED_IMAGE_SAMPLER
    write.pImageInfo = image_sampler_info
    write.dstArrayElement = 0
    write.dstBinding = rprog.layout_bindings[1].binding
  }
  
  vk.UpdateDescriptorSets(ctx.device, auto_cast write_index, &writes[0], 0, nil)

  vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, rprog.pipeline.layout, 0, 1, &desc_set, 0, nil)

  vk.CmdBindPipeline(command_buffer, .GRAPHICS, rprog.pipeline.handle)

  vk.CmdBindIndexBuffer(command_buffer, ibuf.buffer, 0, ibuf.index_type) // TODO -- support other index types

  // const VkDeviceSize offsets[1] = {0};
  // vkCmdBindVertexBuffers(command_buffer, 0, 1, &cmd->render_program.data->vertices->buf, offsets);
  // // vkCmdDraw(command_buffer, 3 * 2 * 6, 1, 0, 0);
  // int index_draw_count = cmd->render_program.data->specific_index_draw_count;
  // if (!index_draw_count)
  //   index_draw_count = cmd->render_program.data->indices->capacity;
  offsets: vk.DeviceSize = 0
  vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vbuf.buffer, &offsets)
  // TODO -- specific index draw count

  // // printf("index_draw_count=%i\n", index_draw_count);
  // // printf("cmd->render_program.data->indices->capacity=%i\n", cmd->render_program.data->indices->capacity);
  // // printf("cmd->render_program.data->specific_index_draw_count=%i\n",
  // //        cmd->render_program.data->specific_index_draw_count);

  // vkCmdDrawIndexed(command_buffer, index_draw_count, 1, 0, 0, 0);
  vk.CmdDrawIndexed(command_buffer, auto_cast ibuf.index_count, 1, 0, 0, 0) // TODO -- index_count as u32?
  // fmt.print("ibuf.index_count:", ibuf.index_count)

  return .Success
}

// vi.stamp_text(rctx, handle_2d, cmd_t.font, cmd_t.text, cmd_t.pos.x, cmd_t.pos.y, cmd_t.color)
stamp_text :: proc(using rctx: ^RenderContext, stamp_handle: StampRenderResourceHandle, font_handle: FontResourceHandle,
  text: string, #any_int pos_x: int, #any_int pos_y: int, color: ^Color) -> ProcResult {
  // fmt.println("stamp_text:", text, "pos_x:", pos_x, "pos_y:", pos_y, "color:", color)
  // Text Length
  text_length := len(text)
  if text_length == 0 do return .Success
  
  // Obtain the resources
  stampr: ^StampRenderResource = auto_cast get_resource(&rctx.ctx.resource_manager, stamp_handle) or_return
  vbuf: ^VertexBuffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.textured_rect_vertex_buffer) or_return
  ibuf: ^IndexBuffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.rect_index_buffer) or_return
  ubuf: ^Buffer = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.uniform_buffer.rh) or_return
  rprog: ^RenderProgram = auto_cast get_resource(&rctx.ctx.resource_manager, stampr.stb_font_render_program) or_return

  // Get the font image
  font: ^Font = auto_cast get_resource(&ctx.resource_manager, font_handle) or_return
  font_texture: ^Texture = auto_cast get_resource(&ctx.resource_manager, font.texture) or_return

  align_x: f32 = auto_cast pos_x
  align_y: f32 = auto_cast pos_y - font.bump_up_y_offset

  letter: u8
  clip: vk.Rect2D
  cc: ^Rectf
  q: stbtt.aligned_quad
  width, height, scale_multiplier: f32

  for c := 0; c < text_length; c += 1 {
    letter = text[c]

    // fmt.println("align_x:", align_x)
    // if align_x > auto_cast font_texture.width do break
    //   letter = cmd->print_text.text[c];
    //   if (letter < 32 || letter > 127) {
    //     printf("TODO character not supported.\n");
    //     return VK_SUCCESS;
    //   }
    //   // printf("printing character '%c' %i\n", letter, (int)letter);
    letter = text[c]
    if letter < 32 || letter > 127 {
      fmt.eprintln(args={"ERROR>stamp_text: character '", letter, "' not supported."}, sep = "")
      return .NotYetDetailed
    }
  
    // Source texture bounds
    stbtt.GetBakedQuad(font.char_data, auto_cast font_texture.width, auto_cast font_texture.height, auto_cast letter - 32,
      &align_x, &align_y, &q, true)
    // TODO -- opengl_fill_rule??? // 1=opengl & d3d10+,0=d3d9 -- should be true, nothing on net about it
  
    rect: Rectf = {q.x0, q.y0, (q.x1 - q.x0), (q.y1 - q.y0)}
    // fmt.println("letter:", letter, "rect:", rect, "q.s0:", q.s0, "q.t0:", q.t0, "q.s1:", q.s1, "q.t1:", q.t1)
    
    // Write the input to the uniform buffer
    tint_ := color
    if tint_ == nil {
      tint_ = &COLOR_White
    }
    PARAM_COUNT :: 12
    parameter_data := [PARAM_COUNT]f32 {
      rect.x / cast(f32)rctx.ctx.swap_chain.extent.width,
      rect.y / cast(f32)rctx.ctx.swap_chain.extent.height,
      rect.width / cast(f32)rctx.ctx.swap_chain.extent.width,
      rect.height / cast(f32)rctx.ctx.swap_chain.extent.height,
      tint_.r,
      tint_.g,
      tint_.b,
      tint_.a,
      q.s0,
      q.t0,
      q.s1 - q.s0,
      q.t1 - q.t0,
    }

    // Write to the HOST_VISIBLE memory
    ubo_offset: vk.DeviceSize = auto_cast stampr.uniform_buffer.utilization
    ubo_range: int : size_of(f32) * PARAM_COUNT

    if ubo_offset + auto_cast ubo_range > stampr.uniform_buffer.capacity {
      fmt.eprintln("Error] stamp_colored_rect> stamp uniform buffer is full (3). Too many calls for initial buffer size.",
        "Consider increasing the buffer size")
      fmt.eprintln("Error] stamp_colored_rect> ubo_offset:", ubo_offset, "ubo_range:", ubo_range, "capacity:", stampr.uniform_buffer.capacity)
      return .NotYetDetailed
    }
    
    // Update the uniform buffer utilization
    stampr.uniform_buffer.utilization += max(cast(vk.DeviceSize) ubo_range, stampr.uniform_buffer.device_min_block_alignment)
    
    // Write to the buffer
    copy_dst: rawptr = auto_cast (cast(uintptr)ubuf.allocation_info.pMappedData + auto_cast ubo_offset)
    mem.copy(copy_dst, auto_cast &parameter_data[0], ubo_range)

    // Setup viewport and clip --- TODO this ain't true
    _set_viewport_cmd(command_buffer, 0, 0, auto_cast ctx.swap_chain.extent.width, auto_cast ctx.swap_chain.extent.height)
    _set_scissor_cmd(command_buffer, 0, 0, ctx.swap_chain.extent.width, ctx.swap_chain.extent.height)
    
    // Queue Buffer Write
    MAX_DESC_SET_WRITES :: 8
    writes: [MAX_DESC_SET_WRITES]vk.WriteDescriptorSet
    buffer_infos: [1]vk.DescriptorBufferInfo
    image_sampler_infos: [1]vk.DescriptorImageInfo
    write_index := 0
    
    // Allocate the descriptor set from the pool
    descriptor_set_index := descriptor_sets_index

    set_alloc_info := vk.DescriptorSetAllocateInfo {
      sType = .DESCRIPTOR_SET_ALLOCATE_INFO,
      // Use the descriptor pool we created earlier (the one dedicated to this frame)
      descriptorPool = descriptor_pool,
      descriptorSetCount = 1,
      pSetLayouts = &rprog.descriptor_layout,
    }
    vkres := vk.AllocateDescriptorSets(ctx.device, &set_alloc_info, &descriptor_sets[descriptor_set_index])
    if vkres != .SUCCESS {
      fmt.eprintln("vkAllocateDescriptorSets failed:", vkres)
      return .NotYetDetailed
    }
    desc_set := descriptor_sets[descriptor_set_index]
    descriptor_sets_index += set_alloc_info.descriptorSetCount

    // Describe the Vertex Shader Uniform Buffer
    {
      buffer_infos[0].buffer = ubuf.buffer
      buffer_infos[0].offset = ubo_offset
      buffer_infos[0].range = auto_cast ubo_range

      write := &writes[write_index]
      write_index += 1

      write.sType = .WRITE_DESCRIPTOR_SET
      write.dstSet = desc_set
      write.descriptorCount = 1
      write.descriptorType = .UNIFORM_BUFFER
      write.pBufferInfo = &buffer_infos[0]
      write.dstArrayElement = 0
      write.dstBinding = rprog.layout_bindings[0].binding
    }

    // Describe the Fragment Shader Combined Image Sampler
    {
      image_sampler_info := &image_sampler_infos[0]
      image_sampler_info.imageLayout = .SHADER_READ_ONLY_OPTIMAL
      image_sampler_info.imageView = font_texture.image_view
      image_sampler_info.sampler = font_texture.sampler
      
      write := &writes[write_index]
      write_index += 1

      write.sType = .WRITE_DESCRIPTOR_SET
      write.dstSet = desc_set
      write.descriptorCount = 1
      write.descriptorType = .COMBINED_IMAGE_SAMPLER
      write.pImageInfo = image_sampler_info
      write.dstArrayElement = 0
      write.dstBinding = rprog.layout_bindings[1].binding
    }
    
    vk.UpdateDescriptorSets(ctx.device, auto_cast write_index, &writes[0], 0, nil)

    vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, rprog.pipeline.layout, 0, 1, &desc_set, 0, nil)

    vk.CmdBindPipeline(command_buffer, .GRAPHICS, rprog.pipeline.handle)

    vk.CmdBindIndexBuffer(command_buffer, ibuf.buffer, 0, ibuf.index_type) // TODO -- support other index types

    // const VkDeviceSize offsets[1] = {0};
    // vkCmdBindVertexBuffers(command_buffer, 0, 1, &cmd->render_program.data->vertices->buf, offsets);
    // // vkCmdDraw(command_buffer, 3 * 2 * 6, 1, 0, 0);
    // int index_draw_count = cmd->render_program.data->specific_index_draw_count;
    // if (!index_draw_count)
    //   index_draw_count = cmd->render_program.data->indices->capacity;
    offsets: vk.DeviceSize = 0
    vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vbuf.buffer, &offsets)
    // TODO -- specific index draw count

    // // printf("index_draw_count=%i\n", index_draw_count);
    // // printf("cmd->render_program.data->indices->capacity=%i\n", cmd->render_program.data->indices->capacity);
    // // printf("cmd->render_program.data->specific_index_draw_count=%i\n",
    // //        cmd->render_program.data->specific_index_draw_count);

    // vkCmdDrawIndexed(command_buffer, index_draw_count, 1, 0, 0, 0);
    vk.CmdDrawIndexed(command_buffer, auto_cast ibuf.index_count, 1, 0, 0, 0) // TODO -- index_count as u32?
    // fmt.print("ibuf.index_count:", ibuf.index_count)
  }
  return .Success
}