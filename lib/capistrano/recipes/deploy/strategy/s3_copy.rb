require 'capistrano/recipes/deploy/strategy/copy'
require 'erb'


module Capistrano
  module Deploy
    module Strategy
      class S3Copy < Copy

        def initialize(config={})
          super(config)

          s3cmd_vars = []
          ["aws_access_key_id", "aws_secret_access_key"].each do |var|
            value = configuration[var.to_sym]
            raise Capistrano::Error, "Missing configuration[:#{var}] setting" if value.nil?
            s3cmd_vars << "#{var.upcase}=#{value}"
          end
          @aws_environment = s3cmd_vars.join(" ")

          @bucket_name = configuration[:aws_releases_bucket]
          raise Capistrano::Error, "Missing configuration[:aws_releases_bucket]" if @bucket_name.nil?
        end

        def check!
          super.check do |d|
            d.local.command("s3cmd")
            d.remote.command("s3cmd")
          end
        end

        # Distributes the file to the remote servers
        def distribute!
          package_path = filename
          package_name = File.basename(package_path)
		  s3_push_cmd = "s3cmd put #{package_path} s3://#{bucket_name}/#{application}/#{rails_env}/#{package_name} 2>&1"
          
          if configuration.dry_run
            logger.debug s3_push_cmd
          else
            system(s3_push_cmd)
            raise Capistrano::Error, "shell command failed with return code #{$?}" if $? != 0
          end

          build_aws_install_script
		  upload_aws_install_script
		  run_aws_install_script

          logger.debug "done!"
        end

        def build_aws_install_script
          logger.debug "Building installation script"
          template_text = configuration[:aws_install_script]
          template_text = File.read(File.join(File.dirname(__FILE__), "aws_install.sh.erb")) if template_text.nil?
          template_text = template_text.gsub("\r\n?", "\n")
          template = ERB.new(template_text, nil, '<>-')
          output = template.result(self.binding)

		  @install_script_name = "#{rails_env}_aws_install.sh"
          local_output_file = File.join(copy_dir, @install_script_name)
          File.open(local_output_file, "w") do  |f|
            f.write(output)
          end
        
		  configuration[:s3_copy_aws_install_cmd] = "s3cmd put #{local_output_file} s3://#{bucket_name}/#{application}/#{rails_env}/#{install_script_name} 2>&1"
		  configuration[:s3_copy_aws_install_cmd_name] = 
          logger.debug "Installation script sent to S3"
        end

		def upload_aws_install_script
			logger.debug "Uploading install script"

			cmd = configuration[:s3_copy_aws_install_cmd]
			raise Capistrano::Error, "Missing install command" if cmd.nil?

			run_locally(cmd)
		end

		def run_aws_install_script
			logger.debug "Running install script"
			get_cmd = "s3cmd get --force s3://#{bucket_name}/#{application}/#{rails_env}/#{install_script_name}"
			run "cd #{configuration[:releases_path]} && #{get_cmd} && bash #{install_script_name}"
			logger.debug "Done."
		end
        
        def binding
          super
        end

        def aws_environment
          @aws_environment
        end

        def bucket_name
          @bucket_name
        end

		def install_script_name
			@install_script_name
		end
      end
    end
  end
end
