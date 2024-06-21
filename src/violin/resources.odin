package violin

import "core:os"
import "core:fmt"
import "core:c/libc"
import mx "core:math"
import "core:mem"
import "core:sync"

import vk "vendor:vulkan"
// import stb "vendor:stb/lib"
import stbi "vendor:stb/image"
import stbtt "vendor:stb/truetype"

import vma "odin-vma"

@(private) RESOURCES_DEBUG_VERBOSE_FLAG :: false
@(private) RESOURCES_DEBUG_AUTO_CLEANUP_FLAG :: true
@(private) INITIAL_RESOURCE_HANDLE_INDEX :: 1000

// https://gpuopen-librariesandsdks.github.io/VulkanMemoryAllocator/html/usage_patterns.html
BufferUsage :: enum {
  Null = 0,
  // When: Any resources that you frequently write and read on GPU, e.g. images used as color attachments (aka "render targets"),
  //   depth-stencil attachments, images/buffers used as storage image/buffer (aka "Unordered Access View (UAV)").
  GpuOnlyDedicated,
  // When: A "staging" buffer than you want to map and fill from CPU code, then use as a source od transfer to some GPU resource.
  Staged,
  // When: Buffers for data written by or transferred from the GPU that you want to read back on the CPU, e.g. results of some computations.
  Readback,
  // When: Resources that you frequently write on CPU via mapped pointer and frequently read on GPU e.g. as a uniform buffer (also called "dynamic")
  Dynamic,
  // DeviceBuffer,
  // TODO -- the 'other use cases'
}

ResourceHandle :: distinct int
BufferResourceHandle :: distinct ResourceHandle
DepthBufferResourceHandle :: distinct ResourceHandle
TextureResourceHandle :: distinct ResourceHandle
VertexBufferResourceHandle :: distinct ResourceHandle
IndexBufferResourceHandle :: distinct ResourceHandle
RenderPassResourceHandle :: distinct ResourceHandle
RenderProgramResourceHandle :: distinct ResourceHandle
StampRenderResourceHandle :: distinct ResourceHandle
FontResourceHandle :: distinct ResourceHandle

ResourceKind :: enum(u8) {
  Any = 0,
  Buffer = 1,
  Texture,
  DepthBuffer,
  RenderPass,
  RenderProgram,
  StampRenderResource,
  VertexBuffer,
  IndexBuffer,
  Font,
}

Resource :: struct {
  kind: ResourceKind,
  data: union {
    Buffer,
    Texture,
    DepthBuffer,
    RenderPass,
    RenderProgram,
    StampRenderResource,
    VertexBuffer,
    IndexBuffer,
    Font,
  },
}

ImageUsage :: enum {
  ShaderReadOnly = 1,
  // ColorAttachment,
  // DepthStencilAttachment,
  // RenderTarget,
  // Present_KHR,
}

Buffer :: struct {
  buffer: vk.Buffer,
  allocation: vma.Allocation,
  allocation_info: vma.AllocationInfo,
  size:   vk.DeviceSize,
}

Texture :: struct {
  sampler_usage: ImageUsage,
  width: u32,
  height: u32,
  mip_levels: u32,
  size:   vk.DeviceSize,
  // format: vk.Format,
  image: vk.Image,
  // image_memory: vk.DeviceMemory,
  image_view: vk.ImageView,
  // framebuffer: vk.Framebuffer,
  sampler: vk.Sampler,
  allocation: vma.Allocation,
  allocation_info: vma.AllocationInfo,

  format: vk.Format,
  current_layout: vk.ImageLayout,
  intended_usage: ImageUsage,
}

DepthBuffer :: struct {
  format: vk.Format,
  image: vk.Image,
  allocation: vma.Allocation,
  allocation_info: vma.AllocationInfo,
  size:   vk.DeviceSize,
  view: vk.ImageView,
}

VertexBuffer :: struct {
  using _buf: Buffer,
  vertices: ^f32, // TODO -- REMOVE THIS ?
  vertex_count: int,
}

IndexBuffer :: struct {
  using _buf: Buffer,
  indices: rawptr, // TODO -- REMOVE THIS ?
  index_count: int,
  index_type: vk.IndexType,
}

RenderPass :: struct {
  config: RenderPassConfigFlags,
  render_pass: vk.RenderPass, // TODO change to vk_handle
  framebuffers: []vk.Framebuffer,
  depth_buffer_rh: ResourceHandle,
  clear_color: Color,
}

StampRenderResource :: struct {
  render_pass: RenderPassResourceHandle,
  colored_rect_render_program, textured_rect_render_program, stb_font_render_program: RenderProgramResourceHandle,
  colored_rect_vertex_buffer, textured_rect_vertex_buffer: VertexBufferResourceHandle,
  rect_index_buffer: IndexBufferResourceHandle,

  uniform_buffer: StampUniformBuffer,
}

StampUniformBuffer :: struct {
  rh: BufferResourceHandle,
  utilization: vk.DeviceSize,
  capacity: vk.DeviceSize,
  device_min_block_alignment: vk.DeviceSize,
}

Font :: struct {
  name: string,
  height: f32,
  texture: TextureResourceHandle,
  char_data: [^]stbtt.bakedchar,
  bump_up_y_offset: f32,
}

// TODO -- this is a bit of a hack, but it works for now
// Allocated memory is disconjugate and not reusable
// RESOURCE_BUCKET_SIZE :: 32
ResourceManager :: struct {
  _mutex: sync.Mutex,
  resource_index: ResourceHandle,
  resource_map: map[ResourceHandle]^Resource,
}

InputAttribute :: struct {
  format: vk.Format,
  location: u32,
  offset: u32,
}

PipelineCreateConfig :: struct {
  render_pass: RenderPassResourceHandle,
  vertex_shader_binary: []u8,
  fragment_shader_binary: []u8,
  cull_mode: vk.CullModeFlags,
  front_face: vk.FrontFace,
  fill_mode: vk.PolygonMode,
  // If using fill_mode == vk.PolygonMode.LINE, this is the modification of the width of the line in pixels
  // -- eg. 1.0 is the standard width, line_width_extra = 1.5 will make the line 2.5 pixels wide (add not multiply)
  line_width_extra: f32,
}

RenderProgramCreateInfo :: struct {
  pipeline_config: PipelineCreateConfig,
  vertex_size: int,
  buffer_bindings: []vk.DescriptorSetLayoutBinding,
  input_attributes: []InputAttribute,
}

RenderProgram :: struct {
  layout_bindings: []vk.DescriptorSetLayoutBinding,
	pipeline: Pipeline,
  descriptor_layout: vk.DescriptorSetLayout,
}

_init_resource_manager :: proc(using rm: ^ResourceManager) -> ProcResult {
  resource_index = INITIAL_RESOURCE_HANDLE_INDEX
  resource_map = make(map[ResourceHandle]^Resource)

  return .Success
}

_end_resource_manager :: proc(ctx: ^VkSDLContext) -> ProcResult {
  using rm: ^ResourceManager = &ctx.resource_manager
  sync.lock(&rm._mutex)
  defer sync.unlock(&rm._mutex)

  if len(resource_map) > 0 {
    if RESOURCES_DEBUG_AUTO_CLEANUP_FLAG do fmt.println("WARNING: resource_map not empty")

    // Destroy Complex Types first
    // -- Resources which contain other resources
    cloop: for len(resource_map) > 0 {
      for k, v in resource_map {
        #partial switch v.kind {
          case .Font, .StampRenderResource:
            // Nothing
          case:
            continue
        }
        // fmt.println("k:", k, "v:", v)
        if RESOURCES_DEBUG_AUTO_CLEANUP_FLAG do fmt.println("-- auto-destroying resource:", k, "-", v.kind)
        destroy_resource_any(ctx, k)
        continue cloop
      }
      break
    }
    
    // Destroy remaining types
    rloop: for len(resource_map) > 0 {
      for k, v in resource_map {
        // fmt.println("k:", k, "v:", v)
        fmt.println("-- auto-destroying resource:", k, "-", v.kind)
        destroy_resource_any(ctx, k)
        continue rloop
      }
      break
    }
  }

  return .Success
}

// TODO -- ? remove size ? not used at all
_create_resource :: proc(using rm: ^ResourceManager, resource_kind: ResourceKind, size: u32 = 0) -> (rh: ResourceHandle, prs: ProcResult) {
  sync.lock(&rm._mutex)
  defer sync.unlock(&rm._mutex)

  switch resource_kind {
    case .Texture,
         .Buffer,
         .DepthBuffer,
         .RenderPass,
         .RenderProgram,
         .StampRenderResource,
         .VertexBuffer,
         .IndexBuffer,
         .Font:
      rh = resource_index
      resource_index += 1
      res: ^Resource
      {
        res_mem, aerr := mem.alloc(size_of(Resource))
        if aerr != .None {
          fmt.eprintln("Error: Failed to allocate memory for resource")
          prs = .AllocationFailed
          return
        }
        res = auto_cast res_mem
      }
      resource_map[rh] = res
      res.kind = resource_kind
      when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Created resource: ", rh)
      return
    case .Any:
      fmt.eprintln("Error: Cannot create resource of kind Any")
      prs = .NotYetDetailed
      return
    case:
      fmt.eprintln("Resource type not supported:", resource_kind)
      prs = .NotYetDetailed
      return
  }
}

_resource_manager_report :: proc(using rm: ^ResourceManager) {
  fmt.println("Resource Manager Report:")
  // fmt.println("  Resource Manager:", rm)
  fmt.println("  Resource Count: ", len(resource_map))
  fmt.println("  Resource Index: ", resource_index)
}

