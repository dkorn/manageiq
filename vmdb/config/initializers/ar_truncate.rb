begin
  ActiveRecord::ConnectionAdapters::PostgreSQLAdapter.instance_method(:truncate)
  puts "Rails is new enough to have truncate, please remove this: #{__FILE__}"
rescue NameError
  class ActiveRecord::ConnectionAdapters::PostgreSQLAdapter
    def truncate(table_name, name = nil)
      execute("TRUNCATE TABLE #{quote_table_name(table_name)}", name)
    end
  end
end
