class DeploySpec
  module RubygemsDiscovery

    def discover_deploy_steps
      discover_gem || super
    end

    def discover_gem
      publish_gem if gem?
    end

    def gem?
      !!gemspec
    end

    def gemspec
      Dir[file('*.gemspec').to_s].first
    end

    def publish_gem
      ["assert-gem-version-tag #{gemspec}", 'bundle exec rake release']
    end

  end
end