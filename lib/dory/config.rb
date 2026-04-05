require 'yaml'
require 'active_support/core_ext/hash/indifferent_access'

module Dory
  class Config
    def self.has_config_file?(dir)
      File.exist?("#{dir}/.dory.yml")
    end

    def self.find_config_file(starting_dir)
      if self.has_config_file?(starting_dir)
        "#{starting_dir}/.dory.yml"
      elsif starting_dir == "/"
        return self.default_filename
      else
        return self.find_config_file(File.dirname(starting_dir)) # recurse up to /
      end
    end

    def self.default_filename
      "#{Dir.home}/.dory.yml"
    end

    def self.filename
      self.find_config_file(Dir.pwd)
    end

    def self.default_yaml
      %q(---
        dory:
          # Be careful if you change the settings of some of
          # these services.  They may not talk to each other
          # if you change IP Addresses.
          # For example, resolv expects a nameserver listening at
          # the specified address.  dnsmasq normally does this,
          # but if you disable dnsmasq, it
          # will make your system look for a name server that
          # doesn't exist.
          dnsmasq:
            enabled: true
            domains:               # array of domains that will be resolved to the specified address
              - domain: docker     # you can set '#' for a wildcard
                address: 127.0.0.1 # return for queries against the domain
            container_name: dory_dnsmasq
            port: 53  # port to listen for dns requests on.  must be 53 on linux. can be anything that's open on macos
            # kill_others: kill processes bound to the port we need (see previous setting 'port')
            #   Possible values:
            #     ask (prompt about killing each time. User can accept/reject)
            #     yes|true (go aheand and kill without asking)
            #     no|false (don't kill, and don't even ask)
            kill_others: ask
            service_start_delay: 5  # seconds to wait after restarting systemd services
          nginx_proxy:
            enabled: true
            container_name: dory_dinghy_http_proxy
            https_enabled: true
            ssl_certs_dir: ''  # leave as empty string to use default certs
            port: 80           # port 80 is default for http
            tls_port: 443      # port 443 is default for https
          resolv:
            enabled: true
            nameserver: 127.0.0.1
            port: 53  # port where the nameserver listens. On linux it must be 53
          aliases:
            enabled: false
      ).split("\n").map{|s| s.sub(' ' * 8, '')}.join("\n")
    end

    def self.default_settings
      YAML.load(self.default_yaml).with_indifferent_access
    end

    def self.settings(filename = self.filename)
      if File.exist?(filename)
        defaults = self.default_settings.dup
        config_file_settings = YAML.load_file(filename).with_indifferent_access
        [:dnsmasq, :nginx_proxy, :resolv, :aliases].each do |service|
          defaults[:dory][service].merge!(config_file_settings[:dory][service] || {})
        end
        defaults[:dory][:debug] = config_file_settings[:dory][:debug]
        defaults
      else
        self.default_settings
      end
    end

    def self.write_settings(settings, filename = self.filename, is_yaml: false)
      settings = settings.to_yaml unless is_yaml
      settings.gsub!(/\s*!ruby\/hash:ActiveSupport::HashWithIndifferentAccess/, '')
      File.write(filename, settings)
    end

    def self.write_default_settings_file(filename = self.filename)
      self.write_settings(self.default_yaml, filename, is_yaml: true)
    end

    def self.upgrade_settings_file(filename = self.filename)
      self.write_settings(self.upgrade(self.settings), filename, is_yaml: false)
    end

    def self.debug?
      self.settings[:dory][:debug]
    end

    def self.upgrade(old_hash)
      newsettings = old_hash.dup

      # If there's a single domain and address, upgrade to the array format
      if newsettings[:dory][:dnsmasq][:domain]
        newsettings[:dory][:dnsmasq][:domains] = [{
          domain: newsettings[:dory][:dnsmasq][:domain],
          address: newsettings[:dory][:dnsmasq][:address] || '127.0.0.1'
        }]
        newsettings[:dory][:dnsmasq].delete(:domain)
        newsettings[:dory][:dnsmasq].delete(:address)
      end

      # Add the option to skip prompts
      unless newsettings[:dory][:dnsmasq][:kill_others]
        newsettings[:dory][:dnsmasq][:kill_others] = 'ask'
      end

      unless newsettings[:dory][:dnsmasq][:service_start_delay]
        newsettings[:dory][:dnsmasq][:service_start_delay] = 5
      end

      # add settings for nginx proxy port
      unless newsettings[:dory][:nginx_proxy][:port]
        newsettings[:dory][:nginx_proxy][:port] = 80
      end
      unless newsettings[:dory][:nginx_proxy][:tls_port]
        newsettings[:dory][:nginx_proxy][:tls_port] = 443
      end

      newsettings
    end
  end
end
