//
//  StickerMaker.swift
//  ImageDemo
//

import CoreImage
import CoreImage.CIFilterBuiltins
import CoreVideo
import UIKit
import Vision

enum StickerError: LocalizedError {
    case unreadable
    case noSubject
    case renderFailed
    case noPermission

    var errorDescription: String? {
        switch self {
        case .unreadable:
            "这张照片读不出来"
        case .noSubject:
            "没有找到清晰的主体，换一张试试"
        case .renderFailed:
            "贴纸生成失败了，再试一次"
        case .noPermission:
            "需要相册权限才能保存"
        }
    }
}

enum StickerMaker {
    /// 长边限制。Vision 和膨胀都在这张图上跑，避免原图太大卡住。
    private nonisolated static let maxSide: CGFloat = 1600

    nonisolated static func makePNG(from data: Data) throws -> Data {
        try autoreleasepool {
            guard let image = UIImage(data: data) else {
                throw StickerError.unreadable
            }
            let source = try rasterize(image, maxSide: maxSide)
            let sticker = try cutOut(source)
            guard let png = sticker.pngData() else {
                throw StickerError.renderFailed
            }
            return png
        }
    }

    nonisolated private static func rasterize(_ image: UIImage, maxSide: CGFloat) throws -> CGImage {
        let pixelWidth = image.size.width * image.scale
        let pixelHeight = image.size.height * image.scale
        guard pixelWidth > 1, pixelHeight > 1 else {
            throw StickerError.unreadable
        }
        let scale = min(1, maxSide / max(pixelWidth, pixelHeight))
        let size = CGSize(width: floor(pixelWidth * scale), height: floor(pixelHeight * scale))
        let format = UIGraphicsImageRendererFormat()
        format.scale = 1
        format.opaque = true
        let renderer = UIGraphicsImageRenderer(size: size, format: format)
        let rendered = renderer.image { _ in
            image.draw(in: CGRect(origin: .zero, size: size))
        }
        guard let cgImage = rendered.cgImage else {
            throw StickerError.unreadable
        }
        return cgImage
    }

    nonisolated private static func cutOut(_ source: CGImage) throws -> UIImage {
        let request = VNGenerateForegroundInstanceMaskRequest()
        let handler = VNImageRequestHandler(cgImage: source, orientation: .up, options: [:])
        do {
            try handler.perform([request])
        } catch {
            throw StickerError.renderFailed
        }

        guard let observation = request.results?.first else {
            throw StickerError.noSubject
        }
        let instances = observation.allInstances
        guard !instances.isEmpty else {
            throw StickerError.noSubject
        }

        let maskBuffer = try observation.generateScaledMaskForImage(forInstances: instances, from: handler)
        let subjectBuffer = try observation.generateMaskedImage(
            ofInstances: instances,
            from: handler,
            croppedToInstancesExtent: false
        )

        let maskImage = CIImage(cvPixelBuffer: maskBuffer)
        let subjectImage = align(CIImage(cvPixelBuffer: subjectBuffer), to: maskImage.extent)
        let composited = try stroke(subject: subjectImage, mask: maskImage, maskBuffer: maskBuffer)

        let context = CIContext(options: [
            .workingColorSpace: CGColorSpaceCreateDeviceRGB(),
            .useSoftwareRenderer: false
        ])
        guard let cgImage = context.createCGImage(composited.image, from: composited.crop) else {
            throw StickerError.renderFailed
        }
        return UIImage(cgImage: cgImage)
    }

    nonisolated private static func stroke(
        subject: CIImage,
        mask: CIImage,
        maskBuffer: CVPixelBuffer
    ) throws -> (image: CIImage, crop: CGRect) {
        let shortSide = min(mask.extent.width, mask.extent.height)
        let radius = min(64, max(24, Double(shortSide) * 0.04))
        let pad = CGFloat(radius) + 28
        let canvas = mask.extent.insetBy(dx: -pad, dy: -pad)

        let black = CIImage(color: CIColor(red: 0, green: 0, blue: 0)).cropped(to: canvas)
        let paddedMask = mask.composited(over: black)

        let morphology = CIFilter.morphologyMaximum()
        morphology.inputImage = paddedMask
        morphology.radius = Float(radius)
        guard let dilatedBase = morphology.outputImage else {
            throw StickerError.renderFailed
        }

        let blur = CIFilter.gaussianBlur()
        blur.inputImage = dilatedBase
        blur.radius = 1.2
        guard let dilated = blur.outputImage?.cropped(to: canvas) else {
            throw StickerError.renderFailed
        }

        let white = CIImage(color: CIColor(red: 1, green: 1, blue: 1)).cropped(to: canvas)
        let clear = CIImage(color: CIColor(red: 0, green: 0, blue: 0, alpha: 0)).cropped(to: canvas)
        let blend = CIFilter.blendWithMask()
        blend.inputImage = white
        blend.backgroundImage = clear
        blend.maskImage = dilated
        guard let strokeImage = blend.outputImage else {
            throw StickerError.renderFailed
        }

        let output = subject.composited(over: strokeImage).cropped(to: canvas)
        let crop = cropRect(maskBuffer: maskBuffer, maskExtent: mask.extent, radius: CGFloat(radius), canvas: canvas)
        return (output, crop)
    }

