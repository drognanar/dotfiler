module Dotfiler
  # Mapping of status kinds to their string represenations.
  # @return [Hash<Symbol, String>]
  STATUS_KINDS = {
    no_sources: 'no sources to synchronize',
    up_to_date: 'up to date',
    backup: 'needs sync',
    sync: 'needs sync',
    restore: 'needs sync',
    resync: 'needs sync',
    overwrite_data: 'differs'
  }.freeze

  # Current synchronization status of a {Tasks::Task}.
  class SyncStatus
    attr_reader :name, :kind, :status_msg

    def initialize(name, kind, status_msg = nil)
      @name = name
      @kind = kind
      @status_msg = status_msg
    end

    def status_str
      kind_str = STATUS_KINDS[kind]
      status_msg.nil? ? "#{name}: #{kind_str}" : "#{name}: #{kind_str}: #{status_msg}"
    end

    def items
      []
    end
  end

  # Current synchronization status of a {Tasks::Package}.
  class GroupStatus
    attr_reader :name, :items, :status_msg

    def initialize(name, items, status_msg = nil)
      @name = name
      @items = items
      @status_msg = status_msg
    end

    def kind
      items.map(&:kind).uniq.length == 1 ? items[0].kind : nil
    end

    def status_str
      return "#{name}:" if !name.nil? && !name.empty?
    end
  end
end
