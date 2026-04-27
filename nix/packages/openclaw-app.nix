{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.4.25";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.4.25/OpenClaw-2026.4.25.zip";
    hash = "sha256-5l5ONPM/vkyQCWf0TcoAP63U6fNxc1BA/qHnQeAP1u8=";
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
