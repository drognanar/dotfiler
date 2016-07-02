class NginxPackage
  name 'Nginx'
  platforms [:MACOS, :LINUX]
  restore_to '/usr/local/etc'

  def steps
    file 'nginx'
  end
end