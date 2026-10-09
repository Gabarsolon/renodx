/*
 * Copyright (C) 2026 Gabarsolon
 * SPDX-License-Identifier: MIT
 */

// HDR10 output, HDR outside exclusive fullscreen, and a monitor brightness slider for the dx11_non-rt build of
// Resident Evil 2 Remake.
//
// The game switches HDR on through the vendor APIs only (NvAPI_Disp_HdrColorControl in HDR10 pass-through mode /
// agsSetDisplayMode) and never tells DXGI: its swap chain stays an 8-bit blt-model R8G8B8A8_UNORM one tagged sRGB.
// With Windows HDR on, the compositor then treats the game's PQ-encoded pixels as SDR, which is the grey,
// washed-out picture. This upgrades the swap chain to R10G10B10A2_UNORM with a flip model and sets its colour space.
//
// The engine also only honours an HDR request while IDXGISwapChain::GetFullscreenState reports exclusive
// fullscreen, and re-enters exclusive fullscreen after every HDR switch. Two jumps in the DX11 render device's
// per-frame update are changed in memory, after a byte-for-byte check against the exe of 2023-04-20, so HDR runs
// in borderless and windowed modes. The engine still drops HDR on every window-mode change, so the request is
// repeated ten times a second.
//
// A flip-model swap chain refuses to present between losing exclusive fullscreen (alt-tab) and the next
// ResizeBuffers, where the game's own blt-model one only reports that it is occluded. The engine exits on any
// failed Present, so its Present call in that same routine is routed through PresentForEngine below.

#ifndef SRC_RE2R_NONRT_HDR10_OUTPUT_HPP_
#define SRC_RE2R_NONRT_HDR10_OUTPUT_HPP_

#include <Windows.h>

#include <dxgi1_6.h>
#include <lowlevelmonitorconfigurationapi.h>
#include <physicalmonitorenumerationapi.h>

#include <atomic>
#include <cstdarg>
#include <cstdint>
#include <cstdio>
#include <cstring>

#include <deps/imgui/imgui.h>
#include <include/reshade.hpp>

#pragma comment(lib, "dxva2.lib")

