require 'r10k/deployment'
require 'r10k/action/visitor'
require 'r10k/action/base'
require 'r10k/action/deploy/deploy_helpers'

module R10K
  module Action
    module Deploy
      class Module < R10K::Action::Base

        include R10K::Action::Deploy::DeployHelpers

        def call
          @visit_ok = true

          expect_config!
          deployment = R10K::Deployment.new(@settings)
          check_write_lock!(@settings)

          deployment.accept(self)
          @visit_ok
        end

        include R10K::Action::Visitor

        private

        def visit_deployment(deployment)
          yield
        end

        def visit_source(source)
          yield
        end

        def visit_environment(environment)
          if @opts[:environment] && (@opts[:environment] != environment.dirname)
            logger.debug1("Only updating modules in environment #{@opts[:environment]}, skipping environment #{environment.path}")
          else
            logger.debug1("Updating modules #{@argv.inspect} in environment #{environment.path}")
            yield
          end
        end

        def visit_puppetfile(puppetfile)
          puppetfile.load
          yield
        end

        def visit_module(mod)
          if @argv.include?(mod.name)
            started_at = Time.new

            logger.info "Deploying module #{mod.path}"
            mod.sync

            write_module_info!(mod, started_at)
          else
            logger.debug1("Only updating modules #{@argv.inspect}, skipping module #{mod.name}")
          end
        end

        def allowed_initialize_opts
          super.merge(environment: true)
        end

        def write_module_info!(mod, started_at)
          require 'pry'
          binding.pry

          File.open("#{mod.path}/.r10k-deploy.json", 'w') do |f|
            # TODO: implement mod.info
            deploy_info = {
              :module_name => mod.name,
              :signature => mod.version,
              :started_at => started_at,
              :finished_at => Time.new,
            }

            f.puts(JSON.pretty_generate(deploy_info))
          end
        end
      end
    end
  end
end
