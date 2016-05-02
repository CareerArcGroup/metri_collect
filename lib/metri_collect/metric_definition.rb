module MetriCollect
  class MetricDefinition
    def initialize(name, namespace, &body)
      @name       = name
      @namespace  = namespace
      @dimensions = []
      @templates  = []
      @watches    = []
      @body       = body
    end

    def call
      @dimensions = []

      instance_eval(&@body)

      @templates.each { |template| template.apply(self) }

      Metric.new.tap do |metric|
        metric.name       = @name
        metric.namespace  = @namespace
        metric.value      = @value
        metric.unit       = @unit
        metric.timestamp  = @timestamp
        metric.dimensions = @dimensions
        metric.watches    = @watches.map { |w| w.call(metric) }
      end
    end

    def template(*names)
      names.each { |name| @templates << MetricTemplate.fetch(name) }
    end

    def name(name)
      @name = name
    end

    def namespace(namespace)
      @namespace = namespace
    end

    def value(value, unit: :count)
      @value = value
      @unit  = unit
    end

    def dimensions(dimensions = {})
      dimensions.each do |k,v|
        @dimensions << { name: k, value: v }
      end
    end

    def timestamp(timestamp)
      @timestamp = timestamp
    end

    def watch(&block)
      @watches << WatchDefinition.new(&block)
    end
  end
end