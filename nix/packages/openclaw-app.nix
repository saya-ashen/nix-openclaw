{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.4.22";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.4.22/OpenClaw-2026.4.22.zip";
    hash = "sha256-v1EikXXUo2xxsEDqZkdRrJR0xo3pSW8r6afjXCfLZ5Q=";
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
