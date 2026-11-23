// 生成「灵感集」桌面图标(1024×1024)
// 设计:暖琥珀渐变底(延续 App 品牌色 #E8862E 家族)+ 白色灯泡 + 琥珀色闪电灯丝
//       + 灯泡右上方两粒白色火星(灵感冒出来的瞬间)。macOS 直跑:swift scripts/gen_appicon.swift
import AppKit
import CoreGraphics

let size = 1024

func makeIcon() -> CGImage {
    let space = CGColorSpace(name: CGColorSpace.sRGB)!
    let ctx = CGContext(data: nil, width: size, height: size, bitsPerComponent: 8,
                        bytesPerRow: 0, space: space,
                        bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!

    // 1) 对角渐变底:左上亮琥珀 → 右下深橙
    let bg = CGGradient(colorsSpace: space, colors: [
        CGColor(red: 0.965, green: 0.678, blue: 0.345, alpha: 1),   // #F6AD58
        CGColor(red: 0.855, green: 0.369, blue: 0.078, alpha: 1),   // #DA5E14
    ] as CFArray, locations: [0, 1])!
    ctx.drawLinearGradient(bg, start: CGPoint(x: 0, y: CGFloat(size)),
                           end: CGPoint(x: CGFloat(size), y: 0), options: [])

    // 2) 左上柔和高光,给底一点体积
    ctx.saveGState()
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.10))
    ctx.fillEllipse(in: CGRect(x: -260, y: CGFloat(size) - 620, width: 980, height: 980))
    ctx.restoreGState()

    // 3) 灯泡玻璃:白色实心圆,圆心略高于画布中心、整体微左移给火星留白
    let bulbCenter = CGPoint(x: 498, y: 498)
    let bulbR: CGFloat = 252
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: bulbCenter.x - bulbR, y: bulbCenter.y - bulbR,
                               width: bulbR * 2, height: bulbR * 2))

    // 4) 灯座:白色圆角矩形 + 两道底色螺纹
    let baseX = bulbCenter.x - 76
    let baseY = bulbCenter.y - bulbR - 148   // 与玻璃底部搭接
    let baseRect = CGRect(x: baseX, y: baseY, width: 152, height: 128)
    let base = CGPath(roundedRect: baseRect, cornerWidth: 26, cornerHeight: 26, transform: nil)
    ctx.addPath(base)
    ctx.fillPath()
    // 螺纹:两道横贯灯座的底色条
    ctx.setFillColor(CGColor(red: 0.909, green: 0.525, blue: 0.180, alpha: 1))
    for dy: CGFloat in [58, 26] {
        ctx.fill(CGRect(x: baseX + 14, y: baseY + dy, width: 152 - 28, height: 15))
    }

    // 5) 闪电灯丝(灯泡内的负空间):琥珀色闪电,倾斜 8° 更有"一闪"的动势
    ctx.saveGState()
    ctx.translateBy(x: bulbCenter.x, y: bulbCenter.y)
    ctx.rotate(by: 8 * .pi / 180)
    let bolt = CGMutablePath()
    let p = { (dx: CGFloat, dy: CGFloat) in CGPoint(x: dx, y: dy) }
    bolt.move(to: p(38, 170))
    bolt.addLine(to: p(-88, 26))
    bolt.addLine(to: p(-8, 26))
    bolt.addLine(to: p(-38, -170))
    bolt.addLine(to: p(88, -30))
    bolt.addLine(to: p(8, -30))
    bolt.closeSubpath()
    ctx.addPath(bolt)
    ctx.setFillColor(CGColor(red: 0.909, green: 0.525, blue: 0.180, alpha: 1))   // #E8862E
    ctx.fillPath()
    ctx.restoreGState()

    // 6) 两粒白色火星:灵感冒出灯泡的瞬间
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
    ctx.fillEllipse(in: CGRect(x: 806, y: 812, width: 58, height: 58))
    ctx.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 0.75))
    ctx.fillEllipse(in: CGRect(x: 886, y: 712, width: 34, height: 34))

    return ctx.makeImage()!
}

let outPath = URL(fileURLWithPath: CommandLine.arguments.count > 1
    ? CommandLine.arguments[1]
    : "IdeaFlow/Assets.xcassets/AppIcon.appiconset/AppIcon.png")
let rep = NSBitmapImageRep(cgImage: makeIcon())
guard let png = rep.representation(using: .png, properties: [:]) else {
    FileHandle.standardError.write("png encode failed\n".data(using: .utf8)!)
    exit(1)
}
try! png.write(to: outPath)
print("wrote \(outPath.path)")
