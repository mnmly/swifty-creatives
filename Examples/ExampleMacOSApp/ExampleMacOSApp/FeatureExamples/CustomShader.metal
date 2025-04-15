//
//  CustomShader.metal
//  ExampleMacOSApp
//
//  Created by HIROAKI YAMANE on 14/04/2025.
//

// CustomShader.metal
#include <metal_stdlib>

// IMPORTANT: You need access to the type definitions used by SwiftyCreatives.
// The easiest way is often to ensure SwiftyCreatives is a dependency and
// the build system handles includes. If not, you might need to copy
// relevant struct definitions from SwiftyCreatives/Resources/Shaders/Types.metal
// and potentially functions from Functions.metal if you use them.
#include <SwiftyCreatives/Types.metal> // <-- This now works!
#include <SwiftyCreatives/Functions.metal> // <-- This works too!
#include <SwiftyCreatives/OIT.metal> // <-- And this!
#include <SwiftyCreatives/SharedIndices.h> // <-- And this!

using namespace metal;

// --- Vertex Shader Example (Pass-through) ---
// This vertex shader is compatible with standard SwiftyCreatives primitives.
// It takes the standard vertex input and produces the standard output.
vertex RasterizerData customVertexShaderPassthrough( const Vertex vIn [[ stage_in ]],
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

// --- Fragment Shader Example (Simple Grayscale with Intensity Uniform) ---
// Takes the standard RasterizerData and a custom uniform.
fragment half4 customFragmentShaderGrayscale(
    RasterizerData in [[stage_in]],
    constant float& intensity [[buffer(20)]], // *** CUSTOM UNIFORM at index 20 ***
    const device FrameUniforms_HasTexture &uniformHasTexture [[ buffer(FragmentBuffer_HasTexture) ]], // Check if texture is bound
    texture2d<half, access::sample> tex [[ texture(FragmentTexture_MainTexture) ]] // Standard texture
) {
    half4 baseColor = half4(in.color);

    // Optionally handle texture if bound by SwiftyCreatives primitive
    if (uniformHasTexture.value) {
        constexpr sampler textureSampler (coord::normalized, address::repeat, filter::linear);
        baseColor = tex.sample(textureSampler, in.uv);
    }

    // Apply custom effect (grayscale)
    half gray = dot(baseColor.rgb, half3(0.299h, 0.587h, 0.114h));
    // Use the custom intensity uniform
    return half4(gray * half(intensity), gray * half(intensity), gray * half(intensity), baseColor.a);
}

// --- Fragment Shader Example (Invert Color) ---
fragment half4 customFragmentShaderInvert(
    RasterizerData in [[stage_in]]
    // Add uniforms or textures if needed
) {
    return half4(1.0h - in.color.r, 1.0h - in.color.g, 1.0h - in.color.b, in.color.a);
}


template <typename OITDataT>
void OITFragmentFunction(RasterizerData in,
                         OITDataT oitData,
                         float intensity,
                         FrameUniforms_HasTexture uniformHasTexture,
                         FrameUniforms_FogDensity uniformFogDensity,
                         FrameUniforms_FogColor uniformFogColor,
                         texture2d<half> tex) {
    const float depth = in.position.z / in.position.w;
    
    half4 baseColor = half4(in.color);
    // Optionally handle texture if bound by SwiftyCreatives primitive
    if (uniformHasTexture.value) {
        constexpr sampler textureSampler (coord::normalized, address::repeat, filter::linear);
        baseColor = tex.sample(textureSampler, in.uv);
    }

    // Apply custom effect (grayscale)
    half gray = dot(baseColor.rgb, half3(0.299h, 0.587h, 0.114h));
    // Use the custom intensity uniform
    half4 fragmentColor = half4(gray * half(intensity), gray * half(intensity), gray * half(intensity), baseColor.a);
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
customFragmentShaderGrayscaleOIT(RasterizerData in [[ stage_in ]],
                           OITImageblock<4> oitImageblock [[ imageblock_data ]],
                           constant float& intensity [[buffer(20)]], // *** CUSTOM UNIFORM at index 20 ***
                           const device FrameUniforms_HasTexture &uniformHasTexture [[ buffer(FragmentBuffer_HasTexture) ]],
                           const device FrameUniforms_FogDensity &fogDensity [[ buffer(FragmentBuffer_FogDensity) ]],
                           const device FrameUniforms_FogColor &fogColor [[ buffer(FragmentBuffer_FogColor) ]],
                           texture2d<half, access::sample> tex [[ texture(FragmentTexture_MainTexture) ]]) {
    OITFragmentFunction(in, &oitImageblock.oitData, intensity, uniformHasTexture, fogDensity, fogColor, tex);
    FragOut<4> Out;
    Out.aoitImageBlock = oitImageblock;
    return Out;
}

