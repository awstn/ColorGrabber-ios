import Foundation

/// One color in OKLCH: lightness (0 to 1), chroma (0 is gray), hue angle in degrees (0 to 360).
struct OKLCH {
    let lightness: Double
    let chroma: Double
    let hue: Double
}

enum ColorConversion {
    /// Converts 8-bit sRGB (0 to 255 per channel) to OKLCH.
    /// Steps: sRGB -> linear light -> LMS (cone-like response) -> OKLab -> OKLCH.
    static func oklch(red: Double, green: Double, blue: Double) -> OKLCH {
        let r = linearized(red / 255)
        let g = linearized(green / 255)
        let b = linearized(blue / 255)

        let l = cbrt(0.4122214708 * r + 0.5363325363 * g + 0.0514459929 * b)
        let m = cbrt(0.2119034982 * r + 0.6806995451 * g + 0.1073969566 * b)
        let s = cbrt(0.0883024619 * r + 0.2817188376 * g + 0.6299787005 * b)

        let lightness = 0.2104542553 * l + 0.7936177850 * m - 0.0040720468 * s
        let a = 1.9779984951 * l - 2.4285922050 * m + 0.4505937099 * s
        let bAxis = 0.0259040371 * l + 0.7827717662 * m - 0.8086757660 * s

        // Chroma is the distance from gray; hue is the angle around it.
        let chroma = hypot(a, bAxis)
        var hue = atan2(bAxis, a) * 180 / .pi
        if hue < 0 { hue += 360 }

        return OKLCH(lightness: lightness, chroma: chroma, hue: hue)
    }

    /// Undoes sRGB's gamma curve so values are proportional to actual light.
    private static func linearized(_ value: Double) -> Double {
        value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
    }
}
