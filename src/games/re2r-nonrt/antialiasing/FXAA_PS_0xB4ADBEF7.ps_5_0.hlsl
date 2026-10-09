#include "./AA.hlsli"

// FXAA from the dx11_non-rt build of Resident Evil 2 (exe of 2023-04-20). Decompiled with 3Dmigoto v1.3.16.
// It runs after the tone mapping pass, so its edge detection is done on colours scaled back to the range the
// vanilla thresholds expect, and the output keeps the original scale. Corrected from the disassembly: the
// gathers read the green channel, and the last sub-pixel offset is a masked select, not an integer AND.

cbuffer SceneInfo : register(b0)
{
  row_major float4x4 viewProjMat : packoffset(c0);
  row_major float3x4 transposeViewMat : packoffset(c4);
  row_major float3x4 transposeViewInvMat : packoffset(c7);
  float4 projElement[2] : packoffset(c10);
  float4 projInvElements[2] : packoffset(c12);
  row_major float4x4 viewProjInvMat : packoffset(c14);
  row_major float4x4 prevViewProjMat : packoffset(c18);
  float3 ZToLinear : packoffset(c22);
  float subdivisionLevel : packoffset(c22.w);
  float2 screenSize : packoffset(c23);
  float2 screenInverseSize : packoffset(c23.z);
  float2 cullingHelper : packoffset(c24);
  float cameraNearPlane : packoffset(c24.z);
  float cameraFarPlane : packoffset(c24.w);
  float4 viewFrustum[6] : packoffset(c25);
  float4 clipplane : packoffset(c31);
}

SamplerState BilinearClamp_s : register(s0);
Texture2D<float4> HDRImage : register(t0);


// 3Dmigoto declarations
#define cmp -


