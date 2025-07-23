{
  outputs = { self, nixpkgs, ... }:
    let
      pkgs = import nixpkgs { system = "x86_64-linux"; };
      addCheck = { name, sylva-core, scenario, ... }: pkgs.testers.runNixOSTest {
        name = name;
        nodes = {
          m1 = { pkgs, ... }: {
            nix.settings.sandbox = false;
            environment.systemPackages = with pkgs; [
              bash binutils
              curl
              docker
              envsubst
              git gnutar gzip
              (python3.withPackages (python-pkgs: with python-pkgs; [
                pyyaml
                yamllint
              ]))
            ];
            networking.useDHCP = false;
            networking.interfaces.eth0.useDHCP = true;
            virtualisation.cores = 2;
            virtualisation.memorySize = 8 * 1024;
            virtualisation.diskSize = 64 * 1024;
            virtualisation.docker.enable = true;
            virtualisation.docker.logDriver = "local";
          };
        };
        testScript = ''
          m1.wait_for_unit("multi-user.target")
          m1.wait_for_unit("network-online.target")
          print(m1.succeed("${scenario}/run.sh ${sylva-core}"))
        '';
      };
    in {
      packages.x86_64-linux = {
        default = pkgs.stdenv.mkDerivation {
          name = "sylva-core";
          git_url = "https://gitlab.com/mopala/sylva-core.git";
          git_rev = "capone";
          dontUnpack = true;
          dontPatch = true;
          dontConfigure = true;
          dontBuild = true;
          dontFixup = false;
          buildInputs = with pkgs; [ cacert git ];
          installPhase = ''
            git clone -b $git_rev $git_url $out/
          '';
          postFixup = ''
            unlink $out/charts/sylva-units/test-values/use-oci-artifacts/use-oci-artifacts-final.values.yaml
          '';
        };
      };
      checks.x86_64-linux = {
        sylva-ci-deploy-kubeadm = addCheck {
          name = "deploy-kubeadm";
          sylva-core = self.packages.x86_64-linux.default;
          scenario = ./deploy/kubeadm;
        };
        sylva-ci-deploy-rke2 = addCheck {
          name = "deploy-rke2";
          sylva-core = self.packages.x86_64-linux.default;
          scenario = ./deploy/rke2;
        };
      };
    };
}
