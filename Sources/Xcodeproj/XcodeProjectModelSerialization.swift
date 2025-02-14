/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2017 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors

 -----------------------------------------------------------------

 An extemely simple rendition of the Xcode project model into a plist.  There
 is only enough functionality to allow serialization of Xcode projects.
*/

import Basics

extension Xcode.Project: PropertyListSerializable {

    /// Generates and returns the contents of a `project.pbxproj` plist.  Does
    /// not generate any ancillary files, such as a set of schemes.
    ///
    /// Many complexities of the Xcode project model are not represented; we
    /// should not add functionality to this model unless it's needed, since
    /// implementation of the full Xcode project model would be unnecessarily
    /// complex.
    public func generatePlist() throws -> PropertyList {
        // The project plist is a bit special in that it's the archive for the
        // whole file.  We create a plist serializer and serialize the entire
        // object graph to it, and then return an archive dictionary containing
        // the serialized object dictionaries.
        let serializer = PropertyListSerializer()
        try serializer.serialize(object: self)
        return .dictionary([
            "archiveVersion": .string("1"),
            "objectVersion": .string("46"),  // Xcode 8.0
            "rootObject": .identifier(serializer.id(of: self)),
            "objects": .dictionary(serializer.idsToDicts),
        ])
    }

    /// Called by the Serializer to serialize the Project.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create a `PBXProject` plist dictionary.
        // Note: we skip things like the `Products` group; they get autocreated
        // by Xcode when it opens the project and notices that they are missing.
        // Note: we also skip schemes, since they are not in the project plist.
        var dict = [String: PropertyList]()
        dict["isa"] = .string("PBXProject")
        // Since the project file is generated, we opt out of upgrade-checking.
        // FIXME: Shoule we really?  Why would we not want to get upgraded?
        dict["attributes"] = .dictionary(["LastUpgradeCheck": .string("9999"),
                                          "LastSwiftMigration": .string("9999")])
        dict["compatibilityVersion"] = .string("Xcode 3.2")
        dict["developmentRegion"] = .string("en")
        // Build settings are a bit tricky; in Xcode, each is stored in a named
        // XCBuildConfiguration object, and the list of build configurations is
        // in turn stored in an XCConfigurationList.  In our simplified model,
        // we have a BuildSettingsTable, with three sets of settings:  one for
        // the common settings, and one each for the Debug and Release overlays.
        // So we consider the BuildSettingsTable to be the configuration list.
        dict["buildConfigurationList"] = try .identifier(serializer.serialize(object: buildSettings))
        dict["mainGroup"] = try .identifier(serializer.serialize(object: mainGroup))
        dict["hasScannedForEncodings"] = .string("0")
        dict["knownRegions"] = .array([.string("en")])
        if let productGroup = productGroup {
            dict["productRefGroup"] = .identifier(serializer.id(of: productGroup))
        }
        dict["projectDirPath"] = .string(projectDir)
        // Ensure that targets are output in a sorted order.
        let sortedTargets = targets.sorted(by: { $0.name < $1.name })
        dict["targets"] = try .array(sortedTargets.map({ target in
            try .identifier(serializer.serialize(object: target))
        }))
        return dict
    }
}

/// Private helper function that constructs and returns a partial property list
/// dictionary for references.  The caller can add to the returned dictionary.
/// FIXME:  It would be nicer to be able to use inheritance to serialize the
/// attributes inherited from Reference, but but in Swift 3.0 we get an error
/// that "declarations in extensions cannot override yet".
fileprivate func makeReferenceDict(
    reference: Xcode.Reference,
    serializer: PropertyListSerializer,
    xcodeClassName: String
) -> [String: PropertyList] {
    var dict = [String: PropertyList]()
    dict["isa"] = .string(xcodeClassName)
    dict["path"] = .string(reference.path)
    if let name = reference.name {
        dict["name"] = .string(name)
    }
    dict["sourceTree"] = .string(reference.pathBase.rawValue)
    return dict
}

extension Xcode.Group: PropertyListSerializable {

