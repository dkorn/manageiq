DEPLOYMENT_TYPES = {
  :origin               => "ManageIQ::Providers::Openshift::ContainerManager",
  :openshift_enterprise => "ManageIQ::Providers::OpenshiftEnterprise::ContainerManager",
}. freeze

def provider_token
  $evm.root['container_deployment'].perform_agent_commands($evm.root['deployment_master'], $evm.get_state_var(:ssh_user), ["sudo oc sa get-token management-admin -n management-infra"])[:stdout]
end

def add_provider
  $evm.log(:info, "**************** #{$evm.root['ae_state']} ****************")
  token = provider_token
  new_provider = $evm.root['container_deployment'].add_deployment_provider(
    :provider_type      => DEPLOYMENT_TYPES[$evm.root['deployment_type'].tr("-", "_").to_sym],
    :provider_name      => $evm.get_state_var(:provider_name),
    :provider_port      => "8443",
    :provider_hostname  => $evm.root['container_deployment'].perform_agent_commands($evm.root['deployment_master'], $evm.get_state_var(:ssh_user), ["sudo hostname --fqdn"])[:stdout].gsub("\r\n", ''),
    :provider_ipaddress => $evm.root['deployment_master'],
    :auth_type          => "bearer",
    :auth_key           => token)
  if new_provider
    $evm.root['ae_result'] = "ok"
    $evm.root['automation_task'].message = "successfully added #{$evm.get_state_var(:provider_name)} as a container provider"
  else
    $evm.root['ae_result'] = "error"
    $evm.root['automation_task'].message = "failed to add #{$evm.get_state_var(:provider_name)} as a container provider"
  end
  $evm.log(:info, "State: #{$evm.root['ae_state']} | Result: #{$evm.root['ae_result']} "\
           "| Message: #{$evm.root['automation_task'].message}")
end

begin
  add_provider
rescue => err
  $evm.log(:error, "[#{err}]\n#{err.backtrace.join("\n")}")
  $evm.root['ae_result'] = 'error'
  $evm.root['ae_reason'] = "Error: #{err.message}"
  exit MIQ_ERROR
end