get_resource :: proc(using rm: ^ResourceManager, #any_int rh: ResourceHandle, loc := #caller_location) \
  -> (ptr: rawptr, prs: ProcResult) {
  res := resource_map[rh]
  if res == nil {
    prs = .ResourceNotFound
    fmt.eprintln("Could not find resource for handle:", rh)
    fmt.eprintln("--Caller:", loc)
    _resource_manager_report(rm)
    return
  }

  ptr = &res.data
  return
}

@(private)__pop_resource_ptr :: proc(using ctx: ^VkSDLContext, rh: ResourceHandle, kind_verification: ResourceKind) \
  -> (res: ^Resource, prs: ProcResult) {
  vk.DeviceWaitIdle(device); // TODO -- will 'probably' need better synchronization

  res = resource_manager.resource_map[rh]
  if res == nil {
    fmt.eprintln("Resource not found(2):", rh)
    prs = .ResourceNotFound
    return
  }

  if res.kind != kind_verification {
    fmt.eprintln("Resource kind mismatch:", res.kind, "!=", kind_verification)
    prs = .ResourceKindMismatch
    return
  }

  delete_key(&resource_manager.resource_map, rh)

  return
}

destroy_resource_any :: proc(using ctx: ^VkSDLContext, rh: ResourceHandle) -> ProcResult {
  res, okay := resource_manager.resource_map[rh]
  if res == nil {
    fmt.println("res:", res, "okay:", okay)
    fmt.println("resource_map:", resource_manager.resource_map)
    fmt.eprintln("Resource not found(1):", rh)
    return .ResourceNotFound
  }

  switch res.kind {
    case .Texture:
      destroy_texture(ctx, auto_cast rh)
    case .Buffer:
      destroy_buffer(ctx, auto_cast rh)
    case .DepthBuffer:
      destroy_depth_buffer(ctx, auto_cast rh)
    case .RenderPass:
      destroy_render_pass(ctx, auto_cast rh)
    case .RenderProgram:
      destroy_render_program(ctx, auto_cast rh)
    case .StampRenderResource:
      destroy_stamp_render_resource(ctx, auto_cast rh)
    case .VertexBuffer:
      destroy_vertex_buffer(ctx, auto_cast rh)
    case .IndexBuffer:
      destroy_index_buffer(ctx, auto_cast rh)
    case .Font:
      destroy_font(ctx, auto_cast rh)
    case .Any:
      fallthrough
    case:
      fmt.println("Resource type not supported:", res.kind)
      return .NotYetDetailed
  }

  // fmt.println("Destroyed resource:", rh, "of type:", res.kind)
  // if render_data.texture.image != 0 {
  //   vk.DestroyImage(ctx.device, render_data.texture.image, nil)
  //   vk.FreeMemory(ctx.device, render_data.texture.image_memory, nil)
  //   vk.DestroyImageView(ctx.device, render_data.texture.image_view, nil)
  //   vk.DestroySampler(ctx.device, render_data.texture.sampler, nil)
  // }
  return .Success
}

destroy_texture :: proc(using ctx: ^VkSDLContext, rh: TextureResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying texture:", rh)

  res := __pop_resource_ptr(ctx, auto_cast rh, .Texture) or_return

  texture: ^Texture = auto_cast &res.data
  vma.DestroyImage(vma_allocator, texture.image, texture.allocation)
  if texture.image_view != 0 {
    vk.DestroyImageView(ctx.device, texture.image_view, nil)
  }
  if texture.sampler != 0 {
    vk.DestroySampler(ctx.device, texture.sampler, nil)
  }

  mem.free(res)

  return .Success
}

destroy_buffer :: proc(using ctx: ^VkSDLContext, rh: BufferResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying buffer:", rh)
  
  res := __pop_resource_ptr(ctx, auto_cast rh, .Buffer) or_return

  buffer: ^Buffer = auto_cast &res.data
  vma.DestroyBuffer(vma_allocator, buffer.buffer, buffer.allocation)

  mem.free(res)

  return .Success
}

destroy_depth_buffer :: proc(using ctx: ^VkSDLContext, rh: DepthBufferResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying depth buffer:", rh)

  res := __pop_resource_ptr(ctx, auto_cast rh, .DepthBuffer) or_return

  depth_buffer: ^DepthBuffer = auto_cast &res.data
  _dispose_depth_buffer_resources(ctx, depth_buffer)

  mem.free(res)

  return .Success
}

destroy_render_pass :: proc(using ctx: ^VkSDLContext, rh: RenderPassResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying render pass:", rh)

  res := __pop_resource_ptr(ctx, auto_cast rh, .RenderPass) or_return

  render_pass: ^RenderPass = auto_cast &res.data
  
  if render_pass.framebuffers != nil {
    for i in 0..<len(render_pass.framebuffers) {
      vk.DestroyFramebuffer(ctx.device, render_pass.framebuffers[i], nil)
    }
    delete_slice(render_pass.framebuffers)
  }

  if render_pass.depth_buffer_rh != 0 {
    destroy_resource(ctx, render_pass.depth_buffer_rh)
  }

  vk.DestroyRenderPass(device, render_pass.render_pass, nil)

  mem.free(res)

  return .Success
}

destroy_render_program :: proc(using ctx: ^VkSDLContext, rh: RenderProgramResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying render program:", rh)

  res := __pop_resource_ptr(ctx, auto_cast rh, .RenderProgram) or_return

  rp: ^RenderProgram = auto_cast &res.data
  if rp.pipeline.handle != 0 do vk.DestroyPipeline(device, rp.pipeline.handle, nil)
  if rp.pipeline.layout != 0 do vk.DestroyPipelineLayout(device, rp.pipeline.layout, nil)
  
  if rp.descriptor_layout != 0 do vk.DestroyDescriptorSetLayout(device, rp.descriptor_layout, nil)

  mem.free(res)

  return .Success
}

destroy_stamp_render_resource :: proc(using ctx: ^VkSDLContext, rh: StampRenderResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying stamp render resource:", rh)

  res := __pop_resource_ptr(ctx, auto_cast rh, .StampRenderResource) or_return

  stamp_render_resource: ^StampRenderResource = auto_cast &res.data

  __release_stamp_render_resource(ctx, stamp_render_resource)

  mem.free(res)

  return .Success
}

destroy_vertex_buffer :: proc(using ctx: ^VkSDLContext, rh: VertexBufferResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying vertex buffer:", rh)

  res := __pop_resource_ptr(ctx, auto_cast rh, .VertexBuffer) or_return

  vertex_buffer: ^VertexBuffer = auto_cast &res.data
  vma.DestroyBuffer(vma_allocator, vertex_buffer.buffer, vertex_buffer.allocation)

  mem.free(res)

  return .Success
}

destroy_index_buffer :: proc(using ctx: ^VkSDLContext, rh: IndexBufferResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying index buffer:", rh)

  res := __pop_resource_ptr(ctx, auto_cast rh, .IndexBuffer) or_return

  index_buffer: ^IndexBuffer = auto_cast &res.data
  vma.DestroyBuffer(vma_allocator, index_buffer.buffer, index_buffer.allocation)

  mem.free(res)

  return .Success
}

destroy_font :: proc(using ctx: ^VkSDLContext, rh: FontResourceHandle) -> ProcResult {
  when RESOURCES_DEBUG_VERBOSE_FLAG do fmt.println("Destroying font:", rh)

  res := __pop_resource_ptr(ctx, auto_cast rh, .Font) or_return

  font: ^Font = auto_cast &res.data
  destroy_resource(ctx, font.texture)

  mem.free(res)

  return .Success
}

destroy_resource :: proc {destroy_resource_any, destroy_texture, destroy_buffer, destroy_depth_buffer, destroy_render_pass,
  destroy_render_program, destroy_stamp_render_resource, destroy_vertex_buffer, destroy_index_buffer, destroy_font}

_resize_framebuffer_resources :: proc(using ctx: ^VkSDLContext) -> ProcResult {

  fmt.println("Resizing framebuffer resources TODO")

  return .NotYetImplemented
  // for f in swap_chain.present_framebuffers
  // {
  //   vk.DestroyFramebuffer(device, f, nil);
  // }
  // for f in swap_chain.framebuffers_3d
  // {
  //   vk.DestroyFramebuffer(device, f, nil);
  // }
  // _create_framebuffers(ctx);
}

// iterate_crackles :: proc(a: ^int) -> (pop: ^Pop, ok: bool) {
//   for a^ < len(Crackles) {
//     pop = &Crackles[a^]
//     a^ += 1
//     if !pop.y do continue
    
//     ok = true
//     return
//   }
//   ok = false
//   return
// }
// i: int
// for pop in iterate_crackles(&i) {
//   fmt.println(pop.i, pop.y)
// }
iterate_resources :: proc(iter_index: ^int, resource_manager: ^ResourceManager, kind: ResourceKind = .Any) \
  -> (rh: ResourceHandle, ok: bool) {
  // fmt.println("Iterating resources:", kind, iter_index^)
  for i: ResourceHandle = auto_cast (INITIAL_RESOURCE_HANDLE_INDEX + iter_index^); i < resource_manager.resource_index; i += 1 {
    res, exists := resource_manager.resource_map[i]
    // fmt.println("i:", i, "res:", res, "ok:", ok)
    iter_index^ += 1
    if !exists do continue
    
    if kind == .Any || res.kind == kind {
      rh = i
      ok = true
      // fmt.println("Returning resource:", rh, "of kind:", res.kind)
      return
    }
  }
  ok = false
  return
}

_begin_single_time_commands :: proc(ctx: ^VkSDLContext) -> ProcResult {
  // -- Reset the Command Buffer
  vkres := vk.ResetCommandBuffer(ctx.st_command_buffer, {})
  if vkres != .SUCCESS {
    fmt.eprintln("Error: Failed to reset command buffer:", vkres)
    return .NotYetDetailed
  }

  // Begin it
  begin_info := vk.CommandBufferBeginInfo {
    sType = .COMMAND_BUFFER_BEGIN_INFO,
    flags = { .ONE_TIME_SUBMIT },
  }
  
  vkres = vk.BeginCommandBuffer(ctx.st_command_buffer, &begin_info)
  if vkres != .SUCCESS {
    fmt.eprintln("vk.BeginCommandBuffer failed:", vkres)
    return .NotYetDetailed
  }
  
  return .Success
}

_end_single_time_commands :: proc(ctx: ^VkSDLContext) -> ProcResult {
  // End
  vkres := vk.EndCommandBuffer(ctx.st_command_buffer)
  if vkres != .SUCCESS {
    fmt.eprintln("vk.EndCommandBuffer failed:", vkres)
    return .NotYetDetailed
  }

  // Submit to queue
  submit_info := vk.SubmitInfo {
    sType = .SUBMIT_INFO,
    commandBufferCount = 1,
    pCommandBuffers = &ctx.st_command_buffer,
  }
  vkres = vk.QueueSubmit(ctx.queues[.Graphics], 1, &submit_info, auto_cast 0)
  if vkres != .SUCCESS {
    fmt.eprintln("vk.QueueSubmit failed:", vkres)
    return .NotYetDetailed
  }

  vkres = vk.QueueWaitIdle(ctx.queues[.Graphics])
  if vkres != .SUCCESS {
    fmt.eprintln("vk.QueueWaitIdle failed:", vkres)
    return .NotYetDetailed
  }

  return .Success
}

transition_image_layout :: proc(ctx: ^VkSDLContext, image: vk.Image, format: vk.Format, mip_levels: u32, old_layout: vk.ImageLayout,
  new_layout: vk.ImageLayout) -> ProcResult {
    
  _begin_single_time_commands(ctx) or_return

  barrier := vk.ImageMemoryBarrier {
    sType = .IMAGE_MEMORY_BARRIER,
    oldLayout = old_layout,
    newLayout = new_layout,
    srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
    image = image,
    subresourceRange = vk.ImageSubresourceRange {
      aspectMask = { .COLOR },
      baseMipLevel = 0,
      levelCount = mip_levels,
      baseArrayLayer = 0,
      layerCount = 1,
    },
  }
  
  source_stage: vk.PipelineStageFlags
  destination_stage: vk.PipelineStageFlags
  
  if old_layout == .UNDEFINED && new_layout == .TRANSFER_DST_OPTIMAL {
    barrier.srcAccessMask = {}
    barrier.dstAccessMask = { .TRANSFER_WRITE }
    
    source_stage = { .TOP_OF_PIPE }
    destination_stage = { .TRANSFER }
  } else if old_layout == .TRANSFER_DST_OPTIMAL && new_layout == .SHADER_READ_ONLY_OPTIMAL {
    barrier.srcAccessMask = { .TRANSFER_WRITE }
    barrier.dstAccessMask = { .SHADER_READ }
    
    source_stage = { .TRANSFER }
    destination_stage = { .FRAGMENT_SHADER } // TODO -- VertexShader?
  } else {
    fmt.eprintln("ERROR transition_image_layout> unsupported layout transition:", old_layout, "to", new_layout)
    return .NotYetDetailed
  }
  
  vk.CmdPipelineBarrier(ctx.st_command_buffer, source_stage, destination_stage, {}, 0, nil, 0, nil, 1, &barrier)
  
  _end_single_time_commands(ctx) or_return

  return .Success
}

@(private="file") _generate_mipmaps :: proc(ctx: ^VkSDLContext, image: vk.Image, format: vk.Format, tex_width: u32, tex_height: u32,
    mip_levels: u32) -> (prs: ProcResult) {
  // Check if image format supports linear blitting
  format_props: vk.FormatProperties
  vk.GetPhysicalDeviceFormatProperties(ctx.physical_device, format, &format_props)
  if .SAMPLED_IMAGE_FILTER_LINEAR not_in format_props.optimalTilingFeatures {
    fmt.eprintln("ERROR _generate_mipmaps> texture image format does not support linear blitting!")
    return .NotYetDetailed
  }

  _begin_single_time_commands(ctx) or_return

  barrier := vk.ImageMemoryBarrier {
    sType = .IMAGE_MEMORY_BARRIER,
    image = image,
    srcQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
    dstQueueFamilyIndex = vk.QUEUE_FAMILY_IGNORED,
    subresourceRange = vk.ImageSubresourceRange {
      aspectMask = { .COLOR },
      baseArrayLayer = 0,
      layerCount = 1,
      levelCount = 1,
    },
  }

  mip_width: i32 = auto_cast tex_width
  mip_height: i32 = auto_cast tex_height

  for i: u32 = 1; i < mip_levels; i += 1 {
    barrier.subresourceRange.baseMipLevel = i - 1
    barrier.oldLayout = .TRANSFER_DST_OPTIMAL
    barrier.newLayout = .TRANSFER_SRC_OPTIMAL
    barrier.srcAccessMask = { .TRANSFER_WRITE }
    barrier.dstAccessMask = { .TRANSFER_READ }

    vk.CmdPipelineBarrier(ctx.st_command_buffer, { .TRANSFER }, { .TRANSFER }, {}, 0, nil, 0, nil, 1, &barrier)

  //     VkImageBlit blit{};
  //     blit.srcOffsets[0] = {0, 0, 0};
  //     blit.srcOffsets[1] = {mipWidth, mipHeight, 1};
  //     blit.srcSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  //     blit.srcSubresource.mipLevel = i - 1;
  //     blit.srcSubresource.baseArrayLayer = 0;
  //     blit.srcSubresource.layerCount = 1;
  //     blit.dstOffsets[0] = {0, 0, 0};
  //     blit.dstOffsets[1] = { mipWidth > 1 ? mipWidth / 2 : 1, mipHeight > 1 ? mipHeight / 2 : 1, 1 };
  //     blit.dstSubresource.aspectMask = VK_IMAGE_ASPECT_COLOR_BIT;
  //     blit.dstSubresource.mipLevel = i;
  //     blit.dstSubresource.baseArrayLayer = 0;
  //     blit.dstSubresource.layerCount = 1;
    blit := vk.ImageBlit {
      srcOffsets = [2]vk.Offset3D {
        vk.Offset3D { x = 0, y = 0, z = 0 },
        vk.Offset3D { x = mip_width, y = mip_height, z = 1 },
      },
      srcSubresource = vk.ImageSubresourceLayers {
        aspectMask = { .COLOR },
        mipLevel = i - 1,
        baseArrayLayer = 0,
        layerCount = 1,
      },
      dstOffsets = [2]vk.Offset3D {
        vk.Offset3D { x = 0, y = 0, z = 0 },
        vk.Offset3D { x = mip_width / 2 if mip_width > 1 else 1, y = mip_height / 2 if mip_height > 1 else 1, z = 1 },
      },
      dstSubresource = vk.ImageSubresourceLayers {
        aspectMask = { .COLOR },
        mipLevel = i,
        baseArrayLayer = 0,
        layerCount = 1,
      },
    }

  //     vkCmdBlitImage(commandBuffer,
  //         image, VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL,
  //         image, VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL,
  //         1, &blit,
  //         VK_FILTER_LINEAR);
    vk.CmdBlitImage(ctx.st_command_buffer, image, .TRANSFER_SRC_OPTIMAL, image, .TRANSFER_DST_OPTIMAL, 1, &blit, .LINEAR)

  //     barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
  //     barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  //     barrier.srcAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
  //     barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
    barrier.oldLayout = .TRANSFER_SRC_OPTIMAL
    barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
    barrier.srcAccessMask = { .TRANSFER_READ }
    barrier.dstAccessMask = { .SHADER_READ }

  //     vkCmdPipelineBarrier(commandBuffer,
  //         VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0,
  //         0, nullptr,
  //         0, nullptr,
  //         1, &barrier);
    vk.CmdPipelineBarrier(ctx.st_command_buffer, { .TRANSFER }, { .FRAGMENT_SHADER }, {}, 0, nil, 0, nil, 1, &barrier)

  //     if (mipWidth > 1) mipWidth /= 2;
  //     if (mipHeight > 1) mipHeight /= 2;
    if mip_width > 1 { mip_width /= 2 }
    if mip_height > 1 { mip_height /= 2 }
  }

  // barrier.subresourceRange.baseMipLevel = mipLevels - 1;
  // barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
  // barrier.newLayout = VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL;
  // barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
  // barrier.dstAccessMask = VK_ACCESS_SHADER_READ_BIT;
  barrier.subresourceRange.baseMipLevel = mip_levels - 1
  barrier.oldLayout = .TRANSFER_DST_OPTIMAL
  barrier.newLayout = .SHADER_READ_ONLY_OPTIMAL
  barrier.srcAccessMask = { .TRANSFER_WRITE }
  barrier.dstAccessMask = { .SHADER_READ }

  // vkCmdPipelineBarrier(commandBuffer,
  //     VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_FRAGMENT_SHADER_BIT, 0,
  //     0, nullptr,
  //     0, nullptr,
  //     1, &barrier);
  vk.CmdPipelineBarrier(ctx.st_command_buffer, { .TRANSFER }, { .FRAGMENT_SHADER }, {}, 0, nil, 0, nil, 1, &barrier)

  _end_single_time_commands(ctx) or_return
  return
}

write_to_texture :: proc(using ctx: ^VkSDLContext, dst: TextureResourceHandle, data: rawptr, size_in_bytes: int) -> ProcResult {
  texture: ^Texture = auto_cast get_resource(&resource_manager, dst) or_return

  // Transition Image Layout
  transition_image_layout(ctx, texture.image, texture.format, texture.mip_levels, texture.current_layout,
    .TRANSFER_DST_OPTIMAL) or_return

  // Get the created buffers memory properties
  mem_property_flags: vk.MemoryPropertyFlags
  vma.GetAllocationMemoryProperties(vma_allocator, texture.allocation, &mem_property_flags)
  
  if vk.MemoryPropertyFlag.HOST_VISIBLE in mem_property_flags {
    // Allocation ended up in a mappable memory and is already mapped - write to it directly.
    // [Executed in runtime]:
    mem.copy(texture.allocation_info.pMappedData, data, size_in_bytes)
  } else {
    // Create a staging buffer
    staging_buffer_create_info := vk.BufferCreateInfo {
      sType = .BUFFER_CREATE_INFO,
      size = auto_cast size_in_bytes,
      usage = {.TRANSFER_SRC},
    }

    staging_allocation_create_info := vma.AllocationCreateInfo {
      usage = .AUTO,
      flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
    }
    
    staging: Buffer
    vkres := vma.CreateBuffer(vma_allocator, &staging_buffer_create_info, &staging_allocation_create_info, &staging.buffer,
      &staging.allocation, &staging.allocation_info)
    if vkres != .SUCCESS {
      fmt.eprintln("write_to_buffer>vmaCreateBuffer failed:", vkres)
      return .NotYetDetailed
    }
    defer vma.DestroyBuffer(vma_allocator, staging.buffer, staging.allocation)

    // Copy data to the staging buffer
    mem.copy(staging.allocation_info.pMappedData, data, size_in_bytes)

    // Copy buffers
    _begin_single_time_commands(ctx) or_return

    // copy_region := vk.BufferCopy {
    //   srcOffset = 0,
    //   dstOffset = 0,
    //   size = auto_cast size_in_bytes,
    // }
    // vk.CmdCopyBuffer(ctx.st_command_buffer, staging.buffer, buffer.buffer, 1, &copy_region)
    region := vk.BufferImageCopy {
      bufferOffset = 0,
      bufferRowLength = 0,
      bufferImageHeight = 0,
      imageSubresource = vk.ImageSubresourceLayers {
        aspectMask = { .COLOR },
        mipLevel = 0,
        baseArrayLayer = 0,
        layerCount = 1,
      },
      // imageOffset = vk.Offset3D { x = 0, y = 0, z = 0 },
      imageExtent = vk.Extent3D {
        width = texture.width,
        height = texture.height,
        depth = 1,
      },
    }
  
    vk.CmdCopyBufferToImage(ctx.st_command_buffer, staging.buffer, texture.image, .TRANSFER_DST_OPTIMAL, 1, &region)

    _end_single_time_commands(ctx) or_return
  }

  if texture.mip_levels > 1 {
    _generate_mipmaps(ctx, texture.image, texture.format, texture.width, texture.height, texture.mip_levels) or_return
  }

  // Transition Image Layout
  target_layout: vk.ImageLayout
  switch texture.intended_usage {
    case .ShaderReadOnly:
      target_layout = .SHADER_READ_ONLY_OPTIMAL
  }
  transition_image_layout(ctx, texture.image, texture.format, texture.mip_levels, .TRANSFER_DST_OPTIMAL, target_layout) or_return

  return .Success
}

TextureCreateOptions :: struct {
  image_usage: ImageUsage,
  generate_mipmaps: bool,
  addressModeU, addressModeV, addressModeW: vk.SamplerAddressMode,
}

DefaultTextureCreateOptions: TextureCreateOptions : TextureCreateOptions {
  image_usage = .ShaderReadOnly,
  generate_mipmaps = false,
  addressModeU = .REPEAT,
  addressModeV = .REPEAT,
}

create_texture :: proc(using ctx: ^VkSDLContext, tex_width: i32, tex_height: i32, tex_channels: i32,
    create_options: TextureCreateOptions = DefaultTextureCreateOptions) -> (handle: TextureResourceHandle, prs: ProcResult) {
  // Mip Levels
  mip_levels: u32 = 1
  if create_options.generate_mipmaps do mip_levels = auto_cast mx.floor(mx.log2(cast(f32) mx.max(tex_width, tex_height))) + 1
  // fmt.println("mip_levels:", mip_levels)
  
  // Create the resource
  handle = auto_cast _create_resource(&resource_manager, .Texture) or_return
  texture: ^Texture = auto_cast get_resource(&resource_manager, handle) or_return
  
  // image_sampler->resource_uid = p_vkrs->resource_uid_counter++; // TODO
  texture.sampler_usage = create_options.image_usage
  texture.width = auto_cast tex_width
  texture.height = auto_cast tex_height
  texture.size = auto_cast (tex_width * tex_height * 4) // TODO
  texture.format = swap_chain.format.format
  texture.intended_usage = create_options.image_usage
  texture.mip_levels = mip_levels

  // Create the image
  image_create_info := vk.ImageCreateInfo {
    sType = .IMAGE_CREATE_INFO,
    imageType = .D2,
    extent = vk.Extent3D {
      width = auto_cast tex_width,
      height = auto_cast tex_height,
      depth = 1,
    },
    mipLevels = mip_levels, 
    arrayLayers = 1,
    format = texture.format,
    tiling = .OPTIMAL,
    initialLayout = .UNDEFINED,
    samples = {._1},
  }
  switch create_options.image_usage {
    case .ShaderReadOnly:
      if texture.mip_levels > 1 {
        image_create_info.usage = { .TRANSFER_SRC, .TRANSFER_DST, .SAMPLED }
      } else {
        image_create_info.usage = { .TRANSFER_DST, .SAMPLED }
      }
      texture.current_layout = .UNDEFINED
    // case .ColorAttachment:
    //   image_create_info.usage = { .COLOR_ATTACHMENT }
    //   image_create_info.initialLayout = .UNDEFINED
    // case .DepthStencilAttachment:
    //   image_create_info.usage = { .DEPTH_STENCIL_ATTACHMENT }
    //   image_create_info.initialLayout = .UNDEFINED
    // case .RenderTarget:
    //   image_create_info.usage = { .COLOR_ATTACHMENT }
    //   image_create_info.initialLayout = .UNDEFINED
    // case .Present_KHR:
    //   image_create_info.usage = { .PRESENT_SRC_KHR }
    //   image_create_info.initialLayout = .UNDEFINED
  }

  // Allocate memory for the image
  alloc_create_info := vma.AllocationCreateInfo {
    usage = .AUTO_PREFER_DEVICE,
    flags = {.DEDICATED_MEMORY},
    priority = 1.0,
  }

  vkres := vma.CreateImage(ctx.vma_allocator, &image_create_info, &alloc_create_info, &texture.image, &texture.allocation, nil)
  if vkres != .SUCCESS {
    fmt.eprintln("vma.CreateImage failed:", vkres)
    prs = .NotYetDetailed
    return
  }

  // Image View
  view_info := vk.ImageViewCreateInfo {
    sType = .IMAGE_VIEW_CREATE_INFO,
    image = texture.image,
    viewType = .D2,
    format = texture.format,
    subresourceRange = vk.ImageSubresourceRange {
      aspectMask = { .COLOR },
      baseMipLevel = 0,
      levelCount = mip_levels,
      baseArrayLayer = 0,
      layerCount = 1,
    },
  }

  vkres = vk.CreateImageView(ctx.device, &view_info, nil, &texture.image_view)
  if vkres != .SUCCESS {
    fmt.eprintln("vkCreateImageView failed:", vkres)
    prs = .NotYetDetailed
    return
  }

  // switch (image_usage) {
  // case MVK_IMAGE_USAGE_READ_ONLY: {
  //   // printf("MVK_IMAGE_USAGE_READ_ONLY\n");
  //   image_sampler->framebuffer = NULL;
  // } break;
  // case MVK_IMAGE_USAGE_RENDER_TARGET_2D: {
  //   // printf("MVK_IMAGE_USAGE_RENDER_TARGET_2D\n");
  //   // Create Framebuffer
  //   VkImageView attachments[1] = {image_sampler->view};

  //   VkFramebufferCreateInfo framebuffer_create_info = {};
  //   framebuffer_create_info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  //   framebuffer_create_info.pNext = NULL;
  //   framebuffer_create_info.renderPass = p_vkrs->offscreen_render_pass_2d;
  //   framebuffer_create_info.attachmentCount = 1;
  //   framebuffer_create_info.pAttachments = attachments;
  //   framebuffer_create_info.width = texWidth;
  //   framebuffer_create_info.height = texHeight;
  //   framebuffer_create_info.layers = 1;

  //   res = vkCreateFramebuffer(p_vkrs->device, &framebuffer_create_info, NULL, &image_sampler->framebuffer);
  //   VK_CHECK(res, "vkCreateFramebuffer");

  // } break;
  // }
  // switch image_usage {
  //   case .ShaderReadOnly:
  //     texture.framebuffer = auto_cast 0
  //   case .RenderTarget:
  //     fmt.eprintln("RenderTarget2D/3D not implemented")
  //     prs = .NotYetImplemented
  //     return
  //   // case .RenderTarget2D:
  //   //   // Create Framebuffer
  //   //   attachments := [1]vk.ImageView { texture.sampler_usage }

  //   //   framebuffer_create_info := vk.FramebufferCreateInfo {
  //   //     sType = .FRAMEBUFFER_CREATE_INFO,
  //   //     renderPass = ctx.offscreen_render_pass_2d,
  //   //     attachmentCount = len(attachments),
  //   //     pAttachments = &attachments[0],
  //   //     width = tex_width,
  //   //     height = tex_height,
  //   //     layers = 1,
  //   //   }

  //   //   vkres = vk.CreateFramebuffer(ctx.device, &framebuffer_create_info, nil, &texture.framebuffer)
  //   //   if vkres != .SUCCESS {
  //   //     fmt.eprintln("vkCreateFramebuffer failed:", vkres)
  //   //     prs = .NotYetDetailed
  //   //     return
  //   //   }
  //   //   // case MVK_IMAGE_USAGE_RENDER_TARGET_3D: {
  //   //   //   // printf("MVK_IMAGE_USAGE_RENDER_TARGET_3D\n");
  //   //   //   // Create Framebuffer
  //   //   //   VkImageView attachments[2] = {image_sampler->view, p_vkrs->depth_buffer.view};
    
  //   //   //   VkFramebufferCreateInfo framebuffer_create_info = {};
  //   //   //   framebuffer_create_info.sType = VK_STRUCTURE_TYPE_FRAMEBUFFER_CREATE_INFO;
  //   //   //   framebuffer_create_info.pNext = NULL;
  //   //   //   framebuffer_create_info.renderPass = p_vkrs->offscreen_render_pass_3d;
  //   //   //   framebuffer_create_info.attachmentCount = 2;
  //   //   //   framebuffer_create_info.pAttachments = attachments;
  //   //   //   framebuffer_create_info.width = texWidth;
  //   //   //   framebuffer_create_info.height = texHeight;
  //   //   //   framebuffer_create_info.layers = 1;
    
  //   //   //   res = vkCreateFramebuffer(p_vkrs->device, &framebuffer_create_info, NULL, &image_sampler->framebuffer);
  //   //   //   VK_CHECK(res, "vkCreateFramebuffer");
  //   //   // } break;
  //   // case .RenderTarget3D:
  //   //   // Create Framebuffer
  //   //   attachments := [2]vk.ImageView { texture.sampler_usage, ctx.depth_buffer.view }

  //   //   framebuffer_create_info = vk.FramebufferCreateInfo {
  //   //     sType = .FRAMEBUFFER_CREATE_INFO,
  //   //     renderPass = ctx.offscreen_render_pass_3d,
  //   //     attachmentCount = len(attachments),
  //   //     pAttachments = &attachments[0],
  //   //     width = tex_width,
  //   //     height = tex_height,
  //   //     layers = 1,
  //   //   }

  //   //   vkres = vk.CreateFramebuffer(ctx.device, &framebuffer_create_info, nil, &texture.framebuffer)
  //   //   if vkres != .SUCCESS {
  //   //     fmt.eprintln("vkCreateFramebuffer failed:", vkres)
  //   //     prs = .NotYetDetailed
  //   //     return
  //   //   }
  // }


  // // Sampler
  // VkSamplerCreateInfo samplerInfo = {};
  // samplerInfo.sType = VK_STRUCTURE_TYPE_SAMPLER_CREATE_INFO;
  // samplerInfo.magFilter = VK_FILTER_LINEAR;
  // samplerInfo.minFilter = VK_FILTER_LINEAR;
  // samplerInfo.addressModeU = VK_SAMPLER_ADDRESS_MODE_REPEAT;
  // samplerInfo.addressModeV = VK_SAMPLER_ADDRESS_MODE_REPEAT;
  // samplerInfo.addressModeW = VK_SAMPLER_ADDRESS_MODE_REPEAT;
  // samplerInfo.anisotropyEnable = VK_TRUE;
  // samplerInfo.maxAnisotropy = 16.0f;
  // samplerInfo.borderColor = VK_BORDER_COLOR_INT_OPAQUE_BLACK;
  // samplerInfo.unnormalizedCoordinates = VK_FALSE;
  // samplerInfo.compareEnable = VK_FALSE;
  // samplerInfo.compareOp = VK_COMPARE_OP_ALWAYS;
  // samplerInfo.mipmapMode = VK_SAMPLER_MIPMAP_MODE_LINEAR;

  // res = vkCreateSampler(p_vkrs->device, &samplerInfo, NULL, &image_sampler->sampler);
  // VK_CHECK(res, "vkCreateSampler");

  // *out_image = image_sampler;

  // Sampler
  sampler_info := vk.SamplerCreateInfo {
    sType = .SAMPLER_CREATE_INFO,
    magFilter = .LINEAR,
    minFilter = .LINEAR,
    addressModeU = create_options.addressModeU,
    addressModeV = create_options.addressModeV,
    addressModeW = create_options.addressModeW,
    anisotropyEnable = false,
    // maxAnisotropy = 16.0,
    borderColor = .INT_OPAQUE_BLACK,
    unnormalizedCoordinates = false,
    compareEnable = false,
    compareOp = .ALWAYS,
    mipmapMode = .LINEAR,
    minLod = 0.0,
    maxLod = auto_cast mip_levels,
    mipLodBias = 0.0,
  }
  vkres = vk.CreateSampler(ctx.device, &sampler_info, nil, &texture.sampler)
  if vkres != .SUCCESS {
    fmt.eprintln("vkCreateSampler failed:", vkres)
    prs = .NotYetDetailed
    return
  }

  return
}

create_depth_buffer :: proc(ctx: ^VkSDLContext) -> (rh: ResourceHandle, prs: ProcResult) {
  // Create the depth buffer resource
  rh = _create_resource(&ctx.resource_manager, .DepthBuffer) or_return
  db: ^DepthBuffer = auto_cast get_resource(&ctx.resource_manager, rh) or_return

  prs = _build_depth_buffer(ctx, db)
  return
}

@(private) _dispose_depth_buffer_resources :: proc(using ctx: ^VkSDLContext, db: ^DepthBuffer) -> (prs: ProcResult) {
  vma.DestroyImage(vma_allocator, db.image, db.allocation)

  vk.DestroyImageView(ctx.device, db.view, nil)
  return
}

@(private) _build_depth_buffer :: proc(ctx: ^VkSDLContext, db: ^DepthBuffer) -> (prs: ProcResult) {
  // TODO -- Allow custom depth formats?
  preferred_depth_formats := [?]vk.Format {
    .D32_SFLOAT,
    .D32_SFLOAT_S8_UINT,
    .D24_UNORM_S8_UINT,
  }

  // Fill it out
  db.format = _find_supported_format(ctx, preferred_depth_formats[:], .OPTIMAL, {.DEPTH_STENCIL_ATTACHMENT})
  if db.format == .UNDEFINED {
    fmt.eprintln("Error: Failed to find supported depth format")
    prs = .NotYetDetailed
    return
  }

  // Create the image
  image_create_info := vk.ImageCreateInfo {
    sType = .IMAGE_CREATE_INFO,
    imageType = .D2,
    format = db.format,
    extent = vk.Extent3D {
      width = ctx.swap_chain.extent.width,
      height = ctx.swap_chain.extent.height,
      depth = 1,
    },
    mipLevels = 1,
    arrayLayers = 1,
    samples = {._1},
    tiling = .OPTIMAL,
    initialLayout = .UNDEFINED,
    usage = {.DEPTH_STENCIL_ATTACHMENT},
  }

  // VMA Allocation Info
  alloc_create_info := vma.AllocationCreateInfo {
    usage = .AUTO_PREFER_DEVICE,
    flags = {.DEDICATED_MEMORY},
    priority = 1.0,
  }

  vkres := vma.CreateImage(ctx.vma_allocator, &image_create_info, &alloc_create_info, &db.image, &db.allocation, nil)
  if vkres != .SUCCESS {
    fmt.eprintln("build_depth_buffer> vma.CreateImage failed:", vkres)
    prs = .NotYetDetailed
    return
  }

  // Create the Image View
  image_view_create_info := vk.ImageViewCreateInfo {
    sType = .IMAGE_VIEW_CREATE_INFO,
    viewType = .D2,
    format = db.format,
    subresourceRange = vk.ImageSubresourceRange {
      aspectMask = {.DEPTH},
      baseMipLevel = 0,
      levelCount = 1,
      baseArrayLayer = 0,
      layerCount = 1,
    },
    image = db.image,
  }
  vkres = vk.CreateImageView(ctx.device, &image_view_create_info, nil, &db.view)
  if vkres != .SUCCESS {
    fmt.eprintln("Error: Failed to create depth buffer image view:", vkres)
    prs = .NotYetDetailed
    return
  }
  
  return
}

// TODO -- PR STBI?
STBI_default :: 0 // only used for desired_channels
STBI_grey :: 1
STBI_grey_alpha :: 2
STBI_rgb :: 3
STBI_rgb_alpha :: 4

@(private)
load_texture_from_memory_options :: proc(using ctx: ^VkSDLContext, buffer: [^]byte, buffer_len: int,
    texture_create_options: TextureCreateOptions) -> (rh: TextureResourceHandle, prs: ProcResult) {

  tex_width, tex_height, tex_channels: libc.int
  pixels := stbi.load_from_memory(buffer, auto_cast buffer_len, &tex_width, &tex_height, &tex_channels, STBI_rgb_alpha)
  defer stbi.image_free(pixels)
  if pixels == nil {
  prs = .NotYetDetailed
  fmt.eprintln("Violin.load_texture_from_file: Failed to load image from memory, len=", buffer_len)
  return
  }

  image_size: int = auto_cast (tex_width * tex_height * STBI_rgb_alpha)
  // fmt.println("pixels:", pixels)
  // fmt.println("width:", tex_width, "height:", tex_height, "channels:", tex_channels, "image_size:", image_size)
  // mipLevels = static_cast<uint32_t>(std::floor(std::log2(std::max(texWidth, texHeight)))) + 1;

  rh = create_texture(ctx, tex_width, tex_height, tex_channels, texture_create_options) or_return
  // texture: ^Texture = auto_cast get_resource(&resource_manager, rh) or_return

  write_to_texture(ctx, rh, pixels, image_size) or_return

  // fmt.printf("loaded %s> width:%i height:%i channels:%i\n", filepath, tex_width, tex_height, tex_channels);

  return
}

@(private)
load_texture_from_memory_default :: proc(using ctx: ^VkSDLContext, buffer: [^]byte, buffer_len: int) -> \
    (rh: TextureResourceHandle, prs: ProcResult) {
    
  return load_texture_from_memory(ctx, buffer, buffer_len, DefaultTextureCreateOptions)
}   

load_texture_from_memory :: proc {
  load_texture_from_memory_options,
  load_texture_from_memory_default,
}

/* Loads a texture from a file for use as an image sampler in a shader.
 * The texture is loaded into a staging buffer, then copied to a device local
 * buffer. The staging buffer is then freed.
 * @param ctx The Violin Context
 * @param filepath The path to the file to load
 */
@(private)
load_texture_from_file_options :: proc(using ctx: ^VkSDLContext, filepath: cstring,
    texture_create_options: TextureCreateOptions) -> (rh: TextureResourceHandle, prs: ProcResult) {
  
  // Load into memory
  tex_width, tex_height, tex_channels: libc.int
  pixels := stbi.load(filepath, &tex_width, &tex_height, &tex_channels, STBI_rgb_alpha)
  defer stbi.image_free(pixels)
  if pixels == nil {
    prs = .NotYetDetailed
    fmt.eprintln("Violin.load_texture_from_file: Failed to load image from file:", filepath)
    return
  }
  
  image_size: int = auto_cast (tex_width * tex_height * STBI_rgb_alpha)
  // fmt.println("pixels:", pixels)
  // fmt.println("width:", tex_width, "height:", tex_height, "channels:", tex_channels, "image_size:", image_size)
  // mipLevels = static_cast<uint32_t>(std::floor(std::log2(std::max(texWidth, texHeight)))) + 1;

  rh = create_texture(ctx, tex_width, tex_height, tex_channels, texture_create_options) or_return
  // texture: ^Texture = auto_cast get_resource(&resource_manager, rh) or_return

  write_to_texture(ctx, rh, pixels, image_size) or_return

  // fmt.printf("loaded %s> width:%i height:%i channels:%i\n", filepath, tex_width, tex_height, tex_channels);

  return
}

@(private)
load_texture_from_file_default :: proc(using ctx: ^VkSDLContext, filepath: cstring) -> (rh: TextureResourceHandle, prs: ProcResult) {
  return load_texture_from_file(ctx, filepath, DefaultTextureCreateOptions)
}

load_texture_from_file :: proc {
  load_texture_from_file_options,
  load_texture_from_file_default,
}

create_uniform_buffer :: proc(using ctx: ^VkSDLContext, size_in_bytes: vk.DeviceSize, intended_usage: BufferUsage) -> (rh: BufferResourceHandle,
  prs: ProcResult) {
  #partial switch intended_usage {
    case .Dynamic:
      // Create the Buffer
      buffer_create_info := vk.BufferCreateInfo {
        sType = .BUFFER_CREATE_INFO,
        size = size_in_bytes,
        usage = {.UNIFORM_BUFFER, .TRANSFER_DST},
      }

      allocation_create_info := vma.AllocationCreateInfo {
        usage = .AUTO,
        flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .HOST_ACCESS_ALLOW_TRANSFER_INSTEAD, .MAPPED},
      }
      
      rh = auto_cast _create_resource(&ctx.resource_manager, .Buffer) or_return
      buffer: ^Buffer = auto_cast get_resource(&ctx.resource_manager, rh) or_return
      buffer.size = size_in_bytes
      vkres := vma.CreateBuffer(vma_allocator, &buffer_create_info, &allocation_create_info, &buffer.buffer,
        &buffer.allocation, &buffer.allocation_info)
      if vkres != .SUCCESS {
        fmt.eprintln("create_uniform_buffer>vmaCreateBuffer failed:", vkres)
        prs = .NotYetDetailed
      }
    case:
      fmt.eprintln("create_uniform_buffer() > Unsupported buffer usage:", intended_usage)
      prs = .NotYetDetailed
  }

  return
}

