package violin

ProcResult :: enum {
  Success = 0,

  NotYetDetailed,
  NotYetImplemented,
 
  // VKSDL Error Codes
  VulkanLayerNotAvailable,
  NoQueueAvailableOnDevice,
  AllocationFailed,
  InvalidResourceHandle,
  ResourceNotFound,
  InvalidState,
  VkSurfaceNotCompatibleWithSwapChain,
  FailedToObtainImageExtents,
  ResourceKindMismatch,
  FileReadError,
  VMAError,

  // Game Error Codes
  AssetLoadError,
  AssetProcessingError,
}
