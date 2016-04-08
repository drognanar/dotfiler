# This tests the overall appliction integration test.
require 'setup/cli'
require 'setup/io'

require 'tmpdir'

module Setup

$thor_runner = false
$0 = "setup"
ARGV.clear

RSpec.shared_examples 'CLIHelper' do |cli|
  let(:cli) { cli }
  let(:backup_manager) { instance_double(Setup::BackupManager) }

  describe '#get_io' do
    it { expect(cli.get_io({})).to eq(CONCRETE_IO) }
    it { expect(cli.get_io dry: true).to eq(DRY_IO) }
  end

  def get_backup_manager(options = {})
    expect(backup_manager).to receive(:load_backups!)
    actual_manager = nil
    cli.with_backup_manager(options) { |backup_manager| actual_manager = backup_manager }
    actual_manager
  end

  describe '#with_backup_manager' do
    it 'creates backup manager with default parameters when no options given' do
      expect(Setup::BackupManager).to receive(:from_config).with(io: CONCRETE_IO, dry: false).and_return backup_manager
      expect(get_backup_manager).to eq(backup_manager)
    end

    it 'creates backup manager with passed in options' do
      expect(Setup::BackupManager).to receive(:from_config).with(io: DRY_IO, dry: true).and_return backup_manager
      expect(get_backup_manager({ dry: true })).to eq(backup_manager)
    end
  end
end

RSpec.describe Cli::PackageCLI do
  include_examples 'CLIHelper', Cli::PackageCLI.new
end

RSpec.describe Cli::SetupCLI do
  include_examples 'CLIHelper', Cli::SetupCLI.new
end

