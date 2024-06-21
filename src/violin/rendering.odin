package violin

import "core:fmt"
import "core:c/libc"
import "core:sync"
import "core:time"

import vk "vendor:vulkan"


_obtain_flight_context :: proc(using ctx: ^VkSDLContext) -> (render_context: ^RenderContext, prs: ProcResult) {
  // Obtain a flight context
  retries := 0
  for !sync.try_lock(&in_flight_mutex) {
    if retries > 30 {
      fmt.println("TODO -- threadlocked render state")
      prs = .NotYetDetailed
      return
    }
    retries += 1
    time.sleep(time.Duration(1000 * retries * retries * 10))
  }
  defer sync.unlock(&in_flight_mutex)

  for i in 0..<MAX_FRAMES_IN_FLIGHT {
    if !sync.try_lock(&_render_contexts[i].mutex) {
      continue
    }
    defer sync.unlock(&_render_contexts[i].mutex)

    in_flight_index = (in_flight_index + 1) % MAX_FRAMES_IN_FLIGHT
    if _render_contexts[in_flight_index].status == .Idle {
      render_context = &_render_contexts[i]
      render_context.status = .Initializing
      render_context.command_buffer = swap_chain.command_buffers[in_flight_index]
      break
    }
    if i == MAX_FRAMES_IN_FLIGHT - 1 {
      fmt.println("TODO -- No Render Contexts available (???)")
      prs = .NotYetDetailed
      return
    }
  }

  if render_context == nil do prs = .NotYetDetailed
  return
}

begin_present :: proc(using ctx: ^VkSDLContext) -> (render_context: ^RenderContext, prs: ProcResult) {
  // Obtain a flight context
  render_context = _obtain_flight_context(ctx) or_return  
  sync.lock(&render_context.mutex)
  defer sync.unlock(&render_context.mutex)

  // Acquire the next image
  acquire_loop: for r in 0..<3 {
    if r == 2 {
      fmt.eprintln("Error: Failed to acquire swap chain image (3 times)")
      prs = .NotYetDetailed
      return
    }

    // Setup the render context
    vk.WaitForFences(device, 1, &render_context.in_flight, true, max(u64))
  
    TEN_MILLISECONDS_ns: u64 = 10000000
    vkres := vk.AcquireNextImageKHR(device, swap_chain.handle, TEN_MILLISECONDS_ns, render_context.image_available,
      {}, &render_context.swap_chain_index)
    if framebuffer_resized do vkres = .ERROR_OUT_OF_DATE_KHR

    #partial switch vkres {
      case .ERROR_OUT_OF_DATE_KHR:
        framebuffer_resized = false
        // fmt.println("handle framebuffer resize")
        _handle_resized_presentation(ctx) or_return
        continue acquire_loop
      case .SUBOPTIMAL_KHR, .SUCCESS:
        break acquire_loop
      case .TIMEOUT:
        fmt.eprintln("Error: Failed to acquire swap chain image (timeout) TODO -- implement soft handling?")
        prs = .NotYetDetailed
        return
      case:
        fmt.eprintln("Error: Failed to acquire swap chain image:", vkres)
        prs = .NotYetDetailed
        return
    }
  }

  // -- The swapchain references
  render_context.image = swap_chain.images[render_context.swap_chain_index]
  render_context.image_view = swap_chain.image_views[render_context.swap_chain_index]

  // Reset
  // -- Fences
  vkres := vk.ResetFences(device, 1, &render_context.in_flight)
  if vkres != .SUCCESS {
    fmt.eprintln("Error: Failed to reset fences:", vkres)
    prs = .NotYetDetailed
    return
  }

  // -- Descriptor Pool
  render_context.descriptor_sets_index = 0
  vkres = vk.ResetDescriptorPool(device, render_context.descriptor_pool, {})
  if vkres != .SUCCESS {
    fmt.eprintln("Error: Failed to reset descriptor pool:", vkres)
    prs = .NotYetDetailed
    return
  }

  // -- Command Buffer
  vk.ResetCommandBuffer(render_context.command_buffer, {})
  if vkres != .SUCCESS {
    fmt.eprintln("Error: Failed to reset command buffer:", vkres)
    prs = .NotYetDetailed
    return
  }
  
  // Begin
  begin_info := vk.CommandBufferBeginInfo {
    sType = .COMMAND_BUFFER_BEGIN_INFO,
    flags = {.ONE_TIME_SUBMIT},
  }
  vkres = vk.BeginCommandBuffer(render_context.command_buffer, &begin_info)
  if vkres != .SUCCESS {
    fmt.eprintln("Error: Failed to begin recording command buffer:", vkres)
    prs = .NotYetDetailed
    return
  }

  render_context.status = .Initialized
  return
}

