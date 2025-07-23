{
  outputs = { self, nixpkgs }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
    in {
      packages.x86_64-linux = {
        asynq-tools =
          let
            checkout = pkgs.fetchFromGitHub {
              owner = "hibiken";
              repo = "asynq";
              rev = "v0.25.1";
              hash = "sha256-aUxqVfAs8xfEIQ7LVibU/Ape+mMCQ/eAf2eN2oaho/8=";
            };
          in pkgs.buildGoModule {
            name = "asynq-tools";
            src = "${checkout}/tools/";
            vendorHash = "sha256-/7aMFgUL3IT5Gn7K/LQrLAICrmzOMJSBFd8nURPL7rk=";
          };
        asynq-ci = pkgs.buildGoModule {
          name = "asynq-ci";
          src = ./.;
          vendorHash = "sha256-xxfZf4LX+C0pdrqME7WX6FeOVy7KgIHzripFwr4yf+Y=";
        };
        default = pkgs.symlinkJoin {
          name = "sylva-ci";
          paths = [
            self.packages.x86_64-linux.asynq-tools
            self.packages.x86_64-linux.asynq-ci
          ];
        };
      };
      apps.x86_64-linux = {
        default = {
          type = "app";
          program = "${self.packages.x86_64-linux.default}/bin/srv";
        };
      };
      nixosModules.x86_64-linux = {
        default = { config, lib, ... }: {
          options.services.sylva-ci = {
            enable = lib.mkEnableOption "Enable sylva-ci";
          };
          config = lib.mkIf config.services.sylva-ci.enable {
            systemd.services.sylva-ci = {
              wantedBy = [ "multi-user.target" ];
              after = [ "network.target" ];
              path = with pkgs; [ bash ];
              serviceConfig = {
                ExecStart = "${self.packages.x86_64-linux.default}/bin/srv";
                Restart = "always";
                Type = "simple";
              };
            };
          };
        };
      };
    };
}
