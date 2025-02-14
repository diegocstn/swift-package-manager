/*
 This source file is part of the Swift.org open source project

 Copyright (c) 2014 - 2020 Apple Inc. and the Swift project authors
 Licensed under Apache License v2.0 with Runtime Library Exception

 See http://swift.org/LICENSE.txt for license information
 See http://swift.org/CONTRIBUTORS.txt for Swift project authors
*/

import Basics
import Dispatch
import PackageGraph
import PackageLoading
import PackageModel
import TSCBasic

/// Local file system package container.
///
/// This class represent packages that are referenced locally in the file system.
/// There is no need to perform any git operations on such packages and they
/// should be used as-is. In fact, they might not even have a git repository.
/// Examples: Root packages, local dependencies, edited packages.
public struct FileSystemPackageContainer: PackageContainer {
    public let package: PackageReference
    private let identityResolver: IdentityResolver
    private let manifestLoader: ManifestLoaderProtocol
    private let toolsVersionLoader: ToolsVersionLoaderProtocol
    private let currentToolsVersion: ToolsVersion

    /// File system that should be used to load this package.
    private let fileSystem: FileSystem

    /// Observability scope to emit diagnostics
    private let observabilityScope: ObservabilityScope

    /// cached version of the manifest
    private let manifest = ThreadSafeBox<Manifest>()

    public init(
        package: PackageReference,
        identityResolver: IdentityResolver,
        manifestLoader: ManifestLoaderProtocol,
        toolsVersionLoader: ToolsVersionLoaderProtocol,
        currentToolsVersion: ToolsVersion,
        fileSystem: FileSystem,
        observabilityScope: ObservabilityScope
    ) throws {
        switch package.kind {
        case .root, .fileSystem:
            break
        default:
            throw InternalError("invalid package type \(package.kind)")
        }
        self.package = package
        self.identityResolver = identityResolver
        self.manifestLoader = manifestLoader
        self.toolsVersionLoader = toolsVersionLoader
        self.currentToolsVersion = currentToolsVersion
        self.fileSystem = fileSystem
        self.observabilityScope = observabilityScope
    }

    private func loadManifest() throws -> Manifest {
        try manifest.memoize() {
            let path: AbsolutePath
            switch self.package.kind {
            case .root(let _path), .fileSystem(let _path):
                path = _path
            default:
                throw InternalError("invalid package type \(package.kind)")
            }

            // Load the tools version.
            let toolsVersion = try self.toolsVersionLoader.load(at: path, fileSystem: self.fileSystem)

            // Validate the tools version.
            try toolsVersion.validateToolsVersion(self.currentToolsVersion, packageIdentity: self.package.identity)

            // Load the manifest.
            // FIXME: this should not block
            return try temp_await {
                manifestLoader.load(
                    at: path,
                    packageIdentity: self.package.identity,
                    packageKind: self.package.kind,
                    packageLocation: path.pathString,
                    version: nil,
                    revision: nil,
                    toolsVersion: toolsVersion,
                    identityResolver: self.identityResolver,
                    fileSystem: self.fileSystem,
                    observabilityScope: self.observabilityScope,
                    on: .sharedConcurrent,
                    completion: $0
                )
            }
        }
    }

    public func getUnversionedDependencies(productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        let manifest = try self.loadManifest()
        return try manifest.dependencyConstraints(productFilter: productFilter)
    }

    public func loadPackageReference(at boundVersion: BoundVersion) throws -> PackageReference {
        assert(boundVersion == .unversioned, "Unexpected bound version \(boundVersion)")
        let manifest = try loadManifest()
        return package.withName(manifest.displayName)
    }

    public func isToolsVersionCompatible(at version: Version) -> Bool {
        fatalError("This should never be called")
    }

    public func toolsVersion(for version: Version) throws -> ToolsVersion {
        fatalError("This should never be called")
    }

    public func toolsVersionsAppropriateVersionsDescending() throws -> [Version] {
        fatalError("This should never be called")
    }

    public func versionsAscending() throws -> [Version] {
        fatalError("This should never be called")
    }

    public func getDependencies(at version: Version, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }

    public func getDependencies(at revision: String, productFilter: ProductFilter) throws -> [PackageContainerConstraint] {
        fatalError("This should never be called")
    }
}

extension FileSystemPackageContainer: CustomStringConvertible  {
    public var description: String {
        return "FileSystemPackageContainer(\(self.package.identity))"
    }
}
