module Dory
  module Alias
    module Macos
      def self.plist_file(address)
        "/Library/LaunchDaemons/com.user.lo0-loopback-#{address.gsub('.', '-')}.plist"
      end

      def self.plist(address) 
        <<-PLIST
        <?xml version="1.0" encoding="UTF-8"?>
        <!DOCTYPE plist PUBLIC -//Apple Computer//DTD PLIST 1.0//EN http://www.apple.com/DTDs/PropertyList-1.0.dtd >
        <plist version="1.0">
        <dict>
          <key>Label</key>
          <string>com.user.lo0-loopback</string>
          <key>ProgramArguments</key>
          <array>
            <string>/sbin/ifconfig</string>
            <string>lo0</string>
            <string>alias</string>
            <string>#{address}</string>
          </array>
          <key>RunAtLoad</key> <true/>
          <key>Nice</key>
          <integer>10</integer>
          <key>KeepAlive</key>
          <false/>
          <key>AbandonProcessGroup</key>
          <true/>
          <key>StandardErrorPath</key>
          <string>/var/log/loopback-alias.log</string>
          <key>StandardOutPath</key>
          <string>/var/log/loopback-alias.log</string>
        </dict>
        </plist>
        PLIST
      end

      def self.autostart
        Dory::Config.settings[:dory][:aliases][:autostart]
      end

      def self.configure(address)
        Bash.run_command("sudo /sbin/ifconfig lo0 alias #{Shellwords.escape(address)} >/dev/null")

        if self.autostart && !File.exist?(self.plist_file(address))
          Bash.run_command("echo -e '#{Bash.escape_single_quotes(self.plist(address))}' | sudo /usr/bin/tee #{Shellwords.escape(self.plist_file(address))} >/dev/null")
        end
      end

      def self.clean(address)
        Bash.run_command("sudo /sbin/ifconfig lo0 delete #{Shellwords.escape(address)} >/dev/null")

        if File.exist?(self.plist_file(address))
          Bash.run_command("sudo rm #{Shellwords.escape(self.plist_file(address))} >/dev/null")
        end
      end

      def self.check(address)
        result = Bash.run_command("/sbin/ifconfig lo0")
        result.stdout.include? "inet #{address}"
      end
    end
  end
end
