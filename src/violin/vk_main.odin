package violin

import "core:fmt"
import "core:os"
import "core:mem"
import "core:c"
import "core:c/libc"
import "core:strings"
import "core:sync"
import "core:time"

import "vendor:sdl2"
import vk "vendor:vulkan"

import vma "odin-vma"

// mat4 :: distinct matrix[4,4]f32

MAX_FRAMES_IN_FLIGHT :: 2
MAX_DESCRIPTOR_SETS :: 4096

InitializedSettings :: struct {
  support_negative_viewport_heights: bool,
  device_extensions: [dynamic]cstring,
}

VkSDLContext :: struct {
  __settings: InitializedSettings,
  window: ^sdl2.Window,

  vma_allocator: vma.Allocator,
  resource_manager: ResourceManager,

  extensions_count: u32,
  extensions_names: [^]cstring,

  instance: vk.Instance,
  device:   vk.Device,
  physical_device: vk.PhysicalDevice,
  swap_chain: Swapchain,
  queue_indices:   [QueueFamily]int,
  queues:   [QueueFamily]vk.Queue,
  surface:  vk.SurfaceKHR,
  command_pool: vk.CommandPool,
  st_command_buffer: vk.CommandBuffer,
  
  framebuffer_resized: bool,

  in_flight_mutex: sync.Mutex,
  in_flight_index: u32,
  _render_contexts: [MAX_FRAMES_IN_FLIGHT]RenderContext,
}

Swapchain :: struct {
  handle: vk.SwapchainKHR,
  format: vk.SurfaceFormatKHR,
  extent: vk.Extent2D,
  present_mode: vk.PresentModeKHR,
  image_count: u32,
  support: SwapChainDetails,
  images: []vk.Image,
  image_views: []vk.ImageView,
  command_buffers: []vk.CommandBuffer,
}

RenderContext :: struct {
  ctx: ^VkSDLContext,

  mutex: sync.Mutex,
  status: FrameRenderStateKind,
  swap_chain_index: u32,

  image_available: vk.Semaphore,
  render_finished: vk.Semaphore,
  in_flight: vk.Fence,

  active_render_pass: RenderPassResourceHandle,
  followup_render_pass: RenderPassResourceHandle,
  // present_framebuffer: vk.Framebuffer,

  image: vk.Image,
  image_view: vk.ImageView,
  command_buffer: vk.CommandBuffer,

  descriptor_pool: vk.DescriptorPool,
  descriptor_sets: [MAX_DESCRIPTOR_SETS]vk.DescriptorSet,
  descriptor_sets_index: u32,
}

FrameRenderStateKind :: enum {
  Idle,
  Initializing,
  Initialized,
  RenderPass,
  StampRenderPass,
  EndedRenderPass,
}

Pipeline :: struct {
  handle: vk.Pipeline,
  layout: vk.PipelineLayout,
}

QueueFamily :: enum {
  Graphics,
  Present,
}

SwapChainDetails :: struct {
  capabilities: vk.SurfaceCapabilitiesKHR,
  formats: []vk.SurfaceFormatKHR,
  present_modes: []vk.PresentModeKHR,
}

ShaderKind :: enum {
  Vertex,
  Fragment,
}

RenderPassConfigFlags :: distinct bit_set[RenderPassConfigFlag; vk.Flags]
RenderPassConfigFlag :: enum vk.Flags {
  HasPreviousColorPass = 0,
	IsPresent            = 1,
  HasDepthBuffer       = 2,
}

VALIDATION_LAYERS := [?]cstring {
  // "VK_LAYER_KHRONOS_validation",
}

init_vksdl :: proc(ctx: ^VkSDLContext, #any_int window_width: int = 960, #any_int window_height: int = 600, support_negative_viewport_heights: bool = true,
  window_bordered: bool = true, init_sdl2_audio: bool = false) -> (prs: ProcResult) {
  using sdl2

  ctx.__settings.support_negative_viewport_heights = support_negative_viewport_heights

  // Init
  sdl2_init_flags := INIT_VIDEO | INIT_EVENTS
  if init_sdl2_audio do sdl2_init_flags |= INIT_AUDIO
  fmt.println("SDL2 Init Flags:", sdl2_init_flags)
  result := auto_cast Init(INIT_VIDEO | INIT_EVENTS)
  if result != 0 {
    fmt.eprintln("Error initializing sdl2: ", result)
    prs = .NotYetDetailed
    return
  }
  
  // Vulkan Library
  result = auto_cast Vulkan_LoadLibrary(nil)
  if result != 0 {
    fmt.eprintln("Error loading Vulkan Library: ", result)
    prs = .NotYetDetailed
    return
  }

  // Window
  ctx.window = CreateWindow("OdWin", 220, 30, auto_cast window_width, auto_cast window_height,
    WINDOW_SHOWN | WINDOW_RESIZABLE | WINDOW_VULKAN)

  init_vulkan(ctx) or_return
  return
}

@(private="file")
init_vulkan :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  context.user_ptr = &instance;
  get_proc_address :: proc(p: rawptr, name: cstring) 
  {
    vkGetInstanceProcAddr := cast(vk.ProcGetInstanceProcAddr) sdl2.Vulkan_GetVkGetInstanceProcAddr()
    (cast(^rawptr)p)^ = auto_cast vkGetInstanceProcAddr((^vk.Instance)(context.user_ptr)^, name)
  // fmt.println("called for:", name, " == ", (cast(^rawptr)p)^)
  }
  
  vk.load_proc_addresses(get_proc_address);
  _create_instance(ctx);
  vk.load_proc_addresses(get_proc_address);
  
  _create_surface_and_set_device(ctx) or_return
  
  // fmt.println("Queue Indices:");
  // for q, f in queue_indices do fmt.printf("  %v: %d\n", f, q);
  
  _create_logical_device(ctx) or_return
  
  for q, f in &queues do vk.GetDeviceQueue(device, u32(queue_indices[f]), 0, &q)

  for i in 0..<MAX_FRAMES_IN_FLIGHT {
    _render_contexts[i].ctx = ctx
    _render_contexts[i].status = .Idle
  }

  // Resource Indices
  _init_vma(ctx) or_return
  _init_resource_manager(&ctx.resource_manager) or_return
  
  // create_swap_chain(ctx)
  // create_swap_chain_image_views(ctx)
  _handle_resized_presentation(ctx) or_return

  create_command_pool(ctx) or_return
  
  create_command_buffers(ctx) or_return
  create_sync_objects(ctx) or_return

  _init_descriptor_pool(ctx) or_return

  return .Success
}

destroy_vksdl :: proc(using ctx: ^VkSDLContext) {
  vk.DeviceWaitIdle(device);
  
  deinit_vulkan(ctx);

  sdl2.DestroyWindow(window);
  sdl2.Vulkan_UnloadLibrary()
  sdl2.Quit()

  delete_dynamic_array(ctx.__settings.device_extensions)
  free(ctx)
}

