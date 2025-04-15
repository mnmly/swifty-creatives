//
//  Feature1.swift
//  ExampleMacOSApp
//
//  Created by Yuki Kuwashima on 2024/08/03.
//

import SwiftyCreatives
import SwiftUI

final class Feature4: Sketch {

    enum StandardGeometry: Int {
        case rect
        case box
        case circle
        case triangle
        case line
        case boldline
        case image
        case svg
        case object3d
        mutating func toggleNext() {
            self = StandardGeometry(rawValue: self.rawValue + 1) ?? StandardGeometry(rawValue: 0)!
        }
    }
    var intensity: Float = 1.0

    var grayscaleShader: CustomShaderPrimitive!

    var frameCount = 0
    var currentGeometry: StandardGeometry = StandardGeometry(rawValue: 0)!

    let imgObj = Img().load(name: "apple", bundle: nil).adjustScale(with: .basedOnWidth).multiplyScale(1.2)
    var svgObj: SVGObj?
    let modelObj = ModelObject().loadModel(name: "sphere", extensionName: "obj")

    override init() {
        super.init()
        
        do {
                   // Initialize shaders - ensure pixel formats match your SketchView setup
                   // Make sure CustomShader.metal functions are compiled!
                   grayscaleShader = try CustomShaderPrimitive(
                       vertexFunctionName: "customVertexShaderPassthrough",
                       fragmentFunctionName: "customFragmentShaderGrayscaleOIT",
                       pixelFormat: .bgra8Unorm,         // Common format
                       depthPixelFormat: .depth32Float_stencil8, // Common format
                       blendingEnabled: false           // Grayscale is opaque
                       // library: specify if not in main bundle or SwiftyCreatives
                   )

        } catch {
                  fatalError("Failed to initialize custom shaders: \(error)")
                  // Handle error appropriately in a real app
              }
            
        DispatchQueue.main.async {
            Task {
                self.svgObj = await SVGObj(url: Bundle.main.url(forResource: "apple", withExtension: "svg")!)?
                    .normalizeScale(imageAdjustOption: .basedOnWidth)
                    .makeAnchorCenter()
                    .changeColors { currentColors in
                        return currentColors.map { _ in f4.randomPoint(0...1) }
                    }
            }
        }
    }

    override func update(camera: MainCamera) {
        frameCount += 1
//        if frameCount.isMultiple(of: 300) {
//            currentGeometry.toggleNext()
//        }
    }

    override func draw(encoder: SCEncoder) {
//        color(1, 1, 1, 1)
////        box(10)
//        push {
//            translate(10, 0, 0)
//            box(5)
//        }

        // 2. Draw a green box using the custom grayscale shader
      grayscaleShader.apply(encoder: encoder) {
          // Bind uniforms for the grayscale shader *before* drawing
          encoder.setFragmentBytes(&self.intensity, length: MemoryLayout<Float>.stride, index: 20) // Index 20 matches shader
      } _: { // No custom textures needed for this shader
          // Drawing commands that will use the grayscale shader
          color(0, 1, 0, 1) // Set base color (will be turned gray)
          push {
              translate(0, 0, 0)
              box(5)
          }
      } // End apply grayscaleShader
    }

    struct VIEW: View {
        var body: some View {
            VStack {
                Text("custom shader")
                SketchView(Feature4())
            }
        }
    }
}