    /// Called by the Serializer to serialize the Group.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create a `PBXGroup` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from Reference, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        var dict = makeReferenceDict(reference: self, serializer: serializer, xcodeClassName: "PBXGroup")
        dict["children"] = try .array(subitems.map({ reference in
            // For the same reason, we have to cast as `PropertyListSerializable`
            // here; as soon as we try to make Reference conform to the protocol,
            // we get the problem of not being able to override `serialize(to:)`.
            try .identifier(serializer.serialize(object: reference as! PropertyListSerializable))
        }))
        return dict
    }
}

extension Xcode.FileReference: PropertyListSerializable {

    /// Called by the Serializer to serialize the FileReference.
    fileprivate func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
        // Create a `PBXFileReference` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from Reference, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        var dict = makeReferenceDict(reference: self, serializer: serializer, xcodeClassName: "PBXFileReference")
        if let fileType = fileType {
            dict["explicitFileType"] = .string(fileType)
        }
        // FileReferences don't need to store a name if it's the same as the path.
        if name == path {
            dict["name"] = nil
        }
        return dict
    }
}

extension Xcode.Target: PropertyListSerializable {

    /// Called by the Serializer to serialize the Target.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create either a `PBXNativeTarget` or an `PBXAggregateTarget` plist
        // dictionary (depending on whether or not we have a product type).
        var dict = [String: PropertyList]()
        dict["isa"] = .string(productType == nil ? "PBXAggregateTarget" : "PBXNativeTarget")
        dict["name"] = .string(name)
        // Build settings are a bit tricky; in Xcode, each is stored in a named
        // XCBuildConfiguration object, and the list of build configurations is
        // in turn stored in an XCConfigurationList.  In our simplified model,
        // we have a BuildSettingsTable, with three sets of settings:  one for
        // the common settings, and one each for the Debug and Release overlays.
        // So we consider the BuildSettingsTable to be the configuration list.
        // This is the same situation as for Project.
        dict["buildConfigurationList"] = try .identifier(serializer.serialize(object: buildSettings))
        dict["buildPhases"] = try .array(buildPhases.map({ phase in
            // Here we have the same problem as for Reference; we cannot inherit
            // functionality since we're in an extension.
            try .identifier(serializer.serialize(object: phase as! PropertyListSerializable))
        }))
        /// Private wrapper class for a target dependency relation.  This is
        /// glue between our value-based settings structures and the Xcode
        /// project model's identity-based TargetDependency objects.
        class TargetDependency: PropertyListSerializable {
            var target: Xcode.Target
            init(target: Xcode.Target) {
                self.target = target
            }
            func serialize(to serializer: PropertyListSerializer) -> [String: PropertyList] {
                // Create a `PBXTargetDependency` plist dictionary.
                var dict = [String: PropertyList]()
                dict["isa"] = .string("PBXTargetDependency")
                dict["target"] = .identifier(serializer.id(of: target))
                return dict
            }
        }
        dict["dependencies"] = try .array(dependencies.map({ dep in
            // In the Xcode project model, target dependencies are objects,
            // so we need a helper class here.
            try .identifier(serializer.serialize(object: TargetDependency(target: dep.target)))
        }))
        dict["productName"] = .string(productName)
        if let productType = productType {
            dict["productType"] = .string(productType.rawValue)
        }
        if let productReference = productReference {
            dict["productReference"] = .identifier(serializer.id(of: productReference))
        }
        return dict
    }
}

/// Private helper function that constructs and returns a partial property list
/// dictionary for build phases.  The caller can add to the returned dictionary.
/// FIXME:  It would be nicer to be able to use inheritance to serialize the
/// attributes inherited from BuildPhase, but but in Swift 3.0 we get an error
/// that "declarations in extensions cannot override yet".
fileprivate func makeBuildPhaseDict(
    buildPhase: Xcode.BuildPhase,
    serializer: PropertyListSerializer,
    xcodeClassName: String
) throws -> [String: PropertyList] {
    var dict = [String: PropertyList]()
    dict["isa"] = .string(xcodeClassName)
    dict["files"] = try .array(buildPhase.files.map({ file in
        try .identifier(serializer.serialize(object: file))
    }))
    return dict
}

