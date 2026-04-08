{ pkgs, lib }:

{
  packageName,
  version,
  packageLock,
  npmDepsHash,
  pname ? let
    s = lib.replaceStrings ["@" "/"] ["" "-"] packageName;
  in s,
}:

let
  src = pkgs.runCommand "${pname}-bundle-src" {} ''
    mkdir -p "$out"

    cat > "$out/package.json" <<EOF
    {
      "name": "${pname}-bundle",
      "version": "0.0.1",
      "private": true,
      "dependencies": {
        "${packageName}": "${version}"
      }
    }
    EOF

    cp ${packageLock} "$out/package-lock.json"
  '';
in
pkgs.buildNpmPackage {
  inherit pname version src npmDepsHash;

  dontNpmBuild = true;
  npmInstallFlags = [ "--ignore-scripts" ];

  installPhase = ''
    runHook preInstall

    plugin_path="node_modules/${packageName}"
    if [ ! -d "$plugin_path" ]; then
      echo "expected plugin at $plugin_path, but it was not installed"
      exit 1
    fi

    mkdir -p "$out"

    # 1. 先把插件包本身展开到输出根目录
    cp -R "$plugin_path"/. "$out"/

    # 2. 再单独准备运行时依赖目录
    mkdir -p "$out/node_modules"
    cp -R node_modules/. "$out/node_modules/"

    # 3. 删除 node_modules 里插件包自己，避免变成自包含嵌套
    rm -rf "$out/node_modules/${packageName}"

    # 4. 清理可能残留的空 scope 目录
    scope_dir="$(dirname "${packageName}")"
    if [ "$scope_dir" != "." ] && [ -d "$out/node_modules/$scope_dir" ]; then
      rmdir --ignore-fail-on-non-empty "$out/node_modules/$scope_dir" || true
    fi

    # 5. 基本校验：应该是 OpenClaw 插件
    if ! grep -q '"openclaw"' "$out/package.json"; then
      echo "warning: plugin package.json has no openclaw field"
    fi

    runHook postInstall
  '';

  meta = with lib; {
    description = "OpenClaw plugin package for ${packageName}";
    platforms = platforms.all;
  };
}
