//  Converted to Swift 5.4 by Swiftify v5.4.27034 - https://swiftify.com/
//
//  MercatorTileLayer.swift
//  OpenStreetMap
//
//  Created by Bryce Cogswell on 10/5/12.
//  Copyright (c) 2012 Bryce Cogswell. All rights reserved.
//

import QuartzCore

//let CUSTOM_TRANSFORM = 1

@inline(__always) func modulus(_ a: Int, _ n: Int) -> Int {
    var m = a % n
    if m < 0 {
        m += n
    }
    assert(m >= 0)
    return m
}

private func TileToWMSCoords(_ tx: Int, _ ty: Int, _ z: Int, _ projection: String) -> OSMPoint {
    let zoomSize = Double(1 << z)
    let lon = Double(tx) / zoomSize * .pi * 2 - .pi
    let lat = atan(sinh(.pi * (1 - Double(2 * ty) / zoomSize)))
    var loc: OSMPoint
    if projection == "EPSG:4326" {
        loc = OSMPointMake(lon * 180 / .pi, lat * 180 / .pi)
    } else {
        // EPSG:3857 and others
        loc = OSMPointMake(lon, log(tan((.pi / 2 + lat) / 2))) // mercatorRaw
        loc = Mult(loc, 20037508.34 / .pi)
    }
    return loc
}

@objcMembers
class MercatorTileLayer: CALayer, GetDiskCacheSize {
    
    var _webCache = PersistentWebCache<UIImage>()
    var _logoUrl: String = ""
    var _layerDict: [String : CALayer] = [:] // map of tiles currently displayed
    
    var mapView = MapView()
    var isPerformingLayout = AtomicInt(0)
    
    // MARK: Implementation
    
    override init(layer: Any) {
        super.init(layer: layer)
    }
    
    init(mapView: MapView) {
        super.init(layer: CALayer())
        //self.opaque = YES;
        
        needsDisplayOnBoundsChange = true
        
        // disable animations
        actions = [
            "onOrderIn": NSNull(),
            "onOrderOut": NSNull(),
            "sublayers": NSNull(),
            "contents": NSNull(),
            "bounds": NSNull(),
            "position": NSNull(),
            "anchorPoint": NSNull(),
            "transform": NSNull(),
            "isHidden": NSNull()
        ]
        
        self.mapView = mapView
        
        self.mapView.addObserver(self, forKeyPath: "screenFromMapTransform", options: [], context: nil)
    }
    
//    deinit {
//        mapView.removeObserver(self, forKeyPath: "screenFromMapTransform")
//    }

    private var _aerialService: AerialService?
    var aerialService: AerialService? {
        get {
            _aerialService
        }
        set(service) {
            if service == _aerialService {
                return
            }
            
            // remove previous data
            sublayers = nil
//            webCache = nil
            _layerDict.removeAll()
            
            // update service
            _aerialService = service
            if let service = service {
                _webCache = PersistentWebCache(name: service.identifier, memorySize: 20 * 1000 * 1000)
            }
            
            let expirationDate = Date(timeIntervalSinceNow: -7 * 24 * 60 * 60)
            purgeOldCacheItemsAsync(expirationDate)
            setNeedsLayout()
        }
    }
    
    
    override func observeValue(forKeyPath keyPath: String?, of object: Any?, change: [NSKeyValueChangeKey : Any]?, context: UnsafeMutableRawPointer?) {
        if (object as? MapView) == mapView && (keyPath == "screenFromMapTransform") {
//#if !CUSTOM_TRANSFORM
//            setAffineTransform(CGAffineTransformFromOSMTransform(mapView.screenFromMapTransform))
//#endif
            var t = CATransform3DIdentity
            t.m34 = -1 / (mapView.birdsEyeDistance)
            t = CATransform3DRotate(t, mapView.birdsEyeRotation, 1, 0, 0)
            sublayerTransform = t
            
            setNeedsLayout()
        }
    }
    
