#!/bin/sh

shell_quote_string() {
    echo "$1" | sed -e 's,\([^a-zA-Z0-9/_.=-]\),\\\1,g'
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS]
    The following options may be given :
        --builddir=DIR      Absolute path to the dir where all actions will be performed
        --get_sources       Source will be downloaded from github
        --build_src_rpm     If it is set - src rpm will be built
        --build_rpm         If it is set - rpm will be built
        --install_deps      Install build dependencies(root privilages are required)
        --branch            Branch for build
        --repo              Repo for build
        --version           Version to build

        --help) usage ;;
Example $0 --builddir=/tmp/percona-binlog-server --get_sources=1 --build_src_rpm=1 --build_rpm=1
EOF
    exit 1
}

append_arg_to_args() {
    args="$args "$(shell_quote_string "$1")
}

parse_arguments() {
    pick_args=
    if test "$1" = PICK-ARGS-FROM-ARGV; then
        pick_args=1
        shift
    fi

    for arg; do
        val=$(echo "$arg" | sed -e 's;^--[^=]*=;;')
        case "$arg" in
        --builddir=*) WORKDIR="$val" ;;
        --build_src_rpm=*) SRPM="$val" ;;
        --build_rpm=*) RPM="$val" ;;
        --get_sources=*) SOURCE="$val" ;;
        --branch=*) BRANCH="$val" ;;
        --repo=*) REPO="$val" ;;
        --version=*) VERSION="$val" ;;
        --install_deps=*) INSTALL="$val" ;;
        --release=*) RELEASE="$val" ;;
        --help) usage ;;
        *)
            if test -n "$pick_args"; then
                append_arg_to_args "$arg"
            fi
            ;;
        esac
    done
}

check_workdir() {
    if [ "x$WORKDIR" = "x$CURDIR" ]; then
        echo >&2 "Current directory cannot be used for building!"
        exit 1
    else
        if ! test -d "$WORKDIR"; then
            echo >&2 "$WORKDIR is not a directory."
            exit 1
        fi
    fi
    return
}

get_sources() {
    cd "${WORKDIR}"
    if [ "${SOURCE}" = 0 ]; then
        echo "Sources will not be downloaded"
        return 0
    fi
    PRODUCT=percona-binlog-server
    PRODUCT_FULL=${PRODUCT}-${VERSION}
    echo "PRODUCT=${PRODUCT}" >percona-binlog-server.properties
    echo "BUILD_NUMBER=${BUILD_NUMBER}" >>percona-binlog-server.properties
    echo "BUILD_ID=${BUILD_ID}" >>percona-binlog-server.properties
    echo "VERSION=${VERSION}" >>percona-binlog-server.properties
    echo "BRANCH=${BRANCH}" >>percona-binlog-server.properties
    git clone "$REPO" ${PRODUCT}
    retval=$?
    if [ $retval != 0 ]; then
        echo "There were some issues during repo cloning from github. Please retry one more time"
        exit 1
    fi
    cd percona-binlog-server
    if [ ! -z "$BRANCH" ]; then
        git reset --hard
        git clean -xdf
        git checkout "$BRANCH"
    fi
    REVISION=$(git rev-parse --short HEAD)
    GITCOMMIT=$(git rev-parse HEAD 2>/dev/null)
    GITBRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
    echo "VERSION=${VERSION}" >VERSION
    echo "REVISION=${REVISION}" >>VERSION
    echo "GITCOMMIT=${GITCOMMIT}" >>VERSION
    echo "GITBRANCH=${GITBRANCH}" >>VERSION
    echo "REVISION=${REVISION}" >>${WORKDIR}/percona-binlog-server.properties
    rm -fr  rpm
    cd ${WORKDIR}

    mv percona-binlog-server ${PRODUCT}-${VERSION}
    tar --owner=0 --group=0 -czf ${PRODUCT}-${VERSION}.tar.gz ${PRODUCT}-${VERSION}
    echo "UPLOAD=UPLOAD/experimental/BUILDS/${PRODUCT}/${PRODUCT}-${VERSION}/${BRANCH}/${REVISION}/${BUILD_ID}" >>percona-binlog-server.properties
    mkdir $WORKDIR/source_tarball
    mkdir $CURDIR/source_tarball
    cp ${PRODUCT}-${VERSION}.tar.gz $WORKDIR/source_tarball
    cp ${PRODUCT}-${VERSION}.tar.gz $CURDIR/source_tarball
    cd $CURDIR
    rm -rf percona-binlog-server
    return
}

get_system() {
    if [ -f /etc/redhat-release ]; then
        RHEL=$(rpm --eval %rhel)
        ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')
        OS_NAME="el$RHEL"
        OS="rpm"
    else
        ARCH=$(uname -m)
        OS_NAME="$(lsb_release -sc)"
        OS="deb"
    fi
    return
}

install_deps() {
    if [ $INSTALL = 0 ]; then
        echo "Dependencies will not be installed"
        return
    fi
    if [ ! $(id -u) -eq 0 ]; then
        echo "It is not possible to install dependencies. Please run as root"
        exit 1
    fi
    CURPLACE=$(pwd)

    if [ "x$OS" = "xrpm" ]; then
        RHEL=$(rpm --eval %rhel)
        yum clean all
        yum -y install epel-release git wget curl
        yum -y install rpm-build make rpmlint rpmdevtools gcc-c++ cmake3 libcurl-devel zlib-devel
	yum -y install gcc-toolset-12-gcc gcc-toolset-12-gcc-c++ gcc-toolset-12-binutils
	source /opt/rh/gcc-toolset-12/enable
	yum -y install https://repo.percona.com/yum/percona-release-latest.noarch.rpm
	percona-release enable ps-80 release
	yum -y install percona-server-devel
    fi
    return
}

