#!/bin/bash -e
source $(dirname $0)/env.sh
BUILD_TYPE="Release"
# BUILD_TYPE="Debug"

GN_ARGS_BASE="
  target_os=\"${PLATFORM}\"
  is_component_build=false
  treat_warnings_as_errors=false
  use_debug_fission=false
  use_custom_libcxx=false
  use_xcode_clang = true
  v8_use_external_startup_data=false
  icu_use_data_file=false
  v8_monolithic=true
  enable_ios_bitcode=false
  is_debug = false
  ios_deployment_target=10
  v8_use_external_startup_data=false
  symbol_level=0
"

if [[ ${PLATFORM} = "ios" ]]; then
  GN_ARGS_BASE="${GN_ARGS_BASE} enable_ios_bitcode=false use_xcode_clang=true ios_enable_code_signing=false v8_enable_pointer_compression=false ios_deployment_target=${IOS_DEPLOYMENT_TARGET}"
fi

if [[ ${NO_INTL} = "1" ]]; then
  GN_ARGS_BASE="${GN_ARGS_BASE} v8_enable_i18n_support=false"
fi

if [[ ${DISABLE_JIT} != "false" ]]; then
  GN_ARGS_BASE="${GN_ARGS_BASE} v8_enable_lite_mode=true"
fi

if [[ "$BUILD_TYPE" = "Debug" ]]
then
  GN_ARGS_BUILD_TYPE='
    is_debug=true
    symbol_level=2
  '
else
  GN_ARGS_BUILD_TYPE='
    is_debug=false
  '
fi

NINJA_PARAMS=""

if [[ ${CIRCLECI} ]]; then
  NINJA_PARAMS="-j4"
fi

cd ${V8_DIR}

function normalize_arch_for_platform()
{
  local arch=$1

  if [[ ${PLATFORM} = "ios" ]]; then
    echo ${arch}
    return
  fi

  case "$1" in
    arm)
      echo "armeabi-v7a"
      ;;
    x86)
      echo "x86"
      ;;
    arm64)
      echo "arm64-v8a"
      ;;
    x64)
      echo "x86_64"
      ;;
    *)
      echo "Invalid arch - ${arch}" >&2
      exit 1
      ;;
  esac
}

function build_arch()
{
  local arch=$1
  local platform_arch=$(normalize_arch_for_platform $arch)

  local target=''
  local target_ext=''
  local targetName=''
  local targetFolder=''
  if [[ ${PLATFORM} = "android" ]]; then
    target="libv8android"
    targetName="libv8android"
    target_ext=".so"
  elif [[ ${PLATFORM} = "ios" ]]; then
    target="v8_monolith"
    targetName="libv8_monolith"
    targetFolder="obj/"
    target_ext=".a"
  else
    exit 1
  fi

  echo "Build v8 ${arch} variant NO_INTL=${NO_INTL}"
  gn gen --args="${GN_ARGS_BASE} ${GN_ARGS_BUILD_TYPE} target_cpu=\"${arch}\"" "out.v8.${arch}"

  if [[ ${MKSNAPSHOT_ONLY} = "1" ]]; then
    date ; ninja ${NINJA_PARAMS} -C "out.v8.${arch}" run_mksnapshot_default ; date
  else
    date ; ninja ${NINJA_PARAMS} -C "out.v8.${arch}" ${target} ; date

    mkdir -p "${BUILD_DIR}/lib/${platform_arch}"
    cp -f "out.v8.${arch}/${targetFolder}${targetName}${target_ext}" "${BUILD_DIR}/lib/${platform_arch}/${targetName}${target_ext}"

    if [[ -d "out.v8.${arch}/lib.unstripped" ]]; then
      mkdir -p "${BUILD_DIR}/lib.unstripped/${platform_arch}"
      cp -f "out.v8.${arch}/lib.unstripped/${target}${target_ext}" "${BUILD_DIR}/lib.unstripped/${platform_arch}/${target}${target_ext}"
    fi
  fi

  mkdir -p "${BUILD_DIR}/tools/${platform_arch}"
  cp -f out.v8.${arch}/clang_*/mksnapshot "${BUILD_DIR}/tools/${platform_arch}/mksnapshot"
}

if [[ ${PLATFORM} = "android" ]]; then
  build_arch "arm"
  build_arch "x86"
  build_arch "arm64"
  build_arch "x64"
elif [[ ${PLATFORM} = "ios" ]]; then
  build_arch "arm64"
  build_arch "x64"
fi
