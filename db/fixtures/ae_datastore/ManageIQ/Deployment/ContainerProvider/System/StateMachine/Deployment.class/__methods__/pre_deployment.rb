LOCAL_BOOK = 'local_book.yaml'.freeze
REPO_URL   = "https://copr.fedorainfracloud.org/coprs/maxamillion/origin-next/repo/epel-7/maxamillion-origin-next-epel-7.repo".freeze

def create_puddle_repo
  File.open("temp.repo", "w") do |f|
    f.write("[temp]\nname=alontemp\nbaseurl=http://download.lab.bos.redhat.com/rcm-guest/puddles/RHAOS/AtomicOpenShift/3.2/2016-08-04.1/x86_64/os\nenabled=1\ngpgcheck=0")
  end
  $evm.root['container_deployment'].perform_scp($evm.root['deployment_master'], $evm.get_state_var(:ssh_user), "temp.repo", "temp.repo")
  $evm.root['container_deployment'].perform_agent_commands($evm.root['deployment_master'], $evm.get_state_var(:ssh_user), ["sudo mv ~/temp.repo /etc/yum.repos.d/temp.repo"])
end

def pre_deployment(user, deployment_master, deployment)
  $evm.log(:info, "********************** #{$evm.root['ae_state']} ***************************")
  deployment.perform_scp(deployment_master, user, "inventory.yaml", "inventory.yaml")
  release = deployment.perform_agent_commands(deployment_master, user, ["sudo cat /etc/redhat-release"])[:stdout]
  commands = ['sudo yum install -y ansible-1.9.4',
              'sudo yum install -y openshift-ansible openshift-ansible-playbooks pyOpenSSL',
              "sudo mv ~/inventory.yaml /usr/share/ansible/openshift-ansible/",
              "sudo yum install -y atomic-openshift-utils"]
  if release.include?("CentOS")
    commands.unshift("sudo yum install epel-release -y",
                     "sudo curl -o /etc/yum.repos.d/maxamillion-origin-next-epel-7.repo #{REPO_URL}",
                     "sudo yum install centos-release-paas-common centos-release-openshift-origin -y")
  elsif release.include?("Red Hat Enterprise Linux")
    deployment.subscribe_deployment_master(deployment_master, user)
    create_puddle_repo
  end
  deployment.perform_agent_commands(deployment_master, user, commands)
  if release.include?("Red Hat Enterprise Linux") && deployment.nodes_subscription_needed?
    deployment.perform_scp(deployment_master, user, "rhel_subscribe_inventory.yaml", "rhel_subscribe_inventory.yaml")
    deployment.subscribe_cluster(deployment_master, user)
    $evm.root['ae_result']         = 'retry'
    $evm.root['ae_retry_interval'] = '1.minute'
  else
    $evm.root['ae_result']               = "ok"
    $evm.root['automation_task'].message = "#{$evm.root['ae_state']} was finished successfully"
  end
end

begin
  $evm.root['container_deployment'] = $evm.vmdb(:container_deployment).find(
    $evm.root['automation_task'].automation_request.options[:attrs][:deployment_id]) unless $evm.root['container_deployment']
  user = $evm.get_state_var(:ssh_user)
  deployment_master = $evm.root['deployment_master']
  deployment = $evm.root['container_deployment']
  if deployment.playbook_running?
    result = deployment.subscribe_cluster(deployment_master, user)
    if result[:finished]
      $evm.root['ae_result'] = deployment.analyze_ansible_output(result[:stdout]) ? "ok" : "error"
    else
      $evm.log(:info, "*********  pre-deployment playbook is runing waiting for it to finish ************")
      $evm.root['ae_result']         = 'retry'
      $evm.root['ae_retry_interval'] = '1.minute'
    end
  else
    pre_deployment(user, deployment_master, deployment)
  end
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