begin_render_pass :: proc(using rctx: ^RenderContext, render_pass_handle: RenderPassResourceHandle) -> ProcResult {
  sync.lock(&rctx.mutex)
  defer sync.unlock(&rctx.mutex)

  return _begin_render_pass(rctx, render_pass_handle)
}

@(private) _begin_render_pass :: proc(using rctx: ^RenderContext, render_pass_handle: RenderPassResourceHandle) -> ProcResult {
  // fmt.println("begin_render_pass: ", rctx.status)

  // render_context.present_framebuffer = swap_chain.present_framebuffers[render_context.swap_chain_index]
  // render_context.framebuffer_3d = swap_chain.framebuffers_3d[render_context.swap_chain_index]
  rp: ^RenderPass = auto_cast get_resource(&rctx.ctx.resource_manager, auto_cast render_pass_handle) or_return
  // fmt.println("--render_pass.handle: ", render_pass_handle)
  // fmt.println("--render_pass.config: ", rp.config)
  
  // Validate State
  switch rctx.status {
    case .RenderPass, .StampRenderPass:
      // End the previous Render Pass
      vk.CmdEndRenderPass(rctx.command_buffer)
    case .EndedRenderPass:
      // Empty
    case .Initialized:
      // if .HasPreviousColorPass in rp.config {
      //   fmt.eprintln("Error: Cannot begin a render pass with a previous color pass when the render context is in the " \
      //     + "Initialized state")
      //   return .NotYetDetailed
      // }
      // Empty
    case .Idle, .Initializing:
      fmt.eprintln("Error: Invalid begin_render_pass Render Context State:", rctx.status)
      return .NotYetDetailed
  }

  // -- Render Pass
  clear_value_count: u32 = 0
  if .HasPreviousColorPass not_in rp.config do clear_value_count += 1
  if .HasDepthBuffer in rp.config do clear_value_count += 1

  clear_values := [2]vk.ClearValue {
    vk.ClearValue {
      color = vk.ClearColorValue {
        float32 = (cast(^[4]f32) &rp.clear_color)^,
      },
    },
    vk.ClearValue {
      depthStencil = vk.ClearDepthStencilValue {
        depth = 1.0,
        stencil = 0,
      },
    },
  }
  
  render_pass_begin_info := vk.RenderPassBeginInfo {
    sType = .RENDER_PASS_BEGIN_INFO,
    renderPass = rp.render_pass,
    framebuffer = rp.framebuffers[rctx.swap_chain_index],
    renderArea = vk.Rect2D {
      offset = vk.Offset2D {x = 0, y = 0},
      extent = ctx.swap_chain.extent,
    },
    clearValueCount = clear_value_count,
    pClearValues = &clear_values[0],
  }
  vk.CmdBeginRenderPass(rctx.command_buffer, &render_pass_begin_info, .INLINE)

  // Update status
  rctx.status = .RenderPass
  rctx.active_render_pass = render_pass_handle

  return .Success
}

