#!/bin/bash

set -ex

source "$(dirname "${BASH_SOURCE[0]}")/compute_utils.sh"

set_component_src hipSOLVER

build_hipsolver() {
    echo "Start build"

    if [ "${ENABLE_STATIC_BUILDS}" == "true" ]; then
        CXX_FLAG=$(set_build_variables __CMAKE_CXX_PARAMS__)
    fi

    cd $COMPONENT_SRC

    CXX=$(set_build_variables __AMD_CLANG_++__)
    if [ "${ENABLE_ADDRESS_SANITIZER}" == "true" ]; then
       set_asan_env_vars
       set_address_sanitizer_on
    fi

    SHARED_LIBS="ON"
    if [ "${ENABLE_STATIC_BUILDS}" == "true" ]; then
        SHARED_LIBS="OFF"
    fi

    echo "C compiler: $CC"
    echo "CXX compiler: $CXX"
    echo "FC compiler: $FC"

    mkdir -p "$BUILD_DIR" && cd "$BUILD_DIR"

    if [ "${ENABLE_ADDRESS_SANITIZER}" == "true" ]; then
       rebuild_lapack
    fi

    init_rocm_common_cmake_params
    cmake \
        -DUSE_CUDA=OFF \
	    -DCMAKE_CXX_COMPILER=${CXX} \
        ${LAUNCHER_FLAGS} \
        "${rocm_math_common_cmake_params[@]}" \
        -DBUILD_SHARED_LIBS=$SHARED_LIBS \
        -DBUILD_CLIENTS_TESTS=ON \
        -DBUILD_CLIENTS_BENCHMARKS=ON \
        -DBUILD_CLIENTS_SAMPLES=ON \
        -DBUILD_ADDRESS_SANITIZER="${ADDRESS_SANITIZER}" \
        ${CXX_FLAG} \
        "$COMPONENT_SRC"

    cmake --build "$BUILD_DIR" -- -j${PROC}
    cmake --build "$BUILD_DIR" -- install
    cmake --build "$BUILD_DIR" -- package

    rm -rf _CPack_Packages/ && find -name '*.o' -delete
    copy_if "${PKGTYPE}" "${CPACKGEN:-"DEB;RPM"}" "${PACKAGE_DIR}" "${BUILD_DIR}"/*."${PKGTYPE}"

    show_build_cache_stats
}

clean_hipsolver() {
    echo "Cleaning hipSOLVER build directory: ${BUILD_DIR} ${PACKAGE_DIR}"
    rm -rf "$BUILD_DIR" "$PACKAGE_DIR"
    echo "Done!"
}

stage2_command_args "$@"

case $TARGET in
    build) build_hipsolver; build_wheel ;;
    outdir) print_output_directory ;;
    clean) clean_hipsolver ;;
    *) die "Invalid target $TARGET" ;;
esac
