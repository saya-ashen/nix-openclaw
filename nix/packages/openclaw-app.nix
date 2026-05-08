{
  lib,
  stdenvNoCC,
  fetchzip,
}:

stdenvNoCC.mkDerivation {
  pname = "openclaw-app";
  version = "2026.5.7";

  src = fetchzip {
    url = "https://github.com/openclaw/openclaw/releases/download/v2026.5.7/OpenClaw-2026.5.7.zip";
    hash = "sha256-LcjnlxUm3SEUz0qPsmHpZbQdLsfjAXKKV+6Wla9V6rQ=";
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