// TODO -- allow/disable staging - test performance
// TODO -- single-use-commands within processing of render command buffers. whats the deal
write_to_buffer :: proc(using ctx: ^VkSDLContext, rh: BufferResourceHandle, data: rawptr, size_in_bytes: int,
    loc := #caller_location) -> ProcResult {
  if rh == 0 {
    fmt.eprintln("write_to_buffer> Invalid resource handle")
    fmt.eprintln("write_to_buffer> Caller:", loc)
    return .InvalidResourceHandle
  }

  buffer: ^Buffer = auto_cast get_resource(&resource_manager, rh) or_return

  // Get the created buffers memory properties
  mem_property_flags: vk.MemoryPropertyFlags
  vma.GetAllocationMemoryProperties(vma_allocator, buffer.allocation, &mem_property_flags)
  
  if vk.MemoryPropertyFlag.HOST_VISIBLE in mem_property_flags {
    // Allocation ended up in a mappable memory and is already mapped - write to it directly.

    // [Executed in runtime]:
    mem.copy(buffer.allocation_info.pMappedData, data, size_in_bytes)
  } else {
    // Create a staging buffer
    staging_buffer_create_info := vk.BufferCreateInfo {
      sType = .BUFFER_CREATE_INFO,
      size = auto_cast size_in_bytes,
      usage = {.TRANSFER_SRC},
    }

    staging_allocation_create_info := vma.AllocationCreateInfo {
      usage = .AUTO,
      flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
    }
    
    staging: Buffer
    vkres := vma.CreateBuffer(vma_allocator, &staging_buffer_create_info, &staging_allocation_create_info, &staging.buffer,
      &staging.allocation, &staging.allocation_info)
    if vkres != .SUCCESS {
      fmt.eprintln("write_to_buffer>vmaCreateBuffer failed:", vkres)
      return .NotYetDetailed
    }
    defer vma.DestroyBuffer(vma_allocator, staging.buffer, staging.allocation)

    // Copy data to the staging buffer
    mem.copy(staging.allocation_info.pMappedData, data, size_in_bytes)

    // Copy buffers
    _begin_single_time_commands(ctx) or_return

    copy_region := vk.BufferCopy {
      srcOffset = 0,
      dstOffset = 0,
      size = auto_cast size_in_bytes,
    }
    vk.CmdCopyBuffer(ctx.st_command_buffer, staging.buffer, buffer.buffer, 1, &copy_region)

    _end_single_time_commands(ctx) or_return
  }

  return .Success
}

