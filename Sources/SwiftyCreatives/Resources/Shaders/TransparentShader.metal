//
//  TransparentShader.metal
//
//  Original source code from Apple Inc. https://developer.apple.com/videos/play/tech-talks/605/
//  Modified by Yuki Kuwashima on 2022/12/14.
//
//  Copyright © 2017 Apple Inc.
//
//  Permission is hereby granted, free of charge, to any person obtaining a copy of this software and associated documentation files (the "Software"), to deal in the Software without restriction, including without limitation the rights to use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of the Software, and to permit persons to whom the Software is furnished to do so, subject to the following conditions:
//
//  The above copyright notice and this permission notice shall be included in all copies or substantial portions of the Software.
//
//  THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

#include <metal_stdlib>
#include "Functions.metal"
#include "OIT.metal"

using namespace metal;

// MARK: vertexTransform

vertex RasterizerData vertexTransform(Vertex vIn [[ stage_in ]],
                                      const device FrameUniforms_ModelPos& uniformModelPos [[ buffer(VertexBuffer_ModelPos) ]],
                                      const device FrameUniforms_ModelRot& uniformModelRot [[ buffer(VertexBuffer_ModelRot) ]],
                                      const device FrameUniforms_ModelScale& uniformModelScale [[ buffer(VertexBuffer_ModelScale) ]],
                                      const device FrameUniforms_ProjectionMatrix& uniformProjectionMatrix [[ buffer(VertexBuffer_ProjectionMatrix) ]],
                                      const device FrameUniforms_UseVertexColor& useVertexColor [[ buffer(VertexBuffer_UseVertexColor) ]],
                                      const device FrameUniforms_ViewMatrix& uniformViewMatrix [[ buffer(VertexBuffer_ViewMatrix) ]],
                                      const device FrameUniforms_CameraPos& uniformCameraPos [[ buffer(VertexBuffer_CameraPos) ]],
                                      const device float4& color [[ buffer(VertexBuffer_Color) ]],
                                      const device FrameUniforms_CustomMatrix& uniformCustomMatrix [[ buffer(VertexBuffer_CustomMatrix) ]]
                                      ) {

    float4x4 modelMatrix = createModelMatrix(
                                             vIn,
                                             uniformModelPos,
                                             uniformModelRot,
                                             uniformModelScale,
                                             uniformProjectionMatrix,
                                             uniformViewMatrix,
                                             uniformCustomMatrix
                                             );
    
    RasterizerData rd;
    rd.worldPosition = (modelMatrix * float4(vIn.position, 1.0)).xyz;
    rd.surfaceNormal = (modelMatrix * float4(vIn.normal, 1.0)).xyz;
    rd.toCameraVector = uniformCameraPos.value - rd.worldPosition;
    rd.position = uniformProjectionMatrix.value * uniformViewMatrix.value * modelMatrix * float4(vIn.position, 1.0);
    rd.size = 1;
    if (useVertexColor.value) {
        rd.color = vIn.color;
    } else {
        rd.color = color;
    }
    rd.uv = vIn.uv;
    return rd;
}

