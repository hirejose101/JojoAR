    func createDrawingLine(from startPoint: SCNVector3, to endPoint: SCNVector3) -> SCNNode {
        let distance = startPoint.distance(vector: endPoint)
        
        // Create a cylinder with proper thickness
        let cylinder = SCNCylinder(radius: 0.008, height: CGFloat(distance)) // 8mm radius for good visibility
        let material = SCNMaterial()
        material.diffuse.contents = selectedBorderColor
        material.lightingModel = .constant
        material.isDoubleSided = true
        material.emission.contents = selectedBorderColor // Add emission for better visibility
        material.emission.intensity = 0.3
        cylinder.materials = [material]
        
        let cylinderNode = SCNNode(geometry: cylinder)
        
        // Position at midpoint
        let midPoint = SCNVector3(
            (startPoint.x + endPoint.x) / 2,
            (startPoint.y + endPoint.y) / 2,
            (startPoint.z + endPoint.z) / 2
        )
        cylinderNode.position = midPoint
        
        // Calculate direction vector
        let direction = SCNVector3(
            endPoint.x - startPoint.x,
            endPoint.y - startPoint.y,
            endPoint.z - startPoint.z
        )
        
        // Normalize direction
        let length = sqrt(direction.x * direction.x + direction.y * direction.y + direction.z * direction.z)
        if length > 0 {
            let normalizedDirection = SCNVector3(direction.x / length, direction.y / length, direction.z / length)
            
            // Create a proper rotation using lookAt approach
            let up = SCNVector3(0, 1, 0)
            
            // Calculate right vector (cross product of up and direction)
            let right = SCNVector3(
                up.y * normalizedDirection.z - up.z * normalizedDirection.y,
                up.z * normalizedDirection.x - up.x * normalizedDirection.z,
                up.x * normalizedDirection.y - up.y * normalizedDirection.x
            )
            
            // Normalize right vector
            let rightLength = sqrt(right.x * right.x + right.y * right.y + right.z * right.z)
            if rightLength > 0 {
                let normalizedRight = SCNVector3(right.x / rightLength, right.y / rightLength, right.z / rightLength)
                
                // Recalculate up vector (cross product of direction and right)
                let finalUp = SCNVector3(
                    normalizedDirection.y * normalizedRight.z - normalizedDirection.z * normalizedRight.y,
                    normalizedDirection.z * normalizedRight.x - normalizedDirection.x * normalizedRight.z,
                    normalizedDirection.x * normalizedRight.y - normalizedDirection.y * normalizedRight.x
                )
                
                // Create rotation matrix
                let rotationMatrix = SCNMatrix4(
                    m11: normalizedRight.x, m12: normalizedRight.y, m13: normalizedRight.z, m14: 0,
                    m21: finalUp.x, m22: finalUp.y, m23: finalUp.z, m24: 0,
                    m31: normalizedDirection.x, m32: normalizedDirection.y, m33: normalizedDirection.z, m34: 0,
                    m41: 0, m42: 0, m43: 0, m44: 1
                )
                
                // Apply rotation and translation
                let translation = SCNMatrix4MakeTranslation(0, 0, -Float(distance) / 2)
                cylinderNode.transform = SCNMatrix4Mult(translation, rotationMatrix)
            }
        }
        
        return cylinderNode
    }