create_vertex_buffer :: proc(using ctx: ^VkSDLContext, vertex_data: rawptr, vertex_size_in_bytes: int,
  vertex_count: int) -> (rh: VertexBufferResourceHandle, prs: ProcResult) {
  // Create the resource
  rh = auto_cast _create_resource(&ctx.resource_manager, .VertexBuffer) or_return
  vertex_buffer: ^VertexBuffer = auto_cast get_resource(&ctx.resource_manager, rh) or_return

  // Set
  vertex_buffer.vertex_count = vertex_count
  vertex_buffer.size = auto_cast (vertex_size_in_bytes * vertex_count)

  // Staging buffer
  staging: Buffer
  buffer_info := vk.BufferCreateInfo{
    sType = .BUFFER_CREATE_INFO,
    size  = cast(vk.DeviceSize)(vertex_size_in_bytes * vertex_count),
    usage = {.TRANSFER_SRC},
    sharingMode = .EXCLUSIVE,
  }
  allocation_create_info := vma.AllocationCreateInfo {
    usage = .AUTO,
    flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
  }

  vkres := vma.CreateBuffer(vma_allocator, &buffer_info, &allocation_create_info, &staging.buffer,
    &staging.allocation, &staging.allocation_info)
  if vkres != .SUCCESS {
    fmt.eprintf("Error: Failed to create staging buffer!\n");
    destroy_resource_any(ctx, auto_cast rh)
    prs = .NotYetDetailed
    return
  }
  defer vma.DestroyBuffer(vma_allocator, staging.buffer, staging.allocation) //TODO -- one day, why isn't this working?

  // Copy data to the staging buffer
  mem.copy(staging.allocation_info.pMappedData, vertex_data, cast(int)vertex_buffer.size)

  // Create the vertex buffer
  buffer_info.usage = {.TRANSFER_DST, .VERTEX_BUFFER}
  allocation_create_info.flags = {}
  vkres = vma.CreateBuffer(vma_allocator, &buffer_info, &allocation_create_info, &vertex_buffer.buffer,
    &vertex_buffer.allocation, &vertex_buffer.allocation_info)
  if vkres != .SUCCESS {
    fmt.eprintf("Error: Failed to create vertex buffer!\n");
    destroy_resource_any(ctx, auto_cast rh)
    prs = .NotYetDetailed
    return
  }

  // Queue Commands to copy the staging buffer to the vertex buffer
  _begin_single_time_commands(ctx) or_return

  copy_region := vk.BufferCopy {
    srcOffset = 0,
    dstOffset = 0,
    size = vertex_buffer.size,
  }
  vk.CmdCopyBuffer(ctx.st_command_buffer, staging.buffer, vertex_buffer.buffer, 1, &copy_region)

  _end_single_time_commands(ctx) or_return

  return
}

