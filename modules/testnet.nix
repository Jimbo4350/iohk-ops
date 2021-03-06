{ name, config, resources, ... }:

with import ./../lib.nix;
{
  config = {

    global = {
      allocateElasticIP = true;
      enableEkgWeb      = false;
      dnsDomainname     = "cardano-testnet.iohkdev.io";
    };

    services = {
      dd-agent.tags              = [ "env:testnet" ];

      # DEVOPS-64: disable log bursting
      journald.rateLimitBurst    = 0;
    };

  };
}
