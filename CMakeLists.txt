cmake_minimum_required(VERSION 3.29)

if(POLICY CMP0157)
    cmake_policy(SET CMP0157 NEW)
endif()

if(DEFINED ENV{IDF_PATH})
    idf_component_register()
else()
    include(ExternalProject)
endif()

file(GLOB_RECURSE JSON_CORE_SOURCES "${CMAKE_CURRENT_SOURCE_DIR}/Sources/JSONCore/*.swift")
add_library(JSON ${JSON_CORE_SOURCES})

if(DEFINED ENV{IDF_PATH})
    enable_language(Swift)    

    # Get the target and architecture to configure the Swift compiler flags
    idf_build_get_property(target IDF_TARGET)
    idf_build_get_property(arch IDF_TARGET_ARCH)

    if(${target} STREQUAL "esp32c2" OR ${target} STREQUAL "esp32c3")
        set(march_flag "rv32imc_zicsr_zifencei")
        set(mabi_flag "ilp32")
    elseif(${target} STREQUAL "esp32p4")
        set(march_flag "rv32imafc_zicsr_zifencei")
        set(mabi_flag "ilp32f")
    else()
        set(march_flag "rv32imac_zicsr_zifencei")
        set(mabi_flag "ilp32")
    endif()

    # We need to clear the default COMPILE_OPTIONS, which include C/C++ specific compiler flags that the
    # Swift compiler will not accept.
    get_target_property(CURRENT_COMPILE_OPTIONS JSON COMPILE_OPTIONS)
    set_target_properties(JSON PROPERTIES COMPILE_OPTIONS "")

    target_compile_options(JSON PUBLIC "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
        -target riscv32-none-none-eabi
        -Xfrontend -function-sections -enable-experimental-feature Embedded -wmo -parse-as-library -Osize
        -Xcc -march=${march_flag} -Xcc -mabi=${mabi_flag}
        
        -pch-output-dir /tmp
        -Xfrontend -enable-single-module-llvm-emission
    >")
else()
    project(JSON LANGUAGES Swift)

    target_compile_options(JSON PRIVATE "$<$<COMPILE_LANGUAGE:Swift>:SHELL:
        -Xfrontend -function-sections -enable-experimental-feature Embedded -wmo -parse-as-library -Osize
        
        -pch-output-dir /tmp
        -Xfrontend -enable-single-module-llvm-emission
    >")
endif()
