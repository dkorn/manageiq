class ContainerDeploymentAuthentication < ApplicationRecord
  belongs_to :container_deployment
  serialize :htpassd_users
  serialize :open_id_extra_authorize_parameters
end
