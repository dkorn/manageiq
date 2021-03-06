FactoryGirl.define do
  factory :miq_dialog do
    sequence(:name)        { |n| "miq_dialog_#{n}" }
    sequence(:description) { |n| "MiqDialog #{n}" }
    content                { {:dialogs => {}} }
  end

  factory :miq_dialog_provision, :parent => :miq_dialog do
    name        "miq_provision_dialogs"
    dialog_type "MiqProvisionWorkflow"

    content do
      {
        :dialogs => {
          :customize => {
            :description => "Customize",
            :fields      => {
              :root_password => {
                :description => "Root Password",
                :required    => false,
                :display     => :edit,
                :data_type   => :string
              }
            }
          }
        }
      }
    end
  end

  factory :miq_dialog_host_provision, :parent => :miq_dialog do
    name        "miq_host_provision_dialogs"
    dialog_type "MiqHostProvisionWorkflow"
  end
end
