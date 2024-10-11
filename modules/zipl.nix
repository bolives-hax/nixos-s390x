{
  config,
  lib,
  pkgs,
  ...
}:
with lib;
let
  blCfg = config.boot.loader;
  cfg = blCfg.zipl;

  builder = pkgs.substituteAll {
    src = ./zipl-conf-builder.sh;
    isExecutable = true;
    path = with pkgs; [
      coreutils
      gnused
      gnugrep
      s390-tools # zipl is found here
    ];
    inherit (pkgs) bash;
  };
in
{
  options = {
    boot.loader.zipl = {
      enable = mkOption {
        default = false;
        type = types.bool;
        description = "wether to enable the s390x zipl bootloader";
      };
      /*
        TODO this doens't work via devices like grub, it may make sense
        to instead define a device for the dumps
        device = mkOption {
          type = types.str;
          description = "dasd/scsi/ETC TODO device to install zipl on";
        };
      */
      configurationLimit = mkOption {
        type = types.int;
        default = 100;
        description = "Maximum of configurations in boot menu";
        example = 200;
      };
      # TODO add timeout and maybe other things part of the zipl spec
    };
  };

  config =
    let
      # TODO parse from option
      timeout =
        if blCfg.timeout == null then
          "-t 0"
        else if blCfg.timeout != 0 then
          "-t ${toString blCfg.timeout}"
        else
          "";
    in
    mkIf cfg.enable {
      system.build.installBootLoader =
        with cfg;
        "${builder} -i ${device} -g ${toString configurationLimit} ${timeout} -c";
      system.boot.loader.id = "zipl";
    };
}
