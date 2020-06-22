load 'bin/dory'

RSpec.describe DoryBin do
  def run_with(*args)
    DoryBin.start(args)
  end

  # This method will wrap the call and return stdout as a string.
  def capture_stdout
    begin
      old_stdout = $stdout
      $stdout = StringIO.new('','w')
      yield
      $stdout.string
    ensure
      $stdout = old_stdout
    end
  end

  def resolv_dir
    '/tmp/resolver'
  end

  def macos_resolv_filenames
    %w[/tmp/resolver/docker /tmp/resolver/dory]
  end

  def linux_resolv_filename
    '/tmp/resolv.conf'
  end

  def config_filename
    '/tmp/dory-test-config-yml'
  end

  def default_config
    %Q(
      ---
      :dory:
        :dnsmasq:
          :enabled: true
          :domains:
            - :domain: docker_test_name
              :address: 192.168.11.1
            - :domain: docker_second_test
              :address: 192.168.11.3
          :container_name: dory_dnsmasq_test_name
        :nginx_proxy:
          :enabled: true
          :ssl_certs_dir: #{ssl_certs_dir}
          :container_name: dory_dinghy_http_proxy_test_name
        :resolv:
          :enabled: true
          :nameserver: 192.168.11.1
    ).split("\n").map{|s| s.sub(' ' * 6, '')}.join("\n")
  end

  let(:dory_bin) { DoryBin.new }

  let(:set_macos) do
    ->() do
      allow(Dory::Os).to receive(:macos?){ true }
      allow(Dory::Os).to receive(:ubuntu?){ false }
      allow(Dory::Os).to receive(:fedora?){ false }
      allow(Dory::Os).to receive(:arch?){ false }
    end
  end

  let(:unset_macos) do
    ->() do
      allow(Dory::Os).to receive(:macos?).and_call_original
      allow(Dory::Os).to receive(:ubuntu?).and_call_original
      allow(Dory::Os).to receive(:fedora?).and_call_original
      allow(Dory::Os).to receive(:arch?).and_call_original
    end
  end

  let(:set_docker_installed) do
    ->(installed) do
      allow(Dory::DockerService).to receive(:docker_installed?) { installed }
    end
  end

  let(:restore_docker_installed) do
    ->() do
      allow(Dory::Dnsmasq).to receive(:docker_installed?).and_call_original
      allow(Dory::Proxy).to receive(:docker_installed?).and_call_original
    end
  end

  let(:ssl_certs_dir) { '/usr/bin' }
  let(:overridden_proxy_container_name) { 'some_container_name' }

  before :all do
    File.delete(config_filename) if File.exist?(config_filename)
    `touch #{linux_resolv_filename}`
  end

  after :all do
    File.delete(config_filename) if File.exist?(config_filename)
  end

  before :each do
    allow(Dory::Config).to receive(:filename) { config_filename }
    allow(Dory::Config).to receive(:default_yaml) { default_config }
    allow(Dory::Resolv::Macos).to receive(:resolv_files) { macos_resolv_filenames }
    allow(Dory::Resolv::Linux).to receive(:common_resolv_file) { linux_resolv_filename }
    allow(Dory::Resolv::Linux).to receive(:ubuntu_resolv_file) { linux_resolv_filename }
  end

  after :each do
    # delete any containers we made so we don't pollute other tests
    Dory::Dnsmasq.delete
    Dory::Proxy.delete
  end

  describe 'up' do
    %w[proxy dns resolv].each do |service|
      it "only starts #{service} when specified by itself" do
        allow(Dory::Proxy).to receive(:start) { service == 'proxy' }
        allow(Dory::Dnsmasq).to receive(:start) { service == 'dns' }
        allow(Dory::Resolv).to receive(:configure) { service == 'resolv' }
        dory_bin.up(service)
        expect(Dory::Proxy).send(service == 'proxy' ? :to : :not_to, have_received(:start))
        expect(Dory::Dnsmasq).send(service == 'dns' ? :to : :not_to, have_received(:start))
        expect(Dory::Resolv).send(service == 'resolv' ? :to : :not_to, have_received(:configure))
      end
    end
  end

  describe 'down' do
    %w[proxy dns resolv].each do |service|
      it "only stops #{service} when specified by itself" do
        allow(Dory::Proxy).to receive(:stop) { service == 'proxy' }
        allow(Dory::Dnsmasq).to receive(:stop) { service == 'dns' }
        allow(Dory::Resolv).to receive(:clean) { service == 'resolv' }
        dory_bin.down(service)
        expect(Dory::Proxy).send(service == 'proxy' ? :to : :not_to, have_received(:stop))
        expect(Dory::Dnsmasq).send(service == 'dns' ? :to : :not_to, have_received(:stop))
        expect(Dory::Resolv).send(service == 'resolv' ? :to : :not_to, have_received(:clean))
      end
    end
  end

  describe 'version' do
    it 'answers with the version' do
      expect(capture_stdout{dory_bin.version}).to match(/dory.*version.*#{Dory.version}/i)
    end
  end

  describe 'restart' do
    %w[proxy dns resolv].each do |service|
      it "only stops #{service} when specified by itself" do
        allow(Dory::Proxy).to receive(:start) { service == 'proxy' }
        allow(Dory::Dnsmasq).to receive(:start) { service == 'dns' }
        allow(Dory::Resolv).to receive(:configure) { service == 'resolv' }
        allow(Dory::Proxy).to receive(:stop) { service == 'proxy' }
        allow(Dory::Dnsmasq).to receive(:stop) { service == 'dns' }
        allow(Dory::Resolv).to receive(:clean) { service == 'resolv' }
        dory_bin.restart(service)
        expect(Dory::Proxy).send(service == 'proxy' ? :to : :not_to, have_received(:stop))
        expect(Dory::Dnsmasq).send(service == 'dns' ? :to : :not_to, have_received(:stop))
        expect(Dory::Resolv).send(service == 'resolv' ? :to : :not_to, have_received(:clean))
        expect(Dory::Proxy).send(service == 'proxy' ? :to : :not_to, have_received(:start))
        expect(Dory::Dnsmasq).send(service == 'dns' ? :to : :not_to, have_received(:start))
        expect(Dory::Resolv).send(service == 'resolv' ? :to : :not_to, have_received(:configure))
      end
    end
  end

  describe 'status' do
    it 'doesnt crash' do
      expect{capture_stdout{dory_bin.status}}.not_to raise_error
      expect{capture_stdout{dory_bin.up}}.not_to raise_error
      expect{capture_stdout{dory_bin.status}}.not_to raise_error
      expect{capture_stdout{dory_bin.down}}.not_to raise_error
      expect{capture_stdout{dory_bin.ip}}.not_to raise_error
      set_macos.call
      expect{capture_stdout{dory_bin.status}}.not_to raise_error
      expect{capture_stdout{dory_bin.up}}.not_to raise_error
      expect{capture_stdout{dory_bin.status}}.not_to raise_error
      expect{capture_stdout{dory_bin.down}}.not_to raise_error
      expect{capture_stdout{dory_bin.ip}}.not_to raise_error
      unset_macos.call
    end
  end

  describe 'pull' do
    it 'prints error message when docker is not installed' do
      set_docker_installed.call(false)
      expect{capture_stdout{dory_bin.pull}}.not_to raise_error
      expect(capture_stdout{dory_bin.pull}).to match(/docker.*not.*installed/i)
    end

    it 'pulls down the images' do
      set_docker_installed.call(true)
      results = capture_stdout{dory_bin.pull}
      expect(results).not_to match(/docker.*not.*installed/i)
      expect(results).to match(/pulling.image/i)
    end
  end

  describe 'ip' do
    %w[dns proxy].each do |cont|
      it "prints the ip address of the #{cont} container" do
        expect(capture_stdout{dory_bin.ip(cont)}).to match(/172\.\d{1,3}\.\d{1,3}\.\d{1,3}/i)
      end
    end
  end

  describe 'config file' do
    let(:config_file_exists?) { ->() { File.exist?(Dory::Config.filename)}}

    let(:old_config) do
      %Q(---
        :dory:
          :dnsmasq:
            :enabled: true
            :domain: docker_test_name
            :address: 192.168.11.1
            :container_name: dory_dnsmasq_test_name
          :nginx_proxy:
            :enabled: true
            :container_name: nginx_container_name
          :resolv:
            :enabled: true
            :nameserver: 192.168.11.1
      ).split("\n").map{|s| s.sub(' ' * 6, '')}.join("\n")
    end

    it 'writes a config file' do
      expect{ run_with('config-file') }.to change{ config_file_exists?.call }.from(false).to(true)
    end

    context 'upgrades' do
      before :each do
        File.write(config_filename, old_config)
        run_with('config-file', '--upgrade')
      end

      it 'converts symbol keys to strings' do
        yaml = YAML.load_file(config_filename)
        yaml.each_key do |k|
          expect(k).to be_a(String)
          yaml[k].each_key{ |ck| expect(ck).to be_a(String) }
        end
      end

      it 'moves domain and address into array' do
        yaml = YAML.load_file(config_filename).with_indifferent_access
        expect(yaml[:dory][:dnsmasq][:domain]).to be_nil
        expect(yaml[:dory][:dnsmasq][:address]).to be_nil
        expect(yaml[:dory][:dnsmasq][:domains].length).to eq(1)
        expect(yaml[:dory][:dnsmasq][:domains][0][:domain]).to eq('docker_test_name')
        expect(yaml[:dory][:dnsmasq][:domains][0][:address]).to eq('192.168.11.1')
      end
    end

    context 'config_file_action' do
      it 'doesn\'t ask about upgrading if flag is set' do
        expect(dory_bin.send('config_file_action', { upgrade: true })).to eq('u')
      end

      it 'doesn\'t ask about overwriting if flag is set' do
        expect(dory_bin.send('config_file_action', { force: true })).to eq('o')
      end

      it 'infers upgrade if both upgrade and force are set' do
        expect(dory_bin.send('config_file_action', { upgrade: true, force: true })).to eq('u')
      end
    end
  end

  context 'services enabled/disabled' do
    %I[nginx_proxy dnsmasq resolv].each do |service|
      context "#{service}" do
        [{ enabled: true}, { disabled: false }].each do |enabled|
          it "is #{enabled.keys.first} when #{enabled.keys.first}" do
            settings = { dory: { service => { enabled: enabled.values.first }}}
            expect(dory_bin.send("#{service}_enabled?", (settings))).to eq(enabled.values.first)
          end
        end
      end
    end
  end

  describe 'specification of services' do
    context 'sanitization' do
      it 'defaults to all services if none are specified' do
        expect(dory_bin.send(:sanitize_services, [])).to eq(dory_bin.send(:valid_services))
      end

      it 'returns false if an invalid service is present' do
        expect(dory_bin.send(:sanitize_services, ['badness'])).to be_falsey
      end

      it 'returns a list of canonical services' do
        input = %w[nginx-proxy resolve dnsmasq]
        output = %w[proxy resolv dns]
        expect(dory_bin.send(:sanitize_services, input)).to match_array(output)
      end
    end

    context 'canonicalization of services' do
      it 'figures out what you mean' do
        {
          'proxy' => 'proxy',
          'nginx' => 'proxy',
          'nginx_proxy' => 'proxy',
          'nginx-proxy' => 'proxy',
          'dns' => 'dns',
          'dnsmasq' => 'dns',
          'resolv' => 'resolv',
          'resolve' => 'resolv'
        }.each do |input, can|
          expect(dory_bin.send(:canonical_service, input)).to eq(can)
        end
      end
    end

    it 'validates the service' do
      {
        'proxy' => true,
        'nginx' => true,
        'nginx_proxy' => true,
        'nginx-proxy' => true,
        'dns' => true,
        'dnsmasq' => true,
        'resolv' => true,
        'resolve' => true,
        'wrong' => false,
        'hello' => false,
        'world' => false
      }.each do |input, valid|
        expect(dory_bin.send(:valid_service?, input)). to eq(valid)
      end
    end
  end

  context "doesn't crash when docker is not installed" do
    %w[status up down restart version pull].each do |method|
      it " - #{method}" do
        set_docker_installed.call(false)
        expect{capture_stdout{dory_bin.send(method)}}.not_to raise_error
        restore_docker_installed.call
      end
    end
  end
end