@(private="file")
deinit_vulkan :: proc(using ctx: ^VkSDLContext) {
  cleanup_swap_chain(ctx);
  
  vk.FreeCommandBuffers(device, command_pool, u32(len(swap_chain.command_buffers)), &swap_chain.command_buffers[0])
  delete(swap_chain.command_buffers)

  for i in 0..<MAX_FRAMES_IN_FLIGHT
  {
    vk.DestroySemaphore(device, _render_contexts[i].image_available, nil)
    vk.DestroySemaphore(device, _render_contexts[i].render_finished, nil)
    vk.DestroyFence(device, _render_contexts[i].in_flight, nil)

    vk.DestroyDescriptorPool(device, _render_contexts[i].descriptor_pool, nil)
  }
  vk.DestroyCommandPool(device, command_pool, nil);
  
  _end_resource_manager(ctx)
  vma.DestroyAllocator(vma_allocator)

  vk.DestroyDevice(device, nil);
  vk.DestroySurfaceKHR(instance, surface, nil);
  destroy_instance(ctx)
}

@(private="file")
set_vulkan_extensions :: proc(ctx: ^VkSDLContext) -> (prs: ProcResult) {

  extra_ext_count : u32 : 0
  sdl2.Vulkan_GetInstanceExtensions(ctx.window, &ctx.extensions_count, nil)
  if ctx.extensions_count + extra_ext_count > 0 {
    en_mem, aerr := mem.alloc(cast(int)((ctx.extensions_count + extra_ext_count) * size_of(cstring)))
    if aerr != .None {
      fmt.eprintln("Error allocating memory for Vulkan extensions")
      return .AllocationFailed
    }

    ctx.extensions_names = cast([^]cstring)en_mem
    sdl2.Vulkan_GetInstanceExtensions(ctx.window, &ctx.extensions_count, ctx.extensions_names);
  }

  // ctx.extensions_count += extra_ext_count
  // ctx.extensions_names[ctx.extensions_count] = vk.EXT_DEBUG_UTILS_EXTENSION_NAME
  // ctx.extensions_names[ctx.extensions_count] = vk.KHR_MAINTENANCE1_EXTENSION_NAME

  // fmt.println("Vulkan extensions:")
  // for i in 0..<ctx.extensions_count do fmt.println("--extension: ", ctx.extensions_names[i])
  return
}

@(private="file")
check_vulkan_layer_support :: proc(create_info: ^vk.InstanceCreateInfo) -> ProcResult {
    when ODIN_DEBUG
    {
      layer_count: u32;
      vk.EnumerateInstanceLayerProperties(&layer_count, nil);
      layers := make([]vk.LayerProperties, layer_count);
      vk.EnumerateInstanceLayerProperties(&layer_count, raw_data(layers));

      builder := strings.builder_make(context.temp_allocator)
      for layer in layers {
        for b in layer.layerName {
          if b == 0 do break
          strings.write_byte(&builder, b)
        }
        
        // fmt.println("--", strings.to_string(builder))
        strings.builder_reset(&builder)
      }
      
      outer: for name in VALIDATION_LAYERS
      {
        for layer in &layers
        {
          if name == cstring(&layer.layerName[0]) do continue outer;
        }
        fmt.eprintf("ERROR: validation layer %q not available\n", name);
        return .VulkanLayerNotAvailable
      }
      
      when len(VALIDATION_LAYERS) > 0 {
        create_info.enabledLayerCount = cast(u32)len(VALIDATION_LAYERS)
        create_info.ppEnabledLayerNames = &VALIDATION_LAYERS[0]
      } else {
        create_info.enabledLayerCount = 0
        create_info.ppEnabledLayerNames = nil
      }
      // fmt.println("Validation Layers Loaded");
    }
    else
    {
      create_info.enabledLayerCount = 0;
    }
  return .Success
}

@(private="file")
_create_instance :: proc(ctx: ^VkSDLContext) -> ProcResult {
  app_info := vk.ApplicationInfo {
    sType = .APPLICATION_INFO,
    pApplicationName = "Violin Experiment",
    applicationVersion = vk.MAKE_VERSION(0, 1, 1),
    pEngineName = "Violin Renderer",
    engineVersion = vk.MAKE_VERSION(0, 1, 1),
    apiVersion = vk.API_VERSION_1_1,
  }

  set_vulkan_extensions(ctx) or_return

  create_info := vk.InstanceCreateInfo {
    sType = .INSTANCE_CREATE_INFO,
    pApplicationInfo = &app_info,
    enabledExtensionCount = ctx.extensions_count,
    ppEnabledExtensionNames = ctx.extensions_names,
  }
  check_vulkan_layer_support(&create_info)

  // Initialize GetInstanceProcAddr
  context.user_ptr = &ctx.instance;
  get_proc_address :: proc(p: rawptr, name: cstring) 
  {
    vkGetInstanceProcAddr := cast(vk.ProcGetInstanceProcAddr) sdl2.Vulkan_GetVkGetInstanceProcAddr()
    (cast(^rawptr)p)^ = auto_cast vkGetInstanceProcAddr((^vk.Instance)(context.user_ptr)^, name)
  // fmt.println("called for:", name, " == ", (cast(^rawptr)p)^)
  }
  vk.load_proc_addresses(get_proc_address)
  
  // Create Instance
  vkres := vk.CreateInstance(&create_info, nil, &ctx.instance)
  if vkres != .SUCCESS {
    fmt.eprintln("Error creating Vulkan Instance:", vkres)
    return .NotYetDetailed
  }
  // fmt.println("created vk Instance")

  // Reiterate procedure load with the instance set
  vk.load_proc_addresses(get_proc_address)

  return .Success
}

@(private="file")
destroy_instance :: proc(ctx: ^VkSDLContext) {
  if ctx.instance != nil {
    vk.DestroyInstance(ctx.instance, nil)
  }
}

@(private="file")
_set_physical_device_queue_families :: proc(surface: vk.SurfaceKHR, physical_device: vk.PhysicalDevice,
  suppress_missing_queue_messages := false) -> (graphics_queue_index: int, present_queue_index: int, prs: ProcResult) {
  graphics_queue_index = -1
  present_queue_index = -1

  queue_count: u32;
  vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_count, nil);
  available_queues, alerr := make([]vk.QueueFamilyProperties, queue_count)
  if alerr != .None {
    fmt.eprintln("Error allocating queue family properties")
    prs = .NotYetDetailed
    return
  }
  defer delete(available_queues)
  vk.GetPhysicalDeviceQueueFamilyProperties(physical_device, &queue_count, raw_data(available_queues))

  // Iterate over each queue to discover if it supports presenting on the created surface
  p_supports_present: [^]b32
  {
    psp_mem, psperr := mem.alloc(cast(int)(queue_count * size_of(b32)))
    if psperr != .None {
      fmt.eprintln("Error allocating queue family properties")
      prs = .NotYetDetailed
      return
    }
    p_supports_present = auto_cast psp_mem
  }
  defer mem.free(p_supports_present)

  for i in 0..<queue_count {
    vkres := vk.GetPhysicalDeviceSurfaceSupportKHR(physical_device, i, surface, &p_supports_present[i])
    if vkres != .SUCCESS {
      fmt.eprintln("Error GetPhysicalDeviceSurfaceSupportKHR:", vkres)
      prs = .NotYetDetailed
      return
    }
  }

  // Search for a graphics queue and a present queue in the array of queue families
  // First attempt to find a queue family that supports both
  for i in 0..<queue_count {
    if .GRAPHICS in available_queues[i].queueFlags {
      if p_supports_present[i] {
        // Found Family that supports both
        graphics_queue_index = auto_cast i
        present_queue_index = auto_cast i

        // Success
        return
      }

      if graphics_queue_index < 0 {
        graphics_queue_index = auto_cast i
      }
    }
  }

  if graphics_queue_index < 0 {
    if !suppress_missing_queue_messages do fmt.eprintln("Could not find a graphics queue on the primary device")
    prs = .NoQueueAvailableOnDevice
    return
  }

  // If there's no family that supports both, then find a separate present queue
  for i in 0..<queue_count {
    if p_supports_present[i] {
      present_queue_index = auto_cast i

      // Success
      return
    }
  }

  if !suppress_missing_queue_messages do fmt.eprintln("Could not find a present queue on the primary device")
  prs = .NoQueueAvailableOnDevice
  return
}

