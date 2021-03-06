RSpec.describe Sanctum::Command::Push do
  let(:helper) {SanctumTest::Helpers.new}
  let(:options) { helper.options }
  let(:vault_client) { helper.vault_client }
  let(:vault_env) { helper.vault_env }
  let(:config_path) { helper.config_path }
  let(:random_value_one) { ('a'..'z').to_a.shuffle[0,8].join }
  let(:random_value_two) { ('a'..'z').to_a.shuffle[0,8].join }
  context "generic secrets backend" do
    before :each do
      helper.vault_cleanup
      helper.vault_setup(secrets_engine: "generic")

      # Write transit encrypted data to a file to test push command
      Sanctum::VaultTransit.write_to_file(vault_client, {"#{config_path}/#{options.dig(:sync).first.dig(:path)}/iad/dev/env" => {"keyone" => "#{random_value_one}"}}, options[:sanctum][:transit_key])
    end

    it "reads local secrets and pushes to vault" do
      described_class.new(options).run
      vault_secret = vault_client.logical.read("#{options.dig(:sync).first.dig(:prefix)}/iad/dev/env").data
      expect(vault_secret).to eq({:keyone=>"#{random_value_one}"})
    end
  end

  context "kv version 1 secrets backend" do
    before :each do
      helper.vault_cleanup
      helper.vault_setup(secrets_engine: "kv", secrets_version: 1)

      # Write transit encrypted data to a file to test push command
      Sanctum::VaultTransit.write_to_file(vault_client, {"#{config_path}/#{options.dig(:sync).first.dig(:path)}/iad/dev/env" => {"keyone" => "#{random_value_one}"}}, options[:sanctum][:transit_key])
    end

    it "reads local secrets and pushes to vault" do
      described_class.new(options).run
      vault_secret = vault_client.logical.read("#{options.dig(:sync).first.dig(:prefix)}/iad/dev/env").data
      expect(vault_secret).to eq({:keyone=>"#{random_value_one}"})
    end
  end

  context "kv version 2 secrets backend" do
    before :each do
      helper.vault_cleanup
      helper.vault_setup(secrets_engine: "kv", secrets_version: 2)
    end

    it "pushes local differences to vault" do
      Sanctum::VaultTransit.write_to_file(vault_client, {"#{config_path}/#{options.dig(:sync).first.dig(:path)}/iad/dev/env" => {"keyone" => "#{random_value_one}"}}, options[:sanctum][:transit_key])
      described_class.new(options).run
      vault_secret = vault_client.logical.read("#{options.dig(:sync).first.dig(:prefix)}/iad/dev/env").data[:data]

      expect(vault_secret).to eq({:keyone=>"#{random_value_one}"})
    end

    it "pushes update secret to vault" do
      # Write local file
      Sanctum::VaultTransit.write_to_file(vault_client, {"#{config_path}/#{options.dig(:sync).first.dig(:path)}/iad/dev/env" => {"keyone" => "#{random_value_one}"}}, options[:sanctum][:transit_key])
      # Write secret to vault
      vault_client.logical.write("#{options.dig(:sync).first.dig(:prefix)}/data/iad/dev/env", data: { keyone: "#{random_value_two}" })

      run_output = with_captured_stdout { described_class.new(options).run }
      vault_secret = vault_client.logical.read("#{options.dig(:sync).first.dig(:prefix)}/iad/dev/env").data[:data]

      expect(vault_secret).to eq({:keyone=>"#{random_value_one}"})
      expect(run_output).to include(
        "keyone => #{random_value_one}",
        "keyone => #{random_value_two}"
      )
    end

    it "does not push to vault if there are no differences" do
      Sanctum::VaultTransit.write_to_file(vault_client, {"#{config_path}/#{options.dig(:sync).first.dig(:path)}/iad/prod/env" => {"keytwo" => "#{random_value_two}"}}, options[:sanctum][:transit_key])
      vault_client.logical.write("#{options.dig(:sync).first.dig(:prefix)}/data/iad/prod/env", data: { keytwo: "#{random_value_two}" })

      run_stderr = with_captured_stderr {described_class.new(options).run}
      expect(run_stderr).to include("contains no differences")
    end

    it "outputs diff with key to stdout" do
      Sanctum::VaultTransit.write_to_file(vault_client, {"#{config_path}/#{options.dig(:sync).first.dig(:path)}/iad/dev/env" => {"keyone" => "#{random_value_one}"}}, options[:sanctum][:transit_key])
      expect { described_class.new(options).run }.to output(
        /\.*+\/vault\/vault-test\/iad\/dev\/env => {"keyone"=>"#{random_value_one}"}/
      ).to_stdout
    end
  end
end
