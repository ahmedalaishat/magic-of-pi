import simd

/// Smoothing helpers for the 3D cameras.
enum Motion {
    /// Smoothstep of x clamped to 0...1: eases in and out.
    static func ease(_ x: Float) -> Float {
        let t = min(max(x, 0), 1)
        return t * t * (3 - 2 * t)
    }

    /// Critically damped spring step (implicit Euler, stable for any frame time).
    static func spring<T: SIMD>(_ x: inout T, _ v: inout T, to target: T, omega: Float, dt: Float) where T.Scalar == Float {
        let f = 1 + 2 * dt * omega
        let oo = omega * omega, hoo = dt * oo, hhoo = dt * hoo
        let inverse = 1 / (f + hhoo)
        let nextX = (x * f + v * dt + target * hhoo) * inverse
        let nextV = (v + (target - x) * hoo) * inverse
        x = nextX
        v = nextV
    }

    static func spring(_ x: inout Float, _ v: inout Float, to target: Float, omega: Float, dt: Float) {
        var vx = SIMD2<Float>(x, 0), vv = SIMD2<Float>(v, 0)
        spring(&vx, &vv, to: SIMD2(target, 0), omega: omega, dt: dt)
        x = vx.x
        v = vv.x
    }

    /// A point `distance` away from `center` in the direction given by yaw (around y) and pitch.
    static func orbit(_ center: SIMD3<Float>, distance: Float, yaw: Float, pitch: Float) -> SIMD3<Float> {
        center + SIMD3(sin(yaw) * cos(pitch), sin(pitch), cos(yaw) * cos(pitch)) * distance
    }
}
