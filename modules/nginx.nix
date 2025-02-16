{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkBefore
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.services.nginx = {
    recommendedSetup = mkEnableOption "recommended setup parameters.";
    recommendedSecurityHeaders = mkEnableOption "additional security headers by default in each location block. Can be overwritten in each location with `recommendedSecurityHeaders`.";
    virtualHosts = mkOption {
      type = types.attrsOf (
        types.submodule {
          options.locations = mkOption {
            type = types.attrsOf (
              types.submodule (submod: {
                options = {
                  recommendedSecurityHeaders = mkOption {
                    type = types.bool;
                    default = config.services.nginx.recommendedSecurityHeaders;
                    description = "Whether to add additional security headers to this location.";
                  };

                  X-Frame-Options = mkOption {
                    type = types.str;
                    default = "DENY";
                    description = "The value to use for X-Frame-Options";
                  };
                };
                config = mkIf submod.config.recommendedSecurityHeaders {
                  extraConfig = mkBefore ''
                    # Enable HTTP Strict Transport Security (HSTS)
                    add_header Strict-Transport-Security "max-age=63072000; includeSubdomains; preload";

                    # Minimize information leaked to other domains
                    add_header Referrer-Policy "origin-when-cross-origin";

                    add_header X-XSS-Protection "1; mode=block";
                    add_header X-Frame-Options "${submod.config.X-Frame-Options}";
                    add_header X-Content-Type-Options "nosniff";
                  '';
                };
              })
            );
          };
        }
      );
    };
  };

  config = mkIf (config.services.nginx.enable && config.services.nginx.recommendedSetup) {
    age.secrets."dhparams.pem" = mkIf (config ? age) {
      generator.script = "dhparams";
      mode = "440";
      group = "nginx";
    };

    networking.firewall.allowedTCPPorts = [
      80
      443
    ];
    # QUIC
    networking.firewall.allowedUDPPorts = [ 443 ];

    # Sensible defaults for nginx
    services.nginx = {
      recommendedBrotliSettings = true;
      recommendedGzipSettings = true;
      recommendedOptimisation = true;
      recommendedProxySettings = true;
      recommendedTlsSettings = true;
      recommendedSecurityHeaders = true;

      # SSL config
      sslCiphers = "EECDH+AESGCM:EDH+AESGCM:!aNULL";
      sslDhparam = mkIf (config ? age) config.age.secrets."dhparams.pem".path;
      commonHttpConfig = ''
        log_format json_combined escape=json '{'
          '"time": $msec,'
          '"remote_addr":"$remote_addr",'
          '"status":$status,'
          '"method":"$request_method",'
          '"host":"$host",'
          '"uri":"$request_uri",'
          '"request_size":$request_length,'
          '"response_size":$body_bytes_sent,'
          '"response_time":$request_time,'
          '"referrer":"$http_referer",'
          '"user_agent":"$http_user_agent"'
        '}';
        error_log syslog:server=unix:/dev/log,nohostname;
        access_log syslog:server=unix:/dev/log,nohostname json_combined;
        ssl_ecdh_curve secp384r1;
      '';

      # Default host that rejects everything.
      # This is selected when no matching host is found for a request.
      virtualHosts.dummy = {
        default = true;
        rejectSSL = true;
        locations."/".extraConfig = ''
          deny all;
        '';
      };
    };
  };
}
