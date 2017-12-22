include_recipe "java::windows"

work_dir = 'C:/teamcity/work'
temp_dir = 'C:/teamcity/tmp'
config_dir = 'C:/teamcity/conf'
bin_dir = 'C:/teamcity/bin'
system_dir = 'C:/teamcity'
agent_file = 'buildAgent.zip'
src_path = "#{system_dir}.zip"
service_name = 'TCBuildAgent'

agent_uri = "http://teamcity.riskmatch.com:8111/update/#{agent_file}"

remote_file src_path do
  source agent_uri
  not_if { ::File.exist?(config_path) }
end

directory system_dir do
  action :create
  recursive true
  not_if { ::File.exist?(config_path) }
end

windows_zipfile system_dir do
  source src_path
  action :unzip
  not_if { ::File.exist?(bin_path) }
end

unless Chef::Config[:solo]
  unless node["teamcity_server"]["build_agent"]["server"]
    server_node = search(:node, "chef_environment:#{node.chef_environment} AND recipes:teamcity_server\\:\\:server").first

    if server_node
      node.default["teamcity_server"]["build_agent"]["server"] = server_node["ipaddress"]
    end
  end
end

unless node["teamcity_server"]["build_agent"]["server"]
  Chef::Application.fatal! "Undefined TeamCity server address"
end

properties_file     = "#{conf_dir}/buildAgent.properties"
server              = node["teamcity_server"]["build_agent"]["server"]
own_address         = node["ipaddress"]
authorization_token = nil

if server == own_address
  server = own_address = "127.0.0.1"
end

if File.exists?(properties_file)
  lines = File.readlines(properties_file).grep(/^authorizationToken=/)

  unless lines.empty?
    match = /authorizationToken=([0-9a-f]+)/.match(lines.first)
    authorization_token = match[1] if match
  end

  unless node["teamcity_server"]["build_agent"]["name"]
    lines = File.readlines(properties_file).grep(/^name=/)

    unless lines.empty?
      match = /name=(.+)/.match(lines.first)
      node.default["teamcity_server"]["build_agent"]["name"] = match[1].strip if match
    end
  end
end

template properties_file do
  source "buildAgent.properties.erb"
  variables(
    :server_address      => server,
    :name                => node["teamcity_server"]["build_agent"]["name"],
    :own_address         => own_address,
    :authorization_token => authorization_token
  )
  notifies :restart, "service[#{service_name}]", :delayed
end

execute 'install teamcity service' do
  command "#{bin_path}/service.install.bat"
  action :run
  cwd bin_path
  not_if { ::Win32::Service.exists?(service_name) }
end

service service_name do
  supports start: true, stop: true, restart: true, status: true
  action [:enable, :start]
end

