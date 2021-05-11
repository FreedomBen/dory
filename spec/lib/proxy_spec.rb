RSpec.describe Dory::Proxy do
  after :all do
    Dory::Proxy.delete
  end

  it "has the docker client" do
    expect(Dory::Proxy.docker_installed?).to be_truthy
  end

  it "starts up the container" do
    Dory::Proxy.delete
    expect(Dory::Proxy).not_to be_running
    expect{Dory::Proxy.start}.to change{Dory::Proxy.running?}.from(false).to(true)
    expect(Dory::Proxy).to be_container_exists
  end

  it "doesn't fail when starting the container twice" do
    2.times{ expect{Dory::Proxy.start}.not_to raise_error }
    expect(Dory::Proxy).to be_running
  end

  it "deletes the container" do
    expect(Dory::Proxy.start).to be_truthy
    expect(Dory::Proxy).to be_running
    expect(Dory::Proxy).to be_container_exists
    expect{Dory::Proxy.delete}.to change{Dory::Proxy.container_exists?}.from(true).to(false)
    expect(Dory::Proxy).not_to be_running
  end

  it "stops the container" do
    expect(Dory::Proxy.start).to be_truthy
    expect(Dory::Proxy).to be_running
    expect(Dory::Proxy.stop).to be_truthy
    expect(Dory::Proxy).to be_container_exists
    expect(Dory::Proxy).not_to be_running
  end

  it "starts the container when it already exists" do
    expect(Dory::Proxy.start).to be_truthy
    expect(Dory::Proxy).to be_running
    expect(Dory::Proxy.stop).to be_truthy
    expect(Dory::Proxy).to be_container_exists
    expect{Dory::Proxy.start}.to change{Dory::Proxy.running?}.from(false).to(true)
    expect(Dory::Proxy).to be_container_exists
    expect(Dory::Proxy).to be_running
  end

  context "ssl" do
    let(:filename) { '/tmp/dory-test-config-yml' }

    let(:expect_proxy_to_start) do
      ->() do
        Dory::Proxy.delete
        expect(Dory::Proxy).not_to be_running
        expect{Dory::Proxy.start}.to change{Dory::Proxy.running?}.from(false).to(true)
        expect(Dory::Proxy).to be_container_exists
      end
    end

    let(:patch_ssl_enabled) do
      ->(enabled) do
        new_config = YAML.load(Dory::Config.default_yaml)
        new_config['dory']['nginx_proxy']['https_enabled'] = enabled
        expect(new_config['dory']['nginx_proxy']['https_enabled']).to eq(enabled)
        allow(Dory::Config).to receive(:default_yaml) { new_config.to_yaml }
        expect(Dory::Config.settings['dory']['nginx_proxy']['https_enabled']).to eq(enabled)
      end
    end

    let(:expect_port) do
      ->(in_cmd:) do
        if in_cmd
          expect(Dory::Proxy.run_command).to match(/-p\s+443:443/)
        else
          expect(Dory::Proxy.run_command).not_to match(/-p\s+443:443/)
        end
      end
    end

    before :each do
      allow(Dory::Config).to receive(:filename) { filename }
    end

    context "enabled" do
      it "enables" do
        patch_ssl_enabled.call(true)
        expect_port.call(in_cmd: true)
        expect_proxy_to_start.call()
      end

      it "disables" do
        patch_ssl_enabled.call(false)
        expect_port.call(in_cmd: false)
        expect_proxy_to_start.call()
      end
    end

    context "port" do
      let(:new_port) { 1234 }
      let(:new_tls_port) { 4567 }

      let(:patch_ports) do
        ->(port:, tls_port:) do
          new_config = YAML.load(Dory::Config.default_yaml)
          new_config['dory']['nginx_proxy']['port'] = port
          new_config['dory']['nginx_proxy']['tls_port'] = tls_port
          expect(new_config['dory']['nginx_proxy']['port']).to eq(port)
          expect(new_config['dory']['nginx_proxy']['tls_port']).to eq(tls_port)
          allow(Dory::Config).to receive(:default_yaml) { new_config.to_yaml }
          expect(Dory::Config.settings['dory']['nginx_proxy']['port']).to eq(port)
          expect(Dory::Config.settings['dory']['nginx_proxy']['tls_port']).to eq(tls_port)
        end
      end

      it "defaults to 80 for http" do
        dy = YAML.load(Dory::Config.default_yaml)
        expect(dy['dory']['nginx_proxy']['port']).to eq(80)
        expect(dy['dory']['nginx_proxy']['tls_port']).to eq(443)
        expect(Dory::Proxy.run_command).to match(/-p\s+80:80/)
        expect(Dory::Proxy.run_command).to match(/-p\s+443:443/)
      end

      it "allows changing the ports" do
        dy = YAML.load(Dory::Config.default_yaml)
        expect(dy['dory']['nginx_proxy']['port']).to eq(80)
        expect(dy['dory']['nginx_proxy']['tls_port']).to eq(443)
        expect(Dory::Proxy.run_command).to match(/-p\s+80:80/)
        expect(Dory::Proxy.run_command).to match(/-p\s+443:443/)

        patch_ports.call(port: new_port, tls_port: new_tls_port)
        dy = YAML.load(Dory::Config.default_yaml)
        expect(dy['dory']['nginx_proxy']['port']).to eq(new_port)
        expect(dy['dory']['nginx_proxy']['tls_port']).to eq(new_tls_port)
        #require 'byebug'; debugger
        patch_ssl_enabled.call(true)
        expect(Dory::Proxy.run_command).to match(/-p\s+#{new_port}:80/)
        expect(Dory::Proxy.run_command).to match(/-p\s+#{new_tls_port}:443/)
      end
    end

    context "certs" do
      let(:patch_config_ssl_certs_dir) do
        ->(ssl_certs_dir) do
          new_config = YAML.load(Dory::Config.default_yaml)
          new_config['dory']['nginx_proxy']['ssl_certs_dir'] = ssl_certs_dir
          expect(new_config['dory']['nginx_proxy']['ssl_certs_dir']).to eq(ssl_certs_dir)
          allow(Dory::Config).to receive(:default_yaml) { new_config.to_yaml }
          expect(Dory::Config.settings[:dory][:nginx_proxy][:ssl_certs_dir]).to eq(ssl_certs_dir)
        end
      end

      let(:expect_not_in_cmd) do
        ->(ssl_certs_dir) do
          patch_config_ssl_certs_dir.call(ssl_certs_dir)
          expect(Dory::Proxy.run_command).not_to match(/-v\s.*..etc.nginx.certs/)
          expect_proxy_to_start.call()
        end
      end

      it "mounts the ssl certs dir when it's set" do
        ssl_certs_dir = '/usr/bin'
        patch_config_ssl_certs_dir.call(ssl_certs_dir)
        expect(Dory::Proxy.run_command).to match(/-v\s#{Regexp.escape(ssl_certs_dir)}..etc.nginx.certs/)
        expect_port.call(in_cmd: true)
        expect_proxy_to_start.call()
      end

      it "does not mount anything when ssl certs is empty string" do
        expect_not_in_cmd.call('')
        expect_proxy_to_start.call()
      end

      it "does not mount anything when ssl certs is nil" do
        expect_not_in_cmd.call(nil)
        expect_proxy_to_start.call()
      end

      it "uses the freedomben proxy image when no ssl certs are being mounted" do
        patch_config_ssl_certs_dir.call('')
        expect(Dory::Proxy.dory_http_proxy_image_name).to match(/^freedomben/)
        patch_config_ssl_certs_dir.call(nil)
        expect(Dory::Proxy.dory_http_proxy_image_name).to match(/^freedomben/)
      end

      it "uses the codekitchen proxy image when ssl certs are being mounted" do
        patch_config_ssl_certs_dir.call('/usr/bin')
        expect(Dory::Proxy.dory_http_proxy_image_name).to match(/^codekitchen/)
      end
    end
  end
end