    func zoomLevel() -> Int {
        return aerialService!.roundZoomUp ? Int(ceil(mapView.zoom())): Int(floor(mapView.zoom()))
    }
    
    func metadata(_ callback: @escaping (Data?, Error?) -> Void) {
        if aerialService?.metadataUrl == nil {
            callback(nil, nil)
        } else {
            let rc = mapView.screenLongitudeLatitude()
            
            var zoomLevel = self.zoomLevel()
            if zoomLevel > 21 {
                zoomLevel = 21
            }
            
            let url = String(format: (aerialService?.metadataUrl)!, rc.origin.y + rc.size.height / 2, rc.origin.x + rc.size.width / 2, zoomLevel)
            
            var task: URLSessionDataTask? = nil
            if let url1 = URL(string: url) {
                task = URLSession.shared.dataTask(with: url1, completionHandler: { data, response, error in
                    DispatchQueue.main.async(execute: {
                        callback(data, error)
                    })
                })
            }
            task?.resume()
        }
    }
    
    func purgeTileCache() {
        _webCache.removeAllObjects()
        _layerDict.removeAll()
        sublayers = nil
        URLCache.shared.removeAllCachedResponses()
        setNeedsLayout()
    }
    
    func purgeOldCacheItemsAsync(_ expiration: Date) {
        _webCache.removeObjectsAsyncOlderThan(expiration)
    }
    
    func getDiskCacheSize(_ pSize: inout Int, count pCount: inout Int) {
        _webCache.getDiskCacheSize(&pSize, count: &pCount)
    }

    func layerOverlapsScreen(_ layer: CALayer) -> Bool {
        let rc = layer.frame
        let center = CGRectCenter(rc)
        
        var p1 = OSMPoint(x: Double(rc.origin.x), y: Double(rc.origin.y))
        var p2 = OSMPoint(x: Double(rc.origin.x), y: Double(rc.origin.y + rc.size.height))
        var p3 = OSMPoint(x: Double(rc.origin.x + rc.size.width), y: Double(rc.origin.y + rc.size.height))
        var p4 = OSMPoint(x: Double(rc.origin.x + rc.size.width), y: Double(rc.origin.y))
        
        p1 = ToBirdsEye(p1, center, Double(mapView.birdsEyeDistance), Double(mapView.birdsEyeRotation))
        p2 = ToBirdsEye(p2, center, Double(mapView.birdsEyeDistance), Double(mapView.birdsEyeRotation))
        p3 = ToBirdsEye(p3, center, Double(mapView.birdsEyeDistance), Double(mapView.birdsEyeRotation))
        p4 = ToBirdsEye(p4, center, Double(mapView.birdsEyeDistance), Double(mapView.birdsEyeRotation))
        
        let rect = OSMRectFromCGRect(rc)
        return OSMRectContainsPoint(rect, p1) || OSMRectContainsPoint(rect, p2) || OSMRectContainsPoint(rect, p3) || OSMRectContainsPoint(rect, p4)
    }

