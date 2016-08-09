require 'net/scp'

module MiqAeMethodService
  class MiqAeServiceContainerDeployment < MiqAeServiceModelBase
    expose :container_deployment_nodes, :association => true
    expose :deployed_ems, :association => true
    expose :deployed_on_ems, :association => true
    expose :automation_task, :association => true
    expose :roles_addresses
    expose :container_nodes_by_role
    expose :ssh_auth
    expose :rhsm_auth
    SUBSCRIPTION_REPOS = ["rhel-7-server-rh-common-rpms", "rhel-7-server-rpms", "rhel-7-server-extras-rpms", "rhel-7-server-ose-3.2-rpms"].freeze
    ANSIBLE_LOG = "/tmp/ansible.log".freeze
    ANSIBLE_ERROR_LOG = "/tmp/openshift-ansible.log".freeze
    INVENTORIES_PATH = "/usr/share/ansible/openshift-ansible/".freeze
    SSH_AGENT_PATH = "/tmp/ssh_manageiq/".freeze

    def assign_container_deployment_node(vm_id, role)
      container_nodes_by_role(role).each do |deployment_node|
        next unless deployment_node.vm_id.nil?
        deployment_node.add_vm vm_id
      end
    end

    def subscribe_deployment_master(deployment_master, user)
      rhsub_user = rhsm_auth.userid
      rhsub_pass = rhsm_auth.password
      rhsm_sku = rhsm_auth.rhsm_sku
      perform_agent_commands(deployment_master, user, ["sudo subscription-manager register --username='#{rhsub_user}' --password='#{rhsub_pass}'"])
      pool_cmdret = perform_agent_commands(deployment_master, user, ["sudo subscription-manager list --available --matches='#{rhsm_sku}' --pool-only"])
      pool_id = pool_cmdret[:stdout].split("\n").first.to_s.strip()
      perform_agent_commands(deployment_master, user, ["sudo subscription-manager attach --pool='#{pool_id}'"]) unless pool_id.blank?
      enabled_repos_cmdret = perform_agent_commands(deployment_master, user, ['sudo subscription-manager repos --disable="*"',
                                                                       "sudo subscription-manager repos --enable=#{SUBSCRIPTION_REPOS.join(" --enable=")}",
                                                                       "sudo subscription-manager repos --list-enabled"])
      enabled_repos = enabled_repos_cmdret[:stdout].split(" ").to_a.map(&:strip).reject(&:empty?)
      missing_repos = SUBSCRIPTION_REPOS - enabled_repos
      raise StandardError, "couldn't register to following repos : #{missing_repos.join(',')} with SKU : #{rhsm_sku}" unless missing_repos.empty?
    end

    def subscribe_cluster(deployment_master, user)
      perform_agent_commands(deployment_master, user, ["sudo mv ~/rhel_subscribe_inventory.yaml #{INVENTORIES_PATH}"])
      run_playbook_command(deployment_master, user, "ansible-playbook /usr/share/ansible/openshift-ansible/playbooks/byo/rhel_subscribe.yml -i "\
                         "#{INVENTORIES_PATH}rhel_subscribe_inventory.yaml 1> #{ANSIBLE_LOG} 2> #{ANSIBLE_ERROR_LOG} < /dev/null")
    end

    def nodes_subscription_needed?
      container_deployment_nodes.count > 1
    end

    def ssh_user
      ssh_auth.userid
    end

    def add_deployment_provider(options)
      object_send(:add_deployment_provider, options)
    end

    def regenerate_ansible_inventory
      object_send(:generate_ansible_yaml)
    end

    def regenerate_ansible_subscription_inventory
      object_send(:generate_ansible_inventory_for_subscription)
    end

    def add_automation_task(task)
      ar_method do
        @object.automation_task = AutomationTask.find_by_id(task.id)
        @object.save!
      end
    end

    def customize(options = {})
      ar_method do
        if @object.customizations.empty?
          @object.customizations = {:agent => {}}
        end
        @object.customizations[:agent].merge!(options)
        @object.save!
      end
    end

    def perform_scp(ip, username, local_path, remote_path)
      Net::SCP.upload!(ip, username, local_path, remote_path, :ssh => {:key_data => ssh_auth.auth_key})
    end

    def perform_agent_commands(ip, username, commands = [])
      @ssh ||= LinuxAdmin::SSH.new(ip, username, ssh_auth.auth_key)
      @ssh.perform_commands(commands)
    end

    def check_connection(deployment_host_ip, username)
      agent = LinuxAdmin::SSHAgent.new(ssh_auth.auth_key, "#{SSH_AGENT_PATH}ssh_manageiq_#{id}")
      nodes_ips = container_deployment_nodes.collect(&:node_address)
      nodes_ips.delete(deployment_host_ip)
      success, unreachable_ips = agent.with_service do |socket|
        @ssh ||= LinuxAdmin::SSH.new(deployment_host_ip, username)
        unreachable_ips = nodes_ips.select do |sub_ip|
          @ssh.perform_commands(["sudo -E ssh -o 'StrictHostKeyChecking no' #{username}@#{sub_ip} echo 0"], socket)[:stdout].exclude?("0\r\n")
        end
        [unreachable_ips.empty?, unreachable_ips]
      end
      unless success
        raise StandardError, "couldn't connect to : #{unreachable_ips.join(',')}"
      end
      success
    end

    def playbook_running?
      pid = ar_method do
        @object.customizations[:agent][:ansible_pid] if @object.customizations[:agent]
      end
      !pid.nil?
    end

    def run_playbook_command(ip, username, cmd)
      result = {:finished => false}
      @ssh ||= LinuxAdmin::SSH.new(ip, username, ssh_auth.auth_key)
      ansible_process_pid = ansible_pid
      if ansible_process_pid
        process_running = @ssh.perform_commands(["sudo kill -0 #{ansible_process_pid}"])[:stdout]
        unless process_running.empty?
          result[:finished] = true
          result[:stdout] = @ssh.perform_commands(["sudo cat /tmp/ansible.log"])[:stdout]
          stop_agent
        end
      else
        start_playbook_command(username, cmd)
      end
      result
    end

    def start_playbook_command(username, cmd)
      pid, socket = create_agent(username)
      @ssh.perform_commands(["sudo rm -f #{ANSIBLE_ERROR_LOG} #{ANSIBLE_LOG}"])
      @ssh.perform_commands(["SSH_AUTH_SOCK=#{socket} nohup sudo -b -E #{cmd} 1> #{ANSIBLE_LOG} 2> #{ANSIBLE_ERROR_LOG} < /dev/null"])
      ansible_process_pid = @ssh.perform_commands(["sudo pgrep -f 'sudo -b -E'"])[:stdout].split("\r").first
      customize(:ansible_pid => ansible_process_pid, :agent_pid => pid, :agent_socket => socket)
    end

    def agent_exists?
      agent_pid
    end

    def create_agent(username)
      output = @ssh.perform_commands(["ssh-agent -a ssh_manageiq_#{id}"])[:stdout]
      vars = {}
      output.scan(/^(\w+)=([^;\n]+)/) { |k, v| vars[k] = v }
      socket, pid = vars.values_at('SSH_AUTH_SOCK', 'SSH_AGENT_PID')
      socket = "/#{username}/#{socket}"
      socket = "/home#{socket}" if username != "root"
      @ssh.perform_commands(["SSH_AUTH_SOCK=#{socket} SSH_AGENT_PID=#{pid} ssh-add -"], nil, ssh_auth.auth_key)
      [pid, socket]
    end

    def stop_agent
      pid =  agent_pid
      socket = agent_socket
      @ssh.perform_commands(["SSH_AGENT_PID=#{pid} ssh-agent -k &> /dev/null"])
      @ssh.perform_commands(["sudo rm -f #{socket}"])
      customize(:ansible_pid => nil, :agent_pid => nil, :agent_socket => nil)
    end

    def analyze_ansible_output(output)
      if output.blank?
        return false
      end
      results = output.rpartition('PLAY RECAP ********************************************************************').last
      results = results.split("\r\n")
      results.shift
      results.detect { |x| !x.include?("unreachable=0") || !x.include?("failed=0") }.blank?
    end

    def agent_pid
      ar_method do
        @object.customizations[:agent][:agent_pid] if @object.customizations[:agent]
      end
    end

    def agent_socket
      ar_method do
        @object.customizations[:agent][:agent_socket] if @object.customizations[:agent]
      end
    end

    def ansible_pid
      ar_method do
        @object.customizations[:agent][:ansible_pid] if @object.customizations[:agent]
      end
    end
  end
end
