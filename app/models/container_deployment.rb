class ContainerDeployment < ApplicationRecord
  has_many :container_deployment_authentications
  belongs_to :deployed_ext_management_system, :class_name => 'ExtManagementSystem'
  belongs_to :deployed_on_ext_management_system, :class_name => 'ExtManagementSystem'
  belongs_to :miq_request_task
  has_many :container_deployment_nodes

  DEPLOYMENT_TYPES = ['OpenShift Origin', 'OpenShift Enterprise', 'Atomic Enterprise'].freeze

end