extension Xcode.HeadersBuildPhase: PropertyListSerializable {

    /// Called by the Serializer to serialize the HeadersBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create a `PBXHeadersBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        return try makeBuildPhaseDict(buildPhase: self, serializer: serializer, xcodeClassName: "PBXHeadersBuildPhase")
    }
}

extension Xcode.SourcesBuildPhase: PropertyListSerializable {

    /// Called by the Serializer to serialize the SourcesBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create a `PBXSourcesBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        return try makeBuildPhaseDict(buildPhase: self, serializer: serializer, xcodeClassName: "PBXSourcesBuildPhase")
    }
}

extension Xcode.FrameworksBuildPhase: PropertyListSerializable {

    /// Called by the Serializer to serialize the FrameworksBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create a `PBXFrameworksBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        return try makeBuildPhaseDict(buildPhase: self, serializer: serializer, xcodeClassName: "PBXFrameworksBuildPhase")
    }
}

extension Xcode.CopyFilesBuildPhase: PropertyListSerializable {

    /// Called by the Serializer to serialize the FrameworksBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create a `PBXCopyFilesBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        var dict = try makeBuildPhaseDict(
            buildPhase: self,
            serializer: serializer,
            xcodeClassName: "PBXCopyFilesBuildPhase"
        )
        dict["dstPath"] = .string("")   // FIXME: needs to be real
        dict["dstSubfolderSpec"] = .string("")   // FIXME: needs to be real
        return dict
    }
}

extension Xcode.ShellScriptBuildPhase: PropertyListSerializable {

    /// Called by the Serializer to serialize the ShellScriptBuildPhase.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create a `PBXShellScriptBuildPhase` plist dictionary.
        // FIXME:  It would be nicer to be able to use inheritance for the code
        // inherited from BuildPhase, but but in Swift 3.0 we get an error that
        // "declarations in extensions cannot override yet".
        var dict = try makeBuildPhaseDict(
            buildPhase: self,
            serializer: serializer,
            xcodeClassName: "PBXShellScriptBuildPhase")
        dict["shellPath"] = .string("/bin/sh")   // FIXME: should be settable
        dict["shellScript"] = .string(script)
        return dict
    }
}

extension Xcode.BuildFile: PropertyListSerializable {

    /// Called by the Serializer to serialize the BuildFile.
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        // Create a `PBXBuildFile` plist dictionary.
        var dict = [String: PropertyList]()
        dict["isa"] = .string("PBXBuildFile")
        if let fileRef = fileRef {
            dict["fileRef"] = .identifier(serializer.id(of: fileRef))
        }

        let settingsDict = try settings.asPropertyList()
        if !settingsDict.isEmpty {
            dict["settings"] = settingsDict
        }

        return dict
    }
}

extension Xcode.BuildSettingsTable: PropertyListSerializable {

    /// Called by the Serializer to serialize the BuildFile.  It is serialized
    /// as an XCBuildConfigurationList and two additional XCBuildConfiguration
    /// objects (one for debug and one for release).
    fileprivate func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
        /// Private wrapper class for BuildSettings structures.  This is glue
        /// between our value-based settings structures and the Xcode project
        /// model's identity-based XCBuildConfiguration objects.
        class BuildSettingsDictWrapper: PropertyListSerializable {
            let name: String
            var baseSettings: BuildSettings
            var overlaySettings: BuildSettings
            let xcconfigFileRef: Xcode.FileReference?

            init(
                name: String,
                baseSettings: BuildSettings,
                overlaySettings: BuildSettings,
                xcconfigFileRef: Xcode.FileReference?
            ) {
                self.name = name
                self.baseSettings = baseSettings
                self.overlaySettings = overlaySettings
                self.xcconfigFileRef = xcconfigFileRef
            }

