#include "../common.hlsli"

// ConvertRec2020PS from the dx11_non-rt build of Resident Evil 2. Decompiled with 3Dmigoto v1.3.16.

cbuffer HDRMapping : register(b0) {
  float whitePaperNits : packoffset(c0);
  float configImageAlphaScale : packoffset(c0.y);
  float displayMaxNits : packoffset(c0.z);
  float displayMinNits : packoffset(c0.w);
  float4 displayMaxNitsRect : packoffset(c1);
  float4 standardMaxNitsRect : packoffset(c2);
  float4 mdrOutRangeRect : packoffset(c3);
  uint drawMode : packoffset(c4);
  float gammaForHDR : packoffset(c4.y);
  float2 configDrawRectSize : packoffset(c4.z);
}

SamplerState PointBorder_s : register(s0);
Texture2D<float4> tLinearImage : register(t0);

// 3Dmigoto declarations
#define cmp -

void main(
    float4 v0: SV_Position0,
    float2 v1: TEXCOORD0,
    out float4 o0: SV_Target0) {
  float4 r0, r1, r2, r3, r4;

  r0.xyz = tLinearImage.SampleLevel(PointBorder_s, v1.xy, 0).xyz;

  if (RENODX_TONE_MAP_TYPE != 0.f) {
    o0 = GenerateOutput(r0.xyz, whitePaperNits, displayMaxNits);
    return;
  }

  r0.w = dot(float3(0.627403975, 0.329281986, 0.0433136001), r0.xyz);
  r1.x = dot(float3(0.0690969974, 0.919539988, 0.0113612004), r0.xyz);
  r0.x = dot(float3(0.0163915996, 0.088013202, 0.895595014), r0.xyz);
  r2.x = log2(r0.w);
  r2.y = log2(r1.x);
  r2.z = log2(r0.x);
  r0.xyz = gammaForHDR * r2.xyz;
  r0.xyz = exp2(r0.xyz);
  r0.w = 10000 / whitePaperNits;
  r0.xyz = saturate(r0.xyz / r0.www);
  r0.xyz = log2(r0.xyz);
  r0.xyz = float3(0.159301758, 0.159301758, 0.159301758) * r0.xyz;
  r0.xyz = exp2(r0.xyz);
  r1.xyz = r0.xyz * float3(18.8515625, 18.8515625, 18.8515625) + float3(0.8359375, 0.8359375, 0.8359375);
  r0.xyz = r0.xyz * float3(18.6875, 18.6875, 18.6875) + float3(1, 1, 1);
  r0.xyz = r1.xyz / r0.xyz;
  r0.xyz = log2(r0.xyz);
  r0.xyz = float3(78.84375, 78.84375, 78.84375) * r0.xyz;
  r0.xyz = exp2(r0.xyz);
  r0.xyz = min(float3(1, 1, 1), r0.xyz);
  r0.w = drawMode & 2;
  if (r0.w != 0) {
    r1.xyzw = saturate(float4(9.99999975e-005, 9.99999975e-005, 9.99999975e-005, 9.99999975e-005) * displayMaxNits);
    r1.xyzw = log2(r1.xyzw);
    r1.xyzw = float4(0.159301758, 0.159301758, 0.159301758, 0.159301758) * r1.xyzw;
    r1.xyzw = exp2(r1.xyzw);
    r1.xyzw = r1.xyzw * float4(18.8515625, 18.6875, 18.8515625, 18.6875) + float4(0.8359375, 1, 0.8359375, 1);
    r1.xy = r1.xz / r1.yw;
    r1.xy = log2(r1.xy);
    r1.xy = float2(78.84375, 78.84375) * r1.xy;
    r1.xy = exp2(r1.xy);
    r1.xy = min(float2(1, 1), r1.xy);
    r1.y = r1.x + -r1.y;
    r2.xyz = r0.xyz / r1.xxx;
    r2.xyz = min(float3(1, 1, 1), r2.xyz);
    r3.xyz = r2.xyz * r1.yyy;
    r4.xyz = float3(1, 1, 1) + -r2.xyz;
    r1.xzw = r2.xyz * r1.xxx;
    r1.xyz = r1.yyy * r4.xyz + r1.xzw;
    r1.xyz = r1.xyz * r2.xyz;
    r1.xyz = r3.xyz * r4.xyz + r1.xyz;
    r1.xyz = min(r1.xyz, r0.xyz);
  }
  if (r0.w == 0) {
    r1.xyz = r0.xyz;
  }
  o0.xyz = r1.xyz;
  o0.w = 1;
  return;
}
