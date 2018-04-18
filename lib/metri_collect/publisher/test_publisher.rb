module MetriCollect
  module Publisher

    class TestPublisher
      def initialize
        @published = []
      end

      def published
        @published
      end

      def clear
        @published.clear
      end

      def publish(*metrics)
        metrics.each do |metric|
          next if metric.external?

          @published.push(metric)

          puts "TestPublisher: Published #{metric}"
        end
      end

      def published?(metric)
        @published.include?(metric)
      end
    end

    add_publisher :test, TestPublisher.new
  end
end