            func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList] {
                // Create a `XCBuildConfiguration` plist dictionary.
                var dict = [String: PropertyList]()
                dict["isa"] = .string("XCBuildConfiguration")
                dict["name"] = .string(name)
                // Combine the base settings and the overlay settings.
                dict["buildSettings"] = try combineBuildSettingsPropertyLists(
                    baseSettings: try baseSettings.asPropertyList(),
                    overlaySettings: try overlaySettings.asPropertyList()
                )
                // Add a reference to the base configuration, if there is one.
                if let xcconfigFileRef = xcconfigFileRef {
                    dict["baseConfigurationReference"] = .identifier(serializer.id(of: xcconfigFileRef))
                }
                return dict
            }
        }

        // Create a `XCConfigurationList` plist dictionary.
        var dict = [String: PropertyList]()
        dict["isa"] = .string("XCConfigurationList")
        dict["buildConfigurations"] = .array([
            // We use a private wrapper to "objectify" our two build settings
            // structures (which, being structs, are value types).
            try .identifier(serializer.serialize(object: BuildSettingsDictWrapper(
                name: "Debug",
                baseSettings: common,
                overlaySettings: debug,
                xcconfigFileRef: xcconfigFileRef))),
            try .identifier(serializer.serialize(object: BuildSettingsDictWrapper(
                name: "Release",
                baseSettings: common,
                overlaySettings: release,
                xcconfigFileRef: xcconfigFileRef))),
        ])
        // FIXME: What is this, and why are we setting it?
        dict["defaultConfigurationIsVisible"] = .string("0")
        // FIXME: Should we allow this to be set in the model?
        dict["defaultConfigurationName"] = .string("Release")
        return dict
    }
}

public protocol PropertyListDictionaryConvertible {
    func asPropertyList() throws -> PropertyList
}

extension PropertyListDictionaryConvertible {
    public static func asPropertyList(_ object: PropertyListDictionaryConvertible) throws -> PropertyList {
        // Borderline hacky, but the main thing is that adding or changing a
        // build setting does not require any changes to the property list
        // representation code.  Using a hand coded serializer might be more
        // efficient but not even remotely as robust, and robustness is the
        // key factor for this use case, as there aren't going to be millions
        // of BuildSettings structs.
        var dict = [String: PropertyList]()
        let mirror = Mirror(reflecting: object)
        for child in mirror.children {
            guard let name = child.label else {
                throw InternalError("unnamed build settings are not supported")
            }
            switch child.value {
            case Optional<Any>.none:
                continue
            case let value as String:
                dict[name] = .string(value)
            case let value as [String]:
                dict[name] = .array(value.map({ .string($0) }))
            default:
                throw InternalError("unexpected build setting value of type `\(type(of: child.value))`")
            }
        }
        return .dictionary(dict)
    }

    /// Returns a property list representation of the build settings, in which
    /// every struct field is represented as a dictionary entry.  Fields of
    /// type `String` are represented as `PropertyList.string` values; fields
    /// of type `[String]` are represented as `PropertyList.array` values with
    /// `PropertyList.string` values as the array elements.  The property list
    /// dictionary only contains entries for struct fields that aren't nil.
    ///
    /// Note: BuildSettings is a value type and PropertyListSerializable only
    /// applies to classes.  Creating a property list representation is totally
    /// independent of that serialization infrastructure (though it might well
    /// be invoked during of serialization of actual model objects).
    public func asPropertyList() throws -> PropertyList {
        return try type(of: self).asPropertyList(self)
    }
}

