//
//  StampMaker.swift
//  ImageDemo
//

import CoreImage
import CoreImage.CIFilterBuiltins
import UIKit

enum StampError: LocalizedError {
    case unreadable
    case renderFailed

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "这张照片读不出来"
        case .renderFailed:
            "邮票生成失败了，再试一次"
        }
    }
}

nonisolated enum StampLook: String, CaseIterable, Identifiable, Sendable {
    case faded
    case silver
    case warm
    case classic

    var id: String { rawValue }

    var title: String {
        switch self {
        case .faded: "褪色"
        case .silver: "银盐"
        case .warm: "暖阳"
        case .classic: "旧照"
        }
    }

    var grain: CGFloat {
        switch self {
        case .faded: 0.4
        case .silver: 0.46
        case .warm: 0.32
        case .classic: 0.38
        }
    }
}

enum StampMaker {
    private nonisolated static let maxSide: CGFloat = 1600

    nonisolated static func makePNG(from data: Data, look: StampLook) throws -> Data {
        try autoreleasepool {
            guard let image = UIImage(data: data) else {
                throw StampError.unreadable
            }
            let source = try rasterize(image, maxSide: maxSide)
            let vintage = try applyVintage(to: source, look: look)
            let stamp = try renderStamp(from: vintage)
            guard let png = stamp.pngData() else {
                throw StampError.renderFailed
            }
            return png
        }
    }

