require 'system/spec_helper'

describe 'with release, stemcell and deployment' do
  before(:all) do
    @requirements.requirement(@requirements.stemcell)
    @requirements.requirement(@requirements.release)
  end

  before(:all) do
    load_deployment_spec
    use_static_ip
    use_vip
    @requirements.requirement(deployment, @spec) # 2.5 min on local vsphere
  end

  after(:all) do
    @requirements.cleanup(deployment)
  end

  describe 'agent' do
    it 'should survive agent dying', ssh: true do
      Dir.mktmpdir do |tmpdir|
        ssh(public_ip_v2, 'vcap', "echo #{@env.vcap_password} | sudo -S pkill -9 agent", ssh_options)
        wait_for_vm('batlight/0')
        expect(bosh_safe("logs batlight 0 --agent --dir #{tmpdir}")).to succeed
      end
    end
  end

  describe 'ssh' do
    it 'can bosh ssh into a vm' do
      private_key = ssh_options[:private_key]

      # Try our best to clean out old host fingerprints for director and vms
      if File.exist?(File.expand_path('~/.ssh/known_hosts'))
        Bosh::Exec.sh("ssh-keygen -R '#{@env.director}'")
        Bosh::Exec.sh("ssh-keygen -R '#{static_ip}'")
      end

      if private_key
        bosh_ssh_options = {
          gateway_host: @env.director,
          gateway_user: 'vcap',
          gateway_identity_file: private_key,
        }.map { |k, v| "--#{k} '#{v}'" }.join(' ')

        # Note gateway_host + ip: ...fingerprint does not match for "micro.ci2.cf-app.com,54.208.15.101" (Net::SSH::HostKeyMismatch)
        if File.exist?(File.expand_path('~/.ssh/known_hosts'))
          Bosh::Exec.sh("ssh-keygen -R '#{@env.director},#{static_ip}'")
        end
      end

      expect(bosh_safe("ssh batlight 0 'uname -a' #{bosh_ssh_options}")).to succeed_with /Linux/
    end
  end

  describe 'job' do
    it 'should recreate a job' do
      expect(bosh_safe('recreate batlight 0')).to succeed_with /batlight\/0 recreated/
    end

    it 'should stop and start a job' do
      expect(bosh_safe('stop batlight 0')).to succeed_with /batlight\/0 stopped/
      expect(bosh_safe('start batlight 0')).to succeed_with /batlight\/0 started/
    end
  end

  describe 'logs' do
    it 'should get agent log' do
      with_tmpdir do
        expect(bosh_safe('logs batlight 0 --agent')).to succeed_with /Logs saved in/
        files = tar_contents(tarfile)
        expect(files).to include './current'
      end
    end

    it 'should get job logs' do
      with_tmpdir do
        expect(bosh_safe('logs batlight 0')).to succeed_with /Logs saved in/
        files = tar_contents(tarfile)
        expect(files).to include './batlight/batlight.stdout.log'
        expect(files).to include './batlight/batlight.stderr.log'
      end
    end
  end

  describe 'restore' do
    # This test is marked pending because it breaks CI.
    # This test fails in various ways, usually in one of the 'deployments' verifications
    # Additionally, this test uses before(:all). This means the director is deployed once for this
    # entire file. This test leaves the deployment in a deleted state, which will cause
    # other tests in an unexpected initial state.
    it 'should restore director DB' do
      with_tmpdir do
        expect(bosh_safe('backup one_deployment.tgz')).to succeed_with /Backup of BOSH director was put in.*one_deployment\.tgz/
        expect(bosh_safe("delete deployment #{deployment_name}")).to succeed_with /Deleted deployment/
        expect(bosh_safe('backup no_deployment.tgz')).to succeed_with /Backup of BOSH director was put in.*no_deployment\.tgz/
        expect(bosh_safe('restore one_deployment.tgz')).to succeed_with /Restore done!/
        expect(bosh_safe('deployments')).to succeed_with /#{deployment_name}/
        expect(bosh_safe('restore no_deployment.tgz')).to succeed_with /Restore done!/
        result = bosh_safe('deployments')
        expect(result.output).to match_regex(/No deployments/)
      end
    end
  end
end
