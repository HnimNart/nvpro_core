# *****************************************************************************
# Copyright 2020 NVIDIA Corporation. All rights reserved.
# *****************************************************************************
include_guard(GLOBAL)

# -------------------------------------------------------------------------------------------------
# function that copies a list of files into the target directory
#
# target_copy_to_output_dir(TARGET foo [RELATIVE <path_prefix>] # allows to keep
# the folder structure starting from this level FILES <absolute_file_path>
# [<absolute_file_path>] )
#
function(target_copy_to_output_dir)
  set(options)
  set(oneValueArgs TARGET RELATIVE DEST_SUBFOLDER)
  set(multiValueArgs FILES)
  cmake_parse_arguments(TARGET_COPY_TO_OUTPUT_DIR "${options}"
                        "${oneValueArgs}" "${multiValueArgs}" ${ARGN})

  foreach(_ELEMENT ${TARGET_COPY_TO_OUTPUT_DIR_FILES})

    # handle absolute and relative paths
    if(TARGET_COPY_TO_OUTPUT_DIR_RELATIVE)
      set(_SOURCE_FILE ${TARGET_COPY_TO_OUTPUT_DIR_RELATIVE}/${_ELEMENT})
      set(_FOLDER_PATH ${_ELEMENT})
    else()
      set(_SOURCE_FILE ${_ELEMENT})
      get_filename_component(_FOLDER_PATH ${_ELEMENT} NAME)
      set(_ELEMENT "")
    endif()

    # handle directories and files slightly different
    if(IS_DIRECTORY ${_SOURCE_FILE})
      if(MDL_LOG_FILE_DEPENDENCIES)
        message(STATUS "- folder to copy: ${_SOURCE_FILE}")
      endif()
      add_custom_command(
        TARGET ${TARGET_COPY_TO_OUTPUT_DIR_TARGET}
        POST_BUILD
        COMMAND
          ${CMAKE_COMMAND} -E copy_directory ${_SOURCE_FILE}
          $<TARGET_FILE_DIR:${TARGET_COPY_TO_OUTPUT_DIR_TARGET}>/${TARGET_COPY_TO_OUTPUT_DIR_DEST_SUBFOLDER}${_FOLDER_PATH}
      )
    else()
      if(MDL_LOG_FILE_DEPENDENCIES)
        message(STATUS "- file to copy:   ${_SOURCE_FILE}")
      endif()
      add_custom_command(
        TARGET ${TARGET_COPY_TO_OUTPUT_DIR_TARGET}
        POST_BUILD
        COMMAND
          ${CMAKE_COMMAND} -E copy_if_different ${_SOURCE_FILE}
          $<TARGET_FILE_DIR:${TARGET_COPY_TO_OUTPUT_DIR_TARGET}>/${TARGET_COPY_TO_OUTPUT_DIR_DEST_SUBFOLDER}${_ELEMENT}
      )
    endif()
  endforeach()
endfunction()