    /// 像素缓冲的第 0 行是画面顶部，CIImage 的 y 从底部起算。
    nonisolated private static func cropRect(
        maskBuffer: CVPixelBuffer,
        maskExtent: CGRect,
        radius: CGFloat,
        canvas: CGRect
    ) -> CGRect {
        let detected = foregroundBounds(maskBuffer: maskBuffer, extent: maskExtent)
        let source = detected ?? maskExtent
        let expanded = source.insetBy(dx: -(radius + 24), dy: -(radius + 24))
        let crop = expanded.intersection(canvas).integral.intersection(canvas)
        if crop.isNull || crop.width < 2 || crop.height < 2 {
            return canvas.integral.intersection(canvas)
        }
        return crop
    }

    nonisolated private static func foregroundBounds(maskBuffer: CVPixelBuffer, extent: CGRect) -> CGRect? {
        CVPixelBufferLockBaseAddress(maskBuffer, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(maskBuffer, .readOnly) }

        let width = CVPixelBufferGetWidth(maskBuffer)
        let height = CVPixelBufferGetHeight(maskBuffer)
        guard width > 0, height > 0, let base = CVPixelBufferGetBaseAddress(maskBuffer) else {
            return nil
        }

        let bytesPerRow = CVPixelBufferGetBytesPerRow(maskBuffer)
        let format = CVPixelBufferGetPixelFormatType(maskBuffer)
        var minX = width
        var minY = height
        var maxX = 0
        var maxY = 0
        var found = false
        let step = 2

        for y in stride(from: 0, to: height, by: step) {
            for x in stride(from: 0, to: width, by: step) {
                let on: Bool
                switch format {
                case kCVPixelFormatType_OneComponent8:
                    let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: UInt8.self)
                    on = row[x] > 16
                case kCVPixelFormatType_OneComponent32Float:
                    let row = base.advanced(by: y * bytesPerRow).assumingMemoryBound(to: Float.self)
                    on = row[x] > 0.08
                case kCVPixelFormatType_32BGRA:
                    let pixel = base.advanced(by: y * bytesPerRow + x * 4).assumingMemoryBound(to: UInt8.self)
                    on = pixel[0] > 16 || pixel[1] > 16 || pixel[2] > 16 || pixel[3] > 16
                default:
                    return nil
                }
                if on {
                    found = true
                    minX = min(minX, x)
                    minY = min(minY, y)
                    maxX = max(maxX, x)
                    maxY = max(maxY, y)
                }
            }
        }

        guard found else { return nil }

        let scaleX = extent.width / CGFloat(width)
        let scaleY = extent.height / CGFloat(height)
        let ciX = extent.minX + CGFloat(minX) * scaleX
        let ciWidth = CGFloat(maxX - minX + step) * scaleX
        let ciHeight = CGFloat(maxY - minY + step) * scaleY
        let ciY = extent.minY + (CGFloat(height - maxY - step) * scaleY)
        return CGRect(x: ciX, y: ciY, width: ciWidth, height: ciHeight)
    }

    nonisolated private static func align(_ image: CIImage, to extent: CGRect) -> CIImage {
        let source = image.extent
        guard source.width > 1, source.height > 1, extent.width > 1, extent.height > 1 else {
            return image
        }
        let scaleX = extent.width / source.width
        let scaleY = extent.height / source.height
        let movedToOrigin = image.transformed(by: CGAffineTransform(
            translationX: -source.origin.x,
            y: -source.origin.y
        ))
        let scaled = movedToOrigin.transformed(by: CGAffineTransform(scaleX: scaleX, y: scaleY))
        return scaled.transformed(by: CGAffineTransform(translationX: extent.origin.x, y: extent.origin.y))
    }
}
