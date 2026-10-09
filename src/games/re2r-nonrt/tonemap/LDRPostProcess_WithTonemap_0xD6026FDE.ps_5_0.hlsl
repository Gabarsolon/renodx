#define SHADER_HASH 0xD6026FDE
#include "./tonemap.hlsli"

// LDRPostProcess_WithTonemap from the dx11_non-rt build of Resident Evil 2 (exe of 2023-04-20).
// Decompiled with 3Dmigoto v1.3.16; the integer hashes were rewritten from the disassembly because the
// decompiler stores them in float registers.

struct RadialBlurComputeResult
{
    float computeAlpha;            // Offset:    0
};

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

cbuffer CameraKerare : register(b1)
{
  float kerare_scale : packoffset(c0);
  float kerare_offset : packoffset(c0.y);
}

cbuffer LensDistortionParam : register(b3)
{
  float fDistortionCoef : packoffset(c0);
  float fRefraction : packoffset(c0.y);
  uint aberrationEnable : packoffset(c0.z);
  uint reserved : packoffset(c0.w);
}

cbuffer RadialBlurRenderParam : register(b4)
{
  float4 cbRadialColor : packoffset(c0);
  float2 cbRadialScreenPos : packoffset(c1);
  float2 cbRadialMaskSmoothstep : packoffset(c1.z);
  float2 cbRadialMaskRate : packoffset(c2);
  float cbRadialBlurPower : packoffset(c2.z);
  float cbRadialSharpRange : packoffset(c2.w);
  uint cbRadialBlurFlags : packoffset(c3);
  float cbRadialReserve0 : packoffset(c3.y);
  float cbRadialReserve1 : packoffset(c3.z);
  float cbRadialReserve2 : packoffset(c3.w);
}

cbuffer FilmGrainParam : register(b5)
{
  float2 fNoisePower : packoffset(c0);
  float2 fNoiseUVOffset : packoffset(c0.z);
  float fNoiseDensity : packoffset(c1);
  float fNoiseContrast : packoffset(c1.y);
  float fBlendRate : packoffset(c1.z);
  float fReverseNoiseSize : packoffset(c1.w);
}

cbuffer ColorCorrectTexture : register(b6)
{
  float fTextureSize : packoffset(c0);
  float fTextureBlendRate : packoffset(c0.y);
  float fTextureBlendRate2 : packoffset(c0.z);
  float fTextureInverseSize : packoffset(c0.w);
  float4 fColorMatrix[4] : packoffset(c1);
}

cbuffer ColorDeficientTable : register(b7)
{
  float4 cvdR : packoffset(c0);
  float4 cvdG : packoffset(c1);
  float4 cvdB : packoffset(c2);
}

cbuffer ImagePlaneParam : register(b8)
{
  float4 ColorParam : packoffset(c0);
  float Levels_Rate : packoffset(c1);
  float Levels_Range : packoffset(c1.y);
  uint Blend_Type : packoffset(c1.z);
}

cbuffer CBControl : register(b9)
{
  uint cPassEnabled : packoffset(c0);
}

SamplerState BilinearClamp_s : register(s0);
SamplerState TrilinearClamp_s : register(s1);
Texture2D<float4> SourceImage : register(t0);
StructuredBuffer<RadialBlurComputeResult> ComputeResultSRV : register(t1);
Texture3D<float4> tTextureMap0 : register(t2);
Texture3D<float4> tTextureMap1 : register(t3);
Texture3D<float4> tTextureMap2 : register(t4);
Texture2D<float4> ImagePlameBase : register(t5);
Texture2D<float> ImagePlameAlpha : register(t6);


// 3Dmigoto declarations
#define cmp -