end_present :: proc(using rctx: ^RenderContext) -> ProcResult {
  sync.lock(&rctx.mutex)
  defer sync.unlock(&rctx.mutex)

  // Validate State
  switch rctx.status {
    case .StampRenderPass:
      // fmt.println("end_present: StampRenderPass -- rctx.followup_render_pass:", rctx.followup_render_pass)
      // End the previous Render Pass
      if rctx.followup_render_pass != 0 do _begin_render_pass(rctx, rctx.followup_render_pass) or_return
      rctx.followup_render_pass = auto_cast 0
      fallthrough
    case .RenderPass:
      // fmt.println("end_present: RenderPass")
      // End the previous Render Pass
      vk.CmdEndRenderPass(rctx.command_buffer)
      fallthrough
    case .EndedRenderPass:
      // fmt.println("end_present: EndedRenderPass")
      // Empty
      rp: ^RenderPass = auto_cast get_resource(&rctx.ctx.resource_manager, auto_cast rctx.active_render_pass) or_return
      if .IsPresent not_in rp.config {
        fmt.eprintln("Error: Invalid render pass to present to screen (Either include .IsPresent flag in create config,",
          "or render a pass after this one with the flag specified", rctx.status)
        return .NotYetDetailed
      }
    case .Initialized:
      // Nothing was rendered
      rctx.status = .Idle
      // return .Success
    case .Idle, .Initializing:
      fmt.eprintln("Error: Invalid end_present Render Context State:", rctx.status)
      return .NotYetDetailed
  }

  vkres := vk.EndCommandBuffer(rctx.command_buffer)
  if vkres != .SUCCESS {
    fmt.eprintln("Error: Failed to end command buffer:", vkres)
    return .NotYetDetailed
  }

  // Submit the command buffer
  submit_info: vk.SubmitInfo;
  submit_info.sType = .SUBMIT_INFO;
  
  wait_semaphores := [?]vk.Semaphore{rctx.image_available};
  wait_stages := [?]vk.PipelineStageFlags{{.COLOR_ATTACHMENT_OUTPUT}};
  submit_info.waitSemaphoreCount = 1;
  submit_info.pWaitSemaphores = &wait_semaphores[0];
  submit_info.pWaitDstStageMask = &wait_stages[0];
  submit_info.commandBufferCount = 1;
  submit_info.pCommandBuffers = &rctx.command_buffer
  
  // signal_semaphores := [?]vk.Semaphore{rctx.render_finished}
  submit_info.signalSemaphoreCount = 1;
  submit_info.pSignalSemaphores = &rctx.render_finished
  
  if res := vk.QueueSubmit(ctx.queues[.Graphics], 1, &submit_info, rctx.in_flight); res != .SUCCESS {
    fmt.eprintln("Error: Failed to submit draw command buffer")
    return .NotYetDetailed
  }
  
  present_info: vk.PresentInfoKHR;
  present_info.sType = .PRESENT_INFO_KHR;
  present_info.waitSemaphoreCount = 1;
  present_info.pWaitSemaphores = &rctx.render_finished;
  
  swap_chains := [?]vk.SwapchainKHR{ctx.swap_chain.handle};
  present_info.swapchainCount = 1;
  present_info.pSwapchains = &swap_chains[0];
  present_info.pImageIndices = &rctx.swap_chain_index;
  present_info.pResults = nil;
  
  vk.QueuePresentKHR(ctx.queues[.Present], &present_info);

  rctx.status = .Idle

  return .Success
}
  
_set_viewport_cmd :: proc(command_buffer: vk.CommandBuffer, x: f32, y: f32, width: f32, height: f32) {
  viewport := vk.Viewport {
    x = x,
    y = y,
    width = width,
    height = height,
    minDepth = 0.0,
    maxDepth = 1.0,
  }

  // fmt.println("viewport:", viewport)

  vk.CmdSetViewport(command_buffer, 0, 1, &viewport)
}

_set_scissor_cmd :: proc(command_buffer: vk.CommandBuffer, x: i32, y: i32, width: u32, height: u32) {
  scissor := vk.Rect2D {
    offset = vk.Offset2D {
      x = x,
      y = y,
    },
    extent = vk.Extent2D {
      width = width,
      height = height,
    },
  }

  vk.CmdSetScissor(command_buffer, 0, 1, &scissor)
}

