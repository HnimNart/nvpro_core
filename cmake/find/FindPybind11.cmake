# Try to find PYBIND11 project so and include file
#
set(PYBIND11_LOCATION "" CACHE STRING "Set to location of pybind11 library/headers")
unset(PYBIND11_INCLUDE_DIR CACHE)
unset(PYBIND11_FOUND CACHE)

if(USE_PACKMAN)
  message ( STATUS "attempting to using packman to source pybind11")

  if (WIN32)
    set(PYBIND11_PACKMAN_PLATFORM "windows-x86_64")
    set(PACKMAN_COMMAND "packman.cmd")
  elseif (UNIX)
    set(PYBIND11_PACKMAN_PLATFORM "linux-${CMAKE_HOST_SYSTEM_PROCESSOR}")
    set(PACKMAN_COMMAND "packman")
  endif()

  if (EXISTS ${BASE_DIRECTORY}/nvpro_core/OV/packman/${PACKMAN_COMMAND})
    message(STATUS "Pulling pybind11 dependencies...")
    message(STATUS "    Platform: ${PYBIND11_PACKMAN_PLATFORM}")

    # To keep python versions in sync (probably need to encapsulate all deps in a single 
    # .xml and individual components could just import what they want from that.
    file(COPY "${BASE_DIRECTORY}/nvpro_core/OV/omniclient-deps.packman.xml"
            DESTINATION "${BASE_DIRECTORY}/nvpro_core/OV/downloaded")

    file(MAKE_DIRECTORY "${BASE_DIRECTORY}/nvpro_core/OV/downloaded")
    configure_file(
      "${BASE_DIRECTORY}/nvpro_core/OV/pybind11.packman.xml"
      "${BASE_DIRECTORY}/nvpro_core/OV/downloaded/pybind11-deps.packman.xml"
      @ONLY
    )

    execute_process(COMMAND "${BASE_DIRECTORY}/nvpro_core/OV/packman/${PACKMAN_COMMAND}" pull "${BASE_DIRECTORY}/nvpro_core/OV/downloaded/pybind11-deps.packman.xml" -p ${PYBIND11_PACKMAN_PLATFORM}
                    WORKING_DIRECTORY "${BASE_DIRECTORY}/nvpro_core/OV/downloaded"
                    RESULT_VARIABLE PYBIND11_PACKMAN_RESULT)

    Message(STATUS "execute_process(COMMAND ${BASE_DIRECTORY}/nvpro_core/OV/packman/${PACKMAN_COMMAND} pull ${BASE_DIRECTORY}/nvpro_core/OV/downloaded/pybind11-deps.packman.xml -p ${PYBIND11_PACKMAN_PLATFORM}
                    WORKING_DIRECTORY ${BASE_DIRECTORY}/nvpro_core/OV/downloaded
                    RESULT_VARIABLE PYBIND11_PACKMAN_RESULT)")

    if (${PYBIND11_PACKMAN_RESULT} EQUAL 0)
      message(STATUS "    Packman result: success")
    else()
      message(FATAL_ERROR "    Packman result: ${PYBIND11_PACKMAN_RESULT}")
    endif()                  

    set(PYBIND11_LOCATION "${BASE_DIRECTORY}/nvpro_core/OV/downloaded/pybind11")
  else()
    message(FATAL_ERROR "Unable to find packman")
  endif()
endif()

if (NOT DEFINED PYBIND11_LOCATION)
  message(WARNING "PYBIND11_LOCATION is not defined")
elseif(NOT EXISTS ${PYBIND11_LOCATION})
  message(WARNING "PYBIND11_LOCATION doesn't exist")
endif()

find_path(PYBIND11_INCLUDE_DIR
  NAMES pybind11/pybind11.h
  PATHS ${PYBIND11_LOCATION}
)

if(PYBIND11_INCLUDE_DIR)
  message(STATUS " pybind11.h found in ${PYBIND11_INCLUDE_DIR}")

  set( PYBIND11_FOUND "YES" )

else(PYBIND11_INCLUDE_DIR)
  message(WARNING "
      pybind11 not found.")
endif(PYBIND11_INCLUDE_DIR)

include(FindPackageHandleStandardArgs)

find_package_handle_standard_args(Pybind11 DEFAULT_MSG
    PYBIND11_INCLUDE_DIR
)

set(PYBIND11_INCLUDE_DIR ${PYBIND11_INCLUDE_DIR} CACHE PATH "path")

mark_as_advanced( PYBIND11_FOUND )
