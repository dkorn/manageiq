INVENTORY_FILE = 'inventory.yaml'.freeze
RHEL_SUBSCRIBE_INVENTORY = 'rhel_subscribe_inventory.yaml'.freeze

def find_vm_by_tag(tag)
  tag = "/managed/miq_openshift_deploy/#{tag}_#{$evm.root['automation_task'][:id]}"
  $evm.vmdb(:vm).find_tagged_with(:any => tag, :ns => "*")
end

def cleanup
  $evm.log(:info, "********************** Cleanup ***************************")
  if File.exist?(INVENTORY_FILE)
    $evm.log(:info, "deleting #{INVENTORY_FILE}")
    system "rm #{INVENTORY_FILE}"
  end
  if File.exist?(RHEL_SUBSCRIBE_INVENTORY)
    $evm.log(:info, "deleting #{RHEL_SUBSCRIBE_INVENTORY}")
    system "rm #{RHEL_SUBSCRIBE_INVENTORY}"
  end
  $evm.log(:info, $evm.root['ae_result'])
  $evm.log(:info, $evm.root['deployment_method'])

  if $evm.root['ae_result'].include?("error") && $evm.root['deployment_method'] == "provision"
    (find_vm_by_tag("node") + find_vm_by_tag("master")).each do |vm|
      $evm.log('info', "Removing VM:<#{vm.name}>")
      vm.remove_from_disk(false)
    end
  end
  $evm.root['ae_result'] = "ok"
  $evm.root['automation_task'].message = "successful deployment cleanup"
  $evm.log(:info, "State: #{$evm.root['ae_state']} | Result: #{$evm.root['ae_result']} "\
           "| Message: #{$evm.root['automation_task'].message}")
end

begin
  cleanup
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
