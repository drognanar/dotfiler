# Allows to discover backups instances under a given machine.
require 'setup/io'
require 'setup/sync_task'
require 'setup/sync_task.platforms'

require 'pathname'
require 'yaml'
require 'yaml/store'

module Setup

# A single backup directory present on a local computer.
# It contains a config.yml file which defines the tasks that should be run for the backup operations.
# Enabled task names contains the list of tasks to be run.
# Disabled task names contains the list of tasks that should be skipped.
# New tasks are tasks for which there are any files to sync but are not part of any lists.
class Backup
  attr_accessor :enabled_task_names, :disabled_task_names, :tasks, :backup_path
  DEFAULT_BACKUP_ROOT = File.expand_path '~/dotfiles'
  DEFAULT_BACKUP_DIR = File.join DEFAULT_BACKUP_ROOT, 'local'
  DEFAULT_BACKUP_CONFIG_PATH = 'config.yml'
  BACKUP_TASKS_PATH = '_tasks'
  APPLICATIONS_DIR = Pathname(__FILE__).dirname().parent.parent.join('applications').to_s

  def initialize(backup_path, host_info, io, store_factory)
    host_info = host_info.merge backup_root: backup_path
    @backup_path = backup_path
    @host_info = host_info
    @io = io
    @store_factory = store_factory

    @tasks = {}
    @enabled_task_names = Set.new
    @disabled_task_names = Set.new
  end

  # Loads the configuration and the tasks.
  def load
    @io.mkdir_p @backup_path unless @io.exist? @backup_path

    backup_tasks_path = Pathname(@backup_path).join(BACKUP_TASKS_PATH)
    backup_tasks = get_backup_tasks backup_tasks_path, @host_info, @io
    app_tasks = get_backup_tasks Pathname(APPLICATIONS_DIR), @host_info, @io
    @tasks = app_tasks.merge(backup_tasks)

    backup_config_path = Pathname(backup_path).join(DEFAULT_BACKUP_CONFIG_PATH)
    @store = @store_factory.new backup_config_path
    @store.transaction(true) do |store|
      @enabled_task_names = Set.new(store.fetch('enabled_task_names', []))
      @disabled_task_names = Set.new(store.fetch('disabled_task_names', []))
    end
    self
  end

  def enable_tasks(task_names)
    task_names_set = Set.new(task_names.map(&:downcase)).intersection Set.new(tasks.keys.map(&:downcase))
    @enabled_task_names += task_names_set
    @disabled_task_names -= task_names_set
    save_config if not task_names_set.empty?
  end

  def disable_tasks(task_names)
    task_names_set = Set.new(task_names.map(&:downcase)).intersection Set.new(tasks.keys.map(&:downcase))
    @enabled_task_names -= task_names_set
    @disabled_task_names += task_names_set
    save_config if not task_names_set.empty?
  end

  # Finds newly added tasks that can be run on this machine.
  # These tasks have not been yet added to the config file's enabled_task_names or disabled_task_names properties.
  def new_tasks
    @tasks.select { |task_name, task| not is_enabled(task_name) and not is_disabled(task_name) and task.should_execute and task.has_data }
  end

  # Finds tasks that should be run under a given machine.
  # This will include tasks that contain errors and do not have data.
  def tasks_to_run
    @tasks.select { |task_name, task| is_enabled(task_name) and task.should_execute }
  end

  def save_config
    @store.transaction do |s|
      s['enabled_task_names'] = @enabled_task_names.to_a
      s['disabled_task_names'] = @disabled_task_names.to_a
    end
  end

  def Backup.resolve_backup(backup_str, options)
    sep = backup_str.index ':'
    backup_dir = options[:backup_dir] || DEFAULT_BACKUP_ROOT
    # TODO: handle local git folders?
    if not sep.nil?
      [File.expand_path(backup_str[0..sep-1]), backup_str[sep+1..-1]]
    elsif is_path(backup_str)
      [File.expand_path(backup_str), nil]
    else
      [File.expand_path(File.join(backup_dir, backup_str)), backup_str]
    end
  end

  private

  # Constructs a backup task given a task yaml configuration.
  def get_backup_task(task_pathname, host_info, io)
    config = YAML.load(io.read(task_pathname))
    SyncTask.new(config, host_info, io) if config
  end

  # Constructs backup tasks that can be found a task folder.
  def get_backup_tasks(tasks_pathname, host_info, io)
    return {} if not io.exist? tasks_pathname
    (io.entries tasks_pathname)
      .map { |task_path| Pathname(task_path) }
      .select { |task_pathname| task_pathname.extname == '.yml' }
      .map { |task_pathname| [File.basename(task_pathname, '.*'), get_backup_task(tasks_pathname.join(task_pathname), host_info, io)] }
      .select { |task_name, task| not task.nil? }
      .to_h
  end

  def is_enabled(task_name)
    @enabled_task_names.any? { |enabled_task_name| enabled_task_name.casecmp(task_name) == 0 }
  end

  def is_disabled(task_name)
    @disabled_task_names.any? { |disabled_task_name| disabled_task_name.casecmp(task_name) == 0 }
  end

  def Backup.is_path(path)
    path.start_with?('..') || path.start_with?('.') || path.start_with?('~') || Pathname.new(path).absolute?
  end
end

class BackupManager
  attr_accessor :backups
  DEFAULT_CONFIG_PATH = File.expand_path '~/setup.yml'
  DEFAULT_RESTORE_ROOT = File.expand_path '~/'

  def initialize(options = {})
    @host_info = options[:host_info] || get_host_info
    @io = options[:io]
    @store_factory = options[:store_factory] || YAML::Store
    @config_path = (options[:config_path] || DEFAULT_CONFIG_PATH)
    @backup_paths = []
  end

  # Loads backup manager configuration and backups it references.
  def load
    @store = @store_factory.new(@config_path)
    @backup_paths = @store.transaction(true) { |store| store.fetch('backups', []) }
    self
  end

  # Gets backups found on a given machine.
  def get_backups
    @backup_paths.map { |backup_path| Backup.new(backup_path, @host_info, @io, @store_factory).load }
  end

  # Creates a new backup and registers it in the global yaml configuration.
  def create_backup(resolved_backup)
    backup_dir, source_url = resolved_backup

    if @backup_paths.include? backup_dir
      puts "Backup \"#{backup_dir}\" already exists."
      return
    end

    backup_exists = @io.exist?(backup_dir)
    if backup_exists and not @io.entries(backup_dir).empty?
      puts "Cannot create backup. The folder #{backup_dir} already exists and is not empty."
      return
    end

    @io.mkdir_p backup_dir if not backup_exists
    @io.shell "git clone \"#{source_url}\" -o \"#{backup_dir}\"" if source_url
    @backup_paths = @backup_paths << backup_dir
    @store.transaction { |store| store['backups'] = @backup_paths }
  end

  private

  # Gets the host info of the current machine.
  def get_host_info
    {label: Config.machine_labels, restore_root: DEFAULT_RESTORE_ROOT, sync_time: Time.new}
  end
end

end # module Setup
