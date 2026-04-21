{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.4.20";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.4.20/OpenClaw-2026.4.20.zip";
    hash = "sha256-JJ3L5xWY3L3Pf/4gBVs+R0tnoZyxBz4Lla4jmDBq4PM=";
    stripRoot = false;
  };

  dontUnpack = true;

  installPhase = "${../scripts/openclaw-app-install.sh}";

  meta = with lib; {
    description = "OpenClaw macOS app bundle";
    homepage = "https://github.com/openclaw/openclaw";
    license = licenses.mit;
    platforms = platforms.darwin;
  };
}