    func removeUnneededTiles(for rect: OSMRect, zoomLevel: Int) {
        let MAX_ZOOM = 30

        var removeList: [CALayer] = []
        
        // remove any tiles that don't intersect the current view
        for layer in sublayers ?? [] {
            if !layerOverlapsScreen(layer) {
                removeList.append(layer)
            }
        }
        for layer in removeList {
            let key = layer.value(forKey: "tileKey") as? String
            if let key = key {
				// DLog("prune \(key): \(layer)")
                _layerDict.removeValue(forKey: key)
                layer.removeFromSuperlayer()
                layer.contents = nil
            }
        }
        removeList.removeAll()
        
        // next remove objects that are covered by a parent (larger) object
        var layerList = [[CALayer]](repeating: [CALayer](), count: MAX_ZOOM)
        var transparent = [Bool](repeating: false, count: MAX_ZOOM) // some objects at this level are transparent
        // place each object in a zoom level bucket
        for layer in sublayers ?? [] {
            let tileKey = layer.value(forKey: "tileKey") as! String
			let z = Int( tileKey[..<tileKey.firstIndex(of: ",")!] )!
            if z < MAX_ZOOM {
                if layer.contents == nil {
                    transparent[z] = true
                }
				layerList[z].append(layer)
            }
        }
        
        // remove tiles at zoom levels less than us if we don't have any transparent tiles (we've tiled everything in greater detail)
        var remove = false
        var z = zoomLevel
        while z >= 0 {
            if remove {
				removeList.append(contentsOf: layerList[z])
            }
            if !transparent[z] {
                remove = true
            }
            z -= 1
        }
        
        // remove tiles at zoom levels greater than us if we're not transparent (we cover the more detailed tiles)
        remove = false
        for z in zoomLevel..<MAX_ZOOM {
            if remove {
				removeList.append(contentsOf: layerList[z])
            }
            if !transparent[z] {
                remove = true
            }
        }
        
        for layer in removeList {
            let key = layer.value(forKey: "tileKey") as? String
            if let key = key {
                // DLog("prune \(key): \(layer)")
                _layerDict.removeValue(forKey: key)
                layer.removeFromSuperlayer()
                layer.contents = nil
            }
        }
    }

    func isPlaceholderImage(_ data: Data?) -> Bool {
        if let data = data {
            return (aerialService!.placeholderImage as NSData?)?.isEqual(to: data) ?? false
        }
        return false
    }
    
    func quadKey(forZoom zoom: Int, tileX: Int, tileY: Int) -> String {
        return TileXYToQuadKey(tileX, tileY, zoom)
    }
    
    func url(forZoom zoom: Int, tileX: Int, tileY: Int) -> URL {
        var url = aerialService!.url
        
        // handle switch in URL
		if let begin = url.range(of: "{switch:"),
		   let end = url[begin.upperBound...].range(of: "}")
		{
			let list = url[begin.upperBound..<end.lowerBound].components(separatedBy: ",")
			if list.count > 0 {
				let t = list[(tileX+tileY) % list.count]
				url.replaceSubrange(begin.lowerBound..<end.upperBound, with: t)
			}
		}

        if let projection = aerialService?.wmsProjection,
		   !projection.isEmpty
		{
            // WMS
            let minXmaxY = TileToWMSCoords(Int(tileX), Int(tileY), Int(zoom), projection)
            let maxXminY = TileToWMSCoords(Int(tileX + 1), Int(tileY + 1), Int(zoom), projection)
            var bbox: String = ""
			if (projection == "EPSG:4326") && url.lowercased().contains("crs={proj}") {
                // reverse lat/lon for EPSG:4326 when WMS version is 1.3 (WMS 1.1 uses srs=epsg:4326 instead
                bbox = "\(maxXminY.y),\(minXmaxY.x),\(minXmaxY.y),\(maxXminY.x)" // lat,lon
            } else {
                bbox = "\(minXmaxY.x),\(maxXminY.y),\(maxXminY.x),\(minXmaxY.y)" // lon,lat
            }

			url = url.replacingOccurrences(of: "{width}", with: "256")
            url = url.replacingOccurrences(of: "{height}", with: "256")
            url = url.replacingOccurrences(of: "{proj}", with: projection)
            url = url.replacingOccurrences(of: "{bbox}", with: bbox)
            url = url.replacingOccurrences(of: "{wkid}", with: projection.replacingOccurrences(of: "EPSG:", with: ""))
            url = url.replacingOccurrences(of: "{w}", with: "\(minXmaxY.x)")
            url = url.replacingOccurrences(of: "{s}", with: "\(maxXminY.y)")
            url = url.replacingOccurrences(of: "{n}", with: "\(maxXminY.x)")
            url = url.replacingOccurrences(of: "{e}", with: "\(minXmaxY.y)")
        } else {
            // TMS
            let u = quadKey(forZoom: zoom, tileX: tileX, tileY: tileY)
            let x = "\(tileX)"
            let y = "\(tileY)"
            let negY = "\((1 << zoom) - tileY - 1)"
            let z = "\(zoom)"
            
            url = url.replacingOccurrences(of: "{u}", with: u)
            url = url.replacingOccurrences(of: "{x}", with: x)
            url = url.replacingOccurrences(of: "{y}", with: y)
            url = url.replacingOccurrences(of: "{-y}", with: negY)
            url = url.replacingOccurrences(of: "{z}", with: z)
        }
        // retina screen
        let retina = UIScreen.main.scale > 1 ? "@2x" : ""
        url = url.replacingOccurrences(of: "{@2x}", with: retina)

        let urlString = url.addingPercentEncoding(withAllowedCharacters: CharacterSet.urlQueryAllowed) ?? url
		//https://ecn.t1.tiles.virtualearth.net/tiles/a12313302102001233031.jpeg?g=587&key=ApunJH62__wQs1qE32KVrf6Fmncn7OZj6gWg_wtr27DQLDCkwkxGl4RsItKW4Fkk
		//https://ecn.%7Bswitch:t0,t1,t2,t3%7D.tiles.virtualearth.net/tiles/a%7Bu%7D.jpeg?g=587&key=ApunJH62__wQs1qE32KVrf6Fmncn7OZj6gWg_wtr27DQLDCkwkxGl4RsItKW4Fkk
		//https://ecn.{switch:t0,t1,t2,t3}.tiles.virtualearth.net/tiles/a{u}.jpeg?g=587&key=ApunJH62__wQs1qE32KVrf6Fmncn7OZj6gWg_wtr27DQLDCkwkxGl4RsItKW4Fkk

        return URL(string: urlString)!
    }

