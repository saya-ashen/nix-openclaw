{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.5.18";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.5.18/OpenClaw-2026.5.18.zip";
    hash = "sha256-Eu2mNQpDOIJ5608T789Hs/nMHL5gnY4pxEwsG5W42aQ=";
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
