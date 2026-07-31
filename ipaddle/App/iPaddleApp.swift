import SwiftUI
import SpriteKit

@main
struct iPaddleApp: App {
    var body: some Scene {
        WindowGroup {
            GameContainerView()
        }
    }
}

struct GameContainerView: View {
    var body: some View {
        SpriteView(scene: MenuScene.make(), preferredFramesPerSecond: 120)
            .ignoresSafeArea()
            .statusBarHidden(true)
            .persistentSystemOverlays(.hidden)
            .background(Color.black)
    }
}
