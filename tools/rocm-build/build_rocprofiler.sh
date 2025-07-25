#!/bin/bash

source "$(dirname "${BASH_SOURCE}")/compute_utils.sh"

printUsage() {
    echo
    echo "Usage: ${BASH_SOURCE##*/} [options ...]"
    echo
    echo "Options:"
    echo "  -c,  --clean              Clean output and delete all intermediate work"
    echo "  -s,  --static             Component/Build does not support static builds just accepting this param & ignore. No effect of the param on this build"
    echo "  -p,  --package <type>     Specify packaging format"
    echo "  -r,  --release            Make a release build instead of a debug build"
    echo "  -a,  --address_sanitizer  Enable address sanitizer"
    echo "  -w,  --wheel              Creates python wheel package of roc-profiler.
                                      It needs to be used along with -r option"
    echo "  -o,  --outdir <pkg_type>  Print path of output directory containing packages of
    type referred to by pkg_type"
    echo "  -h,  --help               Prints this help"
    echo
    echo "Possible values for <type>:"
    echo "  deb -> Debian format (default)"
    echo "  rpm -> RPM format"
    echo

    return 0
}

## Build environment variables
API_NAME="rocprofiler"
PROJ_NAME="$API_NAME"
LIB_NAME="lib${API_NAME}"
TARGET="build"
MAKETARGET="deb"
PACKAGE_ROOT="$(getPackageRoot)"
PACKAGE_LIB="$(getLibPath)"
PACKAGE_INCLUDE="$(getIncludePath)"
BUILD_DIR="$(getBuildPath $API_NAME)"
PACKAGE_DEB="$PACKAGE_ROOT/deb/$PROJ_NAME"
PACKAGE_RPM="$PACKAGE_ROOT/rpm/$PROJ_NAME"
PACKAGE_PREFIX="$ROCM_INSTALL_PATH"
BUILD_TYPE="Debug"
MAKE_OPTS="$DASH_JAY -C $BUILD_DIR"
SHARED_LIBS="ON"
CLEAN_OR_OUT=0
MAKETARGET="deb"
PKGTYPE="deb"
# Handling GPU Targets for HSACO and HIP Executables
GPU_LIST="gfx900,gfx906,gfx908,gfx90a,gfx940,gfx941,gfx942,gfx1030,gfx1031,gfx1100,gfx1101,gfx1102,gfx1200,gfx1201"

#parse the arguments
VALID_STR=$(getopt -o hcraswo:p: --long help,clean,release,static,wheel,address_sanitizer,outdir:,package: -- "$@")
eval set -- "$VALID_STR"

while true; do
    #echo "parocessing $1"
    case "$1" in
    -h | --help)
        printUsage
        exit 0
        ;;
    -c | --clean)
        TARGET="clean"
        ((CLEAN_OR_OUT |= 1))
        shift
        ;;
    -r | --release)
        BUILD_TYPE="RelWithDebInfo"
        shift
        ;;
    -a | --address_sanitizer)
        set_asan_env_vars
        set_address_sanitizer_on
        shift
        ;;
    -s | --static)
        ack_and_skip_static
        ;;
    -w | --wheel)
        WHEEL_PACKAGE=true
        shift
        ;;
    -o | --outdir)
        TARGET="outdir"
        PKGTYPE=$2
        OUT_DIR_SPECIFIED=1
        ((CLEAN_OR_OUT |= 2))
        shift 2
        ;;
    -p | --package)
        MAKETARGET="$2"
        shift 2
        ;;
    --)
        shift
        break
        ;; # end delimiter
    *)
        echo " This should never come but just incase : UNEXPECTED ERROR Parm : [$1] " >&2
        exit 20
        ;;
    esac

done

RET_CONFLICT=1
check_conflicting_options $CLEAN_OR_OUT $PKGTYPE $MAKETARGET
if [ $RET_CONFLICT -ge 30 ]; then
    print_vars $API_NAME $TARGET $BUILD_TYPE $SHARED_LIBS $CLEAN_OR_OUT $PKGTYPE $MAKETARGET
    exit $RET_CONFLICT