void main(
  float4 v0 : SV_Position0,
  out float4 o0 : SV_Target0)
{
  float4 r0,r1,r2,r3,r4,r5;
  uint4 bitmask, uiDest;
  float4 fDest;

  r0.xy = screenInverseSize.xy * v0.xy;
  float4 center_raw = HDRImage.SampleLevel(BilinearClamp_s, r0.xy, 0).xyzw;
  r1.xyzw = center_raw;
  r1.xyz *= INV_WHITE_SCALE;
  r2.xyz = HDRImage.GatherGreen(BilinearClamp_s, r0.xy).xyz * INV_WHITE_SCALE;
  r3.xyz = HDRImage.GatherGreen(BilinearClamp_s, r0.xy, int2(-1, -1)).zxw * INV_WHITE_SCALE;
  r0.z = max(r2.x, r1.y);
  r0.w = min(r2.x, r1.y);
  r0.z = max(r2.z, r0.z);
  r0.w = min(r2.z, r0.w);
  r2.w = max(r3.x, r3.y);
  r3.w = min(r3.x, r3.y);
  r0.z = max(r2.w, r0.z);
  r0.w = min(r3.w, r0.w);
  r2.w = 0.333000004 * r0.z;
  r0.z = r0.z + -r0.w;
  r0.w = max(0.0833000019, r2.w);
  r0.w = cmp(r0.z < r0.w);
  if (r0.w != 0) {
    o0.xyzw = center_raw;
  }
  if (r0.w == 0) {
    r1.xzw = HDRImage.SampleLevel(BilinearClamp_s, r0.xy, 0, int2(1, -1)).xyz * INV_WHITE_SCALE;
    r1.xzw = max(r1.xww, r1.zzx);
    r0.w = min(r1.x, r1.z);
    r0.w = min(r0.w, r1.w);
    r1.xzw = HDRImage.SampleLevel(BilinearClamp_s, r0.xy, 0, int2(-1, 1)).xyz * INV_WHITE_SCALE;
    r1.xzw = max(r1.xww, r1.zzx);
    r1.x = min(r1.x, r1.z);
    r1.x = min(r1.x, r1.w);
    r1.zw = r3.xy + r2.xz;
    r0.z = 1 / r0.z;
    r2.w = r1.z + r1.w;
    r1.zw = r1.yy * float2(-2,-2) + r1.zw;
    r3.w = r0.w + r2.y;
    r0.w = r3.z + r0.w;
    r4.x = r2.z * -2 + r3.w;
    r0.w = r3.x * -2 + r0.w;
    r3.z = r3.z + r1.x;
    r1.x = r1.x + r2.y;
    r1.z = abs(r1.z) * 2 + abs(r4.x);
    r0.w = abs(r1.w) * 2 + abs(r0.w);
    r1.w = r3.y * -2 + r3.z;
    r1.x = r2.x * -2 + r1.x;
    r1.z = abs(r1.w) + r1.z;
    r0.w = abs(r1.x) + r0.w;
    r1.x = r3.z + r3.w;
    r0.w = cmp(r1.z >= r0.w);
    r1.x = r2.w * 2 + r1.x;
    if (r0.w == 0) {
      r3.x = r3.y;
      r2.x = r2.z;
    }
    if (r0.w != 0) {
      r1.z = screenInverseSize.y;
    } else {
      r1.z = screenInverseSize.x;
    }
    r1.x = r1.x * 0.0833333358 + -r1.y;
    r1.w = r3.x + -r1.y;
    r2.y = r2.x + -r1.y;
    r2.z = cmp(abs(r1.w) >= abs(r2.y));
    r1.w = max(abs(r2.y), abs(r1.w));
    if (r2.z != 0) {
      r1.z = -r1.z;
    }
    r0.z = saturate(abs(r1.x) * r0.z);
    r1.x = r0.w ? screenInverseSize.x : 0;
    r2.y = r0.w ? 0 : screenInverseSize.y;
    if (r0.w == 0) {
      r2.w = r1.z * 0.5 + r0.x;
    } else {
      r2.w = r0.x;
    }
    if (r0.w != 0) {
      r3.y = r1.z * 0.5 + r0.y;
    } else {
      r3.y = r0.y;
    }
    r3.z = r2.w + -r1.x;
    r3.w = r3.y + -r2.y;
    r4.x = r2.w + r1.x;
    r4.y = r3.y + r2.y;
    r2.w = r0.z * -2 + 3;
    r5.xyz = HDRImage.SampleLevel(BilinearClamp_s, r3.zw, 0).xyz * INV_WHITE_SCALE;
    r5.xyz = max(r5.xzz, r5.yyx);
    r3.y = min(r5.x, r5.y);
    r3.y = min(r3.y, r5.z);
    r0.z = r0.z * r0.z;
    r5.xyz = HDRImage.SampleLevel(BilinearClamp_s, r4.xy, 0).xyz * INV_WHITE_SCALE;
    r5.xyz = max(r5.xzz, r5.yyx);
    r4.z = min(r5.x, r5.y);
    r4.z = min(r4.z, r5.z);
    if (r2.z == 0) {
      r2.x = r2.x + r1.y;
    } else {
      r2.x = r3.x + r1.y;
    }
    r1.w = 0.25 * r1.w;
    r2.z = -r2.x * 0.5 + r1.y;
    r0.z = r2.w * r0.z;
    r2.z = cmp(r2.z < 0);
    r3.x = -r2.x * 0.5 + r3.y;
    r3.y = -r2.x * 0.5 + r4.z;
    r4.zw = cmp(abs(r3.xy) < r1.ww);
    if (r4.z != 0) {
      r3.z = -r1.x * 1.5 + r3.z;
      r3.w = -r2.y * 1.5 + r3.w;
    }
    r2.w = (int)r4.w | (int)r4.z;
    if (r4.w != 0) {
      r4.x = r1.x * 1.5 + r4.x;
      r4.y = r2.y * 1.5 + r4.y;
    }
    if (r2.w != 0) {
      if (r4.z != 0) {
        r5.xyz = HDRImage.SampleLevel(BilinearClamp_s, r3.zw, 0).xyz * INV_WHITE_SCALE;
        r5.xyz = max(r5.xzz, r5.yyx);
        r2.w = min(r5.x, r5.y);
        r3.x = min(r2.w, r5.z);
      }
      if (r4.w != 0) {
        r5.xyz = HDRImage.SampleLevel(BilinearClamp_s, r4.xy, 0).xyz * INV_WHITE_SCALE;
        r5.xyz = max(r5.xzz, r5.yyx);
        r2.w = min(r5.x, r5.y);
        r3.y = min(r2.w, r5.z);
      }
      if (r4.z != 0) {
        r3.x = -r2.x * 0.5 + r3.x;
      }
      if (r4.w != 0) {
        r3.y = -r2.x * 0.5 + r3.y;
      }
      r4.zw = cmp(abs(r3.xy) < r1.ww);
      if (r4.z != 0) {
        r3.z = -r1.x * 2 + r3.z;
        r3.w = -r2.y * 2 + r3.w;
      }
      r2.w = (int)r4.w | (int)r4.z;
      if (r4.w != 0) {
        r4.x = r1.x * 2 + r4.x;
        r4.y = r2.y * 2 + r4.y;
      }
      if (r2.w != 0) {
        if (r4.z != 0) {
          r5.xyz = HDRImage.SampleLevel(BilinearClamp_s, r3.zw, 0).xyz * INV_WHITE_SCALE;
          r5.xyz = max(r5.xzz, r5.yyx);
          r2.w = min(r5.x, r5.y);
          r3.x = min(r2.w, r5.z);
        }
        if (r4.w != 0) {
          r5.xyz = HDRImage.SampleLevel(BilinearClamp_s, r4.xy, 0).xyz * INV_WHITE_SCALE;
          r5.xyz = max(r5.xzz, r5.yyx);
          r2.w = min(r5.x, r5.y);
          r3.y = min(r2.w, r5.z);
        }
        if (r4.z != 0) {
          r3.x = -r2.x * 0.5 + r3.x;
        }
        if (r4.w != 0) {
          r3.y = -r2.x * 0.5 + r3.y;
        }
        r4.zw = cmp(abs(r3.xy) < r1.ww);
        if (r4.z != 0) {
          r3.z = -r1.x * 4 + r3.z;
          r3.w = -r2.y * 4 + r3.w;
        }
        r2.w = (int)r4.w | (int)r4.z;
        if (r4.w != 0) {
          r4.x = r1.x * 4 + r4.x;
          r4.y = r2.y * 4 + r4.y;
        }
        if (r2.w != 0) {
          if (r4.z != 0) {
            r5.xyz = HDRImage.SampleLevel(BilinearClamp_s, r3.zw, 0).xyz * INV_WHITE_SCALE;
            r5.xyz = max(r5.xzz, r5.yyx);
            r2.w = min(r5.x, r5.y);
            r3.x = min(r2.w, r5.z);
          }
          if (r4.w != 0) {
            r5.xyz = HDRImage.SampleLevel(BilinearClamp_s, r4.xy, 0).xyz * INV_WHITE_SCALE;
            r5.xyz = max(r5.xzz, r5.yyx);
            r2.w = min(r5.x, r5.y);
            r3.y = min(r2.w, r5.z);
          }
          if (r4.z != 0) {
            r3.x = -r2.x * 0.5 + r3.x;
          }
          if (r4.w != 0) {
            r3.y = -r2.x * 0.5 + r3.y;
          }
          r2.xw = cmp(abs(r3.xy) < r1.ww);
          if (r2.x != 0) {
            r3.z = -r1.x * 12 + r3.z;
            r3.w = -r2.y * 12 + r3.w;
          }
          if (r2.w != 0) {
            r4.x = r1.x * 12 + r4.x;
            r4.y = r2.y * 12 + r4.y;
          }
        }
      }
    }
    if (r0.w == 0) {
      r1.x = v0.y * screenInverseSize.y + -r3.w;
      r1.w = -v0.y * screenInverseSize.y + r4.y;
    } else {
      r1.x = v0.x * screenInverseSize.x + -r3.z;
      r1.w = -v0.x * screenInverseSize.x + r4.x;
    }
    r2.xy = cmp(r3.xy < float2(0,0));
    r2.w = r1.w + r1.x;
    r2.xy = cmp((int2)r2.zz != (int2)r2.xy);
    r2.z = 1 / r2.w;
    r2.w = cmp(r1.x < r1.w);
    r1.x = min(r1.x, r1.w);
    r1.w = r2.w ? r2.x : r2.y;
    r0.z = r0.z * r0.z;
    r1.x = r1.x * -r2.z + 0.5;
    r0.z = 0.75 * r0.z;
    r1.x = r1.w ? r1.x : 0;
    r0.z = max(r1.x, r0.z);
    if (r0.w == 0) {
      r0.x = r0.z * r1.z + r0.x;
    }
    if (r0.w != 0) {
      r0.y = r0.z * r1.z + r0.y;
    }
    r0.xyz = HDRImage.SampleLevel(BilinearClamp_s, r0.xy, 0).xyz;
    o0.xyz = r0.xyz;
    o0.w = center_raw.y;
  }
  return;
}