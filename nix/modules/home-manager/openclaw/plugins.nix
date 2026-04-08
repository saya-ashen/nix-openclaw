{
  lib,
  pkgs,
  openclawLib,
  enabledInstances,
}: let
  resolvePath = openclawLib.resolvePath;
  toRelative = openclawLib.toRelative;
  cfg = openclawLib.cfg;

  pluginBaseDirFor = instName:
    resolvePath (if instName == "default" then "~/.openclaw" else "~/.openclaw-${instName}");

  splitPluginAttrs = attrs: {
    slots = attrs._slots or { };
    entries = lib.removeAttrs attrs [ "_slots" ];
  };

  mergePluginEntry = base: override:
    let
      inheritedPackage = base.package or null;
      overridePackage = override.package or null;
      merged = {
        package = if overridePackage != null then overridePackage else inheritedPackage;
        env = lib.recursiveUpdate (base.env or { }) (override.env or { });
        settings = lib.recursiveUpdate (base.settings or { }) (override.settings or { });
        enabled =
          if (override.enabled or null) != null
          then override.enabled
          else (base.enabled or true);
        hooks = if (override.hooks or null) != null then override.hooks else (base.hooks or null);
        subagent = if (override.subagent or null) != null then override.subagent else (base.subagent or null);
      };
    in
      merged;

  mergedPluginDeclsByInstance =
    lib.mapAttrs (
      _instName: inst:
      let
        globalPlugins = splitPluginAttrs cfg.plugins;
        instancePlugins = splitPluginAttrs (inst.plugins or { });
        names = lib.unique ((lib.attrNames globalPlugins.entries) ++ (lib.attrNames instancePlugins.entries));
        mergedEntries = lib.listToAttrs (
          map (
            name: {
              inherit name;
              value = mergePluginEntry (globalPlugins.entries.${name} or { }) (instancePlugins.entries.${name} or { });
            }
          ) names
        );
      in
        {
          _slots = lib.recursiveUpdate globalPlugins.slots instancePlugins.slots;
        }
        // mergedEntries
    )
    enabledInstances;

  pluginSlotsFor = instName: (splitPluginAttrs (mergedPluginDeclsByInstance.${instName} or { })).slots;

  mergedPluginEntriesFor = instName: (splitPluginAttrs (mergedPluginDeclsByInstance.${instName} or { })).entries;

  concretePluginEntriesFor = instName:
    lib.filterAttrs (_: plugin: (plugin.package or null) != null) (mergedPluginEntriesFor instName);

  resolvePlugin = instName: pluginName: plugin: let
    pluginPackage = plugin.package;
    pluginMeta = pluginPackage.passthru.openclawPlugin or (throw "OpenClaw plugin package ${lib.getName pluginPackage} is missing passthru.openclawPlugin");
    needs = pluginMeta.needs or {};
    extensionTarget = "${pluginBaseDirFor instName}/extensions/${pluginMeta.name}";
  in {
    package = pluginPackage;
    name = pluginMeta.name;
    configuredName = pluginName;
    extensionTarget = extensionTarget;
    extensionSource = pluginPackage;
    skills = pluginMeta.skills or [];
    packages = pluginMeta.packages or [];
    needs = {
      stateDirs = needs.stateDirs or [];
      requiredEnv = needs.requiredEnv or [];
    };
    env = plugin.env or {};
    settings = plugin.settings or {};
    enabled = plugin.enabled or true;
    hooks = plugin.hooks or null;
    subagent = plugin.subagent or null;
  };

  resolvedPluginsByInstance =
    lib.mapAttrs (
      instName: inst: let
        resolved = lib.mapAttrsToList (resolvePlugin instName) (concretePluginEntriesFor instName);
        counts = lib.foldl' (acc: p: acc // {"${p.name}" = (acc.${p.name} or 0) + 1;}) {} resolved;
        duplicates = lib.attrNames (lib.filterAttrs (_: v: v > 1) counts);
        byName = lib.foldl' (acc: p: acc // {"${p.name}" = p;}) {} resolved;
        ordered = lib.attrValues byName;
      in
        if duplicates == []
        then ordered
        else lib.warn "programs.openclaw.instances.${instName}: duplicate plugin package names detected (${lib.concatStringsSep ", " duplicates}); last entry wins." ordered
    )
    enabledInstances;

  pluginPackagesFor = instName: lib.flatten (map (p: p.packages) (resolvedPluginsByInstance.${instName} or []));

  pluginPackagesAll = lib.flatten (map pluginPackagesFor (lib.attrNames enabledInstances));

  pluginStateDirsFor = instName: let
    dirs = lib.flatten (map (p: p.needs.stateDirs) (resolvedPluginsByInstance.${instName} or []));
  in
    map (dir: resolvePath ("~/" + dir)) dirs;

  pluginStateDirsAll = lib.flatten (map pluginStateDirsFor (lib.attrNames enabledInstances));

  pluginEnvFor = instName: let
    entries = resolvedPluginsByInstance.${instName} or [];
    toPairs = p: let
      env = p.env or {};
      required = p.needs.requiredEnv;
    in
      map (k: {
        key = k;
        value = env.${k} or "";
        plugin = p.name;
      })
      required;
  in
    lib.flatten (map toPairs entries);

  pluginEnvAllFor = instName: let
    entries = resolvedPluginsByInstance.${instName} or [];
    toPairs = p: let
      env = p.env or {};
    in
      map (k: {
        key = k;
        value = env.${k};
        plugin = p.name;
      }) (lib.attrNames env);
  in
    lib.flatten (map toPairs entries);

  pluginRuntimeEntriesFor = instName: let
    entries = resolvedPluginsByInstance.${instName} or [];
    mkEntry = p: let
      entry = lib.filterAttrs (_: v: v != null) {
        enabled = p.enabled;
        config = if p.settings == {} then null else p.settings;
        hooks = p.hooks;
        subagent = p.subagent;
      };
    in {
      name = p.name;
      value = entry;
    };
  in
    lib.listToAttrs (map mkEntry entries);

  pluginRuntimeConfigFor = instName: let
    entries = pluginRuntimeEntriesFor instName;
    slots = pluginSlotsFor instName;
    pluginsConfig =
      (lib.optionalAttrs (entries != { }) {
        entries = entries;
      })
      // (lib.optionalAttrs (slots != { }) {
        slots = slots;
      });
  in
    lib.optionalAttrs (pluginsConfig != { }) {
      plugins = pluginsConfig;
    };

  pluginAssertions = lib.flatten (
    lib.mapAttrsToList (
      instName: inst: let
        declaredPlugins = mergedPluginEntriesFor instName;
        plugins = resolvedPluginsByInstance.${instName} or [];
        envFor = p: (p.env or {});
        missingFor = p: lib.filter (req: !(builtins.hasAttr req (envFor p))) p.needs.requiredEnv;
        packageAssertions = map (
          pluginName: {
            assertion = (declaredPlugins.${pluginName}.package or null) != null;
            message = "programs.openclaw.instances.${instName}.plugins.${pluginName}: plugin package is required (set it globally under programs.openclaw.plugins.${pluginName}.package or per-instance).";
          }
        ) (lib.attrNames declaredPlugins);
        mkAssertion = p: let
          missing = missingFor p;
        in {
          assertion = missing == [];
          message = "programs.openclaw.instances.${instName}: plugin ${p.name} missing required env: ${lib.concatStringsSep ", " missing}";
        };
      in
        packageAssertions ++ map mkAssertion plugins
    )
    enabledInstances
  );

  pluginExtensionInstalls = lib.flatten (
    lib.mapAttrsToList (
      instName: _: 
        map (
          p: {
            target = p.extensionTarget;
            source = p.extensionSource;
          }
        ) (resolvedPluginsByInstance.${instName} or [ ])
    ) enabledInstances
  );

  pluginSkillsFiles = let
    entriesForInstance = instName: inst: let
      base = "${toRelative (resolvePath inst.workspaceDir)}/skills";
      skillEntriesFor = p:
        map (skillPath: {
          name = "${base}/${builtins.baseNameOf skillPath}";
          value = {
            text = builtins.readFile skillPath;
          };
        })
        p.skills;
      plugins = resolvedPluginsByInstance.${instName} or [];
    in
      lib.flatten (map skillEntriesFor plugins);
  in
    lib.listToAttrs (lib.flatten (lib.mapAttrsToList entriesForInstance enabledInstances));

  pluginConfigFiles = let
    entryFor = instName: inst: let
      plugins = resolvedPluginsByInstance.${instName} or [];
      mkEntries = p: let
        cfg = p.settings or {};
        dir =
          if (p.needs.stateDirs or []) == []
          then null
          else lib.head (p.needs.stateDirs or []);
        baseDir = pluginBaseDirFor instName;
      in
        if cfg == {}
        then []
        else
          (
            if dir == null
            then []
            else [
              {
                name = toRelative "${baseDir}/${dir}/config.json";
                value = {
                  text = builtins.toJSON cfg;
                };
              }
            ]
          );
    in
      lib.flatten (map mkEntries plugins);
    entries = lib.flatten (lib.mapAttrsToList entryFor enabledInstances);
  in
    lib.listToAttrs entries;

  pluginSkillAssertions = let
    skillTargets = lib.flatten (
      lib.concatLists (
        lib.mapAttrsToList (
          instName: inst: let
            base = "${toRelative (resolvePath inst.workspaceDir)}/skills";
            plugins = resolvedPluginsByInstance.${instName} or [];
          in
            map (p: map (skillPath: "${base}/${builtins.baseNameOf skillPath}") p.skills) plugins
        )
        enabledInstances
      )
    );
    counts = lib.foldl' (acc: path: acc // {"${path}" = (acc.${path} or 0) + 1;}) {} skillTargets;
    duplicates = lib.attrNames (lib.filterAttrs (_: v: v > 1) counts);
  in
    if duplicates == []
    then []
    else [
      {
        assertion = false;
        message = "Duplicate skill paths detected: ${lib.concatStringsSep ", " duplicates}";
      }
    ];

  pluginGuards = let
    renderCheck = entry: ''
      if [ -z "${entry.value}" ]; then
        echo "Missing env ${entry.key} for plugin ${entry.plugin} in instance ${entry.instance}." >&2
        exit 1
      fi
      if [ ! -f "${entry.value}" ] || [ ! -s "${entry.value}" ]; then
        echo "Required file for ${entry.key} not found or empty: ${entry.value} (plugin ${entry.plugin}, instance ${entry.instance})." >&2
        exit 1
      fi
    '';
    entriesForInstance = instName: map (entry: entry // {instance = instName;}) (pluginEnvFor instName);
    entries = lib.flatten (map entriesForInstance (lib.attrNames enabledInstances));
  in
    lib.concatStringsSep "\n" (map renderCheck entries);
in {
  inherit
    resolvedPluginsByInstance
    pluginPackagesFor
    pluginPackagesAll
    pluginStateDirsFor
    pluginStateDirsAll
    pluginEnvFor
    pluginEnvAllFor
    pluginRuntimeEntriesFor
    pluginRuntimeConfigFor
    pluginAssertions
    pluginExtensionInstalls
    pluginSkillsFiles
    pluginConfigFiles
    pluginSkillAssertions
    pluginGuards
    ;
}