@(private="file")
_create_index_buffer :: proc(using ctx: ^VkSDLContext, indices: rawptr, index_count: int, index_type: vk.IndexType) -> (rh:IndexBufferResourceHandle, prs: ProcResult) {
  // Create the resource
  rh = auto_cast _create_resource(&ctx.resource_manager, .IndexBuffer) or_return
  index_buffer: ^IndexBuffer = auto_cast get_resource(&ctx.resource_manager, rh) or_return

  // Set
  index_buffer.index_count = index_count
  index_buffer.index_type = index_type
  index_size: int
  #partial switch index_buffer.index_type {
    case .UINT16:
      index_size = 2
    case .UINT32:
      index_size = 4
    case:
      fmt.eprintln("create_index_buffer>Unsupported index type:", index_buffer.index_type)
      destroy_resource_any(ctx, auto_cast rh)
      prs = .NotYetDetailed
      return
  }
  index_buffer.size = auto_cast (index_size * index_count)
  
  // Staging buffer
  staging: Buffer
  buffer_create_info := vk.BufferCreateInfo{
    sType = .BUFFER_CREATE_INFO,
    size  = index_buffer.size,
    usage = {.TRANSFER_SRC},
    sharingMode = .EXCLUSIVE,
  };
  allocation_create_info := vma.AllocationCreateInfo {
    usage = .AUTO,
    flags = {.HOST_ACCESS_SEQUENTIAL_WRITE, .MAPPED},
  }

  vkres := vma.CreateBuffer(vma_allocator, &buffer_create_info, &allocation_create_info, &staging.buffer,
    &staging.allocation, &staging.allocation_info)
  if vkres != .SUCCESS {
    fmt.eprintf("Error: Failed to create staging buffer!\n");
    prs = .NotYetDetailed
    return
  }
  // defer vk.DestroyBuffer(device, staging.buffer, nil)
  // defer vk.FreeMemory(device, staging.allocation_info.deviceMemory, nil)
  defer vma.DestroyBuffer(vma_allocator, staging.buffer, staging.allocation) 

  // Copy from staging buffer to index buffer
  mem.copy(staging.allocation_info.pMappedData, indices, auto_cast index_buffer.size)

  buffer_create_info.usage = {.TRANSFER_DST, .INDEX_BUFFER}
  allocation_create_info.flags = {}
  vkres = vma.CreateBuffer(vma_allocator, &buffer_create_info, &allocation_create_info, &index_buffer.buffer,
    &index_buffer.allocation, &index_buffer.allocation_info)
  if vkres != .SUCCESS {
    fmt.eprintf("Error: Failed to create index buffer!\n");
    prs = .NotYetDetailed
    return
  }

  // Copy buffers
  _begin_single_time_commands(ctx) or_return

  copy_region := vk.BufferCopy {
    srcOffset = 0,
    dstOffset = 0,
    size = index_buffer.size,
  }
  vk.CmdCopyBuffer(ctx.st_command_buffer, staging.buffer, index_buffer.buffer, 1, &copy_region)

  _end_single_time_commands(ctx) or_return

  return
}