@(private="file")
check_device_extension_support :: proc(ctx: ^VkSDLContext, physical_device: vk.PhysicalDevice) -> bool {
  ext_count: u32;
  vk.EnumerateDeviceExtensionProperties(physical_device, nil, &ext_count, nil);
  
  available_extensions := make([]vk.ExtensionProperties, ext_count);
  defer delete(available_extensions)
  vk.EnumerateDeviceExtensionProperties(physical_device, nil, &ext_count, raw_data(available_extensions));
  
  for ext in ctx.__settings.device_extensions
  {
    found: b32;
    for available in &available_extensions
    {
      if cstring(&available.extensionName[0]) == ext
      {
        found = true;
        break;
      }
    }
    if !found do return false;
  }
  return true;
}

@(private="file")
_determine_device_suitability :: proc(using ctx: ^VkSDLContext, dev: vk.PhysicalDevice) -> (score: int, prs: ProcResult) {
  scr := 0

  g, p, res := _set_physical_device_queue_families(surface, dev, true)
  if res == .NoQueueAvailableOnDevice {
    return
  } else if res != .Success {
    fmt.eprintln("Error setting physical device queue families:", res)
    prs = .NotYetDetailed
    return
  }
  if g == p do scr += 99

  props: vk.PhysicalDeviceProperties;
  features: vk.PhysicalDeviceFeatures;
  vk.GetPhysicalDeviceProperties(dev, &props);
  vk.GetPhysicalDeviceFeatures(dev, &features);
  // fmt.println("Device:\n--Props:\n", props, "\n--Features:\n", features)

  if props.deviceType == .DISCRETE_GPU do scr += 1000;
  scr += cast(int)props.limits.maxImageDimension2D;
  
  if !features.geometryShader do return
  if !check_device_extension_support(ctx, dev) do return
  
  _query_swap_chain_details(ctx, dev)
  if len(swap_chain.support.formats) == 0 || len(swap_chain.support.present_modes) == 0 do return

  score = scr
  // fmt.println("Device:", cstring(&props.deviceName[0]), ":", props.deviceType, ":", props.apiVersion, " (Score:", score, ")")
  
  return
}

@(private="file")
_create_surface_and_set_device :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  // Create Surface
  if !sdl2.Vulkan_CreateSurface(window, instance, &surface) {
    fmt.eprintln("Error creating SDL2 Vulkan Surface")
    return .NotYetDetailed
  }
  
  // Find a suitable Physical Device for the surface
  device_count: u32;
  vk.EnumeratePhysicalDevices(instance, &device_count, nil);
  if device_count == 0 {
    fmt.eprintf("ERROR: Failed to find GPUs with Vulkan support\n")
    return .NotYetDetailed
  }
  devices := make([]vk.PhysicalDevice, device_count);
  defer delete(devices)
  vk.EnumeratePhysicalDevices(instance, &device_count, raw_data(devices))

  // Set required device extensions
  append_elem(&ctx.__settings.device_extensions, vk.KHR_SWAPCHAIN_EXTENSION_NAME)
  if ctx.__settings.support_negative_viewport_heights {
    append_elem(&ctx.__settings.device_extensions, vk.KHR_MAINTENANCE1_EXTENSION_NAME)
  }

  hiscore := 0
  for dev in devices {
    score := _determine_device_suitability(ctx, dev) or_return
    if score > hiscore {
      physical_device = dev
      hiscore = score
    }
  }
  if (hiscore == 0) {
    fmt.eprintf("ERROR: Failed to find a suitable GPU\n");
    return .NotYetDetailed
  }
  else {
    props: vk.PhysicalDeviceProperties
    features: vk.PhysicalDeviceFeatures
    vk.GetPhysicalDeviceProperties(physical_device, &props)
    vk.GetPhysicalDeviceFeatures(physical_device, &features)
    fmt.println("Selected Device:", cstring(&props.deviceName[0]), ":", props.deviceType, ":", props.apiVersion)
  }

  return .Success
}

@(private="file")
_create_logical_device :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  unique_indices: map[int]b8;
  defer delete(unique_indices);
  for i in queue_indices do unique_indices[i] = true;
  
  queue_priority := f32(1.0);
  
  queue_create_infos: [dynamic]vk.DeviceQueueCreateInfo;
  defer delete(queue_create_infos);
  for k, _ in unique_indices
  {
    queue_create_info: vk.DeviceQueueCreateInfo;
    queue_create_info.sType = .DEVICE_QUEUE_CREATE_INFO;
    queue_create_info.queueFamilyIndex = u32(queue_indices[.Graphics]);
    queue_create_info.queueCount = 1;
    queue_create_info.pQueuePriorities = &queue_priority;
    append(&queue_create_infos, queue_create_info);
  }
  
  device_features: vk.PhysicalDeviceFeatures;
  device_create_info: vk.DeviceCreateInfo;
  device_create_info.sType = .DEVICE_CREATE_INFO;
  device_create_info.enabledExtensionCount = u32(len(ctx.__settings.device_extensions));
  device_create_info.ppEnabledExtensionNames = &ctx.__settings.device_extensions[0];
  device_create_info.pQueueCreateInfos = raw_data(queue_create_infos);
  device_create_info.queueCreateInfoCount = u32(len(queue_create_infos));
  device_create_info.pEnabledFeatures = &device_features;
  device_create_info.enabledLayerCount = 0;
  
  vkres := vk.CreateDevice(physical_device, &device_create_info, nil, &device)
  if vkres != .SUCCESS {
    fmt.eprintln("ERROR: Failed to create logical device:", vkres);
    return .NotYetDetailed
  }

  return .Success
}

