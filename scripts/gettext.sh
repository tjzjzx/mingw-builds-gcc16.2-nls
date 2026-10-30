#
# libintl (GNU gettext runtime) prereq for GCC NLS support.
# GCC >= 15 no longer ships the bundled intl/ directory, so --enable-nls
# requires an external libintl for the host (x86_64-w64-mingw32).
#

# **************************************************************************

PKG_VERSION=0.26
PKG_NAME=$PKG_ARCHITECTURE-gettext-$LINK_TYPE_SUFFIX
PKG_DIR_NAME=gettext-${PKG_VERSION}
PKG_SUBDIR_NAME=gettext-runtime
PKG_TYPE=.tar.xz
PKG_URLS=(
	"${GNU_URL_PREFIX}/gettext/gettext-${PKG_VERSION}${PKG_TYPE}"
)

PKG_PRIORITY=prereq

#

PKG_CONFIGURE_FLAGS=(
	--host=$HOST
	--build=$BUILD
	--target=$TARGET
	#
	--prefix=$PREREQ_DIR/$PKG_NAME
	#
	$GCC_DEPS_LINK_TYPE
	#
	--enable-nls
	--disable-rpath
	--disable-openmp
	--with-libiconv-prefix=$PREREQ_DIR/$BUILD_ARCHITECTURE-libiconv-$LINK_TYPE_SUFFIX
	#
	CFLAGS="$COMMON_CFLAGS"
	CXXFLAGS="$COMMON_CXXFLAGS"
	CPPFLAGS="$COMMON_CPPFLAGS"
	LDFLAGS="$COMMON_LDFLAGS"
)

#

PKG_MAKE_FLAGS=(
	-j$JOBS
	all
)

#

PKG_INSTALL_FLAGS=(
	-j1
	install
)

# **************************************************************************
