#ifndef RE2R_NONRT_AA_HLSLI_
#define RE2R_NONRT_AA_HLSLI_

#include "../common.hlsli"

// The tone mapping pass scales the picture by game brightness over UI brightness. FXAA runs after it with fixed
// thresholds, so its inputs are scaled back first.
#define WHITE_SCALE     ((RENODX_TONE_MAP_TYPE == 0.f) ? 1.f : (RENODX_DIFFUSE_WHITE_NITS / RENODX_GRAPHICS_WHITE_NITS))
#define INV_WHITE_SCALE (1.f / WHITE_SCALE)

#endif  // RE2R_NONRT_AA_HLSLI_
