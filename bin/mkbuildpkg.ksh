#!/usr/bin/bash
[[ -z $1 ]] && printf "
Usage:
  ${0##*/} build-directory
  where the directory has the same name as the build. A build is 
  typically called 'buildXXX'. The name of the build should also 
  be reflected in the RELEASE file in the buildXXX/install dir.

  Creates a build package called buildXXX.tar.gz in the current 
  directory.

  The build directory contains all the files necessary for an
  installation, and has the following structure:

    buildXXX-+-application-+-korn
             |             +-perl
             |             +-oracle-+-schema1
             |                      +-schema2 etc...
             +-install
             +-tools

" && exit 1

[[ ! -d $1 ]] && \
  printf "The build directory $1 does not exist. Exiting...\n" && \
  exit 1

# Checking for the existance of RELEASE file
[[ ! -r $1/install/RELEASE ]] && \
  printf "The RELEASE file could not be found.\nExiting..." && \
  exit 1

RELEASE_NAME=$(grep "^ *RELEASE_NAME *=" $1/install/RELEASE)
[[ ${#RELEASE_NAME[*]} > 1 ]] && \
  printf "Too many releases defined in the RELEASE note.\nExiting...\n" && \
  exit 1
[[ ${#RELEASE_NAME[*]} = 0 ]] && \
  printf "The RELEASE note does not define a Release.\nExiting...\n" && \
  exit 1

eval ${RELEASE_NAME}
RELEASE=$RELEASE_NAME
BUILD_DIR=${1##*/}
[[ $RELEASE != $BUILD_DIR ]] && \
  printf "The RELEASE name in the build directory is $RELEASE
but is not the same as the build directory name, $BUILD_DIR
Exiting...\n" && \
  exit 1


printf "Build installation package for $1:\n"

printf "Stripping DOS chars from script files...\n"
find $1 -type f -exec dos2unix {} \;

printf "Making shell script executable...\n"
find $1/application/korn -type f -exec chmod +x {} \;
find $1/application/perl -type f -name *.pl -exec chmod +x {} \;
find $1/install -type f -name *.ksh  -exec chmod +x {} \;
find $1/tools -type f -exec chmod +x {} \;

PACKAGE=$1.tar.gz
printf "Creating build package $PACKAGE...\n"
tar -czf $PACKAGE $1 2>/dev/null
md5sum $PACKAGE > $PACKAGE.md5

printf "Done\n"