@(private="file")
_init_vma :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  vulkan_functions := vma.create_vulkan_functions();

  props: vk.PhysicalDeviceProperties
  vk.GetPhysicalDeviceProperties(physical_device, &props)
  // fmt.println("Api version:")
  // fmt.println("-- API_VERSION_1_0:", vk.API_VERSION_1_0)
  // fmt.println("-- API_VERSION_1_1:", vk.API_VERSION_1_1)
  // fmt.println("-- API_VERSION_1_2:", vk.API_VERSION_1_2)
  // fmt.println("-- API_VERSION_1_3:", vk.API_VERSION_1_3)
  // fmt.println(props)
  // TODO set vulkanApiVersion to the version supported by the device not 1_0 below

  vma_allocator_create_info := vma.AllocatorCreateInfo {
    vulkanApiVersion = vk.API_VERSION_1_0,
    instance = instance,
    physicalDevice = physical_device,
    device = device,
    // preferredLargeHeapBlockSize = 0,
    // pAllocationCallbacks = nil,
    // pDeviceMemoryCallbacks = nil,
    // pHeapSizeLimit = nil,
    pVulkanFunctions = &vulkan_functions,
    // pRecordSettings = nil,
  }

  vkres := vma.CreateAllocator(&vma_allocator_create_info, &vma_allocator)
  if vkres != .SUCCESS {
    fmt.eprintln("vma.CreateAllocator:", vkres)
    return .NotYetDetailed
  }

  return .Success
}

@(private="file")
_query_swap_chain_details :: proc(using ctx: ^VkSDLContext, dev: vk.PhysicalDevice) -> ProcResult {
  vkres := vk.GetPhysicalDeviceSurfaceCapabilitiesKHR(dev, surface, &swap_chain.support.capabilities)
  if vkres != .SUCCESS {
    fmt.eprintln("vk.GetPhysicalDeviceSurfaceCapabilitiesKHR:", vkres)
    return .NotYetDetailed
  }
  
  format_count: u32;
  vkres = vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_count, nil)
  if vkres != .SUCCESS {
    fmt.eprintln("vk.GetPhysicalDeviceSurfaceFormatsKHR:", vkres)
    return .NotYetDetailed
  }
  if format_count > 0 {
    swap_chain.support.formats = make([]vk.SurfaceFormatKHR, format_count)
    vkres = vk.GetPhysicalDeviceSurfaceFormatsKHR(dev, surface, &format_count, raw_data(swap_chain.support.formats))
    if vkres != .SUCCESS {
      fmt.eprintln("vk.GetPhysicalDeviceSurfaceFormatsKHR:", vkres)
      return .NotYetDetailed
    }
  }
  
  present_mode_count: u32
  vkres = vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_count, nil)
  if vkres != .SUCCESS {
    fmt.eprintln("vk.GetPhysicalDeviceSurfacePresentModesKHR:", vkres)
    return .NotYetDetailed
  }
  if present_mode_count > 0
  {
    swap_chain.support.present_modes = make([]vk.PresentModeKHR, present_mode_count);
    vkres = vk.GetPhysicalDeviceSurfacePresentModesKHR(dev, surface, &present_mode_count, raw_data(swap_chain.support.present_modes))
    if vkres != .SUCCESS {
      fmt.eprintln("vk.GetPhysicalDeviceSurfacePresentModesKHR:", vkres)
      return .NotYetDetailed
    }
  }

  return .Success
}

choose_surface_format :: proc(using ctx: ^VkSDLContext) -> vk.SurfaceFormatKHR {
  for v in swap_chain.support.formats
  {
    if v.format == .B8G8R8A8_SRGB && v.colorSpace == .SRGB_NONLINEAR do return v;
  }
  
  return swap_chain.support.formats[0];
}

choose_present_mode :: proc(using ctx: ^VkSDLContext) -> vk.PresentModeKHR {
  for v in swap_chain.support.present_modes
  {
    if v == .MAILBOX do return v;
  }
  
  for v in swap_chain.support.present_modes
  {
    // TODO -- this results in visual tearing but gives me fps clues
    if v == .IMMEDIATE do return v;
  }
  
  return .FIFO;
}

get_window_size :: proc(window: ^sdl2.Window) -> (width: i32, height: i32) {
  sdl2.GetWindowSize(window, &width, &height)
  return
}

choose_swap_extent :: proc(using ctx: ^VkSDLContext) -> vk.Extent2D {
  if (swap_chain.support.capabilities.currentExtent.width != max(u32)) {
    return swap_chain.support.capabilities.currentExtent;
  }

  width, height := get_window_size(window)
  
  extent := vk.Extent2D{u32(width), u32(height)};
  
  swap_chain.extent.width = clamp(extent.width, swap_chain.support.capabilities.minImageExtent.width,
    swap_chain.support.capabilities.maxImageExtent.width)
  swap_chain.extent.height = clamp(extent.height, swap_chain.support.capabilities.minImageExtent.height,
    swap_chain.support.capabilities.maxImageExtent.height)

  // fmt.println("Swap Extents:", extent, "from window:", width, height, "min:", swap_chain.support.capabilities.minImageExtent,
  //   "max:", swap_chain.support.capabilities.maxImageExtent)
  
  return extent;
}

create_swap_chain :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  using ctx.swap_chain.support;

  _query_swap_chain_details(ctx, physical_device) or_return
  // TODO -- some of this is not needed to be repeated when just resizing the window (recreating the swap chain)
  // -- Not urgent
  swap_chain.format       = choose_surface_format(ctx)
  swap_chain.present_mode = choose_present_mode(ctx)
  swap_chain.extent       = choose_swap_extent(ctx)
  swap_chain.image_count  = capabilities.minImageCount + 1;
  
  if capabilities.maxImageCount > 0 && swap_chain.image_count > capabilities.maxImageCount {
    swap_chain.image_count = capabilities.maxImageCount;
  }
  
  create_info: vk.SwapchainCreateInfoKHR;
  create_info.sType = .SWAPCHAIN_CREATE_INFO_KHR;
  create_info.surface = surface;
  create_info.minImageCount = swap_chain.image_count;
  create_info.imageFormat = swap_chain.format.format;
  create_info.imageColorSpace = swap_chain.format.colorSpace;
  create_info.imageExtent = swap_chain.extent;
  create_info.imageArrayLayers = 1;
  create_info.imageUsage = {.COLOR_ATTACHMENT};
  
  queue_family_indices := [len(QueueFamily)]u32{u32(queue_indices[.Graphics]), u32(queue_indices[.Present])}
  
  if queue_indices[.Graphics] != queue_indices[.Present] {
    create_info.imageSharingMode = .CONCURRENT;
    create_info.queueFamilyIndexCount = 2;
    create_info.pQueueFamilyIndices = &queue_family_indices[0];
  }
  else {
    create_info.imageSharingMode = .EXCLUSIVE;
    create_info.queueFamilyIndexCount = 0;
    create_info.pQueueFamilyIndices = nil;
  }
  
  create_info.preTransform = capabilities.currentTransform;
  create_info.compositeAlpha = {.OPAQUE};
  create_info.presentMode = swap_chain.present_mode;
  create_info.clipped = true;
  create_info.oldSwapchain = vk.SwapchainKHR{};
  
  // fmt.println("swapchain create info: extents:", create_info.imageExtent)
  if res := vk.CreateSwapchainKHR(device, &create_info, nil, &swap_chain.handle); res != .SUCCESS {
    fmt.eprintf("Error: failed to create swap chain!\n");
    return .NotYetDetailed
  }
  
  if res := vk.GetSwapchainImagesKHR(device, swap_chain.handle, &swap_chain.image_count, nil); res != .SUCCESS {
    fmt.eprintf("Error: failed to get swap chain images!\n");
    return .NotYetDetailed
  }
  swap_chain.images = make([]vk.Image, swap_chain.image_count);
  if res := vk.GetSwapchainImagesKHR(device, swap_chain.handle, &swap_chain.image_count, raw_data(swap_chain.images)); res != .SUCCESS {
    fmt.eprintf("Error: failed to get swap chain images!\n");
    return .NotYetDetailed
  }

  return .Success
}