@(private="file")
_create_index_buffer_u32 :: proc(using ctx: ^VkSDLContext, indices: ^u32, index_count: int) -> (rh:IndexBufferResourceHandle, prs: ProcResult) {
  return _create_index_buffer(ctx, auto_cast indices, index_count, .UINT32)
}

@(private="file")
_create_index_buffer_u16 :: proc(using ctx: ^VkSDLContext, indices: ^u16, index_count: int) -> (rh:IndexBufferResourceHandle, prs: ProcResult) {
  return _create_index_buffer(ctx, auto_cast indices, index_count, .UINT16)
}

create_index_buffer :: proc {
  _create_index_buffer,
  _create_index_buffer_u32,
  _create_index_buffer_u16,
}

// create_index_buffer :: proc(using ctx: ^VkSDLContext, render_data: ^RenderData, indices: ^u16, index_count: int) -> ProcResult {
//   render_data.index_buffer.length = index_count;
//   render_data.index_buffer.size = cast(vk.DeviceSize)(index_count * size_of(u16));
  
//   staging: Buffer;
//   create_buffer(ctx, size_of(u16), index_count, {.TRANSFER_SRC}, {.HOST_VISIBLE, .HOST_COHERENT}, &staging);
  
//   data: rawptr;
//   vk.MapMemory(device, staging.ttmemory, 0, render_data.index_buffer.size, {}, &data);
//   mem.copy(data, indices, cast(int)render_data.index_buffer.size);
//   vk.UnmapMemory(device, staging.ttmemory);
  
