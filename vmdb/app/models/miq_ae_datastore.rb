module MiqAeDatastore
  XML_VERSION = "1.0"
  XML_VERSION_MIN_SUPPORTED = "1.0"
  MANAGEIQ_DOMAIN = "ManageIQ"
  MANAGEIQ_PRIORITY = 0
  DATASTORE_DIRECTORY = Rails.root.join('db/fixtures/ae_datastore')
  DEFAULT_OBJECT_NAMESPACE = "$"
  TEMP_DOMAIN_PREFIX = "TEMP_DOMAIN"
  ALL_DOMAINS = "*"
  PRESERVED_ATTRS = [:priority, :enabled, :system]

  # deprecated module
  module Import
    def self.load_xml(xml, domain = MiqAeDatastore.temp_domain)
      MiqAeDatastore.xml_deprecated_warning
      XmlImport.load_xml(xml, domain)
    end
  end

  TMP_DIR = File.expand_path(File.join(Rails.root, "tmp/miq_automate_engine"))

  def self.temp_domain
    "#{TEMP_DOMAIN_PREFIX}-#{MiqUUID.new_guid}"
  end

  def self.xml_deprecated_warning
    msg = "[DEPRECATION] xml export/import is deprecated. Please use the YAML format instead.  At #{caller[1]}"
    $log.warn msg
    warn msg
  end

  def self.default_backup_filename
    "datastore_#{format_timezone(Time.now, Time.zone, "fname")}.zip"
  end

  def self.backup(options)
    options['zip_file'] ||= default_backup_filename
    export_options = options.slice('zip_file', 'overwrite')
    MiqAeExport.new(ALL_DOMAINS, export_options).export
  end

  def self.convert(filename, domain_name = temp_domain, export_options = {})
    if export_options['zip_file'].blank? && export_options['export_dir'].blank? && export_options['yaml_file'].blank?
      export_options['export_dir'] = TMP_DIR
    end

    File.open(filename, 'r') do |handle|
      XmlYamlConverter.convert(handle, domain_name, export_options)
    end
  end

  def self.upload(fd, name = nil, domain_name = ALL_DOMAINS)
    name     ||= fd.original_filename
    ext        = File.extname(name)
    basename   = File.basename(name, ext)
    name       = "#{basename}.zip"
    block_size = 65_536
    FileUtils.mkdir_p(TMP_DIR) unless File.directory?(TMP_DIR)
    filename = File.join(TMP_DIR, name)

    $log.info("MIQ(MiqAeDatastore) Uploading Datastore Import to file <#{filename}>") if $log

    outfd = File.open(filename, "wb")
    data  = fd.read(block_size)
    until fd.eof
      outfd.write(data)
      data = fd.read(block_size)
    end
    outfd.write(data) if data
    fd.close
    outfd.close

    $log.info("MIQ(MiqAeDatastore) Upload complete (size=#{File.size(filename)})") if $log

    begin
      import_yaml_zip(filename, domain_name)
    ensure
      File.delete(filename)
    end
  end

  def self.import(fname, domain = temp_domain)
    _, t = Benchmark.realtime_block(:total_time) { XmlImport.load_file(fname, domain) }
    $log.info("MIQ(MiqAeDatastore.import) Import #{fname}...Complete - Benchmark: #{t.inspect}")
  end

  def self.restore(fname)
    $log.info("MIQ(MiqAeDatastore.restore) Restore from #{fname}...Starting")
    MiqAeDatastore.reset
    MiqAeImport.new(ALL_DOMAINS, 'zip_file' => fname, 'preview' => false, 'restore' => true).import
    $log.info("MIQ(MiqAeDatastore.restore) Restore from #{fname}...Complete")
  end

  def self.import_yaml_zip(fname, domain)
    t = Benchmark.realtime_block(:total_time) do
      import_options = {'zip_file' => fname, 'preview' => false, 'mode' => 'add'}
      MiqAeImport.new(domain, import_options).import
    end
    $log.info("MIQ(MiqAeDatastore.import) Import #{fname}...Complete - Benchmark: #{t.inspect}")
  end

  def self.import_yaml_dir(dirname, domain)
    t = Benchmark.realtime_block(:total_time) do
      import_options = {'import_dir' => dirname, 'preview' => false, 'mode' => 'add', 'restore' => true}
      MiqAeImport.new(domain, import_options).import
    end
    $log.info("MIQ(MiqAeDatastore.import) Import from #{dirname}...Complete - Benchmark: #{t.inspect}")
  end

  def self.export
    require 'tempfile'
    temp_export = Tempfile.new('ae_export')
    MiqAeDatastore.backup('zip_file' => temp_export.path, 'overwrite' => true)
    File.read(temp_export.path)
  ensure
    temp_export.close
    temp_export.unlink
  end

  def self.export_class(ns, class_name)
    XmlExport.class_to_xml(ns, class_name)
  end

  def self.export_namespace(ns)
    XmlExport.namespace_to_xml(ns)
  end

  def self.reset
    $log.info("MIQ(MiqAeDatastore) Clearing datastore") if $log
    [MiqAeClass, MiqAeField, MiqAeInstance, MiqAeNamespace, MiqAeMethod, MiqAeValue].each(&:delete_all)
  end

  def self.reset_default_namespace
    ns = MiqAeNamespace.find_by_fqname(DEFAULT_OBJECT_NAMESPACE)
    ns.destroy if ns
    seed_default_namespace
  end

  def self.reset_domain(datastore_dir, domain_name)
    $log.info("MIQ(MiqAeDatastore) Resetting domain #{domain_name} from #{datastore_dir}") if $log
    ns = MiqAeDomain.find_by_fqname(domain_name)
    ns.destroy if ns
    import_yaml_dir(datastore_dir, domain_name)
    if domain_name.downcase == MANAGEIQ_DOMAIN.downcase
      ns = MiqAeDomain.find_by_fqname(MANAGEIQ_DOMAIN)
      ns.update_attributes!(:system => true, :enabled => true, :priority => MANAGEIQ_PRIORITY) if ns
    end
  end

  def self.reset_manageiq_domain
    reset_domain(DATASTORE_DIRECTORY, MANAGEIQ_DOMAIN)
  end

  def self.seed_default_namespace
    default_ns   = MiqAeNamespace.create!(:name => DEFAULT_OBJECT_NAMESPACE)
    object_class = default_ns.ae_classes.create!(:name => 'Object')

    default_method_options = {:language => 'ruby', :scope => 'instance', :location => 'builtin'}
    object_class.ae_methods.create!(default_method_options.merge(:name => 'log_object'))
    object_class.ae_methods.create!(default_method_options.merge(:name => 'log_workspace'))

    email_method = object_class.ae_methods.create!(default_method_options.merge(:name => 'send_email'))
    email_method.inputs.build([{:name => 'to',      :priority => 1, :datatype => 'string'},
                               {:name => 'from',    :priority => 2, :datatype => 'string'},
                               {:name => 'subject', :priority => 3, :datatype => 'string'},
                               {:name => 'body',    :priority => 4, :datatype => 'string'}])
    email_method.save!
  end

  def self.reset_to_defaults
    raise "Datastore directory [#{DATASTORE_DIRECTORY}] not found" unless Dir.exist?(DATASTORE_DIRECTORY)
    saved_attrs = preserved_attrs_for_domains
    Dir.glob(DATASTORE_DIRECTORY.join("*", MiqAeDomain::DOMAIN_YAML_FILENAME)).each do |domain_file|
      domain_name = File.basename(File.dirname(domain_file))
      reset_domain(DATASTORE_DIRECTORY, domain_name)
    end

    restore_attrs_for_domains(saved_attrs)
    reset_default_namespace
  end

  def self.seed
    MiqRegion.my_region.lock(:shared, 1800) do
      log_prefix = 'MIQ(MiqAeDatastore.seed)'
      ns = MiqAeDomain.find_by_fqname(MANAGEIQ_DOMAIN)
      unless ns
        $log.info "#{log_prefix} Seeding ManageIQ domain..." if $log
        begin
          reset_to_defaults
        rescue => err
          $log.error "#{log_prefix} Seeding... Reset failed, #{err.message}" if $log
        else
          $log.info "#{log_prefix} Seeding... Complete" if $log
        end
      end
    end
  end

  def self.get_homonymic_across_domains(arclass, fqname, enabled = nil)
    return [] if fqname.blank?
    options = arclass == ::MiqAeClass ? {:has_instance_name => false} : {}
    _, ns, klass, name = ::MiqAeEngine::MiqAePath.get_domain_ns_klass_inst(fqname, options)
    name = klass if arclass == ::MiqAeClass
    MiqAeDatastore.get_sorted_matching_objects(arclass, ns, klass, name, enabled)
  end

  def self.get_sorted_matching_objects(arclass, ns, klass, name, enabled)
    options = arclass == ::MiqAeClass ? {:has_instance_name => false} : {}
    matches = arclass.where("lower(name) = ?", name.downcase).collect do |obj|
      get_domain_priority_object(obj, klass, ns, enabled, options)
    end.compact
    matches.sort { |a, b| b[:priority] <=> a[:priority] }.collect { |v| v[:obj] }
  end

  def self.get_domain_priority_object(obj, klass, ns, enabled, options)
    domain, nsd, klass_name, _ = ::MiqAeEngine::MiqAePath.get_domain_ns_klass_inst(obj.fqname, options)
    return if !klass_name.casecmp(klass).zero? || !nsd.casecmp(ns).zero?
    domain_obj = get_domain_object(domain, enabled)
    {:obj => obj, :priority => domain_obj.priority} if domain_obj
  end

  def self.get_domain_object(name, enabled)
    arel = MiqAeDomain.where("lower(name) = ?", name.downcase)
    arel = arel.where(:enabled => enabled) unless enabled.nil?
    arel.first
  end

  def self.preserved_attrs_for_domains
    MiqAeDomain.all.each_with_object({}) do |dom, h|
      next if dom.name.downcase == MANAGEIQ_DOMAIN.downcase
      h[dom.name] = PRESERVED_ATTRS.each_with_object({}) { |attr, ih| ih[attr] = dom[attr] }
    end
  end

  def self.restore_attrs_for_domains(hash)
    hash.each { |dom, attrs| MiqAeDomain.find_by_fqname(dom, false).update_attributes(attrs) }
  end

  def self.path_includes_domain?(path, options = {})
    nsd, _, _ = ::MiqAeEngine::MiqAePath.split(path, options)
    MiqAeNamespace.find_by_fqname(nsd, false) != nil
  end
end # module MiqAeDatastore