create_swap_chain_image_views :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  using ctx.swap_chain;
  
  image_views = make([]vk.ImageView, len(images))
  
  for _, i in images
  {
    create_info: vk.ImageViewCreateInfo;
    create_info.sType = .IMAGE_VIEW_CREATE_INFO;
    create_info.image = images[i];
    create_info.viewType = .D2;
    create_info.format = format.format;
    create_info.components.r = .IDENTITY;
    create_info.components.g = .IDENTITY;
    create_info.components.b = .IDENTITY;
    create_info.components.a = .IDENTITY;
    create_info.subresourceRange.aspectMask = {.COLOR};
    create_info.subresourceRange.baseMipLevel = 0;
    create_info.subresourceRange.levelCount = 1;
    create_info.subresourceRange.baseArrayLayer = 0;
    create_info.subresourceRange.layerCount = 1;
    
    if res := vk.CreateImageView(device, &create_info, nil, &image_views[i]); res != .SUCCESS {
      fmt.eprintf("Error: failed to create image view!");
      return .NotYetDetailed
    }
  }

  return .Success
}

create_graphics_pipeline :: proc(ctx: ^VkSDLContext, pipeline_config: ^PipelineCreateConfig, vertex_binding_desc: ^vk.VertexInputBindingDescription,
  vertex_attributes: []vk.VertexInputAttributeDescription, descriptor_layout: [^]vk.DescriptorSetLayout,
  caller := #caller_location) -> (pipeline: Pipeline, prs: ProcResult) {

  // Create the Shaders
  vs_shader := create_shader_module(ctx, pipeline_config.vertex_shader_binary) or_return
  fs_shader := create_shader_module(ctx, pipeline_config.fragment_shader_binary) or_return
  defer {
    vk.DestroyShaderModule(ctx.device, vs_shader, nil);
    vk.DestroyShaderModule(ctx.device, fs_shader, nil);
  }
  
  vs_info: vk.PipelineShaderStageCreateInfo;
  vs_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO;
  vs_info.stage = {.VERTEX};
  vs_info.module = vs_shader;
  vs_info.pName = "main";
  
  fs_info: vk.PipelineShaderStageCreateInfo;
  fs_info.sType = .PIPELINE_SHADER_STAGE_CREATE_INFO;
  fs_info.stage = {.FRAGMENT};
  fs_info.module = fs_shader;
  fs_info.pName = "main";
  
  shader_stages := [?]vk.PipelineShaderStageCreateInfo{vs_info, fs_info};
  
  dynamic_states := [?]vk.DynamicState{.VIEWPORT, .SCISSOR};
  dynamic_state: vk.PipelineDynamicStateCreateInfo;
  dynamic_state.sType = .PIPELINE_DYNAMIC_STATE_CREATE_INFO;
  dynamic_state.dynamicStateCount = len(dynamic_states);
  dynamic_state.pDynamicStates = &dynamic_states[0];
  
  vertex_input: vk.PipelineVertexInputStateCreateInfo
  vertex_input.sType = .PIPELINE_VERTEX_INPUT_STATE_CREATE_INFO
  vertex_input.vertexBindingDescriptionCount = 1
  vertex_input.pVertexBindingDescriptions = vertex_binding_desc
  vertex_input.vertexAttributeDescriptionCount = auto_cast len(vertex_attributes)
  vertex_input.pVertexAttributeDescriptions = &vertex_attributes[0]
  
  input_assembly: vk.PipelineInputAssemblyStateCreateInfo
  input_assembly.sType = .PIPELINE_INPUT_ASSEMBLY_STATE_CREATE_INFO
  input_assembly.topology = .TRIANGLE_LIST
  input_assembly.primitiveRestartEnable = false
  
  viewport: vk.Viewport;
  viewport.x = 0.0;
  viewport.y = 0.0;
  viewport.width = cast(f32)ctx.swap_chain.extent.width;
  viewport.height = cast(f32)ctx.swap_chain.extent.height;
  viewport.minDepth = 0.0;
  viewport.maxDepth = 1.0;

  scissor: vk.Rect2D;
  scissor.offset = {0, 0};
  scissor.extent = ctx.swap_chain.extent;

  viewport_state: vk.PipelineViewportStateCreateInfo;
  viewport_state.sType = .PIPELINE_VIEWPORT_STATE_CREATE_INFO;
  viewport_state.viewportCount = 1;
  viewport_state.scissorCount = 1;

  rasterizer: vk.PipelineRasterizationStateCreateInfo;
  rasterizer.sType = .PIPELINE_RASTERIZATION_STATE_CREATE_INFO;
  rasterizer.depthClampEnable = false;
  rasterizer.rasterizerDiscardEnable = false;
  // rasterizer.polygonMode = .FILL;
  rasterizer.polygonMode = pipeline_config.fill_mode
  rasterizer.lineWidth = pipeline_config.line_width_extra + 1.0
  rasterizer.cullMode = pipeline_config.cull_mode
  rasterizer.frontFace = pipeline_config.front_face
  rasterizer.depthBiasEnable = false;
  rasterizer.depthBiasConstantFactor = 0.0;
  rasterizer.depthBiasClamp = 0.0;
  rasterizer.depthBiasSlopeFactor = 0.0;

  multisampling: vk.PipelineMultisampleStateCreateInfo;
  multisampling.sType = .PIPELINE_MULTISAMPLE_STATE_CREATE_INFO;
  multisampling.sampleShadingEnable = false;
  multisampling.rasterizationSamples = {._1};
  multisampling.minSampleShading = 1.0;
  multisampling.pSampleMask = nil;
  multisampling.alphaToCoverageEnable = false;
  multisampling.alphaToOneEnable = false;

  color_blend_attachment: vk.PipelineColorBlendAttachmentState;
  color_blend_attachment.colorWriteMask = {.R, .G, .B, .A};
  color_blend_attachment.blendEnable = true;
  color_blend_attachment.srcColorBlendFactor = .SRC_ALPHA;
  color_blend_attachment.dstColorBlendFactor = .ONE_MINUS_SRC_ALPHA;
  color_blend_attachment.colorBlendOp = .ADD;
  color_blend_attachment.srcAlphaBlendFactor = .ONE;
  color_blend_attachment.dstAlphaBlendFactor = .ZERO;
  color_blend_attachment.alphaBlendOp = .ADD;
  
  color_blending: vk.PipelineColorBlendStateCreateInfo;
  color_blending.sType = .PIPELINE_COLOR_BLEND_STATE_CREATE_INFO;
  color_blending.logicOpEnable = false;
  color_blending.logicOp = .COPY;
  color_blending.attachmentCount = 1;
  color_blending.pAttachments = &color_blend_attachment;
  color_blending.blendConstants[0] = 0.0;
  color_blending.blendConstants[1] = 0.0;
  color_blending.blendConstants[2] = 0.0;
  color_blending.blendConstants[3] = 0.0;
  
  // Create Pipeline Layout
  pipeline_layout_info: vk.PipelineLayoutCreateInfo;
  pipeline_layout_info.sType = .PIPELINE_LAYOUT_CREATE_INFO;
  pipeline_layout_info.setLayoutCount = 1;
  pipeline_layout_info.pSetLayouts = descriptor_layout
  pipeline_layout_info.pushConstantRangeCount = 0;
  pipeline_layout_info.pPushConstantRanges = nil;
  
  if res := vk.CreatePipelineLayout(ctx.device, &pipeline_layout_info, nil, &pipeline.layout); res != .SUCCESS
  {
    fmt.eprintf("Error: Failed to create pipeline layout!\n");
    fmt.eprintf("--Caller:", caller)
    prs = .NotYetDetailed
    return
  }

  depth_stencil_create_info := vk.PipelineDepthStencilStateCreateInfo {
    sType = .PIPELINE_DEPTH_STENCIL_STATE_CREATE_INFO,
    depthTestEnable = true,
    depthWriteEnable = true,
    depthCompareOp = .LESS,
    depthBoundsTestEnable = false,
    minDepthBounds = 0.0,
    maxDepthBounds = 1.0,
    stencilTestEnable = false,
  }

  // Create Pipeline
  pipeline_info := vk.GraphicsPipelineCreateInfo {
    sType = .GRAPHICS_PIPELINE_CREATE_INFO,
    stageCount = 2,
    pStages = &shader_stages[0],
    pVertexInputState = &vertex_input,
    pInputAssemblyState = &input_assembly,
    pViewportState = &viewport_state,
    pRasterizationState = &rasterizer,
    pMultisampleState = &multisampling,
    pColorBlendState = &color_blending,
    pDynamicState = &dynamic_state,
    layout = pipeline.layout,
    subpass = 0,
    basePipelineHandle = vk.Pipeline{},
    basePipelineIndex = -1,
  }

  p_render_pass: rawptr
  p_render_pass, prs = get_resource(&ctx.resource_manager, pipeline_config.render_pass)
  if prs != .Success {
    fmt.eprintf("--Caller:", caller)
    return
  }

  render_pass: ^RenderPass = auto_cast p_render_pass
  pipeline_info.renderPass = render_pass.render_pass
  if .HasDepthBuffer in render_pass.config {
    pipeline_info.pDepthStencilState = &depth_stencil_create_info
  }
  
  if res := vk.CreateGraphicsPipelines(ctx.device, 0, 1, &pipeline_info, nil, &pipeline.handle); res != .SUCCESS {
    fmt.eprintln("Error: Failed to create graphics pipeline! res=", res)
    fmt.eprintln("--Caller:", caller)
    prs = .NotYetDetailed
    return
  }

  return
}

