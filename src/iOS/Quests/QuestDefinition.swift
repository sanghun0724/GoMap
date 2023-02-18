//
//  QuestDefinition.swift
//  Go Map!!
//
//  Created by Bryce Cogswell on 2/8/23.
//  Copyright © 2023 Bryce Cogswell. All rights reserved.
//

import UIKit

protocol QuestProtocol {
	var ident: String { get }
	var title: String { get }
	var label: MapMarkerButton.TextOrImage { get }
	var presetKey: String { get }
	func appliesTo(_ object: OsmBaseObject) -> Bool
	func accepts(tagValue: String) -> Bool
}

enum QuestError: LocalizedError {
	case unknownKey(String)
	case unknownFeature(String)
	case noStringEquivalent
	case illegalLabel(String)

	public var errorDescription: String? {
		switch self {
		case .unknownKey(let text): return "The tag key '\(text)' is not referenced by any features"
		case .unknownFeature(let text): return "The feature '\(text)' does not exist"
		case .noStringEquivalent: return "Unable to convert the data to string"
		case .illegalLabel(let text):return "The quest label '\(text)' must be a single character"
		}
	}

}

struct QuestHighwaySurface: QuestProtocol {
	var ident: String { "QuestHighwaySurface" }
	var title: String { "Highway surface" }
	var presetKey: String { "surface" }
	var label: MapMarkerButton.TextOrImage { .text("Q") }
	var presetField: PresetField

	func appliesTo(_ object: OsmBaseObject) -> Bool {
		if let way = object as? OsmWay,
		   way.tags["highway"] != nil,
		   way.tags["surface"] == nil
		{
			return true
		}
		return false
	}

	func accepts(tagValue: String) -> Bool {
		return !tagValue.isEmpty
	}
}

class QuestDefinition: QuestProtocol {
	// These items define the quest
	let ident: String // Uniquely identify the quest
	let title: String // Localized instructions on what action to take
	let label: MapMarkerButton.TextOrImage
	let presetKey: String // The value the user is being asked to set
	let appliesToObject: (OsmBaseObject) -> Bool
	let acceptsValue: (String) -> Bool

	func appliesTo(_ object: OsmBaseObject) -> Bool {
		return appliesToObject(object)
	}

	func accepts(tagValue: String) -> Bool {
		return acceptsValue(tagValue)
	}

	init(ident: String,
	     title: String,
	     label: MapMarkerButton.TextOrImage,
	     presetKey: String,
	     appliesToObject: @escaping (OsmBaseObject) -> Bool,
	     acceptsValue: @escaping (String) -> Bool)
	{
		self.ident = ident
		self.title = title
		self.label = label
		self.presetKey = presetKey
		self.appliesToObject = appliesToObject
		self.acceptsValue = acceptsValue
	}

	convenience init(ident: String,
	                 title: String,
	                 label: MapMarkerButton.TextOrImage,
	                 presetKey: String, // The value the user is being asked to set
	                 // The set of features the user is interested in (everything if empty)
	                 includeFeaturePresets: [PresetFeature],
	                 accepts: @escaping ((String) -> Bool)) // This is acceptance criteria for a value the user typed in
	{
		guard !includeFeaturePresets.isEmpty else { fatalError() }

		let includeFunc = Self.getMatchFunc(includeFeaturePresets.map { $0.tags })
		let applies: (OsmBaseObject) -> Bool = { obj in
			// we ignore geometry currently, but probably will need to handle it in the future
			let tags = obj.tags
			return tags[presetKey] == nil && includeFunc(tags)
		}
		self.init(ident: ident,
		          title: title,
		          label: label,
		          presetKey: presetKey,
		          appliesToObject: applies,
		          acceptsValue: accepts)
	}

	convenience
	init(ident: String,
	     title: String,
	     label: MapMarkerButton.TextOrImage,
	     presetKey: String, // The value the user is being asked to set
	     includeFeatures: [String], // The set of features the user is interested in (everything if empty)
	     accepts: ((String) -> Bool)? = nil // This is acceptance criteria for a value the user typed in
	) throws {
		if case let .text(text) = label,
		   text.count != 1
		{
			throw QuestError.illegalLabel(text)
		}

		// If the user didn't define any features then infer them
		var includeFeatures = includeFeatures
		if includeFeatures.isEmpty {
			includeFeatures = try Self.featuresContaining(presetKey: presetKey, more: false)
		}

		let include = try includeFeatures.map {
			guard let feature = PresetsDatabase.shared.stdFeatures[$0] else { throw QuestError.unknownFeature($0) }
			return feature
		}

		self.init(ident: ident,
		          title: title,
		          label: label,
		          presetKey: presetKey,
		          includeFeaturePresets: include,
		          accepts: accepts ?? { !$0.isEmpty })
	}

	convenience init(userQuest quest: QuestUserDefition) throws {
		try self.init(ident: quest.title,
		              title: quest.title,
		              label: .text(quest.label),
		              presetKey: quest.presetKey,
		              includeFeatures: quest.includeFeatures)
	}

	// Compute a function that determines whether a given tag dictionary matches the feature(s) of the quest
	static func getMatchFunc(_ featureList: [[String: String]]) -> (([String: String]) -> Bool) {
		if featureList.isEmpty {
			return { _ in false }
		}

		// build a dictionary of tags that must match
		var matchDict: [String: [[String: String]]] = [:]
		for feature in featureList {
			for key in feature.keys {
				if matchDict[key]?.append(feature) == nil {
					matchDict[key] = [feature]
				}
			}
		}

		// check whether candidate object matches all tags in feature
		@inline(__always)
		func matchTagsOf(candidate: [String: String], to feature: [String: String]) -> Bool {
			// check whether candidate object matches all tags in feature
			for kv in feature {
				guard let value = candidate[kv.key],
				      value == kv.value || kv.value == "*"
				else {
					return false
				}
			}
			return true
		}

		return { candidate in
			for key in candidate.keys {
				guard let features = matchDict[key] else { continue }
				for feature in features {
					if matchTagsOf(candidate: candidate, to: feature) {
						return true
					}
				}
			}
			return false
		}
	}

	static func featuresContaining(presetKey: String, more: Bool) throws -> [String] {
		// find all features containing the desired field
		let featureNames = PresetsDatabase.shared.stdFeatures.values.compactMap {
			$0.fieldContainingTagKey(presetKey, more: more) != nil ? $0.featureID : nil
		}
		if featureNames.isEmpty {
			throw QuestError.unknownKey(presetKey)
		}
		return featureNames
	}
}

struct QuestUserDefition: Codable {
	var title: String // "Add Surface" or similar
	var label: String // single character displayed in MapMarkerButton
	var presetKey: String // "surface"
	var includeFeatures: [String] // list of featureID
}