    func fetchTile(
        forTileX tileX: Int,
        tileY: Int,
        minZoom: Int,
        zoomLevel: Int,
        completion: @escaping (_ error: Error?) -> Void )
	{
        let tileModX = modulus(tileX, 1 << zoomLevel)
        let tileModY = modulus(tileY, 1 << zoomLevel)
        let tileKey = "\(zoomLevel),\(tileX),\(tileY)"

		if _layerDict[tileKey] != nil {
			// already have it
			completion(nil)
			return
		} else {
            // create layer
            let layer = CALayer()
            layer.actions = actions
            layer.zPosition = CGFloat(zoomLevel) * 0.01 - 0.25
            layer.edgeAntialiasingMask = CAEdgeAntialiasingMask(rawValue: 0) // don't AA edges of tiles or there will be a seam visible
            layer.isOpaque = true
            layer.isHidden = true
            layer.setValue(tileKey, forKey: "tileKey")
            //#if !CUSTOM_TRANSFORM
            //        layer?.anchorPoint = CGPoint(x: 0, y: 1)
            //        let scale = 256.0 / Double((1 << zoomLevel))
            //        layer?.frame = CGRect(x: CGFloat(Double(tileX) * scale), y: CGFloat(Double(tileY) * scale), width: CGFloat(scale), height: CGFloat(scale))
            //#endif
            _layerDict[tileKey] = layer
            
			isPerformingLayout.increment()
            addSublayer(layer)
			isPerformingLayout.decrement()
            
            // check memory cache
            let cacheKey = String(quadKey(forZoom: zoomLevel, tileX: tileModX, tileY: tileModY))
            let cachedImage: UIImage? = _webCache.object(
                withKey: cacheKey,
                fallbackURL: { [self] in
                    return url(forZoom: zoomLevel, tileX: tileModX, tileY: tileModY)
                },
                objectForData: { data in
					if data.count == 0 || self.isPlaceholderImage(data) {
						return nil
					}
					return UIImage(data: data)
                },
				completion: { [self] image in
					if let image = image {
						if layer.superlayer != nil {
	#if os(iOS)
							layer.contents = image.cgImage
	#else
							layer.contents = image
	#endif
							layer.isHidden = false
							//#if CUSTOM_TRANSFORM
							setSublayerPositions([tileKey: layer])
							//#else
							//                    let rc = mapView.boundingMapRectForScreen()
							//                    removeUnneededTiles(for: rc, zoomLevel: Int(zoomLevel))
							//#endif
						} else {
							// no longer needed
						}
						completion(nil)
					} else if zoomLevel > minZoom {
						// try to show tile at one zoom level higher
						DispatchQueue.main.async(execute: { [self] in
							fetchTile(
								forTileX: tileX >> 1,
								tileY: tileY >> 1,
								minZoom: minZoom,
								zoomLevel: zoomLevel - 1,
								completion: completion)
						})
					} else {
						// report error
	#if false
						if let data = data {
							var json: JSONSerialization?
							do {
								json = try JSONSerialization.jsonObject(with: data, options: [])
								text = json.description()
							} catch error {
								text = String(bytes: data.bytes, encoding: .utf8)
							}
						}
	#endif
						let error = NSError(domain: "Image", code: 100, userInfo: [
							NSLocalizedDescriptionKey: NSLocalizedString("No image data available", comment: "")
						])
						DispatchQueue.main.async(execute: {
							completion(error)
						})
					}
				})
			if cachedImage != nil {
				#if os(iOS)
				layer.contents = cachedImage!.cgImage
				#else
				layer?.contents = cachedImage
				#endif
				layer.isHidden = false
				completion(nil)
				return
			}
			return
        }
    }