fi

clean() {
    echo "Cleaning $PROJ_NAME"
    rm -rf "$BUILD_DIR"
    rm -rf "$PACKAGE_DEB"
    rm -rf "$PACKAGE_RPM"
    rm -rf "$PACKAGE_ROOT/${PROJ_NAME}"
    rm -rf "$PACKAGE_ROOT/libexec/${PROJ_NAME}"
    rm -rf "$PACKAGE_INCLUDE/${PROJ_NAME}"
    rm -rf "$PACKAGE_LIB/${LIB_NAME}"*
    rm -rf "$PACKAGE_LIB/${PROJ_NAME}"
}

build_rocprofiler() {
    echo "Building $PROJ_NAME"
    PACKAGE_CMAKE="$(getCmakePath)"
    if [ ! -d "$BUILD_DIR" ]; then
        mkdir -p "$BUILD_DIR"
        pushd "$BUILD_DIR"
        print_lib_type $SHARED_LIBS

        cmake \
            $(rocm_cmake_params) \
            -DCMAKE_MODULE_PATH="$ROCPROFILER_ROOT/cmake_modules;$PACKAGE_CMAKE/hip" \
            $(rocm_common_cmake_params) \
            -DBUILD_SHARED_LIBS=$SHARED_LIBS \
            -DENABLE_LDCONFIG=OFF \
            -DUSE_PROF_API=1 \
            -DUSE_GET_ROCM_PATH_API=1 \
            -DGPU_TARGETS="$GPU_LIST" \
            -DPython3_EXECUTABLE=$(which python3) \
            -DPROF_API_HEADER_PATH="$WORK_ROOT/roctracer/inc/ext" \
            -DHIP_HIPCC_FLAGS=$HIP_HIPCC_FLAGS";--offload-arch=$GPU_LIST" \
            -DCPACK_OBJCOPY_EXECUTABLE="${ROCM_INSTALL_PATH}/llvm/bin/llvm-objcopy" \
            -DCPACK_READELF_EXECUTABLE="${ROCM_INSTALL_PATH}/llvm/bin/llvm-readelf" \
            -DCPACK_STRIP_EXECUTABLE="${ROCM_INSTALL_PATH}/llvm/bin/llvm-strip" \
            -DCPACK_OBJDUMP_EXECUTABLE="${ROCM_INSTALL_PATH}/llvm/bin/llvm-objdump" \
            "$ROCPROFILER_ROOT"

        popd
    fi
    cmake --build "$BUILD_DIR" -- $MAKE_OPTS
    cmake --build "$BUILD_DIR" -- $MAKE_OPTS mytest
    cmake --build "$BUILD_DIR" -- $MAKE_OPTS install
    cmake --build "$BUILD_DIR" -- $MAKE_OPTS package

    copy_if DEB "${CPACKGEN:-"DEB;RPM"}" "$PACKAGE_DEB" "$BUILD_DIR/${API_NAME}"*.deb
    copy_if RPM "${CPACKGEN:-"DEB;RPM"}" "$PACKAGE_RPM" "$BUILD_DIR/${API_NAME}"*.rpm
}

print_output_directory() {
    case ${PKGTYPE} in
    "deb")
        echo ${PACKAGE_DEB}
        ;;
    "rpm")
        echo ${PACKAGE_RPM}
        ;;
    *)
        echo "Invalid package type \"${PKGTYPE}\" provided for -o" >&2
        exit 1
        ;;
    esac
    exit
}

verifyEnvSetup

case "$TARGET" in
clean) clean ;;
build) build_rocprofiler; build_wheel "$BUILD_DIR" "$PROJ_NAME" ;;
outdir) print_output_directory ;;
*) die "Invalid target $TARGET" ;;
esac

echo "Operation complete"