draw_indexed :: proc(using rctx: ^RenderContext, render_program: RenderProgramResourceHandle, vertex_buffer: VertexBufferResourceHandle,
  index_buffer: IndexBufferResourceHandle, parameters: []ResourceHandle, draw_index_count: u32 = 0) -> ProcResult {
  // Obtain the resources
  vbuf: ^VertexBuffer = auto_cast get_resource(&rctx.ctx.resource_manager, vertex_buffer) or_return
  ibuf: ^IndexBuffer = auto_cast get_resource(&rctx.ctx.resource_manager, index_buffer) or_return
  rprog: ^RenderProgram = auto_cast get_resource(&rctx.ctx.resource_manager, render_program) or_return

  // Setup viewport and clip
  if rctx.ctx.__settings.support_negative_viewport_heights {
    _set_viewport_cmd(command_buffer, 0, auto_cast ctx.swap_chain.extent.height, auto_cast ctx.swap_chain.extent.width,
      -auto_cast ctx.swap_chain.extent.height)
    _set_scissor_cmd(command_buffer, 0, 0, ctx.swap_chain.extent.width, ctx.swap_chain.extent.height)
  } else {
    _set_viewport_cmd(command_buffer, 0, 0, auto_cast ctx.swap_chain.extent.width,
      auto_cast ctx.swap_chain.extent.height)
    _set_scissor_cmd(command_buffer, 0, 0, ctx.swap_chain.extent.width, ctx.swap_chain.extent.height)
  }

  // Queue Buffer Write
  MAX_DESC_SET_WRITES :: 8
  writes: [MAX_DESC_SET_WRITES]vk.WriteDescriptorSet
  buffer_infos: [MAX_DESC_SET_WRITES]vk.DescriptorBufferInfo
  image_sampler_infos: [MAX_DESC_SET_WRITES]vk.DescriptorImageInfo
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

  // TODO check parameters length vs layout bindings?

  // Describe each binding
  // fmt.println("render_program.layout_bindings:", render_program.layout_bindings)
  for i in 0..<len(rprog.layout_bindings) {
    #partial switch rprog.layout_bindings[i].descriptorType {
      case .UNIFORM_BUFFER: {
        // TODO -- refactor / performance check / integrate mrt_write_desc_and_queue_render_data concept into this
        buffer: ^Buffer = auto_cast get_resource(&rctx.ctx.resource_manager, parameters[i]) or_return

        buffer_info := &buffer_infos[i]
        buffer_info.buffer = buffer.buffer
        buffer_info.offset = 0
        buffer_info.range = buffer.size

        // Element Vertex Shader Uniform Buffer
        write := &writes[write_index]
        write_index += 1

        write.sType = .WRITE_DESCRIPTOR_SET
        write.dstSet = desc_set
        write.descriptorCount = 1
        write.descriptorType = .UNIFORM_BUFFER
        write.pBufferInfo = buffer_info
        write.dstArrayElement = 0
        write.dstBinding = rprog.layout_bindings[i].binding
      }
      case .COMBINED_IMAGE_SAMPLER: {
        // Element Fragment Shader Combined Image Sampler
        image_sampler: ^Texture = auto_cast get_resource(&rctx.ctx.resource_manager, parameters[i]) or_return

        image_sampler_info := &image_sampler_infos[i]
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
        write.dstBinding = rprog.layout_bindings[i].binding
      }
      case: {
        fmt.eprintln("Unsupported descriptor type:", rprog.layout_bindings[i].descriptorType, '[', i, ']')
        return .NotYetDetailed
      }
    }
  }
  
  vk.UpdateDescriptorSets(ctx.device, auto_cast write_index, &writes[0], 0, nil)

  vk.CmdBindDescriptorSets(command_buffer, .GRAPHICS, rprog.pipeline.layout, 0, 1, &desc_set, 0, nil)

  vk.CmdBindPipeline(command_buffer, .GRAPHICS, rprog.pipeline.handle)

  vk.CmdBindIndexBuffer(command_buffer, ibuf.buffer, 0, ibuf.index_type) // TODO -- support other index types

  // const VkDeviceSize offsets[1] = {0};
  // vkCmdBindVertexBuffers(command_buffer, 0, 1, &cmd->rprog.data->vertices->buf, offsets);
  // // vkCmdDraw(command_buffer, 3 * 2 * 6, 1, 0, 0);
  // int index_draw_count = cmd->rprog.data->specific_index_draw_count;
  // if (!index_draw_count)
  //   index_draw_count = cmd->rprog.data->indices->capacity;
  offsets: vk.DeviceSize = 0
  vk.CmdBindVertexBuffers(command_buffer, 0, 1, &vbuf.buffer, &offsets)
  // TODO -- specific index draw count

  // // printf("index_draw_count=%i\n", index_draw_count);
  // // printf("cmd->rprog.data->indices->capacity=%i\n", cmd->rprog.data->indices->capacity);
  // // printf("cmd->rprog.data->specific_index_draw_count=%i\n",
  // //        cmd->rprog.data->specific_index_draw_count);

  // vkCmdDrawIndexed(command_buffer, index_draw_count, 1, 0, 0, 0);
  _draw_index_count := draw_index_count
  if draw_index_count == 0 do _draw_index_count = auto_cast ibuf.index_count
  vk.CmdDrawIndexed(command_buffer, _draw_index_count, 1, 0, 0, 0) // TODO -- index_count as u32?
  // fmt.print(render_data.index_count, ":")

  return .Success
}