    nonisolated private static func rasterize(_ image: UIImage, maxSide: CGFloat) throws -> CGImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 1, pixelHeight > 1 else {
            throw StampError.unreadable
        }
        let scale = min(1, maxSide / max(pixelWidth, pixelHeight))
        let size = CGSize(width: floor(pixelWidth * scale), height: floor(pixelHeight * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let rendered = UIGraphicsImageRenderer(size: size, format: format).image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = rendered.cgImage else {
            throw StampError.unreadable
        }
        return cgImage
    }

    nonisolated private static func applyVintage(to source: CGImage, look: StampLook) throws -> CGImage {
        let input = CIImage(cgImage: source)
        let toned = try tone(input, look: look)
        let grained = grain(over: toned, strength: look.grain)
        let context = CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .useSoftwareRenderer: false
        ])
        guard let cgImage = context.createCGImage(grained, from: toned.extent) else {
            throw StampError.renderFailed
        }
        return cgImage
    }

    nonisolated private static func tone(_ input: CIImage, look: StampLook) throws -> CIImage {
        switch look {
        case .faded:
            return try finish(
                input,
                brightness: 0.01,
                contrast: 1.04,
                saturation: 0.78,
                shadow: 0.08,
                vignette: 0.18
            )
        case .silver:
            return try finish(
                input,
                brightness: 0,
                contrast: 1.12,
                saturation: 0,
                shadow: 0.06,
                vignette: 0.2
            )
        case .warm:
            let warmth = CIFilter.temperatureAndTint()
            warmth.inputImage = input
            warmth.neutral = CIVector(x: 6500, y: 0)
            warmth.targetNeutral = CIVector(x: 4800, y: 6)
            return try finish(
                warmth.outputImage,
                brightness: 0,
                contrast: 1.05,
                saturation: 1.05,
                shadow: 0.05,
                vignette: 0.12
            )
        case .classic:
            let sepia = CIFilter.sepiaTone()
            sepia.inputImage = input
            sepia.intensity = 0.28
            return try finish(
                sepia.outputImage,
                brightness: 0,
                contrast: 1.05,
                saturation: 0.9,
                shadow: 0.08,
                vignette: 0.2
            )
        }
    }

    nonisolated private static func finish(
        _ image: CIImage?,
        brightness: Float,
        contrast: Float,
        saturation: Float,
        shadow: Float,
        vignette: Float
    ) throws -> CIImage {
        guard let image else { throw StampError.renderFailed }
        let controls = CIFilter.colorControls()
        controls.inputImage = image
        controls.brightness = brightness
        controls.contrast = contrast
        controls.saturation = saturation

        let lift = CIFilter.highlightShadowAdjust()
        lift.inputImage = controls.outputImage
        lift.shadowAmount = shadow
        lift.highlightAmount = 1

        let edge = CIFilter.vignette()
        edge.inputImage = lift.outputImage
        edge.intensity = vignette
        edge.radius = 2
        guard let output = edge.outputImage else {
            throw StampError.renderFailed
        }
        return output
    }

    /// 用放大的灰噪点做叠加，颗粒能看见，又不会给整张照片蒙上一层暗色。
    nonisolated private static func grain(over image: CIImage, strength: CGFloat) -> CIImage {
        guard strength > 0.01, let noise = CIFilter.randomGenerator().outputImage else {
            return image
        }
        let extent = image.extent
        let sampleScale: CGFloat = 0.55
        let sample = noise.cropped(to: CGRect(
            x: 0,
            y: 0,
            width: max(1, extent.width * sampleScale),
            height: max(1, extent.height * sampleScale)
        ))
        let enlarged = sample.transformed(by: CGAffineTransform(scaleX: 1 / sampleScale, y: 1 / sampleScale))
        let aligned = enlarged.transformed(by: CGAffineTransform(
            translationX: extent.minX - enlarged.extent.minX,
            y: extent.minY - enlarged.extent.minY
        )).cropped(to: extent)

        let gray = CIFilter.colorControls()
        gray.inputImage = aligned
        gray.saturation = 0
        gray.contrast = 1.25
        gray.brightness = 0
        guard let mono = gray.outputImage else { return image }

        let clamped = min(max(strength, 0), 1)
        let keep = 1 - clamped
        let matrix = CIFilter.colorMatrix()
        matrix.inputImage = mono
        matrix.rVector = CIVector(x: clamped, y: 0, z: 0, w: 0)
        matrix.gVector = CIVector(x: 0, y: clamped, z: 0, w: 0)
        matrix.bVector = CIVector(x: 0, y: 0, z: clamped, w: 0)
        matrix.aVector = CIVector(x: 0, y: 0, z: 0, w: 1)
        matrix.biasVector = CIVector(x: 0.5 * keep, y: 0.5 * keep, z: 0.5 * keep, w: 0)
        guard let grainImage = matrix.outputImage?.cropped(to: extent) else { return image }

        let overlay = CIFilter.overlayBlendMode()
        overlay.inputImage = grainImage
        overlay.backgroundImage = image
        return overlay.outputImage?.cropped(to: extent) ?? image
    }

    nonisolated private static func renderStamp(from photo: CGImage) throws -> UIImage {
        let photoSize = CGSize(width: photo.width, height: photo.height)
        let shortSide = min(photoSize.width, photoSize.height)
        let radius = min(34, max(12, shortSide * 0.022))
        let margin = radius * 2.15
        let canvas = CGSize(width: photoSize.width + margin * 2, height: photoSize.height + margin * 2)
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = false

        let rendered = UIGraphicsImageRenderer(size: canvas, format: format).image { renderer in
            let context = renderer.cgContext
            let bounds = CGRect(origin: .zero, size: canvas)
            let clip = perforationPath(size: canvas, radius: radius)
            clip.addClip()

            UIColor(red: 0.99, green: 0.97, blue: 0.93, alpha: 1).setFill()
            UIBezierPath(rect: bounds).fill()

            let photoRect = CGRect(x: margin, y: margin, width: photoSize.width, height: photoSize.height)
            context.interpolationQuality = .high
            UIImage(cgImage: photo).draw(in: photoRect)
            drawFrame(around: photoRect)
            drawMarkings(in: photoRect)
            drawPostmark(in: context, photoRect: photoRect)
        }
        guard rendered.cgImage != nil else {
            throw StampError.renderFailed
        }
        return rendered
    }

    nonisolated private static func perforationPath(size: CGSize, radius: CGFloat) -> UIBezierPath {
        let path = UIBezierPath(rect: CGRect(origin: .zero, size: size))
        let inset = radius * 2.4
        let pitch = radius * 2.7
        for x in punchCenters(length: size.width, inset: inset, pitch: pitch) {
            path.append(circle(center: CGPoint(x: x, y: 0), radius: radius))
            path.append(circle(center: CGPoint(x: x, y: size.height), radius: radius))
        }
        for y in punchCenters(length: size.height, inset: inset, pitch: pitch) {
            path.append(circle(center: CGPoint(x: 0, y: y), radius: radius))
            path.append(circle(center: CGPoint(x: size.width, y: y), radius: radius))
        }
        path.usesEvenOddFillRule = true
        return path
    }

    nonisolated private static func punchCenters(length: CGFloat, inset: CGFloat, pitch: CGFloat) -> [CGFloat] {
        let usable = length - inset * 2
        guard usable >= 0, pitch > 0 else { return [] }
        let count = Int(floor(usable / pitch)) + 1
        guard count > 1 else { return [] }
        let step = usable / CGFloat(count - 1)
        return (0..<count).map { inset + CGFloat($0) * step }
    }

    nonisolated private static func circle(center: CGPoint, radius: CGFloat) -> UIBezierPath {
        UIBezierPath(ovalIn: CGRect(
            x: center.x - radius,
            y: center.y - radius,
            width: radius * 2,
            height: radius * 2
        ))
    }

    nonisolated private static func drawFrame(around photoRect: CGRect) {
        let shortSide = min(photoRect.width, photoRect.height)
        let inset = shortSide * 0.04
        let outer = photoRect.insetBy(dx: inset, dy: inset)
        let line = max(2, shortSide * 0.004)
        let ink = UIColor(red: 0.36, green: 0.18, blue: 0.1, alpha: 0.72)
        ink.setStroke()
        let outerPath = UIBezierPath(rect: outer)
        outerPath.lineWidth = line
        outerPath.stroke()
        let innerPath = UIBezierPath(rect: outer.insetBy(dx: line * 3, dy: line * 3))
        innerPath.lineWidth = max(1, line * 0.55)
        innerPath.stroke()
    }

    nonisolated private static func drawMarkings(in photoRect: CGRect) {
        let shortSide = min(photoRect.width, photoRect.height)
        let ink = UIColor(red: 0.36, green: 0.18, blue: 0.1, alpha: 0.9)
        let frameInset = shortSide * 0.075
        let content = photoRect.insetBy(dx: frameInset, dy: frameInset)

        let titleFont = serifFont(shortSide * 0.052, weight: .bold)
        let title = "CHINA" as NSString
        let titleSize = title.size(withAttributes: [.font: titleFont])
        title.draw(
            at: CGPoint(x: content.midX - titleSize.width / 2, y: content.minY),
            withAttributes: [.font: titleFont, .foregroundColor: ink]
        )

        let valueFont = serifFont(shortSide * 0.064, weight: .semibold)
        let value = "1.20" as NSString
        let valueSize = value.size(withAttributes: [.font: valueFont])
        value.draw(
            at: CGPoint(
                x: content.maxX - valueSize.width,
                y: content.maxY - valueSize.height
            ),
            withAttributes: [.font: valueFont, .foregroundColor: ink]
        )
    }

    nonisolated private static func drawPostmark(in context: CGContext, photoRect: CGRect) {
        let shortSide = min(photoRect.width, photoRect.height)
        let radius = shortSide * 0.23
        let line = max(7, shortSide * 0.016)
        let ink = UIColor(red: 0.86, green: 0.07, blue: 0.09, alpha: 1)
        let halo = UIColor(white: 1, alpha: 0.72)
        let center = CGPoint(
            x: photoRect.midX + photoRect.width * 0.06,
            y: photoRect.midY - photoRect.height * 0.02
        )
        context.saveGState()
        context.translateBy(x: center.x, y: center.y)
        context.rotate(by: -0.28)
        context.setLineCap(.round)
        context.setLineJoin(.round)

        let outer = CGRect(x: -radius, y: -radius, width: radius * 2, height: radius * 2)
        let inner = CGRect(x: -radius * 0.8, y: -radius * 0.8, width: radius * 1.6, height: radius * 1.6)
        context.setStrokeColor(halo.cgColor)
        context.setLineWidth(line * 2.2)
        context.strokeEllipse(in: outer)
        context.strokeEllipse(in: inner)
        context.setStrokeColor(ink.cgColor)
        context.setLineWidth(line)
        context.strokeEllipse(in: outer)
        context.strokeEllipse(in: inner)

        let waves = postmarkWaves(radius: radius)
        waves.lineWidth = line * 2.2
        waves.lineCapStyle = .round
        halo.setStroke()
        waves.stroke()
        waves.lineWidth = line * 0.85
        ink.setStroke()
        waves.stroke()

        let dateFont = serifFont(radius * 0.36, weight: .black)
        let date = "15.10" as NSString
        let dateAttributes: [NSAttributedString.Key: Any] = [
            .font: dateFont,
            .foregroundColor: ink,
            .strokeColor: halo,
            .strokeWidth: -3
        ]
        let dateSize = date.size(withAttributes: dateAttributes)
        date.draw(
            at: CGPoint(x: -dateSize.width / 2, y: -dateSize.height / 2),
            withAttributes: dateAttributes
        )
        context.restoreGState()
    }

    nonisolated private static func postmarkWaves(radius: CGFloat) -> UIBezierPath {
        let waves = UIBezierPath()
        let amplitude = radius * 0.11
        let span = radius * 1.55
        for row in [-1, 1] {
            let baseline = CGFloat(row) * radius * 0.34
            waves.move(to: CGPoint(x: -span / 2, y: baseline))
            var x = -span / 2
            var up = true
            let step = radius * 0.2
            while x < span / 2 {
                let next = min(x + step, span / 2)
                let controlY = baseline + (up ? -amplitude : amplitude)
                waves.addQuadCurve(
                    to: CGPoint(x: next, y: baseline),
                    controlPoint: CGPoint(x: (x + next) / 2, y: controlY)
                )
                x = next
                up.toggle()
            }
        }
        return waves
    }

    nonisolated private static func serifFont(_ size: CGFloat, weight: UIFont.Weight) -> UIFont {
        let base = UIFont.systemFont(ofSize: size, weight: weight)
        let descriptor = base.fontDescriptor.withDesign(.serif) ?? base.fontDescriptor
        return UIFont(descriptor: descriptor, size: size)
    }
}
