#ifndef CBUFFER_TONEMAP_HLSLI
#define CBUFFER_TONEMAP_HLSLI

#include "../common.hlsli"

#ifndef SHADER_HASH
#define SHADER_HASH 0
#endif

#define RENODX_CUSTOM_TOE 1.f

#if SHADER_HASH == 0xD6026FDE  // LDRPostProcess_WithTonemap
#define TONEMAP_PARAM_REGISTER b2
#endif  // SHADER_HASH

#ifdef TONEMAP_PARAM_REGISTER
cbuffer TonemapParam : register(TONEMAP_PARAM_REGISTER) {
  float contrast : packoffset(c000.x);
  float linearBegin : packoffset(c000.y);
  float linearLength : packoffset(c000.z);
  float ORIGINAL_toe : packoffset(c000.w);
  float ORIGINAL_maxNit : packoffset(c001.x);
  float ORIGINAL_linearStart : packoffset(c001.y);
  float displayMaxNitSubContrastFactor : packoffset(c001.z);
  float contrastFactor : packoffset(c001.w);
  float mulLinearStartContrastFactor : packoffset(c002.x);
  float invLinearBegin : packoffset(c002.y);
  float madLinearStartContrastFactor : packoffset(c002.z);
};

float GetToe() {
  return (RENODX_TONE_MAP_TYPE == 0.f) ? ORIGINAL_toe : RENODX_CUSTOM_TOE;
}
float GetMaxNit() {
  return (RENODX_TONE_MAP_TYPE == 0.f) ? ORIGINAL_maxNit : renodx::math::FLT16_MAX;
}
float GetLinearStart() {
  return (RENODX_TONE_MAP_TYPE == 0.f) ? ORIGINAL_linearStart : renodx::math::FLT16_MAX;
}

#define toe         GetToe()
#define maxNit      GetMaxNit()
#define linearStart GetLinearStart()

#endif

#endif  // CBUFFER_TONEMAP_HLSLI
