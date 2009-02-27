#
# Author:: Bryan McLellan (btm@loftninjas.org)
# Copyright:: Copyright (c) 2009 Bryan McLellan
# License:: Apache License, Version 2.0
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#     http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.
#

require 'chef/provider/package'
require 'chef/mixin/command'
require 'chef/resource/package'

class Chef
  class Provider
    class Package
      class Freebsd < Chef::Provider::Package  
      
        def current_installed_version
          command = "pkg_info -E \"#{package_name}*\""
          status = popen4(command) do |pid, stdin, stdout, stderr|
            stdout.each do |line|
              case line
              when /^#{package_name}-(.+)/
                return $1
              end
            end
          end
          unless status.exitstatus == 0 || status.exitstatus == 1
            raise Chef::Exception::Package, "#{command} failed - #{status.inspect}!"
          end
          nil
        end
        
        def port_path
          status = popen4("whereis -s #{port_name}") do |pid, stdin, stdout, stderr|
            stdout.each do |line|
              case line
              when /^#{port_name}:\s+(.+)$/
                return $1
              end
            end
          end
          raise Chef::Exception::Package, "Could not find port with the name #{port_name}"
        end
        
        def ports_makefile_variable_value(variable)
          command = "cd #{port_path}; make -V #{variable}"
          status = popen4(command) do |pid, stdin, stdout, stderr|
            return stdout.readline.strip
          end
          unless status.exitstatus == 0 || status.exitstatus == 1
            raise Chef::Exception::Package, "#{command} failed - #{status.inspect}!"
          end
          nil
        end
        
        def ports_candidate_version
          ports_makefile_variable_value("PORTVERSION")
        end
        
        def load_current_resource
          @current_resource = Chef::Resource::Package.new(@new_resource.name)
          @current_resource.package_name(@new_resource.package_name)
        
          @current_resource.version(current_installed_version)
          Chef::Log.debug("Current version is #{@current_resource.version}") if @current_resource.version
          Chef::Log.debug("Using #{port_name} as package name")
          
          @candidate_version = ports_candidate_version
          Chef::Log.debug("Ports candidate version is #{@candidate_version}") if @candidate_version
          
          @current_resource
        end
        
        # The name of the leaf directory in /usr/ports
        def port_name
          @new_resource.package_name
        end
        
        # The name of the package (without the version number) as understood by pkg_add and pkg_info
        def package_name
          if ports_makefile_variable_value("PKGNAME") =~ /^(.+)-[^-]+$/
            $1
          else
            raise Chef::Exception::Package, "Unexpected form for PKGNAME variable in #{port_path}/Makefile"
          end
        end

        def install_package(name, version)
          unless @current_resource.version
            case @new_resource.source
            when /^ports$/
              run_command(
                :command => "make -DBATCH install",
                :cwd => "#{port_path}"
              )
            when /^http/, /^ftp/
              run_command(
                :command => "pkg_add -r #{package_name}",
                :environment => { "PACKAGESITE" => @new_resource.source }
              )
              Chef::Log.info("Installed package #{package_name} from: #{@new_resource.source}")
            when /^\//
              run_command(
                :command => "pkg_add #{@new_resource.name}",
                :environment => { "PKG_PATH" => @new_resource.source }
              )
              Chef::Log.info("Installed package #{@new_resource.name} from: #{@new_resource.source}")
            else
              run_command(
                :command => "pkg_add -r #{package_name}"
              )
              Chef::Log.info("Installed package #{package_name}")
            end
          end
        end
      
        def remove_package(name, version)
          if @current_resource.version
            run_command(
              :command => "pkg_delete #{package_name}-#{@current_resource.version}"
            )
            Chef::Log.info("Removed package #{package_name}-#{@current_resource.version}")
          end
        end
      end
    end
  end
end
