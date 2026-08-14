//
//  ContentView.swift
//  QuakeGlobe
//
//  Created by Lucas on 14/08/26.
//

import SwiftUI
import SceneKit

struct ContentView: View {
    var body: some View {
        GlobeView()
            .ignoresSafeArea()
            .background(Color.black)
    }
}

struct GlobeView: UIViewRepresentable {
    func makeUIView(context: Context) -> SCNView {
        let scnView = SCNView()
        scnView.backgroundColor = .black
        scnView.allowsCameraControl = true
        scnView.autoenablesDefaultLighting = true
        scnView.antialiasingMode = .multisampling4X
        
        let scene = SCNScene()
        
        // Esfera da Terra
        let earth = SCNSphere(radius: 1.0)
        earth.segmentCount = 96
        
        let earthMaterial = SCNMaterial()
        earthMaterial.diffuse.contents = UIImage(named: "earth_texture")
        earthMaterial.diffuse.mipFilter = .linear
        earth.materials = [earthMaterial]
        
        let earthNode = SCNNode(geometry: earth)
        scene.rootNode.addChildNode(earthNode)
        
        scnView.scene = scene
        return scnView
    }
    
    func updateUIView(_ uiView: SCNView, context: Context) {}
}

#Preview {
    ContentView()
}