create_shader_module :: proc(using ctx: ^VkSDLContext, code: []u8) -> (shader: vk.ShaderModule, prs: ProcResult) {
  create_info: vk.ShaderModuleCreateInfo;
  create_info.sType = .SHADER_MODULE_CREATE_INFO;
  create_info.codeSize = len(code);
  create_info.pCode = cast(^u32)raw_data(code);
  
  if res := vk.CreateShaderModule(device, &create_info, nil, &shader); res != .SUCCESS
  {
    fmt.eprintf("Error: Could not create shader module!\n")
    prs = .NotYetDetailed
    return
  }
  
  return
}

create_command_pool :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  pool_info: vk.CommandPoolCreateInfo
  pool_info.sType = .COMMAND_POOL_CREATE_INFO;
  pool_info.flags = {.RESET_COMMAND_BUFFER};
  pool_info.queueFamilyIndex = u32(queue_indices[.Graphics]);
  
  vkres := vk.CreateCommandPool(device, &pool_info, nil, &command_pool)
  if vkres != .SUCCESS {
    fmt.eprintf("Error: Failed to create command pool:", vkres);
    return .NotYetDetailed
  }

  return .Success
}

create_command_buffers :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  alloc_info := vk.CommandBufferAllocateInfo {
    sType = .COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool = command_pool,
    level = .PRIMARY,
    commandBufferCount = MAX_FRAMES_IN_FLIGHT,
  }
  
  swap_chain.command_buffers = make([]vk.CommandBuffer, MAX_FRAMES_IN_FLIGHT)
  if res := vk.AllocateCommandBuffers(device, &alloc_info, &swap_chain.command_buffers[0]); res != .SUCCESS {
    fmt.eprintf("Error: Failed to allocate command buffers!\n");
    return .NotYetDetailed
  }

  // Single-Time Command Buffer
  alloc_info = vk.CommandBufferAllocateInfo {
    sType = .COMMAND_BUFFER_ALLOCATE_INFO,
    commandPool = command_pool,
    level = .PRIMARY,
    commandBufferCount = 1,
  }

  vkres := vk.AllocateCommandBuffers(ctx.device, &alloc_info, &st_command_buffer)
  if vkres != .SUCCESS {
    fmt.eprintln("vk.AllocateCommandBuffer st_command_buffer failed:", vkres)
    return .NotYetDetailed
  }

  return .Success
}

record_command_buffer :: proc(using ctx: ^VkSDLContext, buffer: vk.CommandBuffer, image_index: u32) {
  fmt.eprintln("record_command_buffer Not using this no more")
  os.exit(1)
  // begin_info: vk.CommandBufferBeginInfo;
  // begin_info.sType = .COMMAND_BUFFER_BEGIN_INFO;
  // begin_info.flags = {};
  // begin_info.pInheritanceInfo = nil;
  
  // if res := vk.BeginCommandBuffer(buffer,  &begin_info); res != .SUCCESS
  // {
  //   fmt.eprintf("Error: Failed to begin recording command buffer!\n");
  //   os.exit(1);
  // }
  
  // render_pass_info: vk.RenderPassBeginInfo;
  // render_pass_info.sType = .RENDER_PASS_BEGIN_INFO;
  // render_pass_info.renderPass = present_render_pass;
  // render_pass_info.framebuffer = swap_chain.present_framebuffers[image_index];
  // render_pass_info.renderArea.offset = {0, 0};
  // render_pass_info.renderArea.extent = swap_chain.extent;
  
  // clear_color: vk.ClearValue;
  // clear_color.color.float32 = [4]f32{0.0, 0.0, 0.0, 1.0};
  // render_pass_info.clearValueCount = 1;
  // render_pass_info.pClearValues = &clear_color;
  
  // vk.CmdBeginRenderPass(buffer, &render_pass_info, .INLINE);
  
  // vk.CmdBindPipeline(buffer, .GRAPHICS, pipeline.handle);
  
  // vertex_buffers := [?]vk.Buffer{vertex_buffer.buffer};
  // offsets := [?]vk.DeviceSize{0};
  // vk.CmdBindVertexBuffers(buffer, 0, 1, &vertex_buffers[0], &offsets[0]);
  // vk.CmdBindIndexBuffer(buffer, index_buffer.buffer, 0, .UINT16);
  
  // viewport: vk.Viewport;
  // viewport.x = 0.0;
  // viewport.y = 0.0;
  // viewport.width = f32(swap_chain.extent.width);
  // viewport.height = f32(swap_chain.extent.height);
  // viewport.minDepth = 0.0;
  // viewport.maxDepth = 1.0;
  // vk.CmdSetViewport(buffer, 0, 1, &viewport);
  
  // scissor: vk.Rect2D;
  // scissor.offset = {0, 0};
  // scissor.extent = swap_chain.extent;
  // vk.CmdSetScissor(buffer, 0, 1, &scissor);
  
  // vk.CmdDrawIndexed(buffer, cast(u32)index_buffer.length, 1, 0, 0, 0);
  
  // vk.CmdEndRenderPass(buffer);
  
  // if res := vk.EndCommandBuffer(buffer); res != .SUCCESS
  // {
  //   fmt.eprintf("Error: Failed to record command buffer!\n");
  //   os.exit(1);
  // }
}

