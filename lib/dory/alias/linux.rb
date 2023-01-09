module Dory
  module Alias
    module Linux
      message = 'Loopback alias creation not implemented on Linux. Please create an alias using your distribution\'s supported configuration mechanism'
      
      def self.configure(address)
        puts message.yellow
      end
      def self.clean(address)
        puts message.yellow
      end
    end
  end
end