namespace hdr10output {

// Bound to the settings in addon.cpp.
static float setting_enabled = 1.f;
static float setting_mode = 1.f;  // 0 follow the game, 1 always HDR10, 2 always SDR
static float setting_windowed_hdr = 1.f;

struct CodePatch {
  uintptr_t rva;
  size_t size;
  uint8_t original[16];
  uint8_t patched[16];
};

// RenderDeviceDX11's per-frame update (0x1424b6a40). A spot is only touched when all of its bytes match.
static const CodePatch HDR_PATCHES[] = {
    // After IDXGISwapChain::GetFullscreenState:  test eax, eax / je <not fullscreen>. That branch switches HDR off
    // and drops the pending request; the jump becomes a NOP so the request is applied in any window mode.
    {0x24b6f65, 12,
     {0x85, 0xC0, 0x0F, 0x84, 0x11, 0x01, 0x00, 0x00, 0x80, 0x7D, 0x98, 0x00},
     {0x85, 0xC0, 0x66, 0x0F, 0x1F, 0x44, 0x00, 0x00, 0x80, 0x7D, 0x98, 0x00}},
    // The HDR switch leaves fullscreen, flips HDR through the vendor API, resizes, and sets a flag (device+0x1a2) so
    // that the next frame jumps to SetFullscreenState(TRUE). Outside fullscreen mode that forces the window into
    // exclusive fullscreen, so the jump is retargeted past the call (0x1424b6f44 -> 0x1424b6f59).
    {0x24b6efc, 16,
     {0x80, 0x3E, 0x00, 0x74, 0x0B, 0x83, 0x7D, 0x9B, 0x00, 0x75, 0x05, 0xC6, 0x06, 0x00, 0xEB, 0x38},
     {0x80, 0x3E, 0x00, 0x74, 0x0B, 0x83, 0x7D, 0x9B, 0x00, 0x75, 0x05, 0xC6, 0x06, 0x00, 0xEB, 0x4D}},
    // Not patched, on purpose: the block at 0x1424b6e57 that switches HDR off before a window-mode change. Skipping
    // it made the game die inside the mode change, right at SetFullscreenState(FALSE).
};

// via.render.Renderer.set_HDRMode as the game's scripts call it: (context, bool).
static const uintptr_t SET_HDR_MODE_RVA = 0x2c77c0;
static const uint8_t SET_HDR_MODE_ORIGINAL[13] = {0x48, 0x8B, 0x0D, 0x61, 0xEF, 0xDD, 0x06, 0x84, 0xD2, 0x0F, 0x95, 0xC2, 0xE9};
// How often the engine is asked to turn HDR back on. The call does nothing while HDR is already on.
static const ULONGLONG HDR_REQUEST_INTERVAL_MS = 100;
static const BYTE VCP_BRIGHTNESS = 0x10;

// The engine's Present call (0x1424b6adc):  mov rax, [r14] / xor r8d, r8d / mov rcx, r14 / call [rax+0x40].
// It becomes  mov rax, <thunk> / call rax,  and the thunk loads the same arguments before jumping to PresentForEngine.
static const uintptr_t PRESENT_CALL_RVA = 0x24b6adc;
static const uint8_t PRESENT_CALL_ORIGINAL[12] = {0x49, 0x8B, 0x06, 0x45, 0x33, 0xC0, 0x49, 0x8B, 0xCE, 0xFF, 0x50, 0x40};
// How long Present may keep failing with the game window in front before the error is handed to the game after all.
static const ULONGLONG PRESENT_STUCK_LIMIT_MS = 5000;

// 0 = checks in place, 1 = checks removed, 2 = this exe is not the build the patches were made for
static int gate_state = 0;
static bool setter_usable = false;
static ULONGLONG last_request_tick = 0;

static uint8_t* present_thunk = nullptr;
// Set from the first refused Present until one goes through again.
static bool present_lost = false;
static unsigned present_masked = 0;
static ULONGLONG present_stuck_since = 0;

static reshade::api::swapchain* current_swapchain = nullptr;
static reshade::api::effect_runtime* current_runtime = nullptr;
// Whether the engine's HDR mode is active, read off the back buffer format the game itself asks for.
static bool game_hdr = false;
static std::atomic_bool reapply = false;
static std::atomic_int view_logs = 0;

// -1 = nothing applied yet, 0 = sRGB, 1 = HDR10
static int applied_state = -1;
static bool status_10bit = false;
static bool status_flip = false;
static bool status_set_ok = false;

// Monitor brightness over DDC/CI. Every command blocks for tens of milliseconds, so they run on a worker thread
// that only ever sends the newest value the slider asked for.
static HANDLE ddc_thread = nullptr;
static HANDLE ddc_wake = nullptr;
static HANDLE ddc_done = nullptr;
static HWND ddc_window = nullptr;
static std::atomic_bool ddc_stop = false;
static std::atomic_int ddc_pending = -1;
// 0 = still asking the monitor, 1 = ready, 2 = the monitor did not answer
static std::atomic_int ddc_state = 0;
static std::atomic_int ddc_brightness = 0;
static std::atomic_int ddc_maximum = 100;
static std::atomic_bool ddc_write_failed = false;

static void Log(reshade::log::level level, const char* format, ...) {
  char buffer[512];
  va_list args;
  va_start(args, format);
  vsnprintf(buffer, sizeof(buffer), format, args);
  va_end(args);
  reshade::log::message(level, buffer);
}

static bool IsEnabled() { return setting_enabled != 0.f; }

static uint8_t* GameCode(uintptr_t rva, size_t size) {
  auto* const base = reinterpret_cast<uint8_t*>(GetModuleHandleW(nullptr));
  const auto* const dos = reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
  const auto* const nt = reinterpret_cast<const IMAGE_NT_HEADERS*>(base + dos->e_lfanew);
  return rva + size <= nt->OptionalHeader.SizeOfImage ? base + rva : nullptr;
}

static bool WriteCode(uint8_t* code, const uint8_t* bytes, size_t size) {
  DWORD protection = 0;
  if (VirtualProtect(code, size, PAGE_EXECUTE_READWRITE, &protection) == FALSE) return false;
  memcpy(code, bytes, size);
  VirtualProtect(code, size, protection, &protection);
  FlushInstructionCache(GetCurrentProcess(), code, size);
  return true;
}

static void SetHdrGate(bool open) {
  // Nothing is written unless every spot holds either its original or its patched bytes.
  for (const CodePatch& patch : HDR_PATCHES) {
    const uint8_t* const code = GameCode(patch.rva, patch.size);
    if (code == nullptr || (memcmp(code, patch.original, patch.size) != 0 && memcmp(code, patch.patched, patch.size) != 0)) {
      gate_state = 2;
      return;
    }
  }
  for (const CodePatch& patch : HDR_PATCHES) {
    uint8_t* const code = GameCode(patch.rva, patch.size);
    const uint8_t* const wanted = open ? patch.patched : patch.original;
    if (memcmp(code, wanted, patch.size) == 0) continue;
    if (!WriteCode(code, wanted, patch.size)) return;
  }
  gate_state = open ? 1 : 0;
}

// What the engine gets back from Present. Its routine handles DXGI_STATUS_OCCLUDED by noting that fullscreen is gone;
// on a plain success after that it sizes the window, resizes the buffers and goes back to fullscreen once the window
// is active again. The first refusal is therefore reported as occluded and the following ones as success, until the
// engine's ResizeBuffers makes Present work again.
static HRESULT PresentForEngine(IDXGISwapChain* swapchain, UINT sync_interval, UINT flags) {
  const HRESULT result = swapchain->Present(sync_interval, flags);
  if (result != DXGI_ERROR_INVALID_CALL) {
    if (present_lost) {
      present_lost = false;
      Log(reshade::log::level::info, "HDR10 output: Present works again after %u refused frames", present_masked);
    }
    if (FAILED(result)) Log(reshade::log::level::error, "HDR10 output: Present failed with 0x%08lx", static_cast<unsigned long>(result));
    return result;
  }

  if (!present_lost) {
    present_lost = true;
    present_masked = 0;
    present_stuck_since = 0;
    Log(reshade::log::level::warning, "HDR10 output: Present refused (DXGI_ERROR_INVALID_CALL) after a fullscreen change; reported to the game as occluded");
    return DXGI_STATUS_OCCLUDED;
  }
  ++present_masked;

  DXGI_SWAP_CHAIN_DESC desc = {};
  const bool in_front = SUCCEEDED(swapchain->GetDesc(&desc)) && desc.OutputWindow == GetForegroundWindow() && IsIconic(desc.OutputWindow) == FALSE;
  if (!in_front) {
    present_stuck_since = 0;
    return S_OK;
  }
  const ULONGLONG now = GetTickCount64();
  if (present_stuck_since == 0) present_stuck_since = now;
  if (now - present_stuck_since < PRESENT_STUCK_LIMIT_MS) return S_OK;

  Log(reshade::log::level::error, "HDR10 output: Present still refused after %u frames with the game in front; passing the error on", present_masked);
  return result;
}

static void SetPresentGuard(bool install) {
  uint8_t* const code = GameCode(PRESENT_CALL_RVA, sizeof(PRESENT_CALL_ORIGINAL));
  if (code == nullptr) return;

  if (!install) {
    if (present_thunk == nullptr) return;
    if (!WriteCode(code, PRESENT_CALL_ORIGINAL, sizeof(PRESENT_CALL_ORIGINAL))) return;
    VirtualFree(present_thunk, 0, MEM_RELEASE);
    present_thunk = nullptr;
    return;
  }

  if (present_thunk != nullptr || memcmp(code, PRESENT_CALL_ORIGINAL, sizeof(PRESENT_CALL_ORIGINAL)) != 0) return;

  // mov rcx, r14 / xor r8d, r8d / mov rax, PresentForEngine / jmp rax. The sync interval is already in edx.
  uint8_t thunk[18] = {0x4C, 0x89, 0xF1, 0x45, 0x31, 0xC0, 0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xE0};
  const auto target = reinterpret_cast<uintptr_t>(&PresentForEngine);
  memcpy(thunk + 8, &target, sizeof(target));

  auto* const memory = static_cast<uint8_t*>(VirtualAlloc(nullptr, sizeof(thunk), MEM_COMMIT | MEM_RESERVE, PAGE_READWRITE));
  if (memory == nullptr) return;
  memcpy(memory, thunk, sizeof(thunk));
  DWORD protection = 0;
  VirtualProtect(memory, sizeof(thunk), PAGE_EXECUTE_READ, &protection);
  FlushInstructionCache(GetCurrentProcess(), memory, sizeof(thunk));

  // mov rax, thunk / call rax
  uint8_t call[12] = {0x48, 0xB8, 0, 0, 0, 0, 0, 0, 0, 0, 0xFF, 0xD0};
  const auto thunk_address = reinterpret_cast<uintptr_t>(memory);
  memcpy(call + 2, &thunk_address, sizeof(thunk_address));
  if (!WriteCode(code, call, sizeof(call))) {
    VirtualFree(memory, 0, MEM_RELEASE);
    return;
  }
  present_thunk = memory;
}

// Checked once at load: other mods may put a hook over the first bytes later, which is fine to call through.
static void CheckHdrSetter() {
  const uint8_t* const setter = GameCode(SET_HDR_MODE_RVA, sizeof(SET_HDR_MODE_ORIGINAL));
  setter_usable = setter != nullptr && memcmp(setter, SET_HDR_MODE_ORIGINAL, sizeof(SET_HDR_MODE_ORIGINAL)) == 0;
}

static void RequestEngineHdr() {
  if (!setter_usable) return;
  const auto setter = reinterpret_cast<void (*)(void*, bool)>(GameCode(SET_HDR_MODE_RVA, sizeof(SET_HDR_MODE_ORIGINAL)));
  setter(nullptr, true);
}

static bool WindowedHdrActive() {
  return IsEnabled() && setting_windowed_hdr != 0.f && setting_mode != 2.f && gate_state == 1;
}

static bool WantHdr() {
  if (!IsEnabled() || setting_mode == 2.f) return false;
  if (setting_mode == 1.f) return true;
  return game_hdr;
}

static bool Is8BitRgba(reshade::api::format value) {
  const auto typeless = reshade::api::format_to_typeless(value);
  return typeless == reshade::api::format::r8g8b8a8_typeless || typeless == reshade::api::format::b8g8r8a8_typeless;
}

static bool Is10BitRgba(reshade::api::format value) {
  return reshade::api::format_to_typeless(value) == reshade::api::format::r10g10b10a2_typeless;
}

static DWORD WINAPI DdcWorker(LPVOID /*unused*/) {
  PHYSICAL_MONITOR monitor = {};
  bool opened = false;
  const HMONITOR display = MonitorFromWindow(ddc_window, MONITOR_DEFAULTTONEAREST);
  DWORD count = 0;
  if (display != nullptr && GetNumberOfPhysicalMonitorsFromHMONITOR(display, &count) != FALSE && count > 0) {
    PHYSICAL_MONITOR monitors[8] = {};
    if (count > 8) count = 8;
    if (GetPhysicalMonitorsFromHMONITOR(display, count, monitors) != FALSE) {
      // More than one physical monitor only shows up for mirrored displays; the first one is used.
      monitor = monitors[0];
      opened = true;
      if (count > 1) DestroyPhysicalMonitors(count - 1, monitors + 1);
    }
  }

  DWORD current = 0;
  DWORD maximum = 0;
  if (opened && GetVCPFeatureAndVCPFeatureReply(monitor.hPhysicalMonitor, VCP_BRIGHTNESS, nullptr, &current, &maximum) != FALSE && maximum > 0) {
    ddc_brightness = static_cast<int>(current);
    ddc_maximum = static_cast<int>(maximum);
    ddc_state = 1;
    Log(reshade::log::level::info, "DDC/CI: monitor reports brightness %lu of %lu.", current, maximum);
  } else {
    ddc_state = 2;
    Log(reshade::log::level::warning, "DDC/CI: the monitor did not answer the brightness query (error %lu).", GetLastError());
  }

  int failures_logged = 0;
  while (ddc_state == 1) {
    WaitForSingleObject(ddc_wake, INFINITE);
    if (ddc_stop) break;
    const int value = ddc_pending.exchange(-1);
    if (value < 0) continue;
    const bool ok = SetVCPFeature(monitor.hPhysicalMonitor, VCP_BRIGHTNESS, static_cast<DWORD>(value)) != FALSE;
    ddc_write_failed = !ok;
    if (!ok && failures_logged++ < 3) {
      Log(reshade::log::level::warning, "DDC/CI: setting brightness %d failed (error %lu).", value, GetLastError());
    }
    // DDC/CI wants a pause between commands.
    Sleep(50);
  }

  if (opened) DestroyPhysicalMonitors(1, &monitor);
  SetEvent(ddc_done);
  return 0;
}

static void StartDdcWorker(HWND window) {
  if (ddc_thread != nullptr || window == nullptr) return;
  ddc_window = window;
  ddc_stop = false;
  ddc_pending = -1;
  ddc_state = 0;
  ddc_write_failed = false;
  ddc_wake = CreateEventW(nullptr, FALSE, FALSE, nullptr);
  ddc_done = CreateEventW(nullptr, TRUE, FALSE, nullptr);
  ddc_thread = CreateThread(nullptr, 0, DdcWorker, nullptr, 0, nullptr);
}

// Inside DllMain the loader lock keeps a thread from finishing its exit, so waiting on the thread handle there would
// only time out; the worker's "done" event says it has left this module's code, which is all an unload needs.
static void StopDdcWorker(bool in_dll_main) {
  if (ddc_thread == nullptr) return;
  ddc_stop = true;
  SetEvent(ddc_wake);
  WaitForSingleObject(in_dll_main ? ddc_done : ddc_thread, 3000);
  if (in_dll_main) Sleep(5);
  CloseHandle(ddc_thread);
  CloseHandle(ddc_wake);
  CloseHandle(ddc_done);
  ddc_thread = ddc_wake = ddc_done = nullptr;
}

static void ApplyColorSpace(reshade::api::swapchain* swapchain, const char* reason) {
  auto* const native = reinterpret_cast<IDXGISwapChain*>(swapchain->get_native());
  if (native == nullptr) return;

  IDXGISwapChain3* swapchain3 = nullptr;
  if (FAILED(native->QueryInterface(IID_PPV_ARGS(&swapchain3)))) {
    Log(reshade::log::level::error, "Swap chain has no IDXGISwapChain3 interface; cannot set a colour space.");
    return;
  }

  DXGI_SWAP_CHAIN_DESC1 desc = {};
  swapchain3->GetDesc1(&desc);

  const bool hdr = WantHdr();
  const DXGI_COLOR_SPACE_TYPE target = hdr ? DXGI_COLOR_SPACE_RGB_FULL_G2084_NONE_P2020 : DXGI_COLOR_SPACE_RGB_FULL_G22_NONE_P709;

  UINT support = 0;
  const HRESULT check = swapchain3->CheckColorSpaceSupport(target, &support);
  HRESULT set = E_FAIL;
  if (SUCCEEDED(check) && (support & DXGI_SWAP_CHAIN_COLOR_SPACE_SUPPORT_FLAG_PRESENT) != 0) {
    set = swapchain3->SetColorSpace1(target);
  }
  swapchain3->Release();

  applied_state = hdr ? 1 : 0;
  if (SUCCEEDED(set) && current_runtime != nullptr) {
    current_runtime->set_color_space(hdr ? reshade::api::color_space::hdr10_st2084 : reshade::api::color_space::srgb_nonlinear);
  }

  status_10bit = desc.Format == DXGI_FORMAT_R10G10B10A2_UNORM;
  status_flip = desc.SwapEffect == DXGI_SWAP_EFFECT_FLIP_DISCARD || desc.SwapEffect == DXGI_SWAP_EFFECT_FLIP_SEQUENTIAL;
  status_set_ok = SUCCEEDED(set);

  Log(SUCCEEDED(set) ? reshade::log::level::info : reshade::log::level::error,
      "HDR10 output %s: %ux%u format=%u swap_effect=%u game_hdr=%d mode=%d -> %s colour space: support=0x%x check=0x%08lx set=0x%08lx",
      reason, desc.Width, desc.Height, static_cast<unsigned>(desc.Format), static_cast<unsigned>(desc.SwapEffect),
      game_hdr ? 1 : 0, static_cast<int>(setting_mode), hdr ? "HDR10" : "sRGB", support,
      static_cast<unsigned long>(check), static_cast<unsigned long>(set));
}

static bool OnCreateSwapchain(reshade::api::device_api api, reshade::api::swapchain_desc& desc, void* /*hwnd*/) {
  if (!IsEnabled() || api != reshade::api::device_api::d3d11) return false;

  const auto old_format = desc.back_buffer.texture.format;
  game_hdr = Is10BitRgba(old_format);
  const uint32_t old_mode = desc.present_mode;
  bool changed = false;

  if (desc.back_buffer.texture.samples > 1) {
    Log(reshade::log::level::warning, "Swap chain is multisampled (%u samples); leaving it alone because flip model does not allow that.",
        static_cast<unsigned>(desc.back_buffer.texture.samples));
    return false;
  }

  if (Is8BitRgba(old_format)) {
    desc.back_buffer.texture.format = reshade::api::format::r10g10b10a2_unorm;
    changed = true;
  }
  if (desc.present_mode == DXGI_SWAP_EFFECT_DISCARD || desc.present_mode == DXGI_SWAP_EFFECT_SEQUENTIAL) {
    desc.present_mode = DXGI_SWAP_EFFECT_FLIP_DISCARD;
    changed = true;
  }
  if (desc.back_buffer_count < 2) {
    desc.back_buffer_count = 2;
    changed = true;
  }

  // The colour space is set on the native swap chain in OnInitSwapchain.
  Log(reshade::log::level::info, "HDR10 output create_swapchain: %ux%u format %u -> %u, swap_effect %u -> %u",
      desc.back_buffer.texture.width, desc.back_buffer.texture.height,
      static_cast<unsigned>(old_format), static_cast<unsigned>(desc.back_buffer.texture.format),
      old_mode, desc.present_mode);

  return changed;
}

static void OnInitSwapchain(reshade::api::swapchain* swapchain, bool resize) {
  if (swapchain->get_device()->get_api() != reshade::api::device_api::d3d11) return;

  current_swapchain = swapchain;
  StartDdcWorker(static_cast<HWND>(swapchain->get_hwnd()));

  if (IsEnabled()) ApplyColorSpace(swapchain, resize ? "resize" : "init");
}

static void OnDestroySwapchain(reshade::api::swapchain* swapchain, bool /*resize*/) {
  if (swapchain != current_swapchain) return;
  current_swapchain = nullptr;
  applied_state = -1;
}

// The worker thread has to be gone before ReShade unloads the add-on, which happens after the game's device is destroyed.
static void OnDestroyDevice(reshade::api::device* device) {
  if (device->get_api() == reshade::api::device_api::d3d11) StopDdcWorker(false);
}

static void OnInitEffectRuntime(reshade::api::effect_runtime* runtime) {
  current_runtime = runtime;
  if (applied_state == 1) runtime->set_color_space(reshade::api::color_space::hdr10_st2084);
}

static void OnDestroyEffectRuntime(reshade::api::effect_runtime* runtime) {
  if (runtime == current_runtime) current_runtime = nullptr;
}

// The game may ask for an explicit 8-bit view format on what is now a 10-bit back buffer, which D3D11 rejects.
static bool OnCreateResourceView(
    reshade::api::device* device,
    reshade::api::resource resource,
    reshade::api::resource_usage /*usage_type*/,
    reshade::api::resource_view_desc& desc) {
  if (!IsEnabled() || resource.handle == 0 || !Is8BitRgba(desc.format) || device->get_api() != reshade::api::device_api::d3d11) return false;

  const auto resource_desc = device->get_resource_desc(resource);
  if (resource_desc.type != reshade::api::resource_type::texture_2d && resource_desc.type != reshade::api::resource_type::surface) return false;
  if (!Is10BitRgba(resource_desc.texture.format)) return false;

  if (view_logs.fetch_add(1) < 8) {
    Log(reshade::log::level::info, "HDR10 output: view format %u on a 10-bit texture retargeted to R10G10B10A2_UNORM",
        static_cast<unsigned>(desc.format));
  }

  desc.format = reshade::api::format::r10g10b10a2_unorm;
  return true;
}

static void OnPresent(
    reshade::api::command_queue* /*queue*/,
    reshade::api::swapchain* swapchain,
    const reshade::api::rect* /*source_rect*/,
    const reshade::api::rect* /*dest_rect*/,
    uint32_t /*dirty_rect_count*/,
    const reshade::api::rect* /*dirty_rects*/) {
  if (swapchain != current_swapchain) return;
  if (reapply.exchange(false)) {
    ApplyColorSpace(swapchain, "setting changed");
    return;
  }
  // The engine drops its HDR mode whenever the window mode changes, so the request is repeated.
  if (!WindowedHdrActive()) return;
  const ULONGLONG now = GetTickCount64();
  if (now - last_request_tick >= HDR_REQUEST_INTERVAL_MS) {
    last_request_tick = now;
    RequestEngineHdr();
  }
}

// Setting callbacks. They run on the thread that presents, which is not inside the patched routine at that point.
static void OnEnabledChanged(float /*previous*/, float /*current*/) {
  SetHdrGate(IsEnabled() && setting_windowed_hdr != 0.f);
  reapply = true;
}

static void OnModeChanged(float /*previous*/, float /*current*/) {
  reapply = true;
}

static void OnWindowedHdrChanged(float /*previous*/, float /*current*/) {
  SetHdrGate(IsEnabled() && setting_windowed_hdr != 0.f);
}

static bool DrawStatus() {
  if (current_swapchain == nullptr || applied_state < 0) {
    ImGui::TextUnformatted("Output: not applied yet");
  } else if (status_set_ok) {
    ImGui::Text("Output: %s, %s, tagged %s. Game HDR mode: %s.",
                status_10bit ? "10-bit" : "8-bit", status_flip ? "flip model" : "blt model",
                applied_state == 1 ? "HDR10" : "SDR (sRGB)", game_hdr ? "on" : "off");
  } else {
    ImGui::TextWrapped("Tagging failed: this output cannot carry that colour space until the game is restarted with HDR10 Output on.");
  }
  if (gate_state == 2) {
    ImGui::TextWrapped("HDR in borderless and windowed mode is not available: this game exe is not the build the fix was made for.");
  }
  return false;
}

static bool DrawBrightness() {
  const int state = ddc_state;
  if (state == 0) {
    ImGui::TextUnformatted("Monitor brightness: asking the monitor...");
  } else if (state == 2) {
    ImGui::TextWrapped("Monitor brightness: the monitor did not answer. Check that DDC/CI is enabled in its on-screen menu.");
  } else {
    int brightness = ddc_brightness;
    if (ImGui::SliderInt("Monitor Brightness", &brightness, 0, ddc_maximum, "%d", ImGuiSliderFlags_AlwaysClamp)) {
      ddc_brightness = brightness;
      ddc_pending = brightness;
      SetEvent(ddc_wake);
    }
    ImGui::SetItemTooltip("The monitor's own brightness over DDC/CI, the same value as in its on-screen menu. It stays after the game closes.");
    if (ddc_write_failed) ImGui::TextUnformatted("The monitor rejected the last change.");
  }
  return false;
}

// Call after the settings have been loaded.
static void Use(DWORD fdw_reason, LPVOID lpv_reserved) {
  switch (fdw_reason) {
    case DLL_PROCESS_ATTACH:
      CheckHdrSetter();
      SetHdrGate(IsEnabled() && setting_windowed_hdr != 0.f);
      SetPresentGuard(true);
      Log(reshade::log::level::info, "HDR10 output: enabled=%d mode=%d windowed_hdr=%d fullscreen_check=%s hdr_setter=%s present_guard=%s",
          IsEnabled() ? 1 : 0, static_cast<int>(setting_mode), setting_windowed_hdr != 0.f ? 1 : 0,
          gate_state == 1 ? "removed" : (gate_state == 0 ? "in place" : "unknown exe, untouched"),
          setter_usable ? "found" : "not found", present_thunk != nullptr ? "on" : "off");
      reshade::register_event<reshade::addon_event::create_swapchain>(OnCreateSwapchain);
      reshade::register_event<reshade::addon_event::init_swapchain>(OnInitSwapchain);
      reshade::register_event<reshade::addon_event::destroy_swapchain>(OnDestroySwapchain);
      reshade::register_event<reshade::addon_event::destroy_device>(OnDestroyDevice);
      reshade::register_event<reshade::addon_event::init_effect_runtime>(OnInitEffectRuntime);
      reshade::register_event<reshade::addon_event::destroy_effect_runtime>(OnDestroyEffectRuntime);
      reshade::register_event<reshade::addon_event::create_resource_view>(OnCreateResourceView);
      reshade::register_event<reshade::addon_event::present>(OnPresent);
      break;
    case DLL_PROCESS_DETACH:
      // A non-null "reserved" means the process is exiting and the worker thread is already gone.
      if (lpv_reserved == nullptr) {
        StopDdcWorker(true);
        if (gate_state == 1) SetHdrGate(false);
        SetPresentGuard(false);
      }
      reshade::unregister_event<reshade::addon_event::create_swapchain>(OnCreateSwapchain);
      reshade::unregister_event<reshade::addon_event::init_swapchain>(OnInitSwapchain);
      reshade::unregister_event<reshade::addon_event::destroy_swapchain>(OnDestroySwapchain);
      reshade::unregister_event<reshade::addon_event::destroy_device>(OnDestroyDevice);
      reshade::unregister_event<reshade::addon_event::init_effect_runtime>(OnInitEffectRuntime);
      reshade::unregister_event<reshade::addon_event::destroy_effect_runtime>(OnDestroyEffectRuntime);
      reshade::unregister_event<reshade::addon_event::create_resource_view>(OnCreateResourceView);
      reshade::unregister_event<reshade::addon_event::present>(OnPresent);
      break;
  }
}

}  // namespace hdr10output

#endif  // SRC_RE2R_NONRT_HDR10_OUTPUT_HPP_
