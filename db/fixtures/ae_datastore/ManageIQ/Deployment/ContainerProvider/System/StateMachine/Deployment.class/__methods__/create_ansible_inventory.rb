INVENTORY_FILE = 'inventory.yaml'.freeze
RHEL_SUBSCRIBE_INVENTORY = 'rhel_subscribe_inventory.yaml'.freeze

def create_ansible_inventory_file(subscribe = false)
  if subscribe
    template = $evm.root['rhel_subscribe_inventory']
    inv_file_path = RHEL_SUBSCRIBE_INVENTORY
  else
    $evm.log(:info, "********************** #{$evm.root['ae_state']} ***************************")
    template = $evm.root['inventory']
    inv_file_path = INVENTORY_FILE
  end
  $evm.log(:info, "creating #{inv_file_path}")
  File.open(inv_file_path, 'w') do |f|
    f.write(template)
  end
  $evm.root['ae_result'] = "ok"
  $evm.root['automation_task'].message = "successfully created #{inv_file_path}"
end

begin
  $evm.root['inventory'] = $evm.root['container_deployment'].regenerate_ansible_inventory
  $evm.root['rhel_subscribe_inventory'] = $evm.root['container_deployment'].regenerate_ansible_subscription_inventory
  create_ansible_inventory_file
  release = $evm.root['container_deployment'].perform_agent_commands($evm.root['deployment_master'], $evm.get_state_var(:ssh_user), ["sudo cat /etc/redhat-release"])[:stdout]
  create_ansible_inventory_file(true) if release.include?("Red Hat Enterprise Linux")
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
$evm.log(:info, "State: #{$evm.root['ae_state']} | Result: #{$evm.root['ae_result']} "\
         "| Message: #{$evm.root['automation_task'].message}")
