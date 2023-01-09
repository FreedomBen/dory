require_relative 'docker_service'

module Dory
  class Dnsmasq
    extend Dory::DockerService

    #
    # I really hate these globals.  It would be great to refactor these out
    #
    @@first_attempt_failed = false
    @@handle_systemd_services = []

    def self.dnsmasq_image_name
      setting = Dory::Config.settings[:dory][:dnsmasq][:image]
      setting ? setting : 'freedomben/dory-dnsmasq:1.1.0'
    end

    def self.first_attempt_failed?
      @@first_attempt_failed ||= false if @first_attempt_failed.nil?
      @@first_attempt_failed
    end

    def self.set_first_attempt_failed(failed)
      @@first_attempt_failed = failed
    end

    def self.systemd_services?
      return false unless self.systemd_services
      self.systemd_services.count > 0
    end

    def self.systemd_services
      @@systemd_services ||= []
      @@systemd_services
    end

    def self.set_systemd_services(services)
      @@systemd_services = services
    end

    def self.run_preconditions
      puts "[DEBUG] dnsmasq service running preconditions" if Dory::Config.debug?

      # we don't want to hassle the user with checking the port unless necessary
      if first_attempt_failed?
        self.set_systemd_services(self.running_services_that_block_dnsmasq)
        self.down_systemd_services if self.systemd_services?

        puts "[DEBUG] First attempt failed.  Checking port #{self.port}" if Dory::Config.debug?
        listener_list = Dory::PortUtils.check_port(self.port)
        unless listener_list.empty?
          return self.offer_to_kill(listener_list)
        end

        return false
      else
        puts "[DEBUG] Skipping preconditions on first run" if Dory::Config.debug?
        return true
      end
    end

    def self.run_postconditions
      puts "[DEBUG] dnsmasq service running postconditions" if Dory::Config.debug?
      self.up_systemd_services if self.systemd_services?
    end

    def self.handle_error(_command_output)
      puts "[DEBUG] handling dnsmasq start error" if Dory::Config.debug?
      # If we've already tried to handle failure, prevent infinite recursion
      if first_attempt_failed?
        puts "[DEBUG] Attempt to kill conflicting service failed" if Dory::Config.debug?
        return false
      else
        if Dory::Config.debug?
          puts "[DEBUG] First attempt to start dnsmasq failed." \
               "There is probably a conflicting service present"
        end
        set_first_attempt_failed(true)
        self.start(handle_error: false)
      end
    end

    def self.ip_from_dinghy?
      Dory::Dinghy.match?(self.address(self.old_address)) ||
        self.domains.any?{ |domain| Dory::Dinghy.match?(self.address(domain[:address])) }
    end

    def self.port
      return 53 unless Os.macos?
      p = Dory::Config.settings[:dory][:dnsmasq][:port]
      p.nil? || p == 0 ? 19323 : self.sanitize_port(p)
    end

    def self.sanitize_port(port)
      port.to_s.gsub(/\D/, '').to_i
    end

    def self.container_name
      Dory::Config.settings[:dory][:dnsmasq][:container_name]
    end

    def self.domains
      Dory::Config.settings[:dory][:dnsmasq][:domains]
    end

    def self.old_domain
      Dory::Config.settings[:dory][:dnsmasq][:domain]
    end

    def self.old_address
      Dory::Config.settings[:dory][:dnsmasq][:address]
    end
    
    def self.address(addr)
      Dory::Dinghy.match?(addr) ? Dory::Dinghy.ip : addr
    end

    def self.autostart
      Dory::Config.settings[:dory][:dnsmasq][:autostart]
    end

    def self.domain_addr_arg_string
      if self.old_domain
        "#{Shellwords.escape(self.old_domain)} #{Shellwords.escape(self.address(self.old_address))}"
      else
        self.domains.map do |domain|
          "#{Shellwords.escape(domain[:domain])} #{Shellwords.escape(self.address(domain[:address]))}"
        end.join(" ")
      end
    end

    def self.run_command
      "docker run -d -p #{self.port}:#{self.port}/tcp -p #{self.port}:#{self.port}/udp " \
      "--restart=#{self.autostart ? 'unless-stopped' : 'no'} " \
      "--name=#{Shellwords.escape(self.container_name)} " \
      "--cap-add=NET_ADMIN #{Shellwords.escape(self.dnsmasq_image_name)} " \
      "#{self.domain_addr_arg_string}"
    end

    def self.offer_to_kill(listener_list, answer: nil)
      listener_list.each do |process|
        puts "Process '#{process.command}' with PID '#{process.pid}' is listening on #{process.node} port #{self.port}.".yellow
      end
      pids = listener_list.uniq(&:pid).map(&:pid)
      pidstr = pids.join(' and ')
      print "This interferes with Dory's dnsmasq container.  Would you like me to kill PID #{pidstr}? (Y/N): ".yellow
      conf = answer ? answer : answer_from_settings
      conf = STDIN.gets.chomp unless conf
      if conf =~ /y/i
        puts "Requesting sudo to kill PID #{pidstr}".green
        return Sh.run_command("sudo kill #{pids.join(' ')}").success?
      else
        puts "OK, not killing PID #{pidstr}.  Please kill manually and try starting dory again.".red
        return false
      end
    end

    def self.services_that_block_dnsmasq
      %w[
        NetworkManager.service
        systemd-resolved.service
      ]
    end

    def self.has_services_that_block_dnsmasq?
      !self.running_services_that_block_dnsmasq.empty?
    end

    def self.running_services_that_block_dnsmasq
      self.services_that_block_dnsmasq.select do |service|
        Dory::Systemd.systemd_service_running?(service)
      end
    end

    def self.down_systemd_services
      puts "[DEBUG] Putting systemd services down" if Dory::Config.debug?

      conf = if ask_about_killing?
               puts "You have some systemd services running that will race against us \n" \
                    "to bind to port 53 (and usually they win):".yellow
               puts "\n     #{self.systemd_services.join(', ')}\n".yellow
               puts "If we don't stop these services temporarily while putting up the \n" \
                    "dnsmasq container, starting it will likely fail.".yellow
               print "Would you like me to put them down while we start dns \n" \
                     "(I'll put them back up when finished)? (Y/N): ".yellow
               STDIN.gets.chomp
             else
               answer_from_settings
             end
      if conf =~ /y/i
        if self.systemd_services.all? { |service|
          Dory::Systemd.set_systemd_service(service: service, up: false)
        }
          puts "Putting down services succeeded".green
        else
          puts "One or more services failed to stop".red
        end
      else
        puts 'OK, not putting down the services'.yellow
        set_systemd_services([])
      end
    end

    def self.up_systemd_services
      if self.systemd_services?
        puts "[DEBUG] Putting systemd services back up: #{self.systemd_services.join(', ')}" if Dory::Config.debug?
        if self.systemd_services.reverse.all? { |service|
          Dory::Systemd.set_systemd_service(service: service, up: true)
        }
          puts "#{self.systemd_services.join(', ')} were successfully restarted".green
        else
          puts "#{self.systemd_services.join(', ')} failed to restart".red
        end
      else
        puts "[DEBUG] Not putting systemd services back up cause array was empty " if Dory::Config.debug?
      end
    end

    def self.ask_about_killing?
      !self.answer_from_settings
    end

    def self.kill_others
      Dory::Config.settings[:dory][:dnsmasq][:kill_others]
    end

    def self.answer_from_settings
      # This `== true` is important because kill_others could be
      # 'no' which would be a truthy value despite the fact that it
      # should be falsey
      if self.kill_others == true || self.kill_others =~ /yes/i
        'Y'
      elsif self.kill_others == false || self.kill_others =~ /no/i
        'N'
      else
        nil
      end
    end
  end
end
