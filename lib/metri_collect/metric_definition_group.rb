module MetriCollect
  class MetricDefinitionGroup
    def initialize(name, namespace, options = {}, &body)
      @name = name
      @namespace = namespace
      @options = options
      @body = body
    end

    def call
      @definitions = []
      time = Time.now

      instance_eval(&@body)

      @definitions.each { |definition| definition.timestamp(time) }.map(&:call)
    end

    def match_roles?(roles_to_match)
      roles.empty? || (roles & roles_to_match).any?
    end

    def metric(&block)
      @definitions ||= []
      @definitions << MetricDefinition.new(@name, @namespace, &block)
    end

    private

    def roles
      @options[:roles]
    end
  end
end