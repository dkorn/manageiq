class ContainerDeploymentNode < ApplicationRecord
  belongs_to :vm
  belongs_to :container_deployment
  serialize :labels, Hash
  serialize :customizations, Hash
  acts_as_miq_taggable

  def node_address
    if vm
      vm.hostnames.last || vm.hardware.ipaddresses.last
    elsif address
      address
    end
  end

  def roles
    tags.reset
    roles = tags.collect { |tag| tag.name.gsub("/user/", "").gsub("deployment_master", "master") }.uniq
    roles
  end

  def to_ansible_config_format
    {
      "connect_to" => node_address,
      "roles"      => roles
    }
  end
end
