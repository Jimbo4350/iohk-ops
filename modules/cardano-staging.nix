with (import ./../lib.nix);

params:
{ name, config, pkgs, resources, ... }: {
  imports = [
    ./staging.nix
    ./datadog.nix
    ./papertrail.nix
  ];

  global.dnsHostname = if params.typeIsRelay then "cardano-node-${toString params.relayIndex}" else null;

  services.dd-agent.processConfig = ''
    init_config:

    instances:
    '' +
    (if params.typeIsExplorer
    then ''
    - name: cardano-explorer
      search_string: ['cardano-explorer']
      ''
    else ''
    - name: cardano-node-simple
      search_string: ['cardano-node']
      '') + ''
    # nix string indentation hack (see DEVOPS-341)
      exact_match: False
      thresholds:
        critical: [1, 1]
  '';
}