if test "$ARCH" = ''; then
  if which dpkg-architecture >/dev/null; then
    ARCH=`dpkg-architecture -q DEB_BUILD_ARCH`
  else
    ARCH=amd64
  fi
fi

echo "Building for $ARCH architecture..."