# Integration tests.
RSpec.describe './setup' do
  let(:cmd)    { instance_double(HighLine) }

  def setup(args)
    Cli::SetupCLI.start args
  end

  # Asserts that a file exists with the specified content.
  def assert_file_content(path, content)
    expect(File.exist? path).to be true
    expect(File.read path).to eq(content)
  end

  # Asserts that a yaml file exists with the specified dictionary.
  def assert_yaml_content(path, yaml_hash)
    expect(File.exist? path).to be true
    expect(YAML::load File.read(path)).to eq(yaml_hash)
  end

  # Saves a file with the specified content.
  def save_file_content(path, content)
    FileUtils.mkdir_p File.dirname path
    File.write path, content
  end

  # Saves a yaml dictionary under path.
  def save_yaml_content(path, yaml_hash)
    save_file_content path, YAML::dump(yaml_hash)
  end

  # Creates a symlink between files.
  def link_files(path, link_path)
    File.link path, link_path
  end

  # Asserts that the two files have the same content.
  def assert_copies(backup_path: nil, restore_path: nil, content: nil)
    expect(File.identical? backup_path, restore_path).to be false
    expect(File.read backup_path).to eq(File.read restore_path)
    expect(File.read backup_path).to eq(content) unless content.nil?
  end

  # Asserts that the two files are symlinks.
  def assert_symlinks(backup_path: nil, restore_path: nil, content: nil)
    expect(File.identical? backup_path, restore_path).to be true
    assert_file_content backup_path, content unless content.nil?
  end

  def assert_ran_unsuccessfully(result)
    expect(result).to be false
    @output_lines = @log_output.readlines
  end

  def assert_ran_without_errors(result)
    expect(result).to be true
    @output_lines = @log_output.readlines
    expect(@output_lines.any? { |line| line.start_with? 'E:'}).to be false
  end
  
  def assert_ran_with_errors(result)
    expect(result).to be true
    @output_lines = @log_output.readlines
    expect(@output_lines.any? { |line| line.start_with? 'E:'}).to be true
  end

  def get_backup_path(path)
    File.join @dotfiles_dir, path
  end

  def get_restore_path(path)
    File.join @tmpdir, 'machine', path
  end

  # Create a temporary folder where the test should sync data data.
  around(:each) do |example|
    Dir.mktmpdir do |tmpdir|
      @tmpdir = tmpdir
      example.call
    end
  end

  # Override app constants to redirect the sync to temp folders.
  before(:each) do
    @applications_dir      = File.join(@tmpdir, 'apps')
    @default_config_root   = File.join(@tmpdir, 'setup.yml')
    @default_restore_root  = File.join(@tmpdir, 'machine')
    @default_backup_root   = File.join(@tmpdir, 'dotfiles')
    @default_backup_dir    = File.join(@tmpdir, 'dotfiles/local')
    @default_backup_config = File.join(@tmpdir, 'dotfiles/local/config.yml')

    @dotfiles_dir = File.join(@tmpdir, 'dotfiles/dotfiles1')
    @dotfiles_config = File.join(@dotfiles_dir, 'config.yml')

    stub_const 'Setup::Backup::APPLICATIONS_DIR', @applications_dir
    stub_const 'Setup::BackupManager::DEFAULT_CONFIG_PATH', @default_config_root
    stub_const 'Setup::BackupManager::DEFAULT_RESTORE_ROOT', @default_restore_root
    stub_const 'Setup::Backup::DEFAULT_BACKUP_ROOT', @default_backup_root
    stub_const 'Setup::Backup::DEFAULT_BACKUP_DIR', @default_backup_dir

    # Take over the interactions with console in order to stub out user interaction.
    stub_const 'Setup::Cli::Commandline', cmd

    # Create a basic layout of files on the disk.
    FileUtils.mkdir_p File.join(@tmpdir, 'apps')
    FileUtils.mkdir_p File.join(@tmpdir, 'machine')

    save_yaml_content @default_config_root, 'backups' => [@dotfiles_dir]

    # An app with no files to sync.
    save_yaml_content File.join(@tmpdir, 'apps/app.yml'), 'name' => 'app', 'files' => []

    # An app where the file is only present at the restore location.
    save_yaml_content File.join(@tmpdir, 'apps/vim.yml'), 'name' => 'vim', 'files' => ['.vimrc']
    save_file_content get_restore_path('.vimrc'), '; Vim configuration.'

    # An app where the backup will overwrite files.
    save_yaml_content File.join(@tmpdir, 'apps/code.yml'), 'name' => 'code', 'files' => ['.vscode']
    save_file_content get_backup_path('code/_vscode'), 'some content'
    save_file_content get_restore_path('.vscode'), 'different content'

    # An app where only some files exist on the machine.
    # An app which only contains the file in the backup directory.
    save_yaml_content File.join(@tmpdir, 'apps/bash.yml'), 'name' => 'bash', 'files' => ['.bashrc', '.bash_local']
    save_file_content get_backup_path('bash/_bashrc'), 'bashrc file'

    # An app where no files exist.
    save_yaml_content File.join(@tmpdir, 'apps/git.yml'), 'name' => 'git', 'files' => ['.gitignore', '.gitconfig']

    # An app where the both backup and restore have the same content.
    save_yaml_content File.join(@tmpdir, 'apps/python.yml'), 'name' => 'python', 'files' => ['.pythonrc']
    save_file_content get_backup_path('python/_pythonrc'), 'pythonrc'
    save_file_content get_restore_path('.pythonrc'), 'pythonrc'

    # An app where all files have been completely synced.
    save_yaml_content File.join(@tmpdir, 'apps/rubocop.yml'), 'name' => 'rubocop', 'files' => ['.rubocop']
    save_file_content get_backup_path('rubocop/_rubocop'), 'rubocop'
    link_files get_backup_path('rubocop/_rubocop'), get_restore_path('.rubocop')
  end

  describe '--help' do
    it do
      expect { setup %w[--help] }.to output(
"Commands:
  setup backup                        # Backup your settings
  setup cleanup                       # Cleans up previous backups
  setup help [COMMAND]                # Describe available commands or one specific command
  setup init [<backups>...]           # Initializes backups
  setup package <subcommand> ...ARGS  # Add/remove packages to be backed up
  setup restore                       # Restore your settings
  setup status                        # Returns the sync status

Options:
  [--help], [--no-help]        # Print help for a specific command
  [--verbose], [--no-verbose]  # Print verbose information to stdout

").to_stdout
    end
  end

  describe 'init' do
    # The default test setup includes a default_config_root. Remove it to init from a bare repository.
    before(:each) { File.delete @default_config_root }

    it 'should clone repositories' do
      source_path = 'https://github.com/username/repository'
      backup_path = "#{@default_backup_root}/github.com/username/repository"
      clone_command = "git clone \"#{source_path}\" -o \"#{backup_path}\""
      expect(CONCRETE_IO).to receive(:shell).with(clone_command).and_return true
      assert_ran_without_errors setup %w[init github.com/username/repository --enable_new=all]
    end

    context 'when no options are passed in' do
      it 'should prompt by default' do
        expect(cmd).to receive(:agree).once.and_return true
        assert_ran_without_errors setup %w[init]

        assert_yaml_content @default_config_root, 'backups' => [@default_backup_dir]
        assert_yaml_content @default_backup_config, 'enabled_task_names' => ['code', 'python', 'rubocop', 'vim'], 'disabled_task_names' => []
      end
    end

    context 'when --enable_new=prompt' do
      it 'should create a local backup and enable tasks if user replies y to prompt' do
        expect(cmd).to receive(:agree).once.and_return true
        assert_ran_without_errors setup %w[init --enable_new=prompt]

        assert_yaml_content @default_config_root,'backups' => [@default_backup_dir]
        assert_yaml_content @default_backup_config,'enabled_task_names' => ['code', 'python', 'rubocop', 'vim'], 'disabled_task_names' => []
      end

      it 'should create a local backup and disable tasks if user replies n to prompt' do
        expect(cmd).to receive(:agree).once.and_return false
        assert_ran_without_errors setup %w[init --enable_new=prompt]

        assert_yaml_content @default_config_root,'backups' => [@default_backup_dir]
        assert_yaml_content @default_backup_config,'enabled_task_names' => [], 'disabled_task_names' => ['code', 'python', 'rubocop', 'vim']
      end
    end

    context 'when --enable_new=all' do
      it 'should create a local backup and enable found tasks' do
        save_yaml_content @default_config_root, 'backups' => [@dotfiles_dir]
        assert_ran_without_errors setup %w[init --enable_new=all]

        assert_yaml_content @default_config_root, 'backups' => [@dotfiles_dir, @default_backup_dir]
        assert_yaml_content @default_backup_config, 'enabled_task_names' => ['code', 'python', 'rubocop', 'vim'], 'disabled_task_names' => []
        assert_yaml_content @dotfiles_config, 'enabled_task_names' => ['bash', 'code', 'python', 'rubocop', 'vim'], 'disabled_task_names' => []
      end
    end

    context 'when --enable_new=none' do
      it 'should create a local backup and disable found tasks' do
        assert_ran_without_errors setup %w[init --enable_new=none]

        assert_yaml_content @default_config_root,'backups' => [@default_backup_dir]
        assert_yaml_content @default_backup_config,'enabled_task_names' => [], 'disabled_task_names' => ['code', 'python', 'rubocop', 'vim']
      end
    end

    context 'when --dir=./custom/path' do
      let(:custom_path) { File.join(@tmpdir, 'custom') }

      it 'should not affect default path' do
        assert_ran_without_errors setup ['init', "--dir=#{custom_path}", '--enable_new=all']

        assert_yaml_content @default_config_root, 'backups' => [@default_backup_dir]
      end

      it 'should not affect absolute path' do
        absolute_path = File.join(@tmpdir, 'absolute')
        assert_ran_without_errors setup ['init', "--dir=#{custom_path}", '--enable_new=all', absolute_path]

        assert_yaml_content @default_config_root, 'backups' => [absolute_path]
      end

      it 'should create a backup relative to the new dir' do
        assert_ran_without_errors setup ['init', '--enable_new=all', "--dir=#{custom_path}", "repo;"]

        assert_yaml_content @default_config_root, 'backups' => [File.join(custom_path, 'repo')]
      end
    end
  end

  def assert_files_unchanged
    expect(File.exist? get_backup_path('vim/_vimrc')).to be false
    assert_file_content get_backup_path('code/_vscode'), 'some content'
    assert_file_content get_restore_path('.vscode'), 'different content'
    expect(File.exist? get_restore_path('.bashrc')).to be false
    expect(File.identical? get_restore_path('.pythonrc'), get_backup_path('python/_pythonrc')).to be false
  end

  describe 'backup' do
    it 'should backup' do
      assert_ran_with_errors setup %w[backup --enable_new=all --verbose]

      assert_symlinks restore_path: get_restore_path('.vimrc'), backup_path: get_backup_path('vim/_vimrc')
      assert_symlinks restore_path: get_restore_path('.vscode'), backup_path: get_backup_path('code/_vscode'), content: 'different content'
      expect(File.exist? get_restore_path('.bashrc')).to be false
      assert_symlinks restore_path: get_restore_path('.pythonrc'), backup_path: get_backup_path('python/_pythonrc')
      expect(@output_lines.join).to eq(
"Backing up:
I: Backing up package bash:
I: Backing up .bashrc
E: Cannot backup: missing \"#{get_restore_path('.bashrc')}\"
I: Backing up .bash_local
E: Cannot backup: missing \"#{get_restore_path('.bash_local')}\"
I: Backing up package code:
I: Backing up .vscode
V: Saving a copy of file \"#{get_backup_path('code/_vscode')}\" under \"#{get_backup_path('code')}\"
V: Moving file from \"#{get_restore_path('.vscode')}\" to \"#{get_backup_path('code/_vscode')}\"
V: Symlinking \"#{get_backup_path('code/_vscode')}\" with \"#{get_restore_path('.vscode')}\"
I: Backing up package python:
I: Backing up .pythonrc
V: Symlinking \"#{get_backup_path('python/_pythonrc')}\" with \"#{get_restore_path('.pythonrc')}\"
I: Backing up package rubocop:
I: Backing up .rubocop
I: Backing up package vim:
I: Backing up .vimrc
V: Moving file from \"#{get_restore_path('.vimrc')}\" to \"#{get_backup_path('vim/_vimrc')}\"
V: Symlinking \"#{get_backup_path('vim/_vimrc')}\" with \"#{get_restore_path('.vimrc')}\"
")
    end

    it 'should not backup if the task is disabled' do
      assert_ran_without_errors setup %w[backup --enable_new=none]
      assert_files_unchanged
    end

    context 'when --copy' do
      it 'should generate file copies instead of symlinks' do
        expect(setup %w[backup --enable_new=all --copy]).to be true

        assert_copies restore_path: get_restore_path('.vimrc'), backup_path: get_backup_path('vim/_vimrc')
        assert_copies restore_path: get_restore_path('.vscode'), backup_path: get_backup_path('code/_vscode'), content: 'different content'
        expect(File.exist? get_restore_path('.bashrc')).to be false
        assert_copies restore_path: get_restore_path('.pythonrc'), backup_path: get_backup_path('python/_pythonrc')
      end
    end
  end

  describe 'restore' do
    it 'should restore' do
      assert_ran_with_errors setup %w[restore --enable_new=all --verbose]

      expect(File.exist? get_backup_path('vim/_vimrc')).to be false
      assert_symlinks restore_path: get_restore_path('.vscode'), backup_path: get_backup_path('code/_vscode'), content: 'some content'
      assert_symlinks restore_path: get_restore_path('.bashrc'), backup_path: get_backup_path('bash/_bashrc'), content: 'bashrc file'
      assert_symlinks restore_path: get_restore_path('.pythonrc'), backup_path: get_backup_path('python/_pythonrc'), content: 'pythonrc'
      expect(@output_lines.join).to eq(
"Restoring:
I: Restoring package bash:
I: Restoring .bashrc
V: Symlinking \"#{get_backup_path('bash/_bashrc')}\" with \"#{get_restore_path('.bashrc')}\"
I: Restoring .bash_local
E: Cannot restore: missing \"#{get_backup_path('bash/_bash_local')}\"
I: Restoring package code:
I: Restoring .vscode
V: Saving a copy of file \"#{get_restore_path('.vscode')}\" under \"#{get_backup_path('code')}\"
V: Symlinking \"#{get_backup_path('code/_vscode')}\" with \"#{get_restore_path('.vscode')}\"
I: Restoring package python:
I: Restoring .pythonrc
V: Symlinking \"#{get_backup_path('python/_pythonrc')}\" with \"#{get_restore_path('.pythonrc')}\"
I: Restoring package rubocop:
I: Restoring .rubocop
I: Restoring package vim:
I: Restoring .vimrc
E: Cannot restore: missing \"#{get_backup_path('vim/_vimrc')}\"
")
    end

    it 'should not restore if the task is disabled' do
      assert_ran_without_errors setup %w[restore --enable_new=none]
      assert_files_unchanged
    end

    context 'when --copy' do
      it 'should generate file copies instead of symlinks' do
        expect(setup %w[restore --enable_new=all --copy]).to be true

        expect(File.exist? get_backup_path('vim/_vimrc')).to be false
        assert_copies restore_path: get_restore_path('.vscode'), backup_path: get_backup_path('code/_vscode'), content: 'some content'
        assert_copies restore_path: get_restore_path('.bashrc'), backup_path: get_backup_path('bash/_bashrc'), content: 'bashrc file'
        assert_copies restore_path: get_restore_path('.pythonrc'), backup_path: get_backup_path('python/_pythonrc'), content: 'pythonrc'
      end
    end
  end

  describe 'cleanup' do
    let(:cleanup_files) { ['bash/setup-backup-1-_bash_local', 'vim/setup-backup-1-_vimrc'].map(&method(:get_backup_path)) }
    before(:each) do
      save_yaml_content @dotfiles_config, 'enabled_task_names' => ['bash', 'vim']
    end

    def create_cleanup_files
      cleanup_files.each { |path| save_file_content path, path }
      FileUtils.mkdir_p get_backup_path('bash/folder/nested/deeper')
    end

    it 'should report when there is nothing to clean' do
      assert_ran_without_errors setup %w[cleanup]

      expect(@output_lines.join).to eq(
"Nothing to clean.
")
    end

    it 'should cleanup old backups' do
      create_cleanup_files
      expect(cmd).to receive(:agree).twice.and_return true
      assert_ran_without_errors setup %w[cleanup]

      cleanup_files.each { |path| expect(File.exist? path).to be false }
      expect(@output_lines.join).to eq(
"Deleting \"#{get_backup_path('bash/setup-backup-1-_bash_local')}\"
Deleting \"#{get_backup_path('vim/setup-backup-1-_vimrc')}\"
")
    end

    it 'should remove untracked backups' do
      create_cleanup_files
      expect(cmd).to receive(:agree).exactly(3).times.and_return true
      assert_ran_without_errors setup %w[cleanup --untracked]

      cleanup_files.each { |path| expect(File.exist? path).to be false }
      expect(@output_lines.join).to eq(
"Deleting \"#{get_backup_path('bash/folder')}\"
Deleting \"#{get_backup_path('bash/setup-backup-1-_bash_local')}\"
Deleting \"#{get_backup_path('vim/setup-backup-1-_vimrc')}\"
")
    end

    context 'when no options are passed in' do
      it 'should require confirmation' do
        create_cleanup_files
        expect(cmd).to receive(:agree).twice.and_return false
        assert_ran_without_errors setup %w[cleanup]

        cleanup_files.each { |path| expect(File.exist? path).to be true }
      end
    end

    context 'when --confirm=false' do
      it 'should cleanup old backups' do
        create_cleanup_files
        assert_ran_without_errors setup %w[cleanup --confirm=false]

        cleanup_files.each { |path| expect(File.exist? path).to be false }
      end
    end
  end

  describe 'status' do
    it 'should print an empty message if no packages exist' do
      save_yaml_content @default_config_root, 'backups' => []
      assert_ran_without_errors setup %w[status]
      
      expect(@output_lines.join).to eq(
"W: No packages enabled.
W: Use ./setup package add to enable packages.
")
    end
  
    it 'should print status' do
      save_yaml_content @default_config_root, 'backups' => [@dotfiles_dir]
      save_yaml_content @dotfiles_config, 'enabled_task_names' => ['bash', 'code', 'vim', 'python', 'rubocop'], 'disabled_task_names' => []
      assert_ran_without_errors setup %w[status]

      expect(@output_lines.join).to eq(
"Current status:

needs sync: bash:.bashrc
error:      bash:.bash_local Cannot sync. Missing both backup and restore.
differs:    code:.vscode
needs sync: python:.pythonrc
up-to-date: rubocop
needs sync: vim:.vimrc
")
    end

    it 'should print verbose status' do
      save_yaml_content @default_config_root, 'backups' => [@dotfiles_dir]
      save_yaml_content @dotfiles_config, 'enabled_task_names' => ['bash', 'code', 'vim', 'python', 'rubocop'], 'disabled_task_names' => []
      assert_ran_without_errors setup %w[status --verbose]

      expect(@output_lines.join).to eq(
"Current status:

needs sync: bash:.bashrc
error:      bash:.bash_local Cannot sync. Missing both backup and restore.
differs:    code:.vscode
needs sync: python:.pythonrc
up-to-date: rubocop:.rubocop
needs sync: vim:.vimrc
")
    end
  end

  describe 'package' do
    before(:each) do
      save_yaml_content @dotfiles_config, 'enabled_task_names' => ['bash', 'code'], 'disabled_task_names' => ['vim']
    end

    describe 'add' do
      it 'should add packages' do
        assert_ran_without_errors setup %w[package add code vim]
        assert_yaml_content @dotfiles_config, 'enabled_task_names' => ['bash', 'code', 'vim'], 'disabled_task_names' => []
      end
    end

    describe 'remove' do
      it 'should remove packages' do
        assert_ran_without_errors setup %w[package remove code vim]
        assert_yaml_content @dotfiles_config, 'enabled_task_names' => ['bash'], 'disabled_task_names' => ['vim', 'code']
      end
    end

    describe 'list' do
      it 'should list packages ready to be add/remove' do
        assert_ran_without_errors setup %w[package list]

        expect(@output_lines.join).to eq(
"Enabled packages:
bash, code

Disabled packages:
vim

New packages:
python, rubocop
")
      end
    end
  end

  # Check that corrupting a file will make all commands fail.
  def assert_commands_fail_if_corrupt(corrupt_file_path)
    save_file_content corrupt_file_path, "---\n"

    commands = ['init', 'restore', 'backup', 'cleanup', 'status', 'package add', 'package remove', 'package list']
    commands.each do |command|
      assert_ran_unsuccessfully setup command.split(' ')
      expect(@output_lines).to eq(["E: An error occured while trying to load \"#{corrupt_file_path}\"\n"])
    end
  end

  context 'when a global config file is invalid' do
    it 'should fail commands' do
      assert_commands_fail_if_corrupt @default_config_root
    end
  end

  context 'when a backup config file is invalid' do
    it 'should fail commands' do
      save_yaml_content @default_config_root, 'backups' => [@dotfiles_dir]
      assert_commands_fail_if_corrupt @dotfiles_config
    end
  end

  context 'when a task config file is invalid' do
    it 'should fail commands' do
      save_yaml_content @default_config_root, 'backups' => [@dotfiles_dir]
      assert_commands_fail_if_corrupt File.join(@tmpdir, 'apps/vim.yml')
    end
  end
end

end # module Setup
