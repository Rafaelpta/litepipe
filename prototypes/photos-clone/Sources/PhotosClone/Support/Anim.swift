import SwiftUI

/// Central animation constants, tuned side-by-side with Photos.app.
enum Anim {
    static let openDetail  = Animation.spring(response: 0.35, dampingFraction: 0.85)
    static let closeDetail = Animation.spring(response: 0.32, dampingFraction: 0.88)
    static let zoom        = Animation.spring(response: 0.30, dampingFraction: 0.90)
    static let selection   = Animation.easeOut(duration: 0.12)
    static let hover       = Animation.easeInOut(duration: 0.15)
    static let favorite    = Animation.spring(response: 0.25, dampingFraction: 0.60)
    static let drill       = Animation.spring(response: 0.35, dampingFraction: 0.86)
    static let crossfade   = Animation.easeInOut(duration: 0.18)
}