    override func setNeedsLayout() {
		if isPerformingLayout.value() != 0 {
            return
        }
        super.setNeedsLayout()
    }
    
//#if CUSTOM_TRANSFORM
    func setSublayerPositions(_ _layerDict: [String : CALayer]) {
        // update locations of tiles
        let tRotation = OSMTransformRotation(mapView.screenFromMapTransform)
        let tScale = OSMTransformScaleX(mapView.screenFromMapTransform)
        for (tileKey, layer) in _layerDict {
            let splitTileKey : [String] = tileKey.components(separatedBy: ",")
            let tileZ: Int32 = Int32(splitTileKey[0]) ?? 0
            let tileX: Int32 = Int32(splitTileKey[1]) ?? 0
            let tileY: Int32 = Int32(splitTileKey[2]) ?? 0
            
//            sscanf(tileKey?.utf8CString, "%d,%d,%d", &tileZ, &tileX, &tileY)
            
            var scale = 256.0 / Double((1 << tileZ))
            var pt = OSMPoint(x: Double(tileX) * scale, y: Double(tileY) * scale)
            pt = mapView.screenPoint(fromMapPoint: pt, birdsEye: false)
            layer.position = CGPointFromOSMPoint(pt)
            layer.bounds = CGRect(x: 0, y: 0, width: 256, height: 256)
            layer.anchorPoint = CGPoint(x: 0, y: 0)
            
            scale *= tScale / 256
            let t = CGAffineTransform(rotationAngle: CGFloat(tRotation)).scaledBy(x: CGFloat(scale), y: CGFloat(scale))
            layer.setAffineTransform(t)
        }
    }
//#endif

    func layoutSublayersSafe() {
		guard let aerialService = aerialService else { return }
        let rect = mapView.boundingMapRectForScreen()
        var zoomLevel = self.zoomLevel()
        
        if zoomLevel < 1 {
            zoomLevel = 1
        } else if zoomLevel > aerialService.maxZoom {
            zoomLevel = aerialService.maxZoom
        }
        
        let zoom = Double((1 << zoomLevel)) / 256.0
        let tileNorth = Int(floor((rect.origin.y) * zoom))
        let tileWest = Int(floor((rect.origin.x) * zoom))
        let tileSouth = Int(ceil((rect.origin.y + rect.size.height) * zoom))
        let tileEast = Int(ceil((rect.origin.x + rect.size.width) * zoom))
        
        if (tileEast - tileWest) * (tileSouth - tileNorth) > 4000 {
            DLog("Bad tile transform: \((tileEast - tileWest) * (tileSouth - tileNorth))")
            return // something is wrong
        }
        
        // create any tiles that don't yet exist
        for tileX in tileWest..<tileEast {
            for tileY in tileNorth..<tileSouth {
                
                mapView.progressIncrement()
                fetchTile(
                    forTileX: tileX,
                    tileY: tileY,
                    minZoom: max(zoomLevel - 8, 1),
                    zoomLevel: zoomLevel,
					completion: { [self] error in
						if let error = error {
							mapView.presentError(error, flash: true)
						}
						mapView.progressDecrement()
                })
            }
        }
        
//#if CUSTOM_TRANSFORM
        // update locations of tiles
        setSublayerPositions(_layerDict)
        removeUnneededTiles(for: OSMRectFromCGRect(bounds), zoomLevel: zoomLevel)
//#else
//        let rc = mapView.boundingMapRectForScreen()
//        removeUnneededTiles(for: rc, zoomLevel: Int(zoomLevel))
//#endif
        
        mapView.progressAnimate()
    }
    