//   create_buffer(ctx, size_of(u16), index_count, {.INDEX_BUFFER, .TRANSFER_DST}, {.DEVICE_LOCAL}, &render_data.index_buffer);
//   copy_buffer(ctx, staging, render_data.index_buffer, render_data.index_buffer.size);
  
//   vk.FreeMemory(device, staging.ttmemory, nil);
//   vk.DestroyBuffer(device, staging.buffer, nil);

//   return .Success
// }

// create_buffer :: proc(using ctx: ^VkSDLContext, member_size: int, count: int, usage: vk.BufferUsageFlags, properties: vk.MemoryPropertyFlags, buffer: ^Buffer) {

//   buffer_info := vk.BufferCreateInfo{
//     sType = .BUFFER_CREATE_INFO,
//     size  = cast(vk.DeviceSize)(member_size * count),
//     usage = usage,
//     sharingMode = .EXCLUSIVE,
//   };
  
//   if res := vk.CreateBuffer(device, &buffer_info, nil, &buffer.buffer); res != .SUCCESS
//   {
//     fmt.eprintf("Error: failed to create buffer\n");
//     os.exit(1);
//   }
  
//   mem_requirements: vk.MemoryRequirements;
//   vk.GetBufferMemoryRequirements(device, buffer.buffer, &mem_requirements);
  
//   alloc_info := vk.MemoryAllocateInfo {
//     sType = .MEMORY_ALLOCATE_INFO,
//     allocationSize = mem_requirements.size,
//     memoryTypeIndex = find_memory_type(ctx, mem_requirements.memoryTypeBits, {.HOST_VISIBLE, .HOST_COHERENT}),
//   }
  
//   if res := vk.AllocateMemory(device, &alloc_info, nil, &buffer.ttmemory); res != .SUCCESS {
//     fmt.eprintf("Error: Failed to allocate buffer memory!\n");
//     os.exit(1);
//   }
  
//   vk.BindBufferMemory(device, buffer.buffer, buffer.ttmemory, 0);
// }
create_render_program :: proc(ctx: ^VkSDLContext, info: ^RenderProgramCreateInfo) -> (rp_rh: RenderProgramResourceHandle, prs: ProcResult) {
  MAX_INPUT :: 16
  prs = .Success

  vertex_binding := vk.VertexInputBindingDescription {
    binding = 0,
    stride = auto_cast info.vertex_size,
    inputRate = .VERTEX,
  }

  vertex_attributes_count := len(info.input_attributes)
  layout_bindings_count := len(info.buffer_bindings)
  if vertex_attributes_count > MAX_INPUT || layout_bindings_count > MAX_INPUT {
    prs = .NotYetDetailed
    return
  }

  vertex_attributes : [MAX_INPUT]vk.VertexInputAttributeDescription
  for i in 0..<len(info.input_attributes) {
    vertex_attributes[i] = vk.VertexInputAttributeDescription {
      binding = 0,
      location = info.input_attributes[i].location,
      format = info.input_attributes[i].format,
      offset = info.input_attributes[i].offset,
    }
  }

  // Create the resource
  rp_rh = auto_cast _create_resource(&ctx.resource_manager, .RenderProgram) or_return
  rp: ^RenderProgram = auto_cast get_resource(&ctx.resource_manager, rp_rh) or_return

  // Descriptors
  rp.layout_bindings = make_slice([]vk.DescriptorSetLayoutBinding, layout_bindings_count)
  for i in 0..<layout_bindings_count do rp.layout_bindings[i] = info.buffer_bindings[i]

  // Next take layout bindings and use them to create a descriptor set layout
  layout_create_info := vk.DescriptorSetLayoutCreateInfo {
    sType = .DESCRIPTOR_SET_LAYOUT_CREATE_INFO,
    bindingCount = auto_cast len(rp.layout_bindings),
    pBindings = &rp.layout_bindings[0],
  }

  // TODO -- may cause segmentation fault? check-it
  res := vk.CreateDescriptorSetLayout(ctx.device, &layout_create_info, nil, &rp.descriptor_layout);
  if res != .SUCCESS {
    fmt.eprintln("Failed to create descriptor set layout")
    prs = .NotYetDetailed
    return
  }

  // Pipeline
  rp.pipeline = create_graphics_pipeline(ctx, &info.pipeline_config, &vertex_binding, vertex_attributes[:vertex_attributes_count],
    &rp.descriptor_layout) or_return

  // fmt.println("create_render_program return")
  return
}

