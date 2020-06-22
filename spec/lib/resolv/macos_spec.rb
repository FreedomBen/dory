require 'rspec'

RSpec.describe Dory::Resolv::Macos do
  let(:resolv_dir) { '/tmp/resolver' }
  let(:resolv_files) { %w[docker dory] }
  let(:system_resolv_file) { '/tmp/resolv.conf' }
  let(:filenames) { %w[/tmp/resolver/docker /tmp/resolver/dev /tmp/resolver/dory] }

  let(:stub_resolv_files) do
    ->(files = filenames) { allow(Dory::Resolv::Macos).to receive(:resolv_files) { files } }
  end

  let(:unstub_resolv_files) do
    ->() { allow(Dory::Resolv::Macos).to receive(:resolv_files).and_call_original }
  end

  let!(:set_macos) do
    allow(Dory::Os).to receive(:macos?){ true }
    allow(Dory::Os).to receive(:ubuntu?){ false }
    allow(Dory::Os).to receive(:fedora?){ false }
    allow(Dory::Os).to receive(:arch?){ false }
  end

  before :each do
    allow(Dory::Resolv::Macos).to receive(:resolv_dir) { resolv_dir }
  end

  after :each do
    allow(Dory::Resolv::Macos).to receive(:resolv_dir).and_call_original
  end

  context 'settings' do
    context 'resolv' do
      let(:default_port) { 19323 }
      let(:specified_port) { 9999 }
      let(:explicit_port) {{ dory: { resolv: { port: specified_port }}}}
      let(:implicit_port) {{ dory: { resolv: {}}}}
      let(:explicit_ip) {{ dory: { resolv: { nameserver: '5.5.5.5' }}}}
      let(:dinghy_ip) {{ dory: { resolv: { nameserver: 'dinghy' }}}}

      it 'has a default port if one is not specified' do
        allow(Dory::Config).to receive(:settings) { explicit_port }
        expect(Dory::Resolv::Macos.port).to eq(specified_port)
      end

      it "let's you specify a port" do
        allow(Dory::Config).to receive(:settings) { implicit_port }
        expect(Dory::Resolv::Macos.port).to eq(default_port)
      end

      it 'uses the specified nameserver' do
        allow(Dory::Config).to receive(:settings) { explicit_ip }
        expect(Dory::Resolv::Macos.nameserver).to eq('5.5.5.5')
      end

      it 'pulls the setting from dinghy if dinghy is specified' do
        allow(Dory::Dinghy).to receive(:ip) { '1.1.1.1' }
        allow(Dory::Config).to receive(:settings) { dinghy_ip }
        expect(Dory::Resolv::Macos.nameserver).to eq('1.1.1.1')
      end

      it 'returns false from #configure if dinghy doesnt return an IP address' do
        allow(Dory::Bash).to receive(:run_command) do
          OpenStruct.new({ stdout: 'Invalid operation' })
        end
        allow(Dory::Config).to receive(:settings) { dinghy_ip }
        expect(Dory::Resolv.configure).to be_falsey
      end
    end

    context 'dnsmasq' do
      let(:domains) { %w[docker dev dory somethingelse] }
      let(:domains_settings) {{ dory: { dnsmasq: {
        domains: domains.map{|d| { domain: d, address: '127.0.0.1' } }
      }}}}

      it 'has a filename for each domain' do
        allow(Dory::Config).to receive(:settings) { domains_settings }
        expect(Dory::Resolv::Macos.resolv_file_names).to match_array(domains)
        expect(Dory::Resolv::Macos.resolv_files).to match_array(
          domains.map{|d| "#{Dory::Resolv::Macos.resolv_dir}/#{d}" }
        )
      end
    end
  end

  context "creating and deleting the file" do
    before :each do
      stub_resolv_files.call
      # To add an extra layer of protection against modifying the
      # real resolv file, make sure it matches
      expect(Dory::Resolv::Macos.resolv_files).to match_array(filenames)
      filenames.each do |filename|
        if File.exist?(filename)
          puts "Requesting sudo to delete #{filename}".green
          Dory::Bash.run_command("sudo rm -f #{filename}")
        end
        expect(File.exist?(filename)).to be_falsey
      end
    end

    after :each do
      unstub_resolv_files.call
    end

    it 'creates the directory if it doesn\'t exist' do
      puts "Requesting sudo to delete #{resolv_dir}".green
      Dory::Bash.run_command("sudo rm -rf #{resolv_dir}")
      expect{Dory::Resolv::Macos.configure}.to change{Dir.exist?(resolv_dir)}.from(false).to(true)
    end

    it "creates the files with the nameserver in it" do
      expect(filenames.all?{|f| !File.exist?(f)}).to be_truthy
      Dory::Resolv::Macos.configure
      expect(filenames.all? do |f|
        File.exist?(f) && File.read(f) =~ /added.by.dory/
      end).to be_truthy
    end

    it "cleans up properly" do
      filenames.each do |filename|
        expect{Dory::Resolv::Macos.configure}.to change{
          File.exist?(filename)
        }.from(false).to(true)
        expect{Dory::Resolv::Macos.clean}.to change{
          File.exist?(filename)
        }.from(true).to(false)
      end
    end

    context 'with dinghy' do
      let(:stub_for_dinghy) do
        ->(nameserver, port) do
          allow(Dory::Dinghy).to receive(:ip) { nameserver }
          allow(Dory::Config).to receive(:settings) do
            { dory: { resolv: { nameserver: 'dinghy', port: port }}}
          end
          expect(Dory::Resolv::Macos.nameserver).to eq(nameserver)
        end
      end

      it 'still knows it has our nameserver if the dinghy ip address changes' do
        expect(filenames.all?{|f| !File.exist?(f)}).to be_truthy

        nameserver_1 = '3.3.3.3'
        nameserver_2 = '4.4.4.4'
        port = 1234
        stub_for_dinghy.call(nameserver_1, port)
        expect(Dory::Resolv::Macos.nameserver).to eq(nameserver_1)

        Dory::Resolv::Macos.configure
        expect(filenames.all? do |f|
          File.exist?(f) && File.read(f) =~ /added.by.dory/
        end).to be_truthy
        expect(Dory::Resolv::Macos.nameserver).to eq(nameserver_1)
        expect(Dory::Resolv::Macos.has_our_nameserver?).to be_truthy

        stub_for_dinghy.call(nameserver_2, port)
        expect(Dory::Resolv::Macos.nameserver).to eq(nameserver_2)
        expect(Dory::Resolv::Macos.has_our_nameserver?).to be_truthy

        filenames.each{ |filename| expect(File.exist?(filename)).to be_truthy }
        Dory::Resolv::Macos.clean
        filenames.each{ |filename| expect(File.exist?(filename)).to be_falsey }
      end
    end
  end

  context "Seeing system settings" do
    it "knows if we are in the resolv file" do
      # TODO check to see if the changes we wrote to the resolv file
      # were propagated into the system resolv file
    end

    it "knows if we are not in the resolv file" do

    end
  end

  context "knows if we've edited the file" do
    let(:comment) { '# added by dory' }

    let(:stub_resolv) do
      ->(nameserver, file_comment = comment) do
        allow(Dory::Resolv::Macos).to receive(:nameserver){ nameserver }
        allow(Dory::Resolv::Macos).to receive(:file_comment){ file_comment }
        expect(Dory::Resolv::Macos.nameserver).to eq(nameserver)
        expect(Dory::Resolv::Macos.file_comment).to eq(file_comment)
      end
    end

    let(:contents) do
      ->(nameserver, port) do
        <<-EOF.gsub(' ' * 10, '')
          # added by dory
          nameserver #{nameserver}
          port #{port}
        EOF
      end
    end

    let(:stub_the_things) do
      ->(nameserver, port) do
        allow(Dory::Resolv::Macos).to receive(:file_nameserver_line) { "nameserver #{nameserver}" }
        allow(Dory::Resolv::Macos).to receive(:port) { port }
      end
    end

    %w[127.0.0.1 192.168.53.164].each do |nameserver|
      %w[53 9965 1234].each do |port|
        it "does think we edited the file if 127.0.0.1 is there but the comment isn't" do
          stub_resolv.call(nameserver)
          stub_the_things.call(nameserver, port)
          expect(
            Dory::Resolv::Macos.contents_has_our_nameserver?(contents.call(nameserver, port))
          ).to be_truthy
        end
      end
    end

    it 'doesnt think we edited the file if we didnt' do
      pending 'implement me plz'
      fail
    end
  end
end