void main(
  float4 v0 : SV_Position0,
  float4 v1 : Kerare0,
  float v2 : Exposure0,
  out float4 o0 : SV_Target0)
{
  float4 r0,r1,r2,r3,r4,r5,r6,r7,r8,r9,r10;
  uint4 bitmask, uiDest;
  float4 fDest;

  r0.xyzw = cPassEnabled & int4(1,32,2,4);
  if (r0.x != 0) {
    r1.xy = v0.xy * screenInverseSize.xy + float2(-0.5,-0.5);
    r1.z = fDistortionCoef * 0.5 + 1;
    r1.z = max(1, r1.z);
    r1.z = rcp(r1.z);
    r1.w = dot(r1.xy, r1.xy);
    r2.x = fDistortionCoef * r1.w + 1;
    r2.xy = r2.xx * r1.xy;
    r2.xy = r2.xy * r1.zz + float2(0.5,0.5);
    if (aberrationEnable == 0) {
      r3.xyz = SourceImage.Sample(BilinearClamp_s, r2.xy).xyz;
      r3.xyz = v2.xxx * r3.xyz;
      r4.xyz = invLinearBegin * r3.xyz;
      r5.xyz = cmp(r3.xyz >= linearBegin);
      r6.xyz = r4.xyz * r4.xyz;
      r7.xyz = -r4.xyz * float3(2,2,2) + float3(3,3,3);
      r6.xyz = r7.xyz * r6.xyz;
      r5.xyz = r5.xyz ? float3(1,1,1) : r6.xyz;
      r5.xyz = float3(1,1,1) + -r5.xyz;
      r6.xyz = cmp(linearStart >= r3.xyz);
      r6.xyz = r6.xyz ? float3(0,0,0) : float3(1,1,1);
      r7.xyz = float3(1,1,1) + -r5.xyz;
      r7.xyz = r7.xyz + -r6.xyz;
      r4.xyz = log2(r4.xyz);
      r4.xyz = toe * r4.xyz;
      r4.xyz = exp2(r4.xyz);
      r4.xyz = linearBegin * r4.xyz;
      r8.xyz = contrast * r3.xyz + madLinearStartContrastFactor;
      r7.xyz = r8.xyz * r7.xyz;
      r4.xyz = r4.xyz * r5.xyz + r7.xyz;
      r3.xyz = contrastFactor * r3.xyz + mulLinearStartContrastFactor;
      r3.xyz = exp2(r3.xyz);
      r3.xyz = -displayMaxNitSubContrastFactor * r3.xyz + maxNit;
      r3.xyz = r3.xyz * r6.xyz + r4.xyz;
    } else {
      r1.w = fRefraction + r1.w;
      r2.z = fDistortionCoef * r1.w + 1;
      r2.zw = r2.zz * r1.xy;
      r2.zw = r2.zw * r1.zz + float2(0.5,0.5);
      r1.w = fRefraction + r1.w;
      r1.w = fDistortionCoef * r1.w + 1;
      r1.xy = r1.xy * r1.ww;
      r1.xy = r1.xy * r1.zz + float2(0.5,0.5);
      r1.w = SourceImage.Sample(BilinearClamp_s, r2.xy).x;
      r1.w = v2.x * r1.w;
      r2.x = invLinearBegin * r1.w;
      r2.y = cmp(r1.w >= linearBegin);
      r3.w = r2.x * r2.x;
      r4.x = -r2.x * 2 + 3;
      r3.w = -r3.w * r4.x + 1;
      r2.y = r2.y ? 0 : r3.w;
      r3.w = cmp(linearStart >= r1.w);
      r4.x = 1 + -r2.y;
      r4.yz = r3.ww ? float2(0,-0) : float2(1,-1);
      r3.w = r4.x + r4.z;
      r2.x = log2(r2.x);
      r2.x = toe * r2.x;
      r2.x = exp2(r2.x);
      r2.x = linearBegin * r2.x;
      r4.x = contrast * r1.w + madLinearStartContrastFactor;
      r3.w = r4.x * r3.w;
      r2.x = r2.x * r2.y + r3.w;
      r1.w = contrastFactor * r1.w + mulLinearStartContrastFactor;
      r1.w = exp2(r1.w);
      r1.w = -displayMaxNitSubContrastFactor * r1.w + maxNit;
      r3.x = r1.w * r4.y + r2.x;
      r1.w = SourceImage.Sample(BilinearClamp_s, r2.zw).y;
      r1.w = v2.x * r1.w;
      r2.x = invLinearBegin * r1.w;
      r2.y = cmp(r1.w >= linearBegin);
      r2.z = r2.x * r2.x;
      r2.w = -r2.x * 2 + 3;
      r2.z = -r2.z * r2.w + 1;
      r2.y = r2.y ? 0 : r2.z;
      r2.z = cmp(linearStart >= r1.w);
      r2.w = 1 + -r2.y;
      r4.xy = r2.zz ? float2(0,-0) : float2(1,-1);
      r2.z = r4.y + r2.w;
      r2.x = log2(r2.x);
      r2.x = toe * r2.x;
      r2.x = exp2(r2.x);
      r2.x = linearBegin * r2.x;
      r2.w = contrast * r1.w + madLinearStartContrastFactor;
      r2.z = r2.w * r2.z;
      r2.x = r2.x * r2.y + r2.z;
      r1.w = contrastFactor * r1.w + mulLinearStartContrastFactor;
      r1.w = exp2(r1.w);
      r1.w = -displayMaxNitSubContrastFactor * r1.w + maxNit;
      r3.y = r1.w * r4.x + r2.x;
      r1.x = SourceImage.Sample(BilinearClamp_s, r1.xy).z;
      r1.x = v2.x * r1.x;
      r1.y = invLinearBegin * r1.x;
      r1.w = cmp(r1.x >= linearBegin);
      r2.x = r1.y * r1.y;
      r2.y = -r1.y * 2 + 3;
      r2.x = -r2.x * r2.y + 1;
      r1.w = r1.w ? 0 : r2.x;
      r2.x = cmp(linearStart >= r1.x);
      r2.y = 1 + -r1.w;
      r2.xz = r2.xx ? float2(0,-0) : float2(1,-1);
      r2.y = r2.y + r2.z;
      r1.y = log2(r1.y);
      r1.y = toe * r1.y;
      r1.y = exp2(r1.y);
      r1.y = linearBegin * r1.y;
      r2.z = contrast * r1.x + madLinearStartContrastFactor;
      r2.y = r2.z * r2.y;
      r1.y = r1.y * r1.w + r2.y;
      r1.x = contrastFactor * r1.x + mulLinearStartContrastFactor;
      r1.x = exp2(r1.x);
      r1.x = -displayMaxNitSubContrastFactor * r1.x + maxNit;
      r3.z = r1.x * r2.x + r1.y;
    }
    r1.x = fDistortionCoef;
  } else {
    r2.xy = (uint2)v0.xy;
    r2.zw = float2(0,0);
    r2.xyz = SourceImage.Load(r2.xyz).xyz;
    r2.xyz = v2.xxx * r2.xyz;
    r4.xyz = invLinearBegin * r2.xyz;
    r5.xyz = cmp(r2.xyz >= linearBegin);
    r6.xyz = r4.xyz * r4.xyz;
    r7.xyz = -r4.xyz * float3(2,2,2) + float3(3,3,3);
    r6.xyz = r7.xyz * r6.xyz;
    r5.xyz = r5.xyz ? float3(1,1,1) : r6.xyz;
    r5.xyz = float3(1,1,1) + -r5.xyz;
    r6.xyz = cmp(linearStart >= r2.xyz);
    r6.xyz = r6.xyz ? float3(0,0,0) : float3(1,1,1);
    r7.xyz = float3(1,1,1) + -r5.xyz;
    r7.xyz = r7.xyz + -r6.xyz;
    r4.xyz = log2(r4.xyz);
    r4.xyz = toe * r4.xyz;
    r4.xyz = exp2(r4.xyz);
    r4.xyz = linearBegin * r4.xyz;
    r8.xyz = contrast * r2.xyz + madLinearStartContrastFactor;
    r7.xyz = r8.xyz * r7.xyz;
    r4.xyz = r4.xyz * r5.xyz + r7.xyz;
    r2.xyz = contrastFactor * r2.xyz + mulLinearStartContrastFactor;
    r2.xyz = exp2(r2.xyz);
    r2.xyz = -displayMaxNitSubContrastFactor * r2.xyz + maxNit;
    r3.xyz = r2.xyz * r6.xyz + r4.xyz;
    r1.xz = float2(0,1);
  }
  if (r0.y != 0) {
    r0.y = asint(cbRadialBlurFlags) & 2;
    r1.yw = r0.yy ? float2(1,0) : float2(0,1);
    r0.y = ComputeResultSRV[0].computeAlpha;
    r0.y = r0.y * r1.y + r1.w;
    r0.y = cbRadialColor.w * r0.y;
    r1.y = cmp(r0.y == 0.000000);
    if (r1.y != 0) {
      r2.xyz = r3.xyz;
    }
    if (r1.y == 0) {
      r0.x = r0.x ? 1 : 0;
      r1.yw = screenInverseSize.xy * v0.xy;
      r4.xy = v0.xy * screenInverseSize.xy + float2(-0.5,-0.5);
      r4.xy = -cbRadialScreenPos.xy + r4.xy;
      r4.zw = cmp(r4.xy < float2(0,0));
      r5.xy = -v0.xy * screenInverseSize.xy + float2(1,1);
      r1.yw = r4.zw ? r5.xy : r1.yw;
      r2.w = asint(cbRadialBlurFlags) & 1;
      r3.w = dot(r4.xy, r4.xy);
      r4.z = rsqrt(r3.w);
      r4.zw = r4.xy * r4.zz;
      r4.zw = cbRadialSharpRange * r4.zw;
      uint2 radial_cell = (uint2)abs(r4.zw);
      uint radial_hash = radial_cell.y + radial_cell.x;
      radial_hash = (radial_hash ^ 61u) ^ (radial_hash >> 16);
      radial_hash *= 9u;
      radial_hash = radial_hash ^ (radial_hash >> 4);
      radial_hash *= 0x27d4eb2du;
      radial_hash = radial_hash ^ (radial_hash >> 15);
      r4.z = (float)radial_hash;
      r4.z = 2.32830644e-010 * r4.z;
      r2.w = r2.w ? r4.z : 1;
      if (r0.x != 0) {
        r0.x = sqrt(r3.w);
        r0.x = max(1, r0.x);
        r0.x = 1 / r0.x;
        r4.zw = -cbRadialBlurPower * r1.yw;
        r4.zw = r4.zw * r0.xx;
        r4.zw = r4.zw * r2.ww;
        r5.xyzw = r4.zwzw * float4(0.00111111114,0.00111111114,0.00999999978,0.00999999978) + float4(1,1,1,1);
        r5.xyzw = r4.xyxy * r5.xyzw + cbRadialScreenPos.xyxy;
        r0.x = dot(r5.xy, r5.xy);
        r0.x = r1.x * r0.x + 1;
        r5.xy = r5.xy * r0.xx;
        r5.xy = r5.xy * r1.zz + float2(0.5,0.5);
        r6.xyz = SourceImage.SampleLevel(BilinearClamp_s, r5.xy, 0).xyz;
        r7.xyzw = r4.zwzw * float4(0.00222222228,0.00222222228,0.00333333341,0.00333333341) + float4(1,1,1,1);
        r7.xyzw = r4.xyxy * r7.xyzw + cbRadialScreenPos.xyxy;
        r0.x = dot(r7.xy, r7.xy);
        r0.x = r1.x * r0.x + 1;
        r5.xy = r7.xy * r0.xx;
        r5.xy = r5.xy * r1.zz + float2(0.5,0.5);
        r8.xyz = SourceImage.SampleLevel(BilinearClamp_s, r5.xy, 0).xyz;
        r8.xyz = float3(0.100000001,0.100000001,0.100000001) * r8.xyz;
        r6.xyz = r6.xyz * float3(0.100000001,0.100000001,0.100000001) + r8.xyz;
        r0.x = dot(r7.zw, r7.zw);
        r0.x = r1.x * r0.x + 1;
        r5.xy = r7.zw * r0.xx;
        r5.xy = r5.xy * r1.zz + float2(0.5,0.5);
        r7.xyz = SourceImage.SampleLevel(BilinearClamp_s, r5.xy, 0).xyz;
        r6.xyz = r7.xyz * float3(0.100000001,0.100000001,0.100000001) + r6.xyz;
        r7.xyzw = r4.zwzw * float4(0.00444444455,0.00444444455,0.00555555569,0.00555555569) + float4(1,1,1,1);
        r7.xyzw = r4.xyxy * r7.xyzw + cbRadialScreenPos.xyxy;
        r0.x = dot(r7.xy, r7.xy);
        r0.x = r1.x * r0.x + 1;
        r5.xy = r7.xy * r0.xx;
        r5.xy = r5.xy * r1.zz + float2(0.5,0.5);
        r8.xyz = SourceImage.SampleLevel(BilinearClamp_s, r5.xy, 0).xyz;
        r6.xyz = r8.xyz * float3(0.100000001,0.100000001,0.100000001) + r6.xyz;
        r0.x = dot(r7.zw, r7.zw);
        r0.x = r1.x * r0.x + 1;
        r5.xy = r7.zw * r0.xx;
        r5.xy = r5.xy * r1.zz + float2(0.5,0.5);
        r7.xyz = SourceImage.SampleLevel(BilinearClamp_s, r5.xy, 0).xyz;
        r6.xyz = r7.xyz * float3(0.100000001,0.100000001,0.100000001) + r6.xyz;
        r7.xyzw = r4.zwzw * float4(0.00666666683,0.00666666683,0.00777777797,0.00777777797) + float4(1,1,1,1);
        r7.xyzw = r4.xyxy * r7.xyzw + cbRadialScreenPos.xyxy;
        r0.x = dot(r7.xy, r7.xy);
        r0.x = r1.x * r0.x + 1;
        r5.xy = r7.xy * r0.xx;
        r5.xy = r5.xy * r1.zz + float2(0.5,0.5);
        r8.xyz = SourceImage.SampleLevel(BilinearClamp_s, r5.xy, 0).xyz;
        r6.xyz = r8.xyz * float3(0.100000001,0.100000001,0.100000001) + r6.xyz;
        r0.x = dot(r7.zw, r7.zw);
        r0.x = r1.x * r0.x + 1;
        r5.xy = r7.zw * r0.xx;
        r5.xy = r5.xy * r1.zz + float2(0.5,0.5);
        r7.xyz = SourceImage.SampleLevel(BilinearClamp_s, r5.xy, 0).xyz;
        r6.xyz = r7.xyz * float3(0.100000001,0.100000001,0.100000001) + r6.xyz;
        r4.zw = r4.zw * float2(0.0088888891,0.0088888891) + float2(1,1);
        r4.zw = r4.xy * r4.zw + cbRadialScreenPos.xy;
        r0.x = dot(r4.zw, r4.zw);
        r0.x = r1.x * r0.x + 1;
        r4.zw = r4.zw * r0.xx;
        r4.zw = r4.zw * r1.zz + float2(0.5,0.5);
        r7.xyz = SourceImage.SampleLevel(BilinearClamp_s, r4.zw, 0).xyz;
        r6.xyz = r7.xyz * float3(0.100000001,0.100000001,0.100000001) + r6.xyz;
        r0.x = dot(r5.zw, r5.zw);
        r0.x = r1.x * r0.x + 1;
        r4.zw = r5.zw * r0.xx;
        r1.xz = r4.zw * r1.zz + float2(0.5,0.5);
        r5.xyz = SourceImage.SampleLevel(BilinearClamp_s, r1.xz, 0).xyz;
        r5.xyz = r5.xyz * float3(0.100000001,0.100000001,0.100000001) + r6.xyz;
        r5.xyz = cbRadialColor.xyz * r5.xyz;
        r5.xyz = v2.xxx * r5.xyz;
        r6.xyz = invLinearBegin * r5.xyz;
        r7.xyz = cmp(r5.xyz >= linearBegin);
        r8.xyz = r6.xyz * r6.xyz;
        r9.xyz = -r6.xyz * float3(2,2,2) + float3(3,3,3);
        r8.xyz = r9.xyz * r8.xyz;
        r7.xyz = r7.xyz ? float3(1,1,1) : r8.xyz;
        r7.xyz = float3(1,1,1) + -r7.xyz;
        r8.xyz = cmp(linearStart >= r5.xyz);
        r8.xyz = r8.xyz ? float3(0,0,0) : float3(1,1,1);
        r9.xyz = float3(1,1,1) + -r7.xyz;
        r9.xyz = r9.xyz + -r8.xyz;
        r6.xyz = log2(r6.xyz);
        r6.xyz = toe * r6.xyz;
        r6.xyz = exp2(r6.xyz);
        r6.xyz = linearBegin * r6.xyz;
        r10.xyz = contrast * r5.xyz + madLinearStartContrastFactor;
        r9.xyz = r10.xyz * r9.xyz;
        r6.xyz = r6.xyz * r7.xyz + r9.xyz;
        r5.xyz = contrastFactor * r5.xyz + mulLinearStartContrastFactor;
        r5.xyz = exp2(r5.xyz);
        r5.xyz = -displayMaxNitSubContrastFactor * r5.xyz + maxNit;
        r5.xyz = r5.xyz * r8.xyz + r6.xyz;
        r6.xyz = cbRadialColor.xyz * r3.xyz;
        r5.xyz = r6.xyz * float3(0.100000001,0.100000001,0.100000001) + r5.xyz;
      } else {
        r0.x = sqrt(r3.w);
        r0.x = max(1, r0.x);
        r0.x = 1 / r0.x;
        r1.xy = -cbRadialBlurPower * r1.yw;
        r1.xy = r1.xy * r0.xx;
        r1.xy = r1.xy * r2.ww;
        r6.xyzw = r1.xyxy * float4(0.00111111114,0.00111111114,0.00999999978,0.00999999978) + float4(1,1,1,1);
        r6.xyzw = r4.xyxy * r6.xyzw + cbRadialScreenPos.xyxy;
        r6.xyzw = float4(0.5,0.5,0.5,0.5) + r6.xyzw;
        r7.xyz = SourceImage.SampleLevel(BilinearClamp_s, r6.xy, 0).xyz;
        r8.xyzw = r1.xyxy * float4(0.00222222228,0.00222222228,0.00333333341,0.00333333341) + float4(1,1,1,1);
        r8.xyzw = r4.xyxy * r8.xyzw + cbRadialScreenPos.xyxy;
        r8.xyzw = float4(0.5,0.5,0.5,0.5) + r8.xyzw;
        r9.xyz = SourceImage.SampleLevel(BilinearClamp_s, r8.xy, 0).xyz;
        r9.xyz = float3(0.100000001,0.100000001,0.100000001) * r9.xyz;
        r7.xyz = r7.xyz * float3(0.100000001,0.100000001,0.100000001) + r9.xyz;
        r8.xyz = SourceImage.SampleLevel(BilinearClamp_s, r8.zw, 0).xyz;
        r7.xyz = r8.xyz * float3(0.100000001,0.100000001,0.100000001) + r7.xyz;
        r8.xyzw = r1.xyxy * float4(0.00444444455,0.00444444455,0.00555555569,0.00555555569) + float4(1,1,1,1);
        r8.xyzw = r4.xyxy * r8.xyzw + cbRadialScreenPos.xyxy;
        r8.xyzw = float4(0.5,0.5,0.5,0.5) + r8.xyzw;
        r9.xyz = SourceImage.SampleLevel(BilinearClamp_s, r8.xy, 0).xyz;
        r7.xyz = r9.xyz * float3(0.100000001,0.100000001,0.100000001) + r7.xyz;
        r8.xyz = SourceImage.SampleLevel(BilinearClamp_s, r8.zw, 0).xyz;
        r7.xyz = r8.xyz * float3(0.100000001,0.100000001,0.100000001) + r7.xyz;
        r8.xyzw = r1.xyxy * float4(0.00666666683,0.00666666683,0.00777777797,0.00777777797) + float4(1,1,1,1);
        r8.xyzw = r4.xyxy * r8.xyzw + cbRadialScreenPos.xyxy;
        r8.xyzw = float4(0.5,0.5,0.5,0.5) + r8.xyzw;
        r9.xyz = SourceImage.SampleLevel(BilinearClamp_s, r8.xy, 0).xyz;
        r7.xyz = r9.xyz * float3(0.100000001,0.100000001,0.100000001) + r7.xyz;
        r8.xyz = SourceImage.SampleLevel(BilinearClamp_s, r8.zw, 0).xyz;
        r7.xyz = r8.xyz * float3(0.100000001,0.100000001,0.100000001) + r7.xyz;
        r1.xy = r1.xy * float2(0.0088888891,0.0088888891) + float2(1,1);
        r1.xy = r4.xy * r1.xy + cbRadialScreenPos.xy;
        r1.xy = float2(0.5,0.5) + r1.xy;
        r1.xyz = SourceImage.SampleLevel(BilinearClamp_s, r1.xy, 0).xyz;
        r1.xyz = r1.xyz * float3(0.100000001,0.100000001,0.100000001) + r7.xyz;
        r4.xyz = SourceImage.SampleLevel(BilinearClamp_s, r6.zw, 0).xyz;
        r1.xyz = r4.xyz * float3(0.100000001,0.100000001,0.100000001) + r1.xyz;
        r1.xyz = cbRadialColor.xyz * r1.xyz;
        r1.xyz = v2.xxx * r1.xyz;
        r4.xyz = invLinearBegin * r1.xyz;
        r6.xyz = cmp(r1.xyz >= linearBegin);
        r7.xyz = r4.xyz * r4.xyz;
        r8.xyz = -r4.xyz * float3(2,2,2) + float3(3,3,3);
        r7.xyz = r8.xyz * r7.xyz;
        r6.xyz = r6.xyz ? float3(1,1,1) : r7.xyz;
        r6.xyz = float3(1,1,1) + -r6.xyz;
        r7.xyz = cmp(linearStart >= r1.xyz);
        r7.xyz = r7.xyz ? float3(0,0,0) : float3(1,1,1);
        r8.xyz = float3(1,1,1) + -r6.xyz;
        r8.xyz = r8.xyz + -r7.xyz;
        r4.xyz = log2(r4.xyz);
        r4.xyz = toe * r4.xyz;
        r4.xyz = exp2(r4.xyz);
        r4.xyz = linearBegin * r4.xyz;
        r9.xyz = contrast * r1.xyz + madLinearStartContrastFactor;
        r8.xyz = r9.xyz * r8.xyz;
        r4.xyz = r4.xyz * r6.xyz + r8.xyz;
        r1.xyz = contrastFactor * r1.xyz + mulLinearStartContrastFactor;
        r1.xyz = exp2(r1.xyz);
        r1.xyz = -displayMaxNitSubContrastFactor * r1.xyz + maxNit;
        r1.xyz = r1.xyz * r7.xyz + r4.xyz;
        r4.xyz = cbRadialColor.xyz * r3.xyz;
        r5.xyz = r4.xyz * float3(0.100000001,0.100000001,0.100000001) + r1.xyz;
      }
      r0.x = cmp(0 < cbRadialMaskRate.x);
      if (r0.x != 0) {
        r0.x = sqrt(r3.w);
        r0.x = saturate(r0.x * cbRadialMaskSmoothstep.x + cbRadialMaskSmoothstep.y);
        r1.x = r0.x * r0.x;
        r0.x = -r0.x * 2 + 3;
        r0.x = r1.x * r0.x;
        r0.x = cbRadialMaskRate.x * r0.x + cbRadialMaskRate.y;
        r1.xyz = r5.xyz + -r3.xyz;
        r5.xyz = r0.xxx * r1.xyz + r3.xyz;
      }
      r1.xyz = r5.xyz + -r3.xyz;
      r3.xyz = r0.yyy * r1.xyz + r3.xyz;
    } else {
      r3.xyz = r2.xyz;
    }
  }
  r1.xyz = v1.xyz / v1.www;
  r0.x = dot(r1.xyz, r1.xyz);
  r0.x = rsqrt(r0.x);
  r0.x = r1.z * r0.x;
  r0.y = saturate(abs(r0.x) * kerare_scale + kerare_offset);
  r0.y = 1 + -r0.y;
  r0.x = abs(r0.x) * abs(r0.x);
  r0.x = r0.x * r0.x;
  r0.x = r0.x * r0.y;
  r0.x = min(1, r0.x);
  r1.xyz = r3.xyz * r0.xxx;
  if (r0.z != 0) {
    r0.yz = fNoiseUVOffset.xy * screenSize.xy + v0.xy;
    r0.yz = fReverseNoiseSize * r0.yz;
    r0.yz = floor(r0.yz);
    r1.w = dot(r0.yz, float2(0.0671105608,0.00583714992));
    r1.w = frac(r1.w);
    r1.w = 52.9829178 * r1.w;
    r1.w = frac(r1.w);
    r2.x = cmp(r1.w < fNoiseDensity);
    if (r2.x != 0) {
      r0.y = r0.y * r0.z;
      uint grain_hash_0 = ((uint)r0.y ^ 0x00bc602fu) * 0x003779b9u;
      grain_hash_0 = grain_hash_0 ^ (grain_hash_0 << 6) ^ (grain_hash_0 >> 26);
      r0.y = 2.32830644e-010 * (float)grain_hash_0;
    } else {
      r0.y = 0;
    }
    r0.z = 757.48468 * r1.w;
    r0.z = frac(r0.z);
    r1.w = cmp(r0.z < fNoiseDensity);
    if (r1.w != 0) {
      uint grain_hash_1 = (asuint(r0.z) ^ 0x00bc602fu) * 0x003779b9u;
      grain_hash_1 = grain_hash_1 ^ (grain_hash_1 << 6) ^ (grain_hash_1 >> 26);
      r1.w = (float)grain_hash_1 * 2.32830644e-010 + -0.5;
    } else {
      r1.w = 0;
    }
    r0.z = 757.48468 * r0.z;
    r0.z = frac(r0.z);
    r2.x = cmp(r0.z < fNoiseDensity);
    if (r2.x != 0) {
      uint grain_hash_2 = (asuint(r0.z) ^ 0x00bc602fu) * 0x003779b9u;
      grain_hash_2 = grain_hash_2 ^ (grain_hash_2 << 6) ^ (grain_hash_2 >> 26);
      r0.z = (float)grain_hash_2 * 2.32830644e-010 + -0.5;
    } else {
      r0.z = 0;
    }
    r2.xy = fNoisePower.xy * r0.yz * CUSTOM_NOISE;
    r2.z = fNoisePower.y * r1.w * CUSTOM_NOISE;
    r4.x = dot(r2.xz, float2(1,1.40199995));
    r4.y = dot(r2.xyz, float3(1,-0.344000012,-0.713999987));
    r4.z = dot(r2.xy, float2(1,1.77199996));
    r0.y = saturate(dot(r1.xyz, float3(0.298999995,-0.169,0.5)));
    r0.y = 1 + -r0.y;
    r0.y = log2(r0.y);
    r0.y = fNoiseContrast * r0.y;
    r0.y = exp2(r0.y);
    r0.y = fBlendRate * r0.y;
    r2.xyz = -r3.xyz * r0.xxx + r4.xyz;
    r1.xyz = r0.yyy * r2.xyz + r1.xyz;
  }
  float3 graded = r1.xyz;
  ApplyColorGrading(
      r1.x, r1.y, r1.z,
      graded.x, graded.y, graded.z,
      cPassEnabled,
      fTextureSize,
      fTextureBlendRate,
      fTextureBlendRate2,
      fTextureInverseSize,
      fColorMatrix,
      tTextureMap0,
      tTextureMap1,
      tTextureMap2,
      TrilinearClamp_s);
  r1.xyz = graded;
  r0.xy = cPassEnabled & int2(8,16);
  if (r0.x != 0) {
    r2.x = saturate(dot(r1.xyz, cvdR.xyz));
    r2.y = saturate(dot(r1.xyz, cvdG.xyz));
    r2.z = saturate(dot(r1.xyz, cvdB.xyz));
    r1.xyz = r2.xyz;
  }
  if (r0.y != 0) {
    r0.xy = screenInverseSize.xy * v0.xy;
    r2.xyzw = ImagePlameBase.SampleLevel(BilinearClamp_s, r0.xy, 0).xyzw;
    r3.xyzw = ColorParam.xyzw * r2.xyzw;
    r0.x = ImagePlameAlpha.SampleLevel(BilinearClamp_s, r0.xy, 0).x;
    r0.x = saturate(r0.x * Levels_Rate + Levels_Range);
    r0.x = r0.x * r3.w;
    r0.yzw = cmp(r3.xyz < float3(0.5,0.5,0.5));
    r3.xyz = r3.xyz * r1.xyz;
    r3.xyz = r3.xyz + r3.xyz;
    r2.xyz = -r2.xyz * ColorParam.xyz + float3(1,1,1);
    r2.xyz = r2.xyz + r2.xyz;
    r4.xyz = float3(1,1,1) + -r1.xyz;
    r2.xyz = -r2.xyz * r4.xyz + float3(1,1,1);
    r0.yzw = r0.yzw ? r3.xyz : r2.xyz;
    r0.yzw = r0.yzw + -r1.xyz;
    r1.xyz = r0.xxx * r0.yzw + r1.xyz;
  }
  o0.xyz = ApplyUserGradingAndToneMap(r1.xyz, v0.xy * screenInverseSize.xy);
  o0.w = 0;
  return;
}