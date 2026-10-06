import SwiftUI

// Select the long-standing property wrapper explicitly. macOS 27's SDK also exports
// a State macro whose plugin is absent from some Command Line Tools installations.
typealias ViewState<Value> = SwiftUI.State<Value>
