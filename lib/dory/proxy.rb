require_relative 'docker_service'

module Dory
  class Proxy
    extend Dory::DockerService

    def self.dory_http_proxy_image_name
      setting = Dory::Config.settings[:dory][:nginx_proxy][:image]
      return setting if setting
      certs_dir && !certs_dir.empty? \
        ? 'codekitchen/dinghy-http-proxy:2.5.3' \
        : 'freedomben/dory-http-proxy:2.2.0.1'
    end

    def self.container_name
      Dory::Config.settings[:dory][:nginx_proxy][:container_name]
    end

    def self.certs_dir
      Dory::Config.settings[:dory][:nginx_proxy][:ssl_certs_dir]
    end

    def self.certs_arg
      if certs_dir && !certs_dir.empty?
        "-v #{certs_dir}:/etc/nginx/certs"
      else
        ''
      end
    end

    def self.tls_arg
      if [:tls_enabled, :ssl_enabled, :https_enabled].any? { |s|
          Dory::Config.settings[:dory][:nginx_proxy][s]
        }
        "-p 443:443"
      else
        ''
      end
    end

    def self.run_command
      "docker run -d -p 80:80 #{self.tls_arg} #{self.certs_arg} "\
        "-v /var/run/docker.sock:/tmp/docker.sock -e " \
        "'CONTAINER_NAME=#{Shellwords.escape(self.container_name)}' --name " \
        "'#{Shellwords.escape(self.container_name)}' " \
        "#{Shellwords.escape(dory_http_proxy_image_name)}"
    end

    def self.start_cmd
      "docker start #{Shellwords.escape(self.container_name)}"
    end
  end
end