extension Xcode.BuildFile.Settings: PropertyListDictionaryConvertible {}
extension Xcode.BuildSettingsTable.BuildSettings: PropertyListDictionaryConvertible {
    public func asPropertyList() throws -> PropertyList {
        var buildSettings = self

        // Space-separated setting is a setting whose value is split into multiple
        // values using space as a separator.
        //
        // Example: ["value1", "value2 value3"] -> ["value1", "value2", "value3"]
        // https://github.com/apple/swift-package-manager/pull/2770#issuecomment-638453861
        let spaceSeparatedSettingKeyPaths: [WritableKeyPath<Xcode.BuildSettingsTable.BuildSettings, [String]?>] = [
            \.FRAMEWORK_SEARCH_PATHS,
            \.GCC_PREPROCESSOR_DEFINITIONS,
            \.HEADER_SEARCH_PATHS,
            \.LD_RUNPATH_SEARCH_PATHS,
            \.LIBRARY_SEARCH_PATHS,
            \.OTHER_CFLAGS,
            \.OTHER_CPLUSPLUSFLAGS,
            \.OTHER_LDFLAGS
        ]

        for settingKeyPath in spaceSeparatedSettingKeyPaths {
            guard let values = buildSettings[keyPath: settingKeyPath] else { continue }

            buildSettings[keyPath: settingKeyPath] = values.map {
                // Here we assume that the user of SPM is unaware of Xcode's behavior
                // to space-separate values and thus each value is considered a single value.
                //
                // However, users who have encountered this issue before it was addressed
                // may have modified their package definitions to circumvent it.
                // An attempt is made to detect such cases to bypass the values unmodified.

                // Extra quotes around the value: "\"single value\"".
                if $0.hasPrefix("\"") && $0.hasSuffix("\"") {
                    return $0
                }
                // Nothing to escape.
                else if !$0.contains(" ") {
                    return $0
                }
                // All spaces are escaped: "single\ value".
                else if $0.components(separatedBy: " ").dropLast().allSatisfy({ $0.hasSuffix(#"\"#) }) {
                    return $0
                }
                else {
                    return "\"\($0)\""
                }
            }
        }

        return try type(of: self).asPropertyList(buildSettings)
    }
}

/// Private helper function that combines a base property list and an overlay
/// property list, respecting the semantics of `$(inherited)` as we go.
fileprivate func combineBuildSettingsPropertyLists(
    baseSettings: PropertyList,
    overlaySettings: PropertyList
) throws -> PropertyList {
    // Extract the base and overlay dictionaries.
    guard case let .dictionary(baseDict) = baseSettings else {
        throw InternalError("base settings plist must be a dictionary")
    }
    guard case let .dictionary(overlayDict) = overlaySettings else {
        throw InternalError("overlay settings plist must be a dictionary")
    }

    // Iterate over the overlay values and apply them to the base.
    var resultDict = baseDict
    for (name, value) in overlayDict {
        if let array = baseDict[name]?.array, let overlayArray = value.array, overlayArray.first?.string == "$(inherited)" {
            resultDict[name] = .array(array + overlayArray.dropFirst())
        } else {
            resultDict[name] = value
        }
    }
    return .dictionary(resultDict)
}

/// A simple property list serializer with the same semantics as the Xcode
/// property list serializer.  Not generally reusable at this point, but only
/// because of implementation details (architecturally it isn't tied to Xcode).
fileprivate class PropertyListSerializer {

    /// Private struct that represents a strong reference to a serializable
    /// object.  This prevents any temporary objects from being deallocated
    /// during the serialization and replaced with other objects having the
    /// same object identifier (a violation of our assumptions)
    struct SerializedObjectRef: Hashable, Equatable {
        let object: PropertyListSerializable

        init(_ object: PropertyListSerializable) {
            self.object = object
        }

        func hash(into hasher: inout Hasher) {
            hasher.combine(ObjectIdentifier(object))
        }

        static func == (lhs: SerializedObjectRef, rhs: SerializedObjectRef) -> Bool {
            return lhs.object === rhs.object
        }
    }

    /// Maps objects to the identifiers that have been assigned to them.  The
    /// next identifier to be assigned is always one greater than the number
    /// of entries in the mapping.
    var objsToIds = [SerializedObjectRef: String]()

    /// Maps serialized objects ids to dictionaries.  This may contain fewer
    /// entries than `objsToIds`, since ids are assigned upon reference, but
    /// plist dictionaries are created only upon actual serialization.  This
    /// dictionary is what gets written to the property list.
    var idsToDicts = [String: PropertyList]()

    /// Returns the quoted identifier for the object, assigning one if needed.
    func id(of object: PropertyListSerializable) -> String {
        // We need a "serialized object ref" wrapper for the `objsToIds` map.
        let serObjRef = SerializedObjectRef(object)
        if let id = objsToIds[serObjRef] {
            return "\"\(id)\""
        }
        // We currently always assign identifiers starting at 1 and going up.
        // FIXME: This is a suboptimal format for object identifier strings;
        // for debugging purposes they should at least sort in numeric order.
        let id = object.objectID ?? "OBJ_\(objsToIds.count + 1)"
        objsToIds[serObjRef] = id
        return "\"\(id)\""
    }

    /// Serializes `object` by asking it to construct a plist dictionary and
    /// then adding that dictionary to the serializer.  This may in turn cause
    /// recursive invocations of `serialize(object:)`; the closure of these
    /// invocations end up serializing the whole object graph.
    @discardableResult
    func serialize(object: PropertyListSerializable) throws -> String {
        // Assign an id for the object, if it doesn't already have one.
        let id = self.id(of: object)

        // If that id is already in `idsToDicts`, we've detected recursion or
        // repeated serialization.
        guard idsToDicts[id] == nil else {
            throw InternalError("tried to serialize \(object) twice")
        }

        // Set a sentinel value in the `idsToDicts` mapping to detect recursion.
        idsToDicts[id] = .dictionary([:])

        // Now recursively serialize the object, and store the result (replacing
        // the sentinel).
        idsToDicts[id] = try .dictionary(object.serialize(to: self))

        // Finally, return the identifier so the caller can store it (usually in
        // an attribute in its own serialization dictionary).
        return id
    }
}

fileprivate protocol PropertyListSerializable: AnyObject {
    /// Called by the Serializer to construct and return a dictionary for a
    /// serializable object.  The entries in the dictionary should represent
    /// the receiver's attributes and relationships, as PropertyList values.
    ///
    /// Every object that is written to the Serializer is assigned an id (an
    /// arbitrary but unique string).  Forward references can use `id(of:)`
    /// of the Serializer to assign and access the id before the object is
    /// actually written.
    ///
    /// Implementations can use the Serializer's `serialize(object:)` method
    /// to serialize owned objects (getting an id to the serialized object,
    /// which can be stored in one of the attributes) or can use the `id(of:)`
    /// method to store a reference to an unowned object.
    ///
    /// The implementation of this method for each serializable objects looks
    /// something like this:
    ///
    ///   // Create a `PBXSomeClassOrOther` plist dictionary.
    ///   var dict = [String: PropertyList]()
    ///   dict["isa"] = .string("PBXSomeClassOrOther")
    ///   dict["name"] = .string(name)
    ///   if let path = path { dict["path"] = .string(path) }
    ///   dict["mainGroup"] = .identifier(serializer.serialize(object: mainGroup))
    ///   dict["subitems"] = .array(subitems.map({ .string($0.id) }))
    ///   dict["cross-ref"] = .identifier(serializer.id(of: unownedObject))
    ///   return dict
    ///
    /// FIXME: I'm not totally happy with how this looks.  It's far too clunky
    /// and could be made more elegant.  However, since the Xcode project model
    /// is static, this is not something that will need to evolve over time.
    /// What does need to evolve, which is how the project model is constructed
    /// from the package contents, is where the elegance and simplicity really
    /// matters.  So this is acceptable for now in the interest of getting it
    /// done.

    /// A custom ID to use for the instance, if enabled.
    ///
    /// This ID must be unique across the entire serialized graph.
    var objectID: String? { get }
    
    /// Should create and return a property list dictionary of the object's
    /// attributes.  This function may also use the serializer's `serialize()`
    /// function to serialize other objects, and may use `id(of:)` to access
    /// ids of objects that either have or will be serialized.
    func serialize(to serializer: PropertyListSerializer) throws -> [String: PropertyList]
}

extension PropertyListSerializable {
    var objectID: String? {
        return nil
    }
}

extension PropertyList {
    var isEmpty: Bool {
        switch self {
        case let .identifier(string): return string.isEmpty
        case let .string(string): return string.isEmpty
        case let .array(array): return array.isEmpty
        case let .dictionary(dictionary): return dictionary.isEmpty
        }
    }
}
