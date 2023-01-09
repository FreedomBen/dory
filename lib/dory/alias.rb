module Dory
  module Alias
    def self.get_module
      return Dory::Alias::Macos if Os.macos?
      Dory::Alias::Linux
    end

    def self.configure()
      puts "Requesting sudo to create loopback aliases".green
      self.each_address lambda {|address|
        puts "[DEBUG] creating loopback alias for #{address}" if Dory::Config.debug?
        self.get_module.configure(address)
      }
    end

    def self.clean()
      puts "Requesting sudo to remove loopback aliases".green
      self.each_address lambda {|address|
        puts "[DEBUG] creating loopback alias for #{address}" if Dory::Config.debug?
        self.get_module.clean(address)
      }
    end

    def self.check()
      addresses = []
      self.each_address lambda {|address|
        addresses.push(address) if self.get_module.check(address)
      }
      addresses
    end

    def self.each_address(cb)
      success = true
      self.addresses.each do |address|
        begin 
          cb.call(address)
        rescue Exception => error
          puts error.message.red
          success = false
        end
      end
      success
    end

    def self.addresses
      Dory::Config.settings[:dory][:aliases][:addresses] || []
    end
  end
end