// FontResourceHandle
// 
// VkResult mvk_load_font(vk_render_state *p_vkrs, const char *const filepath, float font_height,
//   mcr_font_resource **p_resource)
// {
// VkResult res;

load_font :: proc(using ctx: ^VkSDLContext, ttf_filepath: string, font_height: f32) -> (fh: FontResourceHandle, prs: ProcResult) {
// // Font is a common resource -- check font cache for existing -- TODO?
// char *font_name;
// {
// int index_of_last_slash = -1;
// for (int i = 0;; i++) {
// if (filepath[i] == '\0') {
// printf("INVALID FORMAT filepath='%s'\n", filepath);
// return VK_ERROR_UNKNOWN;
// }
// if (filepath[i] == '.') {
// int si = index_of_last_slash >= 0 ? (index_of_last_slash + 1) : 0;
// font_name = (char *)malloc(sizeof(char) * (i - si + 1));
// strncpy(font_name, filepath + si, i - si);
// font_name[i - si] = '\0';
// break;
// }
// else if (filepath[i] == '\\' || filepath[i] == '/') {
// index_of_last_slash = i;
// }
// }

// for (int i = 0; i < p_vkrs->loaded_fonts.count; ++i) {
// if (p_vkrs->loaded_fonts.fonts[i]->height == font_height &&
// !strcmp(p_vkrs->loaded_fonts.fonts[i]->name, font_name)) {
// *p_resource = p_vkrs->loaded_fonts.fonts[i];

// printf("using cached font texture> name:%s height:%.2f resource_uid:%u\n", font_name, font_height,
// (*p_resource)->texture->resource_uid);
// free(font_name);

// return VK_SUCCESS;
// }
// }
// }

// Load font
// stbi_uc ttf_buffer[1 << 20];
// fread(ttf_buffer, 1, 1 << 20, fopen(filepath, "rb"));
  // ttf_buffer[]
  file, oerr := os.open(ttf_filepath)


  errno: os.Errno
  h_ttf: os.Handle

  // Open the source file
  h_ttf, errno = os.open(ttf_filepath)
  if errno != os.ERROR_NONE {
    fmt.eprintf("Error File I/O: couldn't open font path='%s' set full path accordingly\n", ttf_filepath)
    prs = .NotYetDetailed
    return
  }
  defer os.close(h_ttf)

  // read_success: bool
  ttf_buffer, read_success := os.read_entire_file_from_handle(h_ttf)
  if !read_success {
    fmt.eprintln("Could not read full ttf font file:", ttf_filepath)
    prs = .NotYetDetailed
    return
  }
  defer delete(ttf_buffer)

  // Create the resource
  fh = auto_cast _create_resource(&resource_manager, .Font) or_return
  font: ^Font = auto_cast get_resource(&resource_manager, fh) or_return
  font.texture = create_texture(ctx, tex_width, tex_height, tex_channels) or_return
  font.height = font_height
  {
    cd_mem, aerr := mem.alloc(96*size_of(stbtt.bakedchar), allocator=context.temp_allocator)
    if aerr != .None {
      prs = .AllocationFailed
      return
    }
    font.char_data = auto_cast cd_mem
  }

// const int texWidth = 256, texHeight = 256, texChannels = 4;
// stbi_uc temp_bitmap[texWidth * texHeight];
// stbtt_bakedchar *cdata = (stbtt_bakedchar *)malloc(sizeof(stbtt_bakedchar) * 96); // ASCII 32..126 is 95 glyphs
// stbtt_BakeFontBitmap(ttf_buffer, 0, font_height, temp_bitmap, texWidth, texHeight, 32, 96,
//   cdata); // no guarantee this fits!
  tex_width :: 256
  tex_height :: 256
  tex_channels :: 4
  temp_bitmap: [^]u8
  {
    temp_bitmap_mem, aerr := mem.alloc(tex_width * tex_height, allocator=context.temp_allocator)
    if aerr != .None {
      prs = .AllocationFailed
      return
    }
    temp_bitmap = auto_cast temp_bitmap_mem
  }
  // defer free(temp_bitmap) // TODO -- no clue why this is causing segmentation fault. I've gotta be missing something right?

  stb_res := stbtt.BakeFontBitmap(&ttf_buffer[0], 0, font_height, temp_bitmap, tex_width, tex_height, 32, 96, font.char_data)
  if stb_res < 1 {
    fmt.eprintln("ERROR Failed to bake font bitmap:", stb_res)
    prs = .NotYetDetailed
    return
  }
  // stbtt.FreeBitmap(temp_bitmap, nil)

// // // printf("garbagein: font_height:%f\n", font_height);
// // stbi_uc pixels[texWidth * texHeight * 4];
// // {
// // int p = 0;
// // for (int i = 0; i < texWidth * texHeight; ++i) {
// // pixels[p++] = temp_bitmap[i];
// // pixels[p++] = temp_bitmap[i];
// // pixels[p++] = temp_bitmap[i];
// // pixels[p++] = 255;
// // }
// // }

  // Copy the font data into the texture
  pixels := make([^]u8, tex_width * tex_height * 4, context.temp_allocator)
  defer free(pixels)
  {
    p := 0
    for i := 0; i < tex_width * tex_height; i += 1 {
      pixels[p] = temp_bitmap[i]
      pixels[p + 1] = temp_bitmap[i]
      pixels[p + 2] = temp_bitmap[i]
      pixels[p + 3] = 255
      p += 4
    }
  }
  write_to_texture(ctx, font.texture, pixels, tex_width * tex_height * 4) or_return

  // 



// mcr_texture_image *texture;
// res = mvk_load_image_sampler(p_vkrs, texWidth, texHeight, texChannels, MVK_IMAGE_USAGE_READ_ONLY, pixels, &texture);
// VK_CHECK(res, "mvk_load_image_sampler");
  // rh := _create_resource(&ctx.resource_manager, .Texture, )

// append_to_collection((void ***)&p_vkrs->textures.items, &p_vkrs->textures.alloc, &p_vkrs->textures.count, texture);

// // Font is a common resource -- cache so multiple loads reference the same resource uid
// {
// mcr_font_resource *font = (mcr_font_resource *)malloc(sizeof(mcr_font_resource));
// append_to_collection((void ***)&p_vkrs->loaded_fonts.fonts, &p_vkrs->loaded_fonts.capacity,
//     &p_vkrs->loaded_fonts.count, font);

// font->name = font_name;
// font->height = font_height;
// font->texture = texture;
// font->char_data = cdata;
// {
// float lowest = 500;
// for (int ci = 0; ci < 96; ++ci) {
// stbtt_aligned_quad q;

// // printf("garbagein: %i %i %f %f %i\n", (int)font_image->width, (int)font_image->height, align_x, align_y,
// // letter
// // - 32);
// float ax = 100, ay = 300;
// stbtt_GetBakedQuad(cdata, (int)texWidth, (int)texHeight, ci, &ax, &ay, &q, 1);
// if (q.y0 < lowest)
// lowest = q.y0;
// // printf("baked_quad: s0=%.2f s1==%.2f t0=%.2f t1=%.2f x0=%.2f x1=%.2f y0=%.2f y1=%.2f lowest=%.3f\n", q.s0,
// // q.s1,
// //        q.t0, q.t1, q.x0, q.x1, q.y0, q.y1, lowest);
// }
// font->draw_vertical_offset = 300 - lowest;
// }
  {
    low_y0: f32 = 300.0
    high_y1: f32 = 0.0
    for c in 32..<128 {
      q: stbtt.aligned_quad
      ax: f32 = 100
      ay: f32 = 300
      stbtt.GetBakedQuad(font.char_data, tex_width, tex_height, auto_cast c, &ax, &ay, &q, true)
      // fmt.println("c:", cast(rune)c, "y0:", q.y0, "y1:", q.y1)
      // fmt.println("q:", q)
      // Hacky fix for some weird results from stbtt_GetBakedQuad where massive positive/negative values are returned
      if q.y0 > 300 - font_height * 2 do low_y0 = min(low_y0, q.y0)
      if q.y1 < 300 + font_height do high_y1 = max(high_y1, q.y1)
    }
    // fmt.println("low_y0:", low_y0, "high_y1:", high_y1)
    font.bump_up_y_offset = high_y1 - 300
    // font.vertical_size = high_y1 - low_y0
    // fmt.println("font:", ttf_filepath, "height:", font_height, "bump_up_y_offset:", font.bump_up_y_offset)
  }

  return
}

determine_text_display_dimensions :: proc(using ctx: ^VkSDLContext, font: FontResourceHandle, text: string) \
  -> (text_width: f32, text_height: f32, prs: ProcResult) {
  font: ^Font = auto_cast get_resource(&resource_manager, font) or_return

  q: stbtt.aligned_quad

  for c, i in text {
    if c < auto_cast 32 || c > auto_cast 127 {
      fmt.eprintln("ERROR: determine_text_display_dimensions> character '%i' not supported.\n", c)
      continue
    }

    // TODO -- this method seems inefficient. I'm sure there's a better way to do this.
    stbtt.GetBakedQuad(font.char_data, 256, 256, auto_cast c - 32, &text_width, &text_height, &q, true)
    // fmt.println("[q] s0:", q.s0, "s1:", q.s1, "t0:", q.t0, "t1:", q.t1, "x0:", q.x0, "x1:", q.x1, "y0:", q.y0, "y1:", q.y1)
    // fmt.println("char:", c, "i:", i, "text_width:", text_width, "text_height:", text_height)
  }

  text_height = font.height
  return
}