# ------------------------------------------------------------------------------------
# Downloading the URL to FILENAME and extract its content if EXTRACT option is
# present ZIP files should have a folder of the name of the archive - ex.
# foo.zip -> foo/<data> Arguements FILENAMES   : all filenames to download
# EXTRACT     : if present, will extract the content of the file NOINSTALL   :
# if present, will not make files part of install INSTALL_DIR : folder for the
# 'install' build, default is 'media' next to the executable TARGET_DIR  :
# folder where to download to, default is {DOWNLOAD_TARGET_DIR} SOURCE_DIR  :
# folder on server, if not present 'scenes'
#
# Examples: download_files(FILENAMES sample1.zip EXTRACT)
# download_files(FILENAMES env.hdr) download_files(FILENAMES zlib.zip EXTRACT
# TARGET_DIR ${BASE_DIRECTORY}/blah SOURCE_DIR libraries NOINSTALL)
#
function(download_files)
  set(options EXTRACT NOINSTALL)
  set(oneValueArgs INSTALL_DIR SOURCE_DIR TARGET_DIR)
  set(multiValueArgs FILENAMES)
  cmake_parse_arguments(DOWNLOAD_FILES "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  if(NOT DEFINED DOWNLOAD_FILES_INSTALL_DIR)
    set(DOWNLOAD_FILES_INSTALL_DIR "media")
  endif()
  if(NOT DEFINED DOWNLOAD_FILES_SOURCE_DIR)
    set(DOWNLOAD_FILES_SOURCE_DIR "")
  endif()
  if(NOT DEFINED DOWNLOAD_FILES_TARGET_DIR)
    set(DOWNLOAD_FILES_TARGET_DIR ${DOWNLOAD_TARGET_DIR})
  endif()

  # Check each file to download
  foreach(FILENAME ${DOWNLOAD_FILES_FILENAMES})

    set(TARGET_FILENAME ${DOWNLOAD_FILES_TARGET_DIR}/${FILENAME})
    if(NOT EXISTS ${TARGET_FILENAME})
      message(
        STATUS "Downloading ${DOWNLOAD_SITE}/${FILENAME} to ${TARGET_FILENAME}")
      file(DOWNLOAD ${DOWNLOAD_SITE}${DOWNLOAD_FILES_SOURCE_DIR}/${FILENAME}
           ${TARGET_FILENAME} SHOW_PROGRESS)

      # Extracting the ZIP file
      if(DOWNLOAD_FILES_EXTRACT)
        execute_process(COMMAND ${CMAKE_COMMAND} -E tar -xf ${TARGET_FILENAME}
                        WORKING_DIRECTORY ${DOWNLOAD_FILES_TARGET_DIR})
        # ARCHIVE_EXTRACT needs CMake 3.18+ file(ARCHIVE_EXTRACT INPUT
        # ${TARGET_FILENAME} DESTINATION ${DOWNLOAD_FILES_TARGET_DIR})
      endif()
    endif()

    # Installing the files or directory
    if(NOT DOWNLOAD_FILES_NOINSTALL)
      if(DOWNLOAD_FILES_EXTRACT)
        get_filename_component(FILE_DIR ${FILENAME} NAME_WE)
        install(
          DIRECTORY ${DOWNLOAD_FILES_TARGET_DIR}/${FILE_DIR}
          CONFIGURATIONS Release
          DESTINATION "bin_${ARCH}/${DOWNLOAD_FILES_INSTALL_DIR}")
        install(
          DIRECTORY ${DOWNLOAD_FILES_TARGET_DIR}/${FILE_DIR}
          CONFIGURATIONS Debug
          DESTINATION "bin_${ARCH}_debug/${DOWNLOAD_FILES_INSTALL_DIR}")
      else()
        install(
          FILES ${TARGET_FILENAME}
          CONFIGURATIONS Release
          DESTINATION "bin_${ARCH}/${DOWNLOAD_FILES_INSTALL_DIR}")
        install(
          FILES ${TARGET_FILENAME}
          CONFIGURATIONS Debug
          DESTINATION "bin_${ARCH}_debug/${DOWNLOAD_FILES_INSTALL_DIR}")
      endif()
    endif()

  endforeach()
endfunction()

# ------------------------------------------------------------------------------------
# Find dependencies for GLSL files (#include ...) Call 'glslc -M' to find all
# dependencies of the file and return the list in GLSL_DEPENDENCY
#
function(get_glsl_dependencies)
  cmake_parse_arguments(GGD "" "SRC" "FLAGS" ${ARGN})
  get_filename_component(FILE_NAME ${GGD_SRC} NAME)
  get_filename_component(DIR_NAME ${GGD_SRC} DIRECTORY)

  # glslc has a bug where it won't quote paths with spaces As a workaround,
  # assume all paths are absolute and separate based on matching the root path
  # Include any added include paths in case they are on different windows drives
  set(INCLUDE_PATHS ${GGD_FLAGS})
  list(FILTER INCLUDE_PATHS INCLUDE REGEX "-I.*")
  list(TRANSFORM INCLUDE_PATHS REPLACE "-I" "")
  list(APPEND INCLUDE_PATHS ${DIR_NAME})
  set(INCLUDE_ROOTS)
  foreach(INCLUDE_PATH ${INCLUDE_PATHS})
    if(${CMAKE_VERSION} VERSION_LESS "3.20.0")
      string(REGEX MATCH "^([A-Za-z]:)?/" INCLUDE_ROOT ${INCLUDE_PATH})
    else()
      cmake_path(GET INCLUDE_PATH ROOT_PATH INCLUDE_ROOT)
    endif()
    list(APPEND INCLUDE_ROOTS ${INCLUDE_ROOT})
  endforeach()
  list(REMOVE_DUPLICATES INCLUDE_ROOTS)

  message(STATUS " - Find dependencies for ${FILE_NAME}")
  # message(STATUS "calling : ${GLSLC} ${GGD_FLAGS} -M ${GGD_SRC}
  # OUTPUT_VARIABLE DEP RESULT_VARIABLE RES")
  execute_process(
    COMMAND ${GLSLC} ${GGD_FLAGS} -M ${GGD_SRC}
    OUTPUT_VARIABLE DEP
    RESULT_VARIABLE RES)
  if(RES EQUAL 0)
    # Removing "name.spv: "
    string(REGEX REPLACE "[^:]*: " "" DEP ${DEP})
    # The command line may end with newlines. This breaks the Ninja generator on
    # CMake 3.16.2 (fixed as of 3.24.1). As a workaround, remove trailing
    # newlines.
    string(REGEX REPLACE "[\r\n]+$" "" DEP ${DEP})
    # Splitting each root with a ';'. On linux this is just ' /' -> ';/'.
    foreach(ROOT ${INCLUDE_ROOTS})
      string(REPLACE " ${ROOT}" ";${ROOT}" DEP ${DEP})
    endforeach()
    set(GLSL_DEPENDENCY
        ${DEP}
        PARENT_SCOPE)
  endif()
endfunction()

# ------------------------------------------------------------------------------------
# Function to compile all GLSL source files to Spir-V
#
# SOURCE_FILES : List of sources to compile HEADER_FILES : List of dependency
# header files DST : The destination directory (need to be absolute)
# VULKAN_TARGET : to define the vulkan target i.e vulkan1.2 (default vulkan1.1)
# HEADER ON: if ON, will generate headers instead of binary Spir-V files
# DEPENDENCY : ON|OFF will create the list of dependencies for the GLSL source
# file FLAGS: List of compile flags
#
# compile_glsl( SOURCES_FILES foo.vert foo.frag DST
# ${CMAKE_CURRENT_SOURCE_DIR}/shaders FLAGS -g0 )

function(compile_glsl)
  set(oneValueArgs DST VULKAN_TARGET HEADER DEPENDENCY)
  set(multiValueArgs SOURCE_FILES HEADER_FILES FLAGS)
  cmake_parse_arguments(COMPILE "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  # Check if the GLSL compiler is present
  if(NOT GLSLANGVALIDATOR)
    message(ERROR "Could not find GLSLANGVALIDATOR to compile shaders")
    return()
  endif()

  # By default use Vulkan 1.1
  if(NOT DEFINED COMPILE_VULKAN_TARGET)
    set(COMPILE_VULKAN_TARGET vulkan1.1)
  endif()

  # If destination is not present, same as source
  if(NOT DEFINED COMPILE_DST)
    message(ERROR " --- DST not defined")
    return()
  endif()

  # Make the output directory if needed
  file(MAKE_DIRECTORY ${COMPILE_DST})

  # If no flag set -g (debug)
  if(NOT DEFINED COMPILE_FLAGS)
    set(COMPILE_FLAGS -g)
  endif()

  # Compiling all GLSL sources
  foreach(GLSL_SRC ${COMPILE_SOURCE_FILES})

    # Find the dependency files for the GLSL source or use all headers as
    # dependencies.
    if(COMPILE_DEPENDENCY)
      get_glsl_dependencies(SRC ${GLSL_SRC} FLAGS ${COMPILE_FLAGS})
    else()
      set(GLSL_DEPENDENCY ${HEADER_FILES})
    endif()

    # Default compiler command, always adding debug information (Add and option
    # to opt-out?)
    set(COMPILE_CMD ${COMPILE_FLAGS} --target-env ${COMPILE_VULKAN_TARGET})

    # Compilation to headers need a variable name, the output will be a .h
    get_filename_component(FILE_NAME ${GLSL_SRC} NAME)
    if(COMPILE_HEADER)
      string(REPLACE "." "_" VAR_NAME ${FILE_NAME}) # Name of the variable in
                                                    # the header
      list(APPEND COMPILE_CMD --vn ${VAR_NAME})
      set(GLSL_OUT "${COMPILE_DST}/${FILE_NAME}.h")
    else()
      set(GLSL_OUT "${COMPILE_DST}/${FILE_NAME}.spv")
      list(APPEND _SPVS ${GLSL_OUT})
    endif()

    # Appending the output name and the file source
    list(APPEND COMPILE_CMD -o ${GLSL_OUT} ${GLSL_SRC})

    # The custom command is added to the build system, check for the presence of
    # the output but also for changes done in GLSL headers
    add_custom_command(
      PRE_BUILD
      OUTPUT ${GLSL_OUT}
      COMMAND echo ${GLSLANGVALIDATOR} ${COMPILE_CMD}
      COMMAND ${GLSLANGVALIDATOR} ${COMPILE_CMD}
      MAIN_DEPENDENCY ${GLSL_SRC}
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      DEPENDS ${GLSL_DEPENDENCY})
  endforeach()

  # Setting OUT variables
  set(GLSL_SOURCES
      ${COMPILE_SOURCE_FILES}
      PARENT_SCOPE)
  set(GLSL_HEADERS
      ${COMPILE_HEADER_FILES}
      PARENT_SCOPE)
  set(SPV_OUTPUT
      ${_SPVS}
      PARENT_SCOPE)

endfunction()

# ------------------------------------------------------------------------------------
# Function to compile all GLSL files from a source to Spir-V The sources are all
# .vert, .frag, .r*  and the headers for the source are .glsl and .h This allows
# to modify one of the header and getting the sources recompiled.
#
# SRC : The directory source of the shaders DST : The destination directory
# (need to be absolute) VULKAN_TARGET : to define the vulkan target i.e
# vulkan1.2 (default vulkan1.1) HEADER ON: if present, will generate headers
# instead of binary Spir-V files DEPENDENCY : ON|OFF will create the list of
# dependencies for the GLSL source file FLAGS : other glslValidator flags
#
# compile_glsl_directory( SRC "${CMAKE_CURRENT_SOURCE_DIR}/shaders" DST
# "${CMAKE_CURRENT_SOURCE_DIR}/autogen" VULKAN_TARGET "vulkan1.2" HEADER ON )
#
function(compile_glsl_directory)
  set(oneValueArgs SRC DST VULKAN_TARGET HEADER DEPENDENCY FLAGS)
  set(multiValueArgs)
  cmake_parse_arguments(COMPILE "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  # Collecting all source files
  file(
    GLOB
    GLSL_SOURCE_FILES
    "${COMPILE_SRC}/raster/*.comp" # Compute
    "${COMPILE_SRC}/raster/*.frag" # Fragment
    "${COMPILE_SRC}/raster/*.geom" # Geometry
    "${COMPILE_SRC}/raster/*.mesh" # Mesh
    "${COMPILE_SRC}/raster/*.task" # Task
    "${COMPILE_SRC}/raster/*.tesc" # Tessellation control
    "${COMPILE_SRC}/raster/*.tese" # Tessellation evaluation
    "${COMPILE_SRC}/raster/*.vert" # Vertex
    "${COMPILE_SRC}/raytrace/*.rahit" # Ray any hit
    "${COMPILE_SRC}/raytrace/*.rcall" # Ray callable
    "${COMPILE_SRC}/raytrace/*.rchit" # Ray closest hit
    "${COMPILE_SRC}/raytrace/*.rgen" # Ray generation
    "${COMPILE_SRC}/raytrace/*.rint" # Ray intersection
    "${COMPILE_SRC}/raytrace/*.rmiss" # Ray miss
  )

  # Collecting headers for dependencies
  set(GLSL_INCLUDE_DIR "${COMPILE_SRC}/include")
  file(GLOB GLSL_HEADER_FILES "${COMPILE_SRC}/include/*.glsl" # Auto detect -
                                                              # used for header
       "${COMPILE_SRC}/include/*.h")

  # By default use Vulkan 1.1
  if(NOT DEFINED COMPILE_VULKAN_TARGET)
    set(COMPILE_VULKAN_TARGET vulkan1.1)
  endif()

  # If destination is not present, same as source
  if(NOT DEFINED COMPILE_DST)
    set(COMPILE_DST ${COMPILE_SRC})
  endif()

  # If no flag set -g (debug)
  if(NOT DEFINED COMPILE_FLAGS)
    set(COMPILE_FLAGS -g -I${GLSL_INCLUDE_DIR})
  endif()

  # Compiling all GLSL
  compile_glsl(
    SOURCE_FILES
    ${GLSL_SOURCE_FILES}
    HEADER_FILES
    ${GLSL_HEADER_FILES}
    DST
    ${COMPILE_DST}
    VULKAN_TARGET
    ${COMPILE_VULKAN_TARGET}
    HEADER
    ${COMPILE_HEADER}
    DEPENDENCY
    ${COMPILE_DEPENDENCY}
    FLAGS
    ${COMPILE_FLAGS})

  # Setting OUT variables
  set(GLSL_SOURCES
      ${GLSL_SOURCE_FILES}
      PARENT_SCOPE)
  set(GLSL_HEADERS
      ${GLSL_HEADER_FILES}
      PARENT_SCOPE)
  set(SPV_OUTPUT
      ${SPV_OUTPUT}
      PARENT_SCOPE) # propagate value set in compile_glsl
endfunction()

# ------------------------------------------------------------------------------------
# Function to compile all HLSL source files to Spir-V
#
# SOURCE_FILES : List of sources to compile HEADER_FILES : List of dependency
# header files DST : The destination directory (need to be absolute)
# VULKAN_TARGET : to define the vulkan target i.e vulkan1.2 (default vulkan1.1)
# HEADER ON: if ON, will generate headers instead of binary Spir-V files
# DEPENDENCY : ON|OFF will create the list of dependencies for the HLSL source
# file FLAGS: List of compile flags
#
# compile_glsl( SOURCES_FILES foo.vert foo.frag DST
# ${CMAKE_CURRENT_SOURCE_DIR}/shaders FLAGS -g0 )

function(compile_hlsl)
  set(oneValueArgs DST VULKAN_TARGET DXC_TARGET HEADER DEPENDENCY)
  set(multiValueArgs SOURCE_FILES HEADER_FILES FLAGS)
  cmake_parse_arguments(COMPILE "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  # Check if the HLSL compiler is present
  if(NOT DIRECTXCOMPILER)
    message(ERROR "Could not find DIRECTXCOMPILER to compile shaders")
    return()
  endif()

  # By default use Vulkan 1.1
  if(NOT DEFINED COMPILE_VULKAN_TARGET)
    set(COMPILE_VULKAN_TARGET vulkan1.1)
  endif()

  # By default use Vulkan 1.1
  if(NOT DEFINED COMPILE_DXC_TARGET)
    set(COMPILE_DXC_TARGET 6_0)
  endif()

  # If destination is not present, same as source
  if(NOT DEFINED COMPILE_DST)
    message(ERROR " --- DST not defined")
    return()
  endif()

  # Make the output directory if needed
  file(MAKE_DIRECTORY ${COMPILE_DST})

  # If no flag set -g (debug)
  if(NOT DEFINED COMPILE_FLAGS)
    set(COMPILE_FLAGS -spirv)
  endif()

  # Compiling all HLSL sources
  foreach(HLSL_SRC ${COMPILE_SOURCE_FILES})

    # Find the dependency files for the HLSL source or use all headers as
    # dependencies. if(COMPILE_DEPENDENCY) get_glsl_dependencies(SRC ${HLSL_SRC}
    # FLAGS ${COMPILE_FLAGS}) else() set(HLSL_DEPENDENCY ${HEADER_FILES})
    # endif()

    set(HLSL_DEPENDENCY ${HLSL_SRC})

    # Default compiler command, always adding debug information (Add and option
    # to opt-out?)
    set(COMPILE_CMD ${COMPILE_FLAGS} -fspv-target-env=${COMPILE_VULKAN_TARGET})

    # Compilation to headers need a variable name, the output will be a .h
    get_filename_component(FILE_NAME ${HLSL_SRC} NAME)
    get_filename_component(EXTENSION ${FILE_NAME} EXT)
    if(COMPILE_HEADER)
      string(REPLACE "." "_" VAR_NAME ${FILE_NAME}) # Name of the variable in
                                                    # the header
      list(APPEND COMPILE_CMD --vn ${VAR_NAME})
      set(HLSL_OUT "${COMPILE_DST}/${FILE_NAME}.h")
    else()
      set(HLSL_OUT "${COMPILE_DST}/${FILE_NAME}.spv")
      list(APPEND _SPVS ${HLSL_OUT})
    endif()

    if("${EXTENSION}" STREQUAL ".vert")
      list(APPEND COMPILE_CMD -T vs_${COMPILE_DXC_TARGET})
    elseif("${EXTENSION}" STREQUAL ".frag")
      list(APPEND COMPILE_CMD -T ps_${COMPILE_DXC_TARGET})
    endif()

    # Appending the output name and the file source
    list(
      APPEND
      COMPILE_CMD
      -Fo
      ${HLSL_OUT}
      ${HLSL_SRC}
      -E
      main)

    # The custom command is added to the build system, check for the presence of
    # the output but also for changes done in HLSL headers
    add_custom_command(
      PRE_BUILD
      OUTPUT ${HLSL_OUT}
      COMMAND echo ${DIRECTXCOMPILER} ${COMPILE_CMD}
      COMMAND ${DIRECTXCOMPILER} ${COMPILE_CMD}
      MAIN_DEPENDENCY ${HLSL_SRC}
      WORKING_DIRECTORY ${CMAKE_CURRENT_SOURCE_DIR}
      DEPENDS ${HLSL_DEPENDENCY})
  endforeach()

  # Setting OUT variables
  set(HLSL_SOURCES
      ${COMPILE_SOURCE_FILES}
      PARENT_SCOPE)
  set(HLSL_HEADERS
      ${COMPILE_HEADER_FILES}
      PARENT_SCOPE)
  set(HLSL_SPV_OUTPUT
      ${_SPVS}
      PARENT_SCOPE)

endfunction()

function(compile_hlsl_directory)
  set(oneValueArgs
      SRC
      DST
      VULKAN_TARGET
      DXC_TARGET
      HEADER
      DEPENDENCY
      FLAGS)
  set(multiValueArgs)
  cmake_parse_arguments(COMPILE "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  # Collecting all source files
  file(
    GLOB
    HLSL_SOURCE_FILES
    "${COMPILE_SRC}/raster/*.comp" # Compute
    "${COMPILE_SRC}/raster/*.frag" # Fragment
    "${COMPILE_SRC}/raster/*.geom" # Geometry
    "${COMPILE_SRC}/raster/*.mesh" # Mesh
    "${COMPILE_SRC}/raster/*.task" # Task
    "${COMPILE_SRC}/raster/*.tesc" # Tessellation control
    "${COMPILE_SRC}/raster/*.tese" # Tessellation evaluation
    "${COMPILE_SRC}/raster/*.vert" # Vertex

    "${COMPILE_SRC}/raytrace/*.rahit" # Ray any hit
    "${COMPILE_SRC}/raytrace/*.rcall" # Ray callable
    "${COMPILE_SRC}/raytrace/*.rchit" # Ray closest hit
    "${COMPILE_SRC}/raytrace/*.rgen" # Ray generation
    "${COMPILE_SRC}/raytrace/*.rint" # Ray intersection
    "${COMPILE_SRC}/raytrace/*.rmiss" # Ray miss
  )

  message(STATUS "STATUS ${HLSL_SOURCE_FILES}")

  # Collecting headers for dependencies
  set(HLSL_INCLUDE_DIR "${COMPILE_SRC}/include" "${COMPILE_SRC}/")
  file(GLOB HLSL_HEADER_FILES "${COMPILE_SRC}/include/*.hlsl" # Auto detect -
                                                              # used for header
       "${COMPILE_SRC}/include/*.h")

  # By default use Vulkan 1.1
  if(NOT DEFINED COMPILE_VULKAN_TARGET)
    set(COMPILE_VULKAN_TARGET vulkan1.1)
  endif()

  # By default use 6_0
  if(NOT DEFINED COMPILE_DXC_TARGET)
    set(COMPILE_DXC_TARGET 6_0)
  endif()

  # If destination is not present, same as source
  if(NOT DEFINED COMPILE_DST)
    set(COMPILE_DST ${COMPILE_SRC})
  endif()

  # If no flag set -g (debug)
  if(NOT DEFINED COMPILE_FLAGS)
    set(COMPILE_FLAGS -spirv -I${HLSL_INCLUDE_DIR})
  endif()

  # Compiling all HLSL
  compile_hlsl(
    SOURCE_FILES
    ${HLSL_SOURCE_FILES}
    HEADER_FILES
    ${HLSL_HEADER_FILES}
    DST
    ${COMPILE_DST}
    VULKAN_TARGET
    ${COMPILE_VULKAN_TARGET}
    DXC_TARGET
    ${COMPILE_DXC_TARGET}
    HEADER
    ${COMPILE_HEADER}
    DEPENDENCY
    ${COMPILE_DEPENDENCY}
    FLAGS
    ${COMPILE_FLAGS})

  # Setting OUT variables
  set(HLSL_SOURCES
      ${HLSL_SOURCE_FILES}
      PARENT_SCOPE)
  set(HLSL_HEADERS
      ${HLSL_HEADER_FILES}
      PARENT_SCOPE)
  set(HLSL_SPV_OUTPUT
      ${HLSL_SPV_OUTPUT}
      PARENT_SCOPE) # propagate value set in compile_glsl
endfunction()

function(compile_shader_directory)
  set(oneValueArgs SRC VULKAN_TARGET HEADER DEPENDENCY FLAGS)
  set(multiValueArgs)
  cmake_parse_arguments(COMPILE "${options}" "${oneValueArgs}"
                        "${multiValueArgs}" ${ARGN})

  # HLSL Shaders
  if(COMPILE_HLSL)
    set(HLSL_SOURCE_DIR "${COMPILE_SRC}/hlsl")
    compile_hlsl_directory(
      SRC
      "${HLSL_SOURCE_DIR}"
      DST
      "${HLSL_SOURCE_DIR}/spv"
      VULKAN_TARGET
      "${COMPILE_VULKAN_TARGET}"
      DXC_TARGET
      "6_4"
      DEPENDENCY
      ${COMPILE_DEPENDENCY})
  endif()

  set(HLSL_SOURCES
      ${HLSL_SOURCES}
      PARENT_SCOPE)
  set(HLSL_HEADERS
      ${HLSL_HEADERS}
      PARENT_SCOPE)
  set(HLSL_SPV_OUTPUT
      ${HLSL_SPV_OUTPUT}
      PARENT_SCOPE) # propagate value set in compile_glsl
  set(GLSL_SOURCE_DIR "${COMPILE_SRC}/glsl")

  # GLSL Shaders
  compile_glsl_directory(
    SRC
    "${GLSL_SOURCE_DIR}"
    DST
    "${GLSL_SOURCE_DIR}/spv"
    VULKAN_TARGET
    "${COMPILE_VULKAN_TARGET}"
    DEPENDENCY
    ${COMPILE_DEPENDENCY})

  # Setting OUT variables
  set(GLSL_SOURCES
      ${GLSL_SOURCES}
      PARENT_SCOPE)
  set(GLSL_HEADERS
      ${GLSL_HEADERS}
      PARENT_SCOPE)
  set(GLSL_SPV_OUTPUT
      ${GLSL_SPV_OUTPUT}
      PARENT_SCOPE) # propagate value set in compile_glsl

endfunction()