create_sync_objects :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  semaphore_info: vk.SemaphoreCreateInfo;
  semaphore_info.sType = .SEMAPHORE_CREATE_INFO;
  
  fence_info: vk.FenceCreateInfo;
  fence_info.sType = .FENCE_CREATE_INFO;
  fence_info.flags = {.SIGNALED}
  
  for i in 0..<MAX_FRAMES_IN_FLIGHT
  {
    res := vk.CreateSemaphore(device, &semaphore_info, nil, &_render_contexts[i].image_available);
    if res != .SUCCESS
    {
      fmt.eprintf("Error: Failed to create \"image_available\" semaphore\n");
      return .NotYetDetailed
    }
    res = vk.CreateSemaphore(device, &semaphore_info, nil, &_render_contexts[i].render_finished);
    if res != .SUCCESS
    {
      fmt.eprintf("Error: Failed to create \"render_finished\" semaphore\n");
      return .NotYetDetailed
    }
    res = vk.CreateFence(device, &fence_info, nil, &_render_contexts[i].in_flight);
    if res != .SUCCESS
    {
      fmt.eprintf("Error: Failed to create \"in_flight\" fence\n");
      return .NotYetDetailed
    }
  }

  return .Success
}

@(private) _handle_resized_presentation :: proc(using ctx: ^VkSDLContext) -> ProcResult {

  width, height := get_window_size(window)
  if width == auto_cast swap_chain.extent.width && height == auto_cast swap_chain.extent.height {
    // fmt.println("same dimensions") TODO???
    // return .Success
  }

  // vk.DeviceWaitIdle(device)
  cleanup_swap_chain(ctx)

  create_swap_chain(ctx) or_return
  create_swap_chain_image_views(ctx) or_return
    
  sync.lock(&ctx.resource_manager._mutex)
  defer sync.unlock(&ctx.resource_manager._mutex)

  iter: int
  for rprh in iterate_resources(&iter, &ctx.resource_manager, .RenderPass) {
    // fmt.println("rprh:", rprh)
    render_pass: ^RenderPass = auto_cast get_resource(&ctx.resource_manager, rprh) or_return
    // fmt.println("render_pass:", render_pass)

    // Delete Current
    if render_pass.framebuffers != nil {
      for i in 0..<len(render_pass.framebuffers) {
        vk.DestroyFramebuffer(ctx.device, render_pass.framebuffers[i], nil)
      }
      if delete_slice(render_pass.framebuffers) != .None {
        fmt.eprintln("Error: Failed to delete render_pass.framebuffers")
        return .NotYetDetailed
      }
    }

    if render_pass.depth_buffer_rh != 0 {
      db: ^DepthBuffer = auto_cast get_resource(&ctx.resource_manager, render_pass.depth_buffer_rh) or_return
      _dispose_depth_buffer_resources(ctx, db) or_return
      _build_depth_buffer(ctx, db) or_return
    }

    // Recreate
    _create_framebuffers(ctx, render_pass) or_return
  }

  return .Success
}

cleanup_swap_chain :: proc(using ctx: ^VkSDLContext) {
  for view in swap_chain.image_views
  {
    vk.DestroyImageView(device, view, nil);
  }
  vk.DestroySwapchainKHR(device, swap_chain.handle, nil);
}

// TODO -- not used?
copy_buffer :: proc(using ctx: ^VkSDLContext, src, dst: Buffer, size: vk.DeviceSize) {
  alloc_info := vk.CommandBufferAllocateInfo{
    sType = .COMMAND_BUFFER_ALLOCATE_INFO,
    level = .PRIMARY,
    commandPool = command_pool,
    commandBufferCount = 1,
  };
  
  cmd_buffer: vk.CommandBuffer;
  vk.AllocateCommandBuffers(device, &alloc_info, &cmd_buffer);
  
  begin_info := vk.CommandBufferBeginInfo{
    sType = .COMMAND_BUFFER_BEGIN_INFO,
    flags = {.ONE_TIME_SUBMIT},
  }
  
  vk.BeginCommandBuffer(cmd_buffer, &begin_info);
  
  copy_region := vk.BufferCopy{
    srcOffset = 0,
    dstOffset = 0,
    size = size,
  }
  vk.CmdCopyBuffer(cmd_buffer, src.buffer, dst.buffer, 1, &copy_region);
  vk.EndCommandBuffer(cmd_buffer);
  
  submit_info := vk.SubmitInfo{
    sType = .SUBMIT_INFO,
    commandBufferCount = 1,
    pCommandBuffers = &cmd_buffer,
  };
  
  vk.QueueSubmit(queues[.Graphics], 1, &submit_info, {});
  vk.QueueWaitIdle(queues[.Graphics]);
  vk.FreeCommandBuffers(device, command_pool, 1, &cmd_buffer);
}

// TODO -- not used?
find_memory_type :: proc(using ctx: ^VkSDLContext, type_filter: u32, properties: vk.MemoryPropertyFlags) -> u32 {
  mem_properties: vk.PhysicalDeviceMemoryProperties;
  vk.GetPhysicalDeviceMemoryProperties(physical_device, &mem_properties);
  for i in 0..<mem_properties.memoryTypeCount
  {
    if (type_filter & (1 << i) != 0) && (mem_properties.memoryTypes[i].propertyFlags & properties) == properties
    {
      return i;
    }
  }
  
  fmt.eprintf("Error: Failed to find suitable memory type!\n");
  os.exit(1);
}

// Depends on init_uniform_buffer() and init_descriptor_and_pipeline_layouts() TODO ?
_init_descriptor_pool :: proc(using ctx: ^VkSDLContext) -> ProcResult {
  DESCRIPTOR_POOL_COUNT :: 2

  type_count := [DESCRIPTOR_POOL_COUNT]vk.DescriptorPoolSize {
    vk.DescriptorPoolSize {
      type = .UNIFORM_BUFFER,
      descriptorCount = 4096,
    },
    vk.DescriptorPoolSize {
      type = .COMBINED_IMAGE_SAMPLER,
      descriptorCount = 2048,
    },
  }

  descriptor_pool_create_info := vk.DescriptorPoolCreateInfo {
    sType = .DESCRIPTOR_POOL_CREATE_INFO,
    maxSets = MAX_DESCRIPTOR_SETS,
    poolSizeCount = DESCRIPTOR_POOL_COUNT,
    pPoolSizes = &type_count[0],
  }

  for i in 0..<MAX_FRAMES_IN_FLIGHT {
    vkres := vk.CreateDescriptorPool(ctx.device, &descriptor_pool_create_info, nil, & _render_contexts[i].descriptor_pool)
    if vkres != .SUCCESS {
      fmt.eprintln("vkCreateDescriptorPool:", vkres)
      return .NotYetDetailed
    }
  }

  return .Success
}

