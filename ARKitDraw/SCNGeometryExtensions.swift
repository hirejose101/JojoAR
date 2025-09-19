import Foundation
import SceneKit

extension SCNGeometry {
    static func lineGeometry(from startPoint: SCNVector3, to endPoint: SCNVector3, color: UIColor = .white) -> SCNGeometry {
        // Create a simple line geometry (thickness will be handled by cylinders in ViewController)
        let vertices = [startPoint, endPoint]
        let vertexData = NSData(bytes: vertices, length: MemoryLayout<SCNVector3>.size * vertices.count) as Data
        
        let vertexSource = SCNGeometrySource(data: vertexData,
                                           semantic: .vertex,
                                           vectorCount: vertices.count,
                                           usesFloatComponents: true,
                                           componentsPerVector: 3,
                                           bytesPerComponent: MemoryLayout<Float>.size,
                                           dataOffset: 0,
                                           dataStride: MemoryLayout<SCNVector3>.stride)
        
        let indices: [Int32] = [0, 1]
        let indexData = NSData(bytes: indices, length: MemoryLayout<Int32>.size * indices.count) as Data
        
        let element = SCNGeometryElement(data: indexData,
                                       primitiveType: .line,
                                       primitiveCount: 1,
                                       bytesPerIndex: MemoryLayout<Int32>.size)
        
        let geometry = SCNGeometry(sources: [vertexSource], elements: [element])
        
        // Set up material with enhanced visibility
        let material = SCNMaterial()
        material.diffuse.contents = color
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.emission.contents = color // Add emission for better visibility
        material.emission.intensity = 0.8 // High intensity for better visibility
        
        geometry.materials = [material]
        
        return geometry
    }
}