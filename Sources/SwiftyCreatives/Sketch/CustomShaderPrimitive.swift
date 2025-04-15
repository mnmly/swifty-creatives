//
//  CustomShaderPrimitive.swift
//  SwiftyCreatives
//
//  Created by HIROAKI YAMANE on 14/04/2025.
//

import MetalKit

enum CustomShaderError: Error {
    case functionNotFound(String)
    case pipelineCreationFailed(Error)
}

public class CustomShaderPrimitive {

    public let customPipelineState: MTLRenderPipelineState
    public let customDepthStencilState: MTLDepthStencilState // Keep depth testing consistent

    /// Initializes a custom shader primitive helper.
    /// - Parameters:
    ///   - vertexFunctionName: The name of your custom vertex function in the Metal library.
    ///   - fragmentFunctionName: The name of your custom fragment function in the Metal library.
    ///   - pixelFormat: The pixel format of the render target (usually from the MTKView).
    ///   - depthPixelFormat: The depth/stencil format of the render target (usually from the MTKView).
    ///   - blendingEnabled: Set to true if your fragment shader outputs non-opaque colors that need blending.
    ///   - library: The Metal library containing your shaders (default: main bundle's library or SwiftyCreatives' library).
    public init(
        vertexFunctionName: String,
        fragmentFunctionName: String,
        pixelFormat: MTLPixelFormat, // e.g., .bgra8Unorm
        depthPixelFormat: MTLPixelFormat, // e.g., .depth32Float_stencil8
        blendingEnabled: Bool = false, // Default to opaque
        library: MTLLibrary = ShaderCore.mainLibrary ?? ShaderCore.library // Prefer main bundle
    ) throws {

        guard let vertexFunction = library.makeFunction(name: vertexFunctionName) else {
            throw CustomShaderError.functionNotFound(vertexFunctionName)
        }
        guard let fragmentFunction = library.makeFunction(name: fragmentFunctionName) else {
            throw CustomShaderError.functionNotFound(fragmentFunctionName)
        }

        // --- Create Pipeline State ---
        let pipelineDescriptor = MTLRenderPipelineDescriptor()
        pipelineDescriptor.vertexFunction = vertexFunction
        pipelineDescriptor.fragmentFunction = fragmentFunction

        // Use the standard SwiftyCreatives vertex descriptor so attributes match
        pipelineDescriptor.vertexDescriptor = RendererBase.createVertexDescriptor()

        // Configure color attachment to match the view/renderer
        pipelineDescriptor.colorAttachments[0].pixelFormat = pixelFormat

        // Configure blending based on parameter
        pipelineDescriptor.colorAttachments[0].isBlendingEnabled = blendingEnabled
        if blendingEnabled {
            // Standard alpha blending, adjust if needed
            pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].rgbBlendOperation = .add
            pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = .sourceAlpha
            pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
            pipelineDescriptor.colorAttachments[0].alphaBlendOperation = .add
        }

        // Configure depth/stencil attachment
        pipelineDescriptor.depthAttachmentPixelFormat = depthPixelFormat
        pipelineDescriptor.stencilAttachmentPixelFormat = depthPixelFormat // Often the same

        do {
            customPipelineState = try ShaderCore.device.makeRenderPipelineState(descriptor: pipelineDescriptor)
        } catch {
            throw CustomShaderError.pipelineCreationFailed(error)
        }

        // --- Create Depth Stencil State ---
        // Use standard depth testing (less, write enabled) unless you need otherwise
        let depthDescriptor = MTLDepthStencilDescriptor()
        depthDescriptor.depthCompareFunction = .less
        depthDescriptor.isDepthWriteEnabled = true // Write depth for opaque parts
        guard let state = ShaderCore.device.makeDepthStencilState(descriptor: depthDescriptor) else {
             fatalError("Failed to create custom depth stencil state") // Or throw
        }
        customDepthStencilState = state
    }

    /// Applies the custom shader for a block of drawing commands.
    /// - Parameters:
    ///   - encoder: The current render command encoder provided in `Sketch.draw()`.
    ///   - uniforms: An optional closure to bind your custom vertex/fragment buffers *before* drawing.
    ///   - textures: An optional closure to bind your custom fragment textures *before* drawing.
    ///   - drawCommands: A closure containing the SwiftyCreatives drawing calls (e.g., `box()`, `sphere()`) that should use this custom shader.
    public func apply(
        encoder: SCEncoder,
        uniforms: (() -> Void)? = nil,
        textures: (() -> Void)? = nil,
        _ drawCommands: () -> Void
    ) {
         // --- Set Custom State ---
         encoder.setRenderPipelineState(customPipelineState)
         encoder.setDepthStencilState(customDepthStencilState) // Ensure consistent depth testing

         // --- Bind Custom Data ---
         // User binds their specific buffers/textures needed by *their* shader
         uniforms?()
         textures?()

         // --- Execute Drawing ---
         // The standard SwiftyCreatives functions (box, sphere, etc.) will now
         // use the pipeline state we just set. They will bind their own
         // vertex data, model matrices, color uniforms etc.
         drawCommands()

         // --- State Restoration ---
         // We don't explicitly restore the *previous* pipeline state.
         // We rely on the fact that the *next* standard SwiftyCreatives primitive
         // called *outside* this `apply` block, or the renderer's loop itself,
         // will set the default pipeline state required for that operation.
         // This works because primitive functions like box() don't set the pipeline state,
         // they assume it's already set by the Renderer.
    }
}