create_render_pass :: proc(using ctx: ^VkSDLContext, config: RenderPassConfigFlags, clear_color: Color = {0, 0.01, 0, 1}) ->
    (rh: RenderPassResourceHandle, prs: ProcResult) {
  rh = auto_cast _create_resource(&ctx.resource_manager, .RenderPass) or_return
  rp: ^RenderPass = auto_cast get_resource(&ctx.resource_manager, auto_cast rh) or_return
  rp.config = config
  rp.clear_color = clear_color

  has_depth_buffer := .HasDepthBuffer in config
  depth_buffer_format: vk.Format = .UNDEFINED
  if has_depth_buffer {
    rp.depth_buffer_rh = create_depth_buffer(ctx) or_return

    // Obtain & Set the Created Format
    db: ^DepthBuffer = auto_cast get_resource(&ctx.resource_manager, rp.depth_buffer_rh) or_return
    depth_buffer_format = db.format
  }

  // Attachments
  attachments := [2]vk.AttachmentDescription {
    vk.AttachmentDescription {
      format = swap_chain.format.format,
      samples = {._1},
      loadOp = (.HasPreviousColorPass in config) ? .LOAD : .CLEAR,
      storeOp = .STORE,
      stencilLoadOp = .DONT_CARE,
      stencilStoreOp = .DONT_CARE,
      initialLayout = (.HasPreviousColorPass in config) ? .COLOR_ATTACHMENT_OPTIMAL : .UNDEFINED,
      finalLayout = (.IsPresent in config) ? .PRESENT_SRC_KHR : .COLOR_ATTACHMENT_OPTIMAL,
    },
    vk.AttachmentDescription {
      format = depth_buffer_format,
      samples = {._1},
      loadOp = .CLEAR,
      storeOp = .DONT_CARE,
      stencilLoadOp = .DONT_CARE,
      stencilStoreOp = .DONT_CARE,
      initialLayout = .UNDEFINED,
      finalLayout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL,
    },
  }
    
  color_attachment_ref: vk.AttachmentReference
  color_attachment_ref.attachment = 0
  color_attachment_ref.layout = .COLOR_ATTACHMENT_OPTIMAL

  depth_attachment_ref: vk.AttachmentReference
  depth_attachment_ref.attachment = 1
  depth_attachment_ref.layout = .DEPTH_STENCIL_ATTACHMENT_OPTIMAL
  
  // Subpass
  subpass := vk.SubpassDescription {
    pipelineBindPoint = .GRAPHICS,
    colorAttachmentCount = 1,
    pColorAttachments = &color_attachment_ref,
    pDepthStencilAttachment = has_depth_buffer ? &depth_attachment_ref : nil,
  }

  dependencies := [2]vk.SubpassDependency {
    vk.SubpassDependency {
      srcSubpass = vk.SUBPASS_EXTERNAL,
      dstSubpass = 0,
      srcStageMask = {.COLOR_ATTACHMENT_OUTPUT},
      srcAccessMask = {},
      dstStageMask = {.COLOR_ATTACHMENT_OUTPUT},
      dstAccessMask = {.COLOR_ATTACHMENT_WRITE},
    },
    vk.SubpassDependency {
      srcSubpass = vk.SUBPASS_EXTERNAL,
      dstSubpass = 0,
      srcStageMask = {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
      srcAccessMask = {},
      dstStageMask = {.EARLY_FRAGMENT_TESTS, .LATE_FRAGMENT_TESTS},
      dstAccessMask = {.DEPTH_STENCIL_ATTACHMENT_WRITE},
    },
    // TODO srcSubpass = 0, dstSubpass = vk.SUBPASS_EXTERNAL, ???
  }
  
  // Create Render Pass
  render_pass_info: vk.RenderPassCreateInfo;
  render_pass_info.sType = .RENDER_PASS_CREATE_INFO;
  render_pass_info.attachmentCount = has_depth_buffer ? 2 : 1
  render_pass_info.pAttachments = &attachments[0];
  render_pass_info.subpassCount = 1;
  render_pass_info.pSubpasses = &subpass;
  render_pass_info.dependencyCount = has_depth_buffer ? 2 : 1
  render_pass_info.pDependencies = &dependencies[0];
  
  if res := vk.CreateRenderPass(ctx.device, &render_pass_info, nil, &rp.render_pass); res != .SUCCESS {
    fmt.eprintf("Error: Failed to create render pass!\n");
    prs = .NotYetDetailed
    return
  }

  res := _create_framebuffers(ctx, rp)
  if res != .Success {
    destroy_render_pass(ctx, rh)
    prs = .NotYetDetailed
    return
  }
  
  return
}

_create_framebuffers :: proc(using ctx: ^VkSDLContext, rp: ^RenderPass) -> ProcResult {
  db: ^DepthBuffer
  if rp.depth_buffer_rh != 0 {
    db = auto_cast get_resource(&ctx.resource_manager, rp.depth_buffer_rh) or_return
  }

  rp.framebuffers = make([]vk.Framebuffer, len(swap_chain.image_views))
  for v, i in swap_chain.image_views {
    attachments := [?]vk.ImageView{v, (db == nil) ? 0 : db.view}

    framebuffer_create_info := vk.FramebufferCreateInfo {
      sType = .FRAMEBUFFER_CREATE_INFO,
      renderPass = rp.render_pass,
      attachmentCount = (db == nil) ? 1 : 2,
      pAttachments = &attachments[0],
      width = swap_chain.extent.width,
      height = swap_chain.extent.height,
      layers = 1,
    }
    
    if res := vk.CreateFramebuffer(device, &framebuffer_create_info, nil, &rp.framebuffers[i]); res != .SUCCESS {
      fmt.eprintln("Error: Failed to create framebuffer:", res)
      return .NotYetDetailed
    }
  }

  return .Success
}

// VkImageTiling image_tiling, VkFormatFeatureFlagBits features, VkFormat *result)
_find_supported_format :: proc(ctx: ^VkSDLContext, preferred_formats: []vk.Format, image_tiling: vk.ImageTiling,
  features: vk.FormatFeatureFlags) -> vk.Format {
  
  props: vk.FormatProperties
  for i in 0..<len(preferred_formats) {
    vk.GetPhysicalDeviceFormatProperties(ctx.physical_device, preferred_formats[i], &props)

    // TODO check <= means in and not less-than-or-equal-to IN THIS CASE
    // fmt.println("CHECK props.linearTilingFeatures:", props.linearTilingFeatures, "props.optimalTilingFeatures:",
    //   props.optimalTilingFeatures, "features:", features)
    if image_tiling == .LINEAR && features <= props.linearTilingFeatures {
      return preferred_formats[i]
    } else if image_tiling == .OPTIMAL && features <= props.optimalTilingFeatures {
      // fmt.println("using preferred depth format:", preferred_formats[i])
      return preferred_formats[i]
    }
  }

  return .UNDEFINED
}