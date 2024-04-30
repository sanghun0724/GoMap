//
//  LineDrawingLayer.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 4/27/24.
//  Copyright © 2024 Bryce Cogswell. All rights reserved.
//

import UIKit

class LineShapeLayer: CAShapeLayer {
	struct Properties {
		var position: OSMPoint?
		var lineWidth: CGFloat
	}

	fileprivate var props = Properties(position: nil, lineWidth: 0.0)

	// An array of paths, each simplified according to zoom level
	// so we have good performance when zoomed out:
	fileprivate var shapePaths = [CGPath?](repeating: nil, count: 32)

	var color: UIColor = .red {
		didSet {
			strokeColor = color.cgColor
			setNeedsLayout()
		}
	}

	override init(layer: Any) {
		let layer = layer as! LineShapeLayer
		props = layer.props
		shapePaths = layer.shapePaths
		color = layer.color
		super.init(layer: layer)
	}

	init(with points: [LatLon]) {
		super.init()
		var refPoint = OSMPoint.zero
		shapePaths = [CGPath?](repeating: nil, count: 32)
		shapePaths[0] = Self.path(for: points, refPoint: &refPoint)
		path = shapePaths[0]
		anchorPoint = CGPoint.zero
		position = CGPoint(refPoint)
		strokeColor = color.cgColor
		fillColor = nil
		lineWidth = 2.0
		lineCap = .square
		lineJoin = .miter
		zPosition = 0.0
		actions = actions
		props.position = refPoint
		props.lineWidth = lineWidth

		actions = [
			"onOrderIn": NSNull(),
			"onOrderOut": NSNull(),
			"hidden": NSNull(),
			"sublayers": NSNull(),
			"contents": NSNull(),
			"bounds": NSNull(),
			"position": NSNull(),
			"transform": NSNull(),
			"lineWidth": NSNull()
		]
	}

	@available(*, unavailable)
	required init?(coder: NSCoder) {
		fatalError("init(coder:) has not been implemented")
	}

	// Convert the points to a CGPath so we can draw it
	fileprivate static func path(for points: [LatLon], refPoint: inout OSMPoint) -> CGPath {
		var path = CGMutablePath()
		var initial = OSMPoint(x: 0, y: 0)
		var haveInitial = false
		var first = true

		for point in points {
			var pt = MapTransform.mapPoint(forLatLon: point)
			if pt.x.isInfinite {
				break
			}
			if !haveInitial {
				initial = pt
				haveInitial = true
			}
			pt.x -= initial.x
			pt.y -= initial.y
			pt.x *= PATH_SCALING
			pt.y *= PATH_SCALING
			if first {
				path.move(to: CGPoint(x: pt.x, y: pt.y))
				first = false
			} else {
				path.addLine(to: CGPoint(x: pt.x, y: pt.y))
			}
		}

		if haveInitial {
			// place refPoint at upper-left corner of bounding box so it can be the origin for the frame/anchorPoint
			let bbox = path.boundingBoxOfPath
			if !bbox.origin.x.isInfinite {
				var tran = CGAffineTransform(translationX: -bbox.origin.x, y: -bbox.origin.y)
				if let path2 = path.mutableCopy(using: &tran) {
					path = path2
				}
				refPoint = OSMPoint(x: initial.x + Double(bbox.origin.x) / PATH_SCALING,
				                    y: initial.y + Double(bbox.origin.y) / PATH_SCALING)
			} else {}
		}

		return path
	}
}

class LineDrawingLayer: CALayer {
	func allLineShapeLayers() -> [LineShapeLayer] { fatalError() } // superclass should implement this
	let mapView: MapView

	@available(*, unavailable)
	required init?(coder aDecoder: NSCoder) {
		fatalError()
	}

	init(mapView: MapView) {
		self.mapView = mapView
		super.init()

		actions = [
			"onOrderIn": NSNull(),
			"onOrderOut": NSNull(),
			"hidden": NSNull(),
			"sublayers": NSNull(),
			"contents": NSNull(),
			"bounds": NSNull(),
			"position": NSNull(),
			"transform": NSNull(),
			"lineWidth": NSNull()
		]

		// observe changes to geometry
		mapView.mapTransform.observe(by: self, callback: { self.setNeedsLayout() })

		setNeedsLayout()
	}

	// MARK: Drawing

	override var bounds: CGRect {
		get {
			return super.bounds
		}
		set(bounds) {
			super.bounds = bounds
			setNeedsLayout()
		}
	}

	func layoutSublayersSafe() {
		let tRotation = mapView.screenFromMapTransform.rotation()
		let tScale = mapView.screenFromMapTransform.scale()
		let pScale = tScale / PATH_SCALING
		var scale = Int(floor(-log(pScale)))
		if scale < 0 {
			scale = 0
		}

		for layer in allLineShapeLayers() {
			if layer.shapePaths[scale] == nil {
				let epsilon = pow(Double(10.0), Double(scale)) / 256.0
				layer.shapePaths[scale] = layer.shapePaths[0]?.pathWithReducedPoints(epsilon)
			}
			layer.path = layer.shapePaths[scale]

			// configure the layer for presentation
			guard let pt = layer.props.position else { return }
			let pt2 = OSMPoint(mapView.mapTransform.screenPoint(forMapPoint: pt, birdsEye: false))

			// rotate and scale
			var t = CGAffineTransform(translationX: CGFloat(pt2.x - pt.x), y: CGFloat(pt2.y - pt.y))
			t = t.scaledBy(x: CGFloat(pScale), y: CGFloat(pScale))
			t = t.rotated(by: CGFloat(tRotation))
			layer.setAffineTransform(t)

			layer.lineWidth = layer.props.lineWidth / CGFloat(pScale)

			// add the layer if not already present
			if layer.superlayer == nil {
				insertSublayer(layer, at: UInt32(sublayers?.count ?? 0)) // place at bottom
			}
		}

		if mapView.mapTransform.birdsEyeRotation != 0 {
			var t = CATransform3DIdentity
			t.m34 = -1.0 / CGFloat(mapView.mapTransform.birdsEyeDistance)
			t = CATransform3DRotate(t, CGFloat(mapView.mapTransform.birdsEyeRotation), 1.0, 0, 0)
			sublayerTransform = t
		} else {
			sublayerTransform = CATransform3DIdentity
		}
	}

	override func layoutSublayers() {
		if !isHidden {
			layoutSublayersSafe()
		}
	}
}
