import AppKit
import ImageIO
import UniformTypeIdentifiers

// Run from the repository root: swift tools/build_pixel32_assets.swift
let root = FileManager.default.currentDirectoryPath + "/assets"

func writeAsset(_ source: String, _ output: String, _ width: Int, _ height: Int, crop: CGRect? = nil) throws {
    let sourceURL = URL(fileURLWithPath: root + "/" + source)
    let outputURL = URL(fileURLWithPath: root + "/" + output)
    guard let imageSource = CGImageSourceCreateWithURL(sourceURL as CFURL, nil),
          let image = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
        fatalError("Could not read \(source)")
    }
    let sourceImage = crop.flatMap { image.cropping(to: $0) } ?? image
    let colorSpace = CGColorSpaceCreateDeviceRGB()
    guard let context = CGContext(data: nil, width: width, height: height, bitsPerComponent: 8,
                                  bytesPerRow: 0, space: colorSpace,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else {
        fatalError("Could not create canvas")
    }
    context.interpolationQuality = .none
    context.clear(CGRect(x: 0, y: 0, width: width, height: height))
    context.draw(sourceImage, in: CGRect(x: 0, y: 0, width: width, height: height))
    guard let result = context.makeImage(),
          let destination = CGImageDestinationCreateWithURL(outputURL as CFURL, UTType.png.identifier as CFString, 1, nil) else {
        fatalError("Could not write \(output)")
    }
    CGImageDestinationAddImage(destination, result, nil)
    guard CGImageDestinationFinalize(destination) else { fatalError("Could not finish \(output)") }
    print("\(output): \(width)x\(height)")
}

for i in 1...5 {
    try writeAsset("backgrounds/tiles/floor_grain_\(i).png", "backgrounds/tiles/floor_tile_\(i).png", 32, 32)
}
try writeAsset("backgrounds/tiles/wall.png", "backgrounds/tiles/wall_32.png", 32, 65)
try writeAsset("backgrounds/tiles/border.png", "backgrounds/tiles/border_32.png", 32, 8)
try writeAsset("backgrounds/restaurant.webp", "backgrounds/restaurant_wall_32.png", 608, 65,
               crop: CGRect(x: 0, y: 0, width: 1216, height: 130))
for name in ["stove", "sink", "serving_counter"] {
    try writeAsset("furniture/\(name).png", "furniture/\(name)_32.png", 64, 48)
}
try writeAsset("furniture/table.png", "furniture/table_32.png", 48, 32)
try writeAsset("furniture/chair.png", "furniture/chair_32.png", 28, 35)
try writeAsset("furniture/cash_register_counter.png", "furniture/cash_register_counter_32.png", 64, 19)
for name in ["chef", "customer"] {
    try writeAsset("characters/\(name).png", "characters/\(name)_32.png", 128, 176)
}
try writeAsset("items/meal.png", "items/meal_32.png", 40, 14)
try writeAsset("recipes/dishes.png", "recipes/dishes_32.png", 128, 128)
try writeAsset("ui/wood_board.png", "ui/wood_board_32.png", 112, 36)
