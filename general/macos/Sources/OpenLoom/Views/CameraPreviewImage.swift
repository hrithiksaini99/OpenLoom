import SwiftUI

struct CameraPreview: View {
    let frame: CGImage?
    let mirrored: Bool

    var body: some View {
        ZStack {
            Color.black
            if let frame {
                Image(decorative: frame, scale: 1)
                    .resizable().scaledToFill()
                    .scaleEffect(x: mirrored ? -1 : 1, y: 1)
            } else {
                ProgressView("Waiting for camera frame…").tint(.white)
            }
        }.clipped()
    }
}