    override func layoutSublayers() {
        if isHidden {
            return
        }
		isPerformingLayout.increment()
        layoutSublayersSafe()
		isPerformingLayout.decrement()
    }
    
    func downloadTile(forKey cacheKey: String, completion: @escaping () -> Void) {
        var tileX = Int()
        var tileY = Int()
        var zoomLevel = Int()
        QuadKeyToTileXY(cacheKey, &tileX, &tileY, &zoomLevel)
        let data2 = _webCache.object(withKey: cacheKey,
			fallbackURL: {
				return self.url(forZoom: zoomLevel, tileX: tileX, tileY: tileY)
			},
			objectForData: { data in
				if data.count == 0 || self.isPlaceholderImage(data) {
					return nil
				}
				return UIImage(data: data)
			}, completion: { data in
				completion()
			})
        if data2 != nil {
            completion()
        }
    }
    
    // Used for bulk downloading tiles for offline use
    func allTilesIntersectingVisibleRect() -> [String] {
        let currentTiles = _webCache.allKeys()
        let currentSet = Set(currentTiles)
        
        let rect = mapView.boundingMapRectForScreen()
        var minZoomLevel = zoomLevel()
        
        if minZoomLevel < 1 {
            minZoomLevel = 1
        }
        if minZoomLevel > 31 {
            minZoomLevel = 31 // shouldn't be necessary, except to shup up the Xcode analyzer
        }
        
        var maxZoomLevel = aerialService?.maxZoom ?? 0
        if maxZoomLevel > minZoomLevel + 2 {
            maxZoomLevel = minZoomLevel + 2
        }
        if maxZoomLevel > 31 {
            maxZoomLevel = 31 // shouldn't be necessary, except to shup up the Xcode analyzer
        }
        
        var neededTiles: [String] = []
        for zoomLevel in minZoomLevel...maxZoomLevel {
            let zoom = Double((1 << zoomLevel)) / 256.0
            let tileNorth = Int(floor((rect.origin.y) * zoom))
            let tileWest = Int(floor((rect.origin.x) * zoom))
            let tileSouth = Int(ceil((rect.origin.y + rect.size.height) * zoom))
            let tileEast = Int(ceil((rect.origin.x + rect.size.width) * zoom))
            
            for tileX in tileWest..<tileEast {
                for tileY in tileNorth..<tileSouth {
                    let cacheKey = String(quadKey(forZoom: zoomLevel, tileX: tileX, tileY: tileY))
                    let file = cacheKey + ".jpg"
                    if currentSet.contains(file) {
                        // already have it
                    } else {
                        neededTiles.append(cacheKey)
                    }
                }
            }
        }
        return neededTiles
    }
    
    override var transform: CATransform3D {
        get {
            return super.transform
        }
        set(transform) {
            super.transform = transform
            setNeedsLayout()
        }
    }
    
    override var isHidden: Bool {
        get {
            return super.isHidden
        }
        set(isHidden) {
            super.isHidden = isHidden
            
            if !isHidden {
                setNeedsLayout()
            }
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        super.init(coder: aDecoder)
    }
}
