package client

import la "core:math/linalg"
import vi "violin"

vec2 :: la.Vector2f32
vec2i :: [2]i32
vec3 :: la.Vector3f32
vec4 :: la.Vector4f32
mat4 :: la.Matrix4f32

ProcResult :: vi.ProcResult

ResourceHandle :: vi.ResourceHandle
BufferResourceHandle :: vi.BufferResourceHandle
DepthBufferResourceHandle :: vi.DepthBufferResourceHandle
TextureResourceHandle :: vi.TextureResourceHandle
VertexBufferResourceHandle :: vi.VertexBufferResourceHandle
IndexBufferResourceHandle :: vi.IndexBufferResourceHandle
RenderPassResourceHandle :: vi.RenderPassResourceHandle
RenderProgramResourceHandle :: vi.RenderProgramResourceHandle
StampRenderResourceHandle :: vi.StampRenderResourceHandle
FontResourceHandle :: vi.FontResourceHandle


PropAppData :: struct {
  vctx: ^vi.VkSDLContext,
  ft: vi.FrameTime,

  stamprr: vi.StampRenderResourceHandle,
  default_font: vi.FontResourceHandle,
  small_font: vi.FontResourceHandle,

  game_camera: GameCamera,
  player_input: PlayerInput,
  world: WorldData,
}