get_tar() {
    TARBALL=$1
    TARFILE=$(basename $(find $WORKDIR/$TARBALL -name 'percona-binlog-server*.tar.gz' | sort | tail -n1))
    if [ -z $TARFILE ]; then
        TARFILE=$(basename $(find $CURDIR/$TARBALL -name 'percona-binlog-server*.tar.gz' | sort | tail -n1))
        if [ -z $TARFILE ]; then
            echo "There is no $TARBALL for build"
            exit 1
        else
            cp $CURDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
        fi
    else
        cp $WORKDIR/$TARBALL/$TARFILE $WORKDIR/$TARFILE
    fi
    return
}

build_srpm() {
    if [ $SRPM = 0 ]; then
        echo "SRC RPM will not be created"
        return
    fi
    if [ "x$OS" = "xdeb" ]; then
        echo "It is not possible to build src rpm here"
        exit 1
    fi
    cd $WORKDIR
    get_tar "source_tarball"
    rm -fr rpmbuild
    ls | grep -v tar.gz | xargs rm -rf
    TARFILE=$(find . -name 'percona-binlog-server*.tar.gz' | sort | tail -n1)
    SRC_DIR=${TARFILE%.tar.gz}
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/packaging' --strip=1
    tar vxzf ${WORKDIR}/${TARFILE} --wildcards '*/VERSION' --strip=1
    source VERSION
    #
    sed -e "s:@@VERSION@@:${VERSION}:g" \
        -e "s:@@RELEASE@@:${RELEASE}:g" \
        -e "s:@@REVISION@@:${REVISION}:g" \
        packaging/rpm/binlog-server.spec >rpmbuild/SPECS/binlog-server.spec
    mv -fv ${TARFILE} ${WORKDIR}/rpmbuild/SOURCES
    rpmbuild -bs --define "_topdir ${WORKDIR}/rpmbuild" --define "version ${VERSION}" --define "dist .generic" rpmbuild/SPECS/binlog-server.spec
    mkdir -p ${WORKDIR}/srpm
    mkdir -p ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${CURDIR}/srpm
    cp rpmbuild/SRPMS/*.src.rpm ${WORKDIR}/srpm
    ls -la ${WORKDIR}/srpm
    ls -la ${CURDIR}/srpm
    return
}

build_rpm() {
    if [ $RPM = 0 ]; then
        echo "RPM will not be created"
        return
    fi
    if [ "x$OS" = "xdeb" ]; then
        echo "It is not possible to build rpm here"
        exit 1
    fi
    ls -la $WORKDIR
    ls -la $CURDIR
    ls -la $WORKDIR/srpm 
    ls -la $CURDIR/srpm 
    SRC_RPM=$(basename $(find $WORKDIR/srpm -name 'percona-binlog-server*.src.rpm' | sort | tail -n1))
    if [ -z $SRC_RPM ]; then
        SRC_RPM=$(basename $(find $CURDIR/srpm -name 'percona-binlog-server*.src.rpm' | sort | tail -n1))
        if [ -z $SRC_RPM ]; then
            echo "There is no src rpm for build"
            echo "You can create it using key --build_src_rpm=1"
            exit 1
        else
            cp $CURDIR/srpm/$SRC_RPM $WORKDIR
        fi
    else
        cp $WORKDIR/srpm/$SRC_RPM $WORKDIR
    fi
    cd $WORKDIR
    rm -fr rpmbuild
    mkdir -vp rpmbuild/{SOURCES,SPECS,BUILD,SRPMS,RPMS}
    cp $SRC_RPM rpmbuild/SRPMS/

    RHEL=$(rpm --eval %rhel)
    ARCH=$(echo $(uname -m) | sed -e 's:i686:i386:g')

    echo "RHEL=${RHEL}" >>percona-binlog-server.properties
    echo "ARCH=${ARCH}" >>percona-binlog-server.properties
    #fi
    rpmbuild --define "_topdir ${WORKDIR}/rpmbuild" --define "dist .$OS_NAME" --rebuild rpmbuild/SRPMS/$SRC_RPM

    return_code=$?
    if [ $return_code != 0 ]; then
        exit $return_code
    fi
    mkdir -p ${WORKDIR}/rpm
    mkdir -p ${CURDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${WORKDIR}/rpm
    cp rpmbuild/RPMS/*/*.rpm ${CURDIR}/rpm
}

CURDIR=$(pwd)
VERSION_FILE=$CURDIR/percona-binlog-server.properties
args=
WORKDIR=
SRPM=0
SDEB=0
RPM=0
DEB=0
SOURCE=0
TARBALL=0
OS_NAME=
ARCH=
OS=
INSTALL=0
VERSION="1.0.0"
RELEASE="1"
REVISION=0
BRANCH="main"
REPO="https://github.com/Percona-Lab/percona-binlog-server"
PRODUCT=percona-telemetry-agent
parse_arguments PICK-ARGS-FROM-ARGV "$@"

check_workdir
get_system
install_deps
get_sources
build_srpm
build_rpm
