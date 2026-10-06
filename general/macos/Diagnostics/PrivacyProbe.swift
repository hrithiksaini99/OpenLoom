import Darwin
import Foundation

// Separate diagnostic executable, signed with the app's exact entitlements.
// It sends no payload and attempts only loopback. It is never part of the app process.
@main
enum PrivacyProbe {
    static func main() {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else {
            if errno == EPERM || errno == EACCES { print("PASS: sandbox denied socket creation"); return }
            fputs("FAIL: socket could not be created for an unrelated reason\n", stderr)
            exit(1)
        }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = UInt16(9).bigEndian
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) { pointer in
            pointer.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                connect(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        let denied = result == -1 && (errno == EPERM || errno == EACCES)
        if denied { print("PASS: sandbox denied a loopback connection with no payload") }
        else {
            fputs("FAIL: connection was not rejected by the sandbox (errno \(errno))\n", stderr)
            exit(1)
        }
    }
}
