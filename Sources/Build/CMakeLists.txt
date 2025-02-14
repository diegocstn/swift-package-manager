# This source file is part of the Swift.org open source project
#
# Copyright (c) 2014 - 2021 Apple Inc. and the Swift project authors
# Licensed under Apache License v2.0 with Runtime Library Exception
#
# See http://swift.org/LICENSE.txt for license information
# See http://swift.org/CONTRIBUTORS.txt for Swift project authors

add_library(Build
  BuildOperationBuildSystemDelegateHandler.swift
  BuildOperation.swift
  BuildPlan.swift
  LLBuildManifestBuilder.swift
  SPMSwiftDriverExecutor.swift
  SwiftCompilerOutputParser.swift)
target_link_libraries(Build PUBLIC
  TSCBasic
  Basics
  PackageGraph
  LLBuildManifest
  SPMBuildCore
  SPMLLBuild)
target_link_libraries(Build PRIVATE
  SwiftDriver)

# NOTE(compnerd) workaround for CMake not setting up include flags yet
set_target_properties(Build PROPERTIES
  INTERFACE_INCLUDE_DIRECTORIES ${CMAKE_Swift_MODULE_DIRECTORY})

if(USE_CMAKE_INSTALL)
install(TARGETS Build
  ARCHIVE DESTINATION lib
  LIBRARY DESTINATION lib
  RUNTIME DESTINATION bin)
endif()
set_property(GLOBAL APPEND PROPERTY SwiftPM_EXPORTS Build)
