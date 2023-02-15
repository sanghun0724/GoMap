//
//  MapMarkerButton.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/6/23.
//  Copyright © 2023 Bryce. All rights reserved.
//

import UIKit

@IBDesignable
final class MapMarkerButton: MapView.MapViewButton {
	enum TextOrImage {
		case text(String)
		case image(UIImage)
	}

	let radius: CGFloat // radius of ciruclar part
	let height: CGFloat // distance from center of circle to bottom vertex
	let isCurvy: Bool

	static let PreferredRadius = 18.0

	init(radius: CGFloat = PreferredRadius, height: CGFloat = 15.0 + 18.0, isCurvy: Bool = true, label: TextOrImage) {
		arrowPoint = CGPoint.zero
		self.radius = radius
		self.height = height
		self.isCurvy = isCurvy
		super.init(frame: CGRect.zero)

		// build the path for it, starting at the bottom vertex
		let arcAngle = asin(radius / height)
		let path = UIBezierPath()
		if isCurvy {
			// The botton portion is more pointy
			let radius2 = (height * height / radius - radius) / 2
			path.addArc(withCenter: CGPoint(x: radius - radius2, y: height + radius),
			            radius: radius2,
			            startAngle: 0.0,
			            endAngle: -arcAngle,
			            clockwise: false)
			path.addArc(withCenter: CGPoint(x: radius, y: radius),
			            radius: radius,
			            startAngle: Double.pi - arcAngle,
			            endAngle: arcAngle,
			            clockwise: true)
			path.addArc(withCenter: CGPoint(x: radius + radius2, y: height + radius),
			            radius: radius2,
			            startAngle: Double.pi + arcAngle,
			            endAngle: Double.pi,
			            clockwise: false)
			path.close()
		} else {
			// The bottom portion is a simple triangle
			path.move(to: CGPoint(x: radius, y: height + radius))
			path.addArc(withCenter: CGPoint(x: radius, y: radius),
			            radius: radius,
			            startAngle: Double.pi - arcAngle,
			            endAngle: arcAngle,
			            clockwise: true)
			path.close()
		}

		let shapeLayer = CAShapeLayer()
		shapeLayer.fillColor = UIColor.blue.cgColor
		shapeLayer.strokeColor = UIColor.blue.cgColor
		shapeLayer.borderWidth = 2.0
		shapeLayer.path = path.cgPath

		let labelLayer: CALayer
		switch label {
		case let .image(image):
			labelLayer = CALayer()
			labelLayer.contents = image.cgImage
			labelLayer.frame = CGRect(x: 1, y: 1, width: 2 * radius - 2, height: 2 * radius - 2)
		case let .text(text):
			let textLayer = CATextLayer()
			textLayer.string = text
			textLayer.font = UIFont.preferredFont(forTextStyle: .caption1)
			textLayer.fontSize = 20
			textLayer.foregroundColor = UIColor.black.cgColor
			textLayer.alignmentMode = .center
			textLayer.contentsScale = UIScreen.main.scale
			labelLayer = textLayer
			// FIXME: This doesn't reliably center the text in the button
			let font = UIFont(name: (textLayer.font as! UIFont).fontName,
							  size: textLayer.fontSize)!
			let size = (text as NSString).size(withAttributes: [ NSAttributedString.Key.font: font ])
			labelLayer.frame = CGRect(x: 0, y: (2*radius - size.height)/2, width: 2 * radius, height: 2 * radius)
		}
		shapeLayer.addSublayer(labelLayer)

		layer.addSublayer(shapeLayer)
	}

	convenience init(withLabel label: TextOrImage) {
		self.init(label: label)
	}

	override func hitTest(_ point: CGPoint, with event: UIEvent?) -> UIView? {
		let rect = CGRect(x: 0, y: 0, width: 2*radius, height: 2*radius)
		if rect.contains(point) {
			return self
		}
		return nil
	}

	static func imageFrom(string: String) -> UIImage {
		let size = 2 * (Self.PreferredRadius - 2)
		let image = Self.imageFrom(string: string,
		                           withAttributes: [
		                           	.foregroundColor: UIColor.white,
		                           	.font: UIFont.systemFont(ofSize: 30.0)
		                           ],
		                           size: CGSize(width: size, height: size))
		return image!
	}

	private static func imageFrom(string: String,
	                              withAttributes attributes: [NSAttributedString.Key: Any],
	                              size: CGSize?) -> UIImage?
	{
		let size = size ?? (string as NSString).size(withAttributes: attributes)
		return UIGraphicsImageRenderer(size: size).image { _ in
			(string as NSString).draw(in: CGRect(origin: .zero, size: size),
			                          withAttributes: attributes)
		}
	}

	var arrowPoint: CGPoint {
		didSet {
			frame = CGRect(x: arrowPoint.x - radius,
			               y: arrowPoint.y - (height + radius),
			               width: 2 * radius,
			               height: height + radius)
		}
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}
}