vertex RasterizerData vertexTransform_vision(Vertex vIn [[ stage_in ]],
                                      const device FrameUniforms_ModelPos& uniformModelPos [[ buffer(VertexBuffer_ModelPos) ]],
                                      const device FrameUniforms_ModelRot& uniformModelRot [[ buffer(VertexBuffer_ModelRot) ]],
                                      const device FrameUniforms_ModelScale& uniformModelScale [[ buffer(VertexBuffer_ModelScale) ]],
                                      const device FrameUniforms_ProjectionMatrix* uniformProjectionMatrix [[ buffer(VertexBuffer_ProjectionMatrix) ]],
                                      const device FrameUniforms_UseVertexColor& useVertexColor [[ buffer(VertexBuffer_UseVertexColor) ]],
                                      const device FrameUniforms_ViewMatrix* uniformViewMatrix [[ buffer(VertexBuffer_ViewMatrix) ]],
                                      const device FrameUniforms_CameraPos& uniformCameraPos [[ buffer(VertexBuffer_CameraPos) ]],
                                      const device float4& color [[ buffer(VertexBuffer_Color) ]],
                                      const device FrameUniforms_CustomMatrix& uniformCustomMatrix [[ buffer(VertexBuffer_CustomMatrix) ]],
                                      ushort amp_id [[amplification_id]]
                                      ) {

    float4x4 modelMatrix = createModelMatrix(
                                             vIn,
                                             uniformModelPos,
                                             uniformModelRot,
                                             uniformModelScale,
                                             uniformProjectionMatrix[amp_id],
                                             uniformViewMatrix[amp_id],
                                             uniformCustomMatrix
                                             );
    
    RasterizerData rd;
    rd.worldPosition = (modelMatrix * float4(vIn.position, 1.0)).xyz;
    rd.surfaceNormal = (modelMatrix * float4(vIn.normal, 1.0)).xyz;
    rd.toCameraVector = uniformCameraPos.value - rd.worldPosition;
    rd.position = uniformProjectionMatrix[amp_id].value * uniformViewMatrix[amp_id].value * modelMatrix * float4(vIn.position, 1.0);
    if (useVertexColor.value) {
        rd.color = vIn.color;
    } else {
        rd.color = color;
    }
    rd.uv = vIn.uv;
    return rd;
}

// MARK: transparency

constant uint useDeviceMemory [[ function_constant(0) ]];

template <typename OITDataT>
void OITFragmentFunction(RasterizerData in,
                         OITDataT oitData,
                         FrameUniforms_HasTexture uniformHasTexture,
                         FrameUniforms_FogDensity uniformFogDensity,
                         FrameUniforms_FogColor uniformFogColor,
                         texture2d<half> tex) {
    const float depth = in.position.z / in.position.w;
    
    half4 fragmentColor = half4(in.color);
    fragmentColor.rgb *= (fragmentColor.a);
    
    if (uniformHasTexture.value) {
        constexpr sampler textureSampler (coord::pixel, address::clamp_to_edge, filter::linear);
        fragmentColor = tex.sample(textureSampler, float2(in.uv.x*tex.get_width(), in.uv.y*tex.get_height()));
    }

    if (fragmentColor.a == 0) {
        fragmentColor = half4(0, 0, 0, 0);
    }

    fragmentColor = half4(createFog(in.position.z / in.position.w,
                                    float4(fragmentColor),
                                    uniformFogDensity.value,
                                    uniformFogColor.value));
    
    InsertFragment(oitData, fragmentColor, depth, 1 - fragmentColor.a);
}

fragment FragOut<4>
OITFragmentFunction_4Layer(RasterizerData in [[ stage_in ]],
                           OITImageblock<4> oitImageblock [[ imageblock_data ]],
                           const device FrameUniforms_HasTexture &uniformHasTexture [[ buffer(FragmentBuffer_HasTexture) ]],
                           const device FrameUniforms_FogDensity &fogDensity [[ buffer(FragmentBuffer_FogDensity) ]],
                           const device FrameUniforms_FogColor &fogColor [[ buffer(FragmentBuffer_FogColor) ]],
                           texture2d<half, access::sample> tex [[ texture(FragmentTexture_MainTexture) ]]) {
    OITFragmentFunction(in, &oitImageblock.oitData, uniformHasTexture, fogDensity, fogColor, tex);
    FragOut<4> Out;
    Out.aoitImageBlock = oitImageblock;
    return Out;
}

kernel void OITClear_4Layer(imageblock<OITImageblock<4>, imageblock_layout_explicit> oitData,
                            ushort2 tid [[ thread_position_in_threadgroup ]]) {
    OITClear(oitData, tid);
}

fragment half4 OITResolve_4Layer(OITImageblock<4> oitImageblock [[ imageblock_data ]]) {
    return OITResolve(oitImageblock.oitData);
}

