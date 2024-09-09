Name:           percona-binlog-server
Version:        @@VERSION@@
Release:        1%{?dist}
Summary:        Percona Binary Log Server

License:        GPLv2
URL:            https://github.com/Percona-Lab/percona-binlog-server
Source0:        %{name}-%{version}.tar.gz

%description
Percona Binary Log Server is a command-line utility that acts as an enhanced version of mysqlbinlog in --read-from-remote-server mode. It serves as a replication client and can stream binary log events from a remote Oracle MySQL Server / Percona Server for MySQL both to a local filesystem and to a cloud storage (currently AWS S3). The tool is capable of automatically reconnecting to the remote server and resuming operations from the point where it was previously stopped.

%prep
%setup -q

%build
export BUILD_CC=gcc
export BUILD_CXX=g++

# Build Debug version
mkdir -p debug
(
  cd debug
  # Build Boost Libraries
  git clone --recurse-submodules --jobs=8 https://github.com/boostorg/boost.git boost-debug
  cd boost-debug
  git checkout --recurse-submodules -b required_release boost-1.84.0
  cd ..
  cmake -B ./boost-build-debug -S ./boost-debug \
    -DCMAKE_INSTALL_PREFIX=./boost-install-debug \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=${BUILD_CC} \
    -DCMAKE_CXX_COMPILER=${BUILD_CXX} \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF
  cmake --build ./boost-build-debug --config Debug --parallel
  cmake --install ./boost-build-debug --config Debug
  

  # Build AWS SDK for C++ Libraries
  git clone --recurse-submodules --jobs=8 https://github.com/aws/aws-sdk-cpp.git aws-sdk-cpp-debug
  cd aws-sdk-cpp-debug
  git checkout --recurse-submodules -b required_release 1.11.286
  cd ..
  cmake -B ./aws-sdk-cpp-build-debug -S ./aws-sdk-cpp-debug \
    -DCMAKE_INSTALL_PREFIX=./aws-sdk-cpp-install-debug \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=${BUILD_CC} \
    -DCMAKE_CXX_COMPILER=${BUILD_CXX} \
    -DCPP_STANDARD=20 \
    -DENABLE_UNITY_BUILD=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DFORCE_SHARED_CRT=OFF \
    -DENABLE_TESTING=OFF \
    -DAUTORUN_UNIT_TESTS=OFF \
    -DBUILD_ONLY=s3-crt
  cmake --build ./aws-sdk-cpp-build-debug --config Debug --parallel
  cmake --install ./aws-sdk-cpp-build-debug --config Debug
  

  # Build Percona Binlog Server
  cd ../..
  cmake -B ./percona-binlog-server-build-debug -S ./percona-binlog-server-%{version} \
    -DCMAKE_BUILD_TYPE=Debug \
    -DCMAKE_C_COMPILER=${BUILD_CC} \
    -DCMAKE_CXX_COMPILER=${BUILD_CXX} \
    -DCPP_STANDARD=20 \
    -DCMAKE_PREFIX_PATH=${PWD}/percona-binlog-server-%{version}/debug/aws-sdk-cpp-install-debug \
    -DBoost_ROOT=${PWD}/percona-binlog-server-%{version}/debug/boost-install-debug
  cmake --build ./percona-binlog-server-build-debug --config Debug --parallel
)
# Build Release version
mkdir -p release
(
  cd release
  # Build Boost Libraries
  git clone --recurse-submodules --jobs=8 https://github.com/boostorg/boost.git boost-release
  cd boost-release
  git checkout --recurse-submodules -b required_release boost-1.84.0
  cd ..
  cmake -B ./boost-build-release -S ./boost-release \
    -DCMAKE_INSTALL_PREFIX=./boost-install-release \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=${BUILD_CC} \
    -DCMAKE_CXX_COMPILER=${BUILD_CXX} \
    -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_TESTING=OFF
  cmake --build ./boost-build-release --config RelWithDebInfo --parallel
  cmake --install ./boost-build-release --config RelWithDebInfo
  

  # Build AWS SDK for C++ Libraries
  git clone --recurse-submodules --jobs=8 https://github.com/aws/aws-sdk-cpp.git aws-sdk-cpp-release
  cd aws-sdk-cpp-release
  git checkout --recurse-submodules -b required_release 1.11.286
  cd ..
  cmake -B ./aws-sdk-cpp-build-release -S ./aws-sdk-cpp-release \
    -DCMAKE_INSTALL_PREFIX=./aws-sdk-cpp-install-release \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=${BUILD_CC} \
    -DCMAKE_CXX_COMPILER=${BUILD_CXX} \
    -DCPP_STANDARD=20 \
    -DENABLE_UNITY_BUILD=ON \
    -DBUILD_SHARED_LIBS=OFF \
    -DFORCE_SHARED_CRT=OFF \
    -DENABLE_TESTING=OFF \
    -DAUTORUN_UNIT_TESTS=OFF \
    -DBUILD_ONLY=s3-crt
  cmake --build ./aws-sdk-cpp-build-release --config RelWithDebInfo --parallel
  cmake --install ./aws-sdk-cpp-build-release --config RelWithDebInfo
 

  # Build Percona Binlog Server
  cd ../..
  cmake -B ./percona-binlog-server-build-release -S ./percona-binlog-server-%{version} \
    -DCMAKE_BUILD_TYPE=RelWithDebInfo \
    -DCMAKE_C_COMPILER=${BUILD_CC} \
    -DCMAKE_CXX_COMPILER=${BUILD_CXX} \
    -DCPP_STANDARD=20 \
    -DCMAKE_PREFIX_PATH=${PWD}/percona-binlog-server-%{version}/release/aws-sdk-cpp-install-release \
    -DBoost_ROOT=${PWD}/percona-binlog-server-%{version}/release/boost-install-release
  cmake --build ./percona-binlog-server-build-release --config RelWithDebInfo --parallel
)

%install
install -d %{buildroot}/usr/bin
install -m 755 ../percona-binlog-server-build-debug/binlog_server %{buildroot}/usr/bin/binlog_server-debug
install -m 755 ../percona-binlog-server-build-release/binlog_server %{buildroot}/usr/bin/binlog_server
install -m 0755 -d %{buildroot}/%{_sysconfdir}
install -D -m 0644  main_config.json %{buildroot}/%{_sysconfdir}/percona-binlog-server/main_config.json


%files
%license LICENSE
%doc README.md
%config(noreplace) %attr(0640,root,root) /%{_sysconfdir}/percona-binlog-server/main_config.json
/usr/bin/binlog_server-debug
/usr/bin/binlog_server


%changelog
* Mon Aug 26 2024 Surabhi Bhat <surabhi.bhat@percona.com> - 1.0.0-1
- Initial package with separate builds for Debug and RelWithDebInfo versions.
