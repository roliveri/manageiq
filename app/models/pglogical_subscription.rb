# This model wraps a pglogical stored proc (pglogical.show_subscription_status)
# This is exposed to us through the PostgreSQLAdapter#pglogical object's #subscriptions method
# This model then exposes select values returned from that method
class PglogicalSubscription < ActsAsArModel
  set_columns_hash(
    :id              => :string,
    :status          => :string,
    :dbname          => :string,
    :host            => :string,
    :user            => :string,
    :password        => :string,
    :port            => :integer,
    :provider_region => :integer
  )

  def self.find(*args)
    subs = pglogical.enabled? ? pglogical.subscriptions : []
    case args.first
    when :all then subs.collect { |s| new(subscription_to_columns(s)) }
    when :first, :last then subs.presence && new(subscription_to_columns(subs.send(args.first)))
    end
  end

  def save!
    raise "Cannot update an existing subscription" if id
    create_node.check if !pglogical.enabled? || self.class.count == 0
    id = "subscription_#{host.gsub(/\.|-/, "_")}"
    pglogical.subscription_create(id, dsn, ['miq'], false).check
  end

  def save
    save!
    true
  rescue
    false
  end

  def delete
    pglogical.subscription_drop(id, true)
    MiqRegion.destroy_region(connection, provider_region)
    pglogical.node_drop(node_name, true) if self.class.count == 0
  end

  def self.delete_all
    find(:all).each(&:delete)
  end

  def disable
    pglogical.subscription_disable(id).check
  end

  def enable
    pglogical.subscription_enable(id).check
  end

  def self.pglogical(refresh = false)
    @pglogical = nil if refresh
    @pglogical ||= connection.pglogical
  end

  def pglogical(refresh = false)
    self.class.pglogical(refresh)
  end

  # translate the output from the pglogical stored proc to our object columns
  def self.subscription_to_columns(sub)
    cols = sub.symbolize_keys

    # delete the things we dont care about
    cols.delete(:slot_name)
    cols.delete(:replication_sets)
    cols.delete(:forward_origins)

    cols[:id] = cols.delete(:subscription_name)

    # create the individual dsn columns
    cols.merge!(dsn_attributes(cols.delete(:provider_dsn)))

    cols[:provider_region] = cols.delete(:provider_node).sub("region_", "").to_i
    cols
  end
  private_class_method :subscription_to_columns

  def self.dsn_attributes(dsn)
    attrs = connection.class.parse_dsn(dsn)
    attrs.delete(:password)
    port = attrs.delete(:port)
    attrs[:port] = port.to_i unless port.blank?
    attrs
  end
  private_class_method :dsn_attributes

  private

  def node_name
    "region_#{MiqRegion.my_region_number}"
  end

  def create_node
    pglogical.enable

    node_dsn = PG::Connection.parse_connect_args(connection.raw_connection.conninfo_hash.delete_blanks)
    pglogical.node_create(node_name, node_dsn)
  end

  def dsn
    conf = {
      :dbname   => dbname,
      :host     => host,
      :user     => user,
      :password => MiqPassword.try_decrypt(password),
      :port     => port
    }.delete_blanks
    PG::Connection.parse_connect_args(conf)
